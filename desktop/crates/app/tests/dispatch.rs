//! dispatch 契约测试：不联网，只验命令名、参数反序列化与返回结构。

use std::sync::Arc;

use serde_json::json;
use tinymusic_app::{dispatch, AppState, NoopHost};

fn tmpdir(name: &str) -> std::path::PathBuf {
    std::env::temp_dir().join(format!("tm-test-{name}-{}", std::process::id()))
}

async fn state(name: &str) -> Arc<AppState> {
    let dir = tmpdir(name);
    let _ = std::fs::remove_dir_all(&dir);
    AppState::new(dir.clone(), dir.join("dl"), Arc::new(NoopHost))
        .await
        .expect("装配后端失败")
}

#[tokio::test]
async fn settings_and_quality_are_shared() {
    let st = state("settings").await;
    let v = dispatch::dispatch(&st, "settings_get", json!({}), None, None)
        .await
        .unwrap();
    assert!(v["download_dir"].as_str().unwrap().ends_with("dl"), "默认下载目录应来自调用方: {v}");

    let caps = dispatch::dispatch(&st, "quality_capabilities", json!({}), None, None)
        .await
        .unwrap();
    let arr = caps.as_array().unwrap();
    assert!(arr.len() >= 3);
    assert!(arr.iter().any(|c| c["value"] == "lossless"));
}

#[tokio::test]
async fn download_lists_are_empty_on_first_launch() {
    let st = state("downloads").await;
    let list = dispatch::dispatch(&st, "download_list", json!({}), None, None)
        .await
        .unwrap();
    assert_eq!(list.as_array().unwrap().len(), 0);

    let failures = dispatch::dispatch(&st, "download_failures", json!({}), None, None)
        .await
        .unwrap();
    assert_eq!(failures.as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn bad_args_and_unknown_cmd_are_reported() {
    let st = state("errors").await;
    let err = dispatch::dispatch(&st, "track_detail", json!({}), None, None)
        .await
        .unwrap_err();
    assert!(err.contains("参数错误"), "{err}");

    let err = dispatch::dispatch(&st, "no_such_cmd", json!({}), None, None)
        .await
        .unwrap_err();
    assert!(err.contains("未知命令"), "{err}");

    let err = dispatch::dispatch(&st, "download_start", json!({ "track": null }), None, None)
        .await
        .unwrap_err();
    assert!(err.contains("参数错误") || err.contains("缺少进度回调"), "{err}");
}

#[tokio::test]
async fn favorite_check_recognises_same_song_under_liked_copy() {
    use tinymusic_core::model::Track;

    let st = state("favcheck").await;
    // 收藏存在「喜欢」目录里，id 是那边的副本 key：
    // 歌单里那首用原始 key 查不到，要按歌名 + 歌手认出来。
    st.storage
        .add_favorite(&Track {
            provider: "s3".into(),
            id: "TinyMusic/喜欢/Artist - Song.mp3".into(),
            title: "Song".into(),
            artist: "Artist".into(),
            ..Track::default()
        })
        .unwrap();

    let ok = dispatch::dispatch(
        &st,
        "favorite_check",
        json!({
            "provider": "s3",
            "id": "TinyMusic/Test/Artist - Song.mp3",
            "title": "Song",
            "artist": "Artist",
        }),
        None,
        None,
    )
    .await
    .unwrap();
    assert_eq!(ok, json!(true), "同一首歌不能因为 key 不同就显示成未收藏");

    let no = dispatch::dispatch(
        &st,
        "favorite_check",
        json!({
            "provider": "s3",
            "id": "TinyMusic/Test/Artist - Other.mp3",
            "title": "Other",
            "artist": "Artist",
        }),
        None,
        None,
    )
    .await
    .unwrap();
    assert_eq!(no, json!(false));
}

