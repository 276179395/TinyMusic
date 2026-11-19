//! 网盘（S3）联通性/生命周期测试，默认忽略：
//!
//! ```sh
//! S3_EP=... S3_BUCKET=... S3_AK=... S3_SK=... \
//!   cargo test -p tinymusic-core --test s3_live -- --ignored --nocapture
//! ```

use tinymusic_core::s3::{S3Config, S3};

fn client() -> S3 {
    let cfg = S3Config {
        endpoint: std::env::var("S3_EP").expect("S3_EP"),
        region: std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".into()),
        bucket: std::env::var("S3_BUCKET").expect("S3_BUCKET"),
        access_key: std::env::var("S3_AK").expect("S3_AK"),
        secret_key: std::env::var("S3_SK").expect("S3_SK"),
        prefix: "TinyMusic".into(),
        path_style: true,
    };
    S3::new(cfg, reqwest::Client::new())
}

#[tokio::test]
#[ignore]
async fn s3_list_prefixes() {
    let s3 = client();
    match s3.test().await {
        Ok(msg) => println!("TEST OK: {}", msg),
        Err(e) => println!("TEST ERR: {}", e),
    }
    for p in ["TinyMusic", "TinyMusic/喜欢", "TinyMusic/favorites.json"] {
        match s3.list_keys(p).await {
            Ok(keys) => {
                println!("PREFIX {:?}: {} keys", p, keys.len());
                for k in keys.iter().take(10) {
                    println!("   - {}", k);
                }
            }
            Err(e) => println!("PREFIX {:?}: ERR {}", p, e),
        }
    }
}

#[tokio::test]
#[ignore]
async fn s3_presign_copy_delete() {
    let s3 = client();
    let key =
        std::env::var("S3_TEST_KEY").unwrap_or_else(|_| "TinyMusic/喜欢/周杰伦 - 稻香.lrc".into());

    let url = s3.presign_get(&key, 600).expect("presign");
    println!("PRESIGN: {}", url);
    let resp = reqwest::Client::new().get(&url).send().await.expect("GET");
    let status = resp.status();
    let body = resp.bytes().await.expect("body");
    println!("PRESIGN STATUS: {} bytes={}", status, body.len());
    assert!(status.is_success());

    let moved_key = "TinyMusic/__move_test__.lrc";
    s3.move_object(&key, moved_key).await.expect("move");
    let moved = s3.get_object(moved_key).await.expect("get moved");
    assert!(moved.is_some(), "移动后对象应存在");
    println!("MOVE OK bytes={}", moved.unwrap().len());

    s3.delete_object(moved_key).await.expect("delete");
    let gone = s3.get_object(moved_key).await.expect("get after delete");
    assert!(gone.is_none(), "删除后应为 None");
    println!("DELETE OK");
}
#[tokio::test]
#[ignore]
async fn s3_playlist_crud_lifecycle() {
    use tinymusic_core::library;
    use tinymusic_core::storage::Storage;

    let s3 = client();
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let source = format!("CRUD源{suffix}");
    let target = format!("CRUD目标{suffix}");
    let renamed = format!("CRUD改名{suffix}");
    let dir = std::env::temp_dir().join(format!("tinymusic-crud-{suffix}"));
    std::fs::create_dir_all(&dir).unwrap();
    let storage = Storage::open(dir.join("test.db")).expect("storage");

    let source_key = format!("TinyMusic/{source}/Artist - Song.mp3");
    let lrc_key = format!("TinyMusic/{source}/Artist - Song.lrc");
    s3.put_object(&source_key, b"audio".to_vec(), "audio/mpeg")
        .await
        .expect("put audio");
    s3.put_object(&lrc_key, b"[00:00.00]hi".to_vec(), "text/plain")
        .await
        .expect("put lrc");
    storage.save_s3_playlist(&source).unwrap();

    library::create_s3_playlist(&s3, &storage, &target)
        .await
        .expect("create target");
    library::move_s3_track(&s3, &storage, &source_key, &target)
        .await
        .expect("move track");
    assert!(s3.get_object(&source_key).await.unwrap().is_none());
    let moved_key = format!("TinyMusic/{target}/Artist - Song.mp3");
    assert!(s3.get_object(&moved_key).await.unwrap().is_some());
    let moved_lrc = format!("TinyMusic/{target}/Artist - Song.lrc");
    assert!(s3.get_object(&moved_lrc).await.unwrap().is_some());

    library::rename_s3_playlist(&s3, &storage, &target, &renamed)
        .await
        .expect("rename");
    let renamed_key = format!("TinyMusic/{renamed}/Artist - Song.mp3");
    assert!(s3.get_object(&renamed_key).await.unwrap().is_some());
    assert!(s3.get_object(&moved_key).await.unwrap().is_none());

    library::purge_s3_playlist(&s3, &storage, &renamed)
        .await
        .expect("purge");
    assert!(s3
        .list_keys(&format!("TinyMusic/{renamed}/"))
        .await
        .unwrap()
        .is_empty());
    assert!(!storage
        .list_s3_playlists()
        .unwrap()
        .iter()
        .any(|n| n == &renamed));

    let _ = std::fs::remove_dir_all(&dir);
}

