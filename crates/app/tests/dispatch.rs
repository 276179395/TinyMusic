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
async fn providers_and_download_lists() {
    let st = state("providers").await;
    let v = dispatch::dispatch(&st, "get_providers", json!({}), None, None)
        .await
        .unwrap();
    let ids: Vec<String> = v.as_array().unwrap().iter().map(|p| p["id"].as_str().unwrap().to_string()).collect();
    assert!(ids.contains(&"kuwo".to_string()), "providers: {ids:?}");

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
    let err = dispatch::dispatch(&st, "search", json!({ "provider": "kuwo" }), None, None)
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
