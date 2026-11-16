//! 最小 S3 兼容桩：给网盘功能做本地验收用（不参与打包）。
//!
//! 支持：PUT / HEAD / GET / DELETE 对象，GET /{bucket}?list-type=2 列表。
//! 不校验签名（测试用），不支持 multipart —— 与本项目网盘代码用的能力集一致。
//!
//!   cargo run -p tinymusic-server --example s3_stub -- --port 9100 --dir /tmp/s3stub

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::Router;

#[derive(Clone)]
struct Store {
    dir: PathBuf,
}

fn safe_path(dir: &PathBuf, bucket: &str, key: &str) -> PathBuf {
    let clean: String = key.chars().map(|c| if c == '/' { c } else { c }).collect();
    let mut p = dir.join(bucket);
    for part in clean.split('/') {
        if part.is_empty() || part == "." || part == ".." {
            continue;
        }
        p.push(part);
    }
    p
}

async fn put_object(
    State(store): State<Arc<Store>>,
    Path((bucket, key)): Path<(String, String)>,
    headers: HeaderMap,
    body: axum::body::Bytes,
) -> Response {
    let path = safe_path(&store.dir, &bucket, &key);
    if let Some(parent) = path.parent() {
        if std::fs::create_dir_all(parent).is_err() {
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    }
    let ct = headers
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("application/octet-stream")
        .to_string();
    if std::fs::write(&path, &body).is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let _ = std::fs::write(path.with_extension(format!("{}.ctype", "")) , ct.as_bytes());
    StatusCode::OK.into_response()
}

async fn head_object(State(store): State<Arc<Store>>, Path((bucket, key)): Path<(String, String)>) -> Response {
    let path = safe_path(&store.dir, &bucket, &key);
    match std::fs::metadata(&path) {
        Ok(meta) => {
            let mut res = StatusCode::OK.into_response();
            res.headers_mut().insert(
                axum::http::header::CONTENT_LENGTH,
                meta.len().to_string().parse().unwrap(),
            );
            res.headers_mut().insert(
                axum::http::header::CONTENT_TYPE,
                "audio/mpeg".parse().unwrap(),
            );
            res
        }
        Err(_) => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn get_object(
    State(store): State<Arc<Store>>,
    Path((bucket, key)): Path<(String, String)>,
    headers: HeaderMap,
) -> Response {
    let path = safe_path(&store.dir, &bucket, &key);
    let Ok(bytes) = std::fs::read(&path) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let total = bytes.len();
    // Range 支持（播放/校验都会用）
    if let Some(range) = headers.get(axum::http::header::RANGE).and_then(|v| v.to_str().ok()) {
        if let Some(spec) = range.strip_prefix("bytes=") {
            let mut it = spec.splitn(2, '-');
            let start: usize = it.next().and_then(|s| s.parse().ok()).unwrap_or(0);
            let end: usize = it
                .next()
                .and_then(|s| if s.is_empty() { None } else { s.parse().ok() })
                .unwrap_or(total.saturating_sub(1));
            let end = end.min(total.saturating_sub(1));
            if start > end || start >= total {
                return StatusCode::RANGE_NOT_SATISFIABLE.into_response();
            }
            let slice = bytes[start..=end].to_vec();
            let mut res = StatusCode::PARTIAL_CONTENT.into_response();
            res.headers_mut().insert(
                axum::http::header::CONTENT_RANGE,
                format!("bytes {}-{}/{}", start, end, total).parse().unwrap(),
            );
            *res.body_mut() = Body::from(slice);
            return res;
        }
    }
    let mut res = StatusCode::OK.into_response();
    res.headers_mut()
        .insert(axum::http::header::CONTENT_TYPE, "audio/mpeg".parse().unwrap());
    *res.body_mut() = Body::from(bytes);
    res
}

async fn delete_object(State(store): State<Arc<Store>>, Path((bucket, key)): Path<(String, String)>) -> Response {
    let path = safe_path(&store.dir, &bucket, &key);
    let _ = std::fs::remove_file(path);
    StatusCode::NO_CONTENT.into_response()
}

fn collect_files(dir: &PathBuf, base: &PathBuf, prefix: &str, out: &mut Vec<(String, u64)>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_files(&path, base, prefix, out);
        } else {
            let rel = path.strip_prefix(base).unwrap_or(&path).to_string_lossy().to_string();
            let rel = rel.replace('\\', "/");
            if rel.contains(".ctype") || !rel.starts_with(prefix) {
                continue;
            }
            let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
            out.push((rel, size));
        }
    }
}

async fn list_objects(
    State(store): State<Arc<Store>>,
    Path(bucket): Path<String>,
    Query(q): Query<BTreeMap<String, String>>,
) -> Response {
    let prefix = q.get("prefix").cloned().unwrap_or_default();
    let mut items = Vec::new();
    collect_files(&store.dir.join(&bucket), &store.dir.join(&bucket), &prefix, &mut items);
    items.sort();
    let mut xml = String::from(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">",
    );
    xml.push_str(&format!("<Name>{}</Name><Prefix>{}</Prefix><KeyCount>{}</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>", bucket, prefix, items.len()));
    for (key, size) in items {
        xml.push_str(&format!(
            "<Contents><Key>{}</Key><Size>{}</Size><LastModified>2026-01-01T00:00:00.000Z</LastModified><ETag>\"stub\"</ETag><StorageClass>STANDARD</StorageClass></Contents>",
            key.replace('&', "&amp;").replace('<', "&lt;"),
            size
        ));
    }
    xml.push_str("</ListBucketResult>");
    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/xml")
        .body(Body::from(xml))
        .unwrap()
}

async fn head_bucket() -> Response {
    StatusCode::OK.into_response()
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut port = 9100u16;
    let mut dir = std::env::temp_dir().join("tm-s3-stub");
    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--port" => {
                port = args.get(i + 1).and_then(|v| v.parse().ok()).unwrap_or(9100);
                i += 2;
            }
            "--dir" => {
                dir = PathBuf::from(args.get(i + 1).cloned().unwrap_or_default());
                i += 2;
            }
            _ => i += 1,
        }
    }
    std::fs::create_dir_all(&dir)?;
    let store = Arc::new(Store { dir: dir.clone() });
    println!("S3 stub listening on 127.0.0.1:{port}, dir={}", dir.display());

    let app = Router::new()
        .route("/", get(|| async { "s3-stub" }))
        .route("/{bucket}", get(list_objects).head(head_bucket))
        .route(
            "/{bucket}/{*key}",
            get(get_object)
                .put(put_object)
                .head(head_object)
                .delete(delete_object),
        )
        .with_state(store);

    let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