/// 收藏只认「喜欢」目录：文件没了就不该再出现在喜欢里。
///
/// 本地跑法（桩）：
/// ```sh
/// cargo run -p tinymusic-server --example s3_stub -- --port 9107 --dir /tmp/tm-fav
/// S3_EP=http://127.0.0.1:9107 S3_BUCKET=music S3_AK=x S3_SK=y \
///   cargo test -p tinymusic-core --test s3_live favorites -- --ignored --nocapture
/// ```
#[tokio::test]
#[ignore]
async fn s3_favorites_follow_liked_folder() {
    use tinymusic_core::library;
    use tinymusic_core::model::Track;
    use tinymusic_core::storage::Storage;

    let s3 = client();
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let folder = library::favorites_folder("TinyMusic");
    assert_eq!(folder, "TinyMusic/喜欢/");

    // 原歌单里的一首歌（旧版本只在 favorites.json 里记了它）
    let playlist = format!("Fav源{suffix}");
    let src_key = format!("TinyMusic/{playlist}/Artist{suffix} - Song{suffix}.mp3");
    let src_lrc = format!("TinyMusic/{playlist}/Artist{suffix} - Song{suffix}.lrc");
    s3.put_object(&src_key, b"audio".to_vec(), "audio/mpeg")
        .await
        .expect("put audio");
    s3.put_object(&src_lrc, b"[00:00.00]hi".to_vec(), "text/plain")
        .await
        .expect("put lrc");
    // 「喜欢」目录里已经有的一首
    let kept_key = format!("{folder}Kept{suffix} - Song{suffix}.mp3");
    s3.put_object(&kept_key, b"audio".to_vec(), "audio/mpeg")
        .await
        .expect("put kept");
    // 文件已经被删掉、只在本地收藏里残留的一条
    let gone_key = format!("{folder}Gone{suffix} - Song{suffix}.mp3");
    // 旧版本写出来的 favorites.json：迁移完应该被删掉
    s3.put_object("TinyMusic/favorites.json", b"[]".to_vec(), "application/json")
        .await
        .expect("put legacy json");

    let dir = std::env::temp_dir().join(format!("tinymusic-fav-{suffix}"));
    std::fs::create_dir_all(&dir).unwrap();
    let storage = Storage::open(dir.join("test.db")).expect("storage");
    let fav = |id: &str, title: &str, artist: &str| Track {
        provider: "s3".into(),
        id: id.into(),
        title: title.into(),
        artist: artist.into(),
        ..Track::default()
    };
    storage
        .add_favorite(&fav(&src_key, &format!("Song{suffix}"), &format!("Artist{suffix}")))
        .unwrap();
    storage
        .add_favorite(&fav(&gone_key, &format!("Song{suffix}"), &format!("Gone{suffix}")))
        .unwrap();
    storage
        .add_favorite(&Track {
            provider: "netease".into(),
            id: "42".into(),
            title: "Remote".into(),
            artist: "平台".into(),
            ..Track::default()
        })
        .unwrap();

    // 1) 老收藏搬进「喜欢」目录；文件没了的丢掉；目录里已有的照旧
    let list = library::pull_favorites(&s3, &storage).await.expect("pull");
    let copied = format!("{folder}Artist{suffix} - Song{suffix}.mp3");
    assert!(
        s3.get_object(&copied).await.unwrap().is_some(),
        "老的 S3 收藏要复制进「喜欢」目录"
    );
    assert!(
        s3.get_object(&format!("{folder}Artist{suffix} - Song{suffix}.lrc"))
            .await
            .unwrap()
            .is_some(),
        "歌词要跟着走"
    );
    let ids: Vec<String> = list.iter().map(|t| t.id.clone()).collect();
    assert!(ids.contains(&copied), "喜欢里应该有复制过来的那首: {ids:?}");
    assert!(ids.contains(&kept_key), "目录里已有的那首不能掉: {ids:?}");
    assert!(!ids.contains(&gone_key), "文件没了就不该再算收藏: {ids:?}");
    assert!(
        list.iter().any(|t| t.provider == "netease"),
        "平台收藏不在网盘里，不能被顺手删掉"
    );
    let local = storage.list_favorites().unwrap();
    assert!(
        !local.iter().any(|t| t.id == gone_key),
        "本地缓存要跟目录对齐"
    );
    assert!(
        !s3.get_object("TinyMusic/favorites.json").await.unwrap().is_some(),
        "迁移后不再留着 favorites.json"
    );

    // 2) 取消喜欢只删「喜欢」里的副本，歌单里的原文件不动
    library::remove_from_favorites(&s3, &copied)
        .await
        .expect("unfavorite");
    assert!(s3.get_object(&copied).await.unwrap().is_none());
    assert!(s3.get_object(&src_key).await.unwrap().is_some(), "原文件不能被删");
    assert!(s3.get_object(&src_lrc).await.unwrap().is_some());

    // 3) 再拉一次不会复活（迁移只跑一次）
    let again = library::pull_favorites(&s3, &storage).await.unwrap();
    assert!(!again.iter().any(|t| t.id == copied), "取消过的收藏不能复活");

    // 4) 歌单里删歌之后，喜欢里跟着少
    s3.delete_object(&kept_key).await.unwrap();
    let after = library::pull_favorites(&s3, &storage).await.unwrap();
    assert!(!after.iter().any(|t| t.id == kept_key));

    // 清理
    for key in [src_key, src_lrc, kept_key, copied] {
        let _ = s3.delete_object(&key).await;
    }
    let _ = s3.delete_object(&format!("{folder}Artist{suffix} - Song{suffix}.lrc")).await;
    let _ = std::fs::remove_dir_all(&dir);
}


