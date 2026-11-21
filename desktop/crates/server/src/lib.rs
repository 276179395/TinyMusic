//! 本地 HTTP API：mobile 通过它调用 `tinymusic_app::dispatch`。
//!
//! 设计约束：
//! - 只绑 127.0.0.1，端口由系统分配（0）；
//! - 每次启动生成随机 token，放在 `X-Tm-Token` 头里；
//! - 进度不推流，写进内存登记表由客户端轮询（少一套事件机制）。

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::{json, Value};

use tinymusic_app::{dispatch, AppState, Host, Progress, ProgressFn, S3FixFn, S3FixProgress};
use tinymusic_core::storage::FailedDownload;

/// 一次运行的上下文：后端状态、token、进度快照
#[derive(Clone)]
pub struct Ctx {
    pub state: Arc<AppState>,
    pub token: String,
    pub progress: Arc<Mutex<HashMap<String, Value>>>,
    pub s3fix: Arc<Mutex<Option<Value>>>,
}

struct ServerHost {
    errors: Arc<Mutex<Vec<FailedDownload>>>,
}

impl Host for ServerHost {
    fn failed(&self, failures: &[FailedDownload]) {
        if let Ok(mut list) = self.errors.lock() {
            list.extend(failures.iter().cloned());
        }
    }
}

fn unauthorized() -> Response {
    (StatusCode::UNAUTHORIZED, Json(json!({ "error": "token 无效" }))).into_response()
}

async fn health(State(ctx): State<Ctx>) -> Response {
    let download_dir = ctx.state.settings_snapshot().download_dir;
    Json(json!({
        "ok": true,
        "version": env!("CARGO_PKG_VERSION"),
        "configDir": ctx.state.config_dir().to_string_lossy(),
        "downloadDir": download_dir,
    }))
    .into_response()
}

async fn progress(State(ctx): State<Ctx>) -> Response {
    let tasks = ctx.progress.lock().map(|m| m.clone()).unwrap_or_default();
    let s3fix = ctx.s3fix.lock().ok().and_then(|v| v.clone());
    Json(json!({ "tasks": tasks, "s3fix": s3fix })).into_response()
}

async fn call(
    State(ctx): State<Ctx>,
    Path(cmd): Path<String>,
    headers: HeaderMap,
    body: axum::body::Bytes,
) -> Response {
    let token = headers
        .get("x-tm-token")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();
    if token != ctx.token {
        return unauthorized();
    }

    let args: Value = if body.is_empty() {
        json!({})
    } else {
        match serde_json::from_slice(&body) {
            Ok(v) => v,
            Err(e) => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({ "error": format!("body 不是合法 JSON: {e}") })),
                )
                    .into_response()
            }
        }
    };

    let progress_map = ctx.progress.clone();
    let sink: ProgressFn = Arc::new(move |p: Progress| {
        if let Ok(mut m) = progress_map.lock() {
            m.insert(p.task_id.clone(), serde_json::to_value(&p).unwrap_or(Value::Null));
        }
    });
    let s3fix_slot = ctx.s3fix.clone();
    let s3_sink: S3FixFn = Arc::new(move |p: S3FixProgress| {
        if let Ok(mut slot) = s3fix_slot.lock() {
            *slot = serde_json::to_value(&p).ok();
        }
    });

    match dispatch::dispatch(&ctx.state, &cmd, args, Some(sink), Some(s3_sink)).await {
        Ok(v) => Json(json!({ "ok": true, "data": v })).into_response(),
        Err(e) => (
            StatusCode::OK,
            Json(json!({ "ok": false, "error": e })),
        )
            .into_response(),
    }
}

/// 起服务，返回实际监听地址与任务句柄
pub async fn start(
    config_dir: std::path::PathBuf,
    download_dir: std::path::PathBuf,
    bind: &str,
    token: String,
) -> Result<(SocketAddr, tokio::task::JoinHandle<()>, Arc<AppState>), String> {
    let errors = Arc::new(Mutex::new(Vec::new()));
    let state = AppState::new(
        config_dir,
        download_dir,
        Arc::new(ServerHost { errors }),
    )
    .await?;

    let ctx = Ctx {
        state: state.clone(),
        token,
        progress: Arc::new(Mutex::new(HashMap::new())),
        s3fix: Arc::new(Mutex::new(None)),
    };

    let app = Router::new()
        .route("/api/health", get(health))
        .route("/api/progress", get(progress))
        .route("/api/{cmd}", post(call))
        .with_state(ctx);

    let listener = tokio::net::TcpListener::bind(bind)
        .await
        .map_err(|e| format!("绑定 {bind} 失败: {e}"))?;
    let addr = listener.local_addr().map_err(|e| e.to_string())?;

    let handle = tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, app).await {
            eprintln!("[tinymusic-server] 服务退出: {e}");
        }
    });

    Ok((addr, handle, state))
}

/// 便于 main 与 ffi 复用的随机 token
pub fn random_token() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = std::process::id();
    format!("{nanos:x}{pid:x}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{header, HeaderMap, StatusCode};
    use tinymusic_core::{
        cloud::CloudLibrary, http::HttpClient, model::Codec, proxy::StreamProxy, webdav::WebDav,
    };

    #[tokio::test]
    async fn webdav_playback_uses_audio_bytes_over_filename_and_upstream_mime() {
        let app = Router::new().route(
            "/music/song.flac",
            get(|headers: HeaderMap| async move {
                assert!(matches!(
                    headers[header::RANGE].to_str().unwrap(),
                    "bytes=0-65535" | "bytes=0-3"
                ));
                (
                    StatusCode::PARTIAL_CONTENT,
                    [
                        (header::CONTENT_TYPE, "audio/flac"),
                        (header::CONTENT_RANGE, "bytes 0-3/4"),
                    ],
                    [0xff, 0xfb, 0x90, 0x64],
                )
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let upstream = tokio::spawn(async move { axum::serve(listener, app).await });
        let http = Arc::new(HttpClient::new(0, 4));
        let proxy = StreamProxy::start(http.clone()).await.unwrap();
        let dav = WebDav::new(&endpoint, "music", String::new(), String::new()).unwrap();
        let cloud = CloudLibrary::WebDav(dav, proxy.clone());
        let (url, format, bytes) = cloud
            .audio_url("music/song.flac", &proxy, http.client())
            .await
            .unwrap();
        assert_eq!(format.codec, Codec::Mp3);
        assert!(!format.lossless);
        assert_eq!(bytes, Some(4));
        let response = http
            .client()
            .get(url)
            .header(header::RANGE, "bytes=0-3")
            .send()
            .await
            .unwrap();
        assert_eq!(response.headers()[header::CONTENT_TYPE], "audio/mpeg");
        assert_eq!(
            response.bytes().await.unwrap().as_ref(),
            &[0xff, 0xfb, 0x90, 0x64]
        );
        upstream.abort();
    }
}