/// 超过阈值必须走分片：反向代理把 client_max_body_size 卡在 50MB 时，
/// 整包 PUT 会被 413 挡掉，30MB 的曲子必须还能传上去。
///
/// 真机跑法：
/// S3_EP=... S3_BUCKET=... S3_AK=... S3_SK=... \
///   cargo test -p tinymusic-core --test s3_live multipart -- --ignored --nocapture
#[tokio::test]
#[ignore]
async fn s3_multipart_upload_roundtrip() {
    let s3 = client();
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let key = format!("TinyMusic/__multipart_test_{suffix}.bin");

    // 30MB ＞ 24MB 阈值：必定走分片；内容可校验，避免「传上去是空的」
    let size = 30 * 1024 * 1024;
    let body: Vec<u8> = (0..size).map(|i| (i % 251) as u8).collect();
    println!("UPLOAD {} bytes", body.len());
    s3.put_object(&key, body.clone(), "application/octet-stream")
        .await
        .expect("multipart put");

    let got = s3.get_object(&key).await.expect("get").expect("exists");
    println!("DOWNLOAD {} bytes", got.len());
    assert_eq!(got.len(), body.len(), "分片上传后大小应一致");
    assert!(got == body, "内容应逐字节一致");

    s3.delete_object(&key).await.expect("cleanup delete");
    println!("MULTIPART OK, cleanup done");
}
