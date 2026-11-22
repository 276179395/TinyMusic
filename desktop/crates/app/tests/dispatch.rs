//! dispatch 契约测试：不联网，只验命令名、参数反序列化与返回结构。

use std::sync::Arc;

use serde_json::json;
use tinymusic_app::{dispatch, local_music, AppState, NoopHost};

fn tmpdir(name: &str) -> std::path::PathBuf {
    std::env::temp_dir().join(format!("tm-test-{name}-{}", std::process::id()))
}

#[tokio::test]
async fn local_music_is_persisted_and_only_registered_files_are_playable() {
    let app = state("local-music").await;
    let dir = app.config_dir().to_owned();
    let audio = dir.join("本地测试.flac");
    let wave = b"RIFF\x26\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x80\x3e\x00\x00\x02\x00\x10\x00data\x02\x00\x00\x00\x00\x00";
    std::fs::write(&audio, wave).unwrap();
    std::fs::write(audio.with_extension("lrc"), "[00:01.50]测试歌词").unwrap();
    std::fs::write(audio.with_extension("png"), b"cover fixture").unwrap();
    let path = audio.to_str().unwrap().to_owned();

    let added = local_music::add(&app, vec![path.clone(), path]).unwrap();
    assert_eq!(added.len(), 1);
    assert_eq!(added[0].title, "本地测试");
    assert_eq!(added[0].id, "本地测试/本地测试.flac");
    let managed = dir.join("dl").join("Local").join(&added[0].id);
    assert_eq!(std::fs::read(&managed).unwrap(), wave);
    local_music::create_folder(&app, "通勤").unwrap();
    local_music::set_folder_track(&app, "通勤", &added[0].id, true).unwrap();
    let link = dir.join("dl/通勤/本地测试/track.json");
    let link: serde_json::Value = serde_json::from_slice(&std::fs::read(link).unwrap()).unwrap();
    assert_eq!(link["path"], "Local/本地测试/本地测试.flac");
    drop(app);

    let app = AppState::new(dir.clone(), dir.join("dl"), Arc::new(NoopHost))
        .await
        .unwrap();
    let list = dispatch::dispatch(&app, "local_music_list", json!({}), None, None)
        .await
        .unwrap();
    assert_eq!(list[0]["source"], "imported");
    let track = &list[0]["track"];
    assert_eq!(track["id"], added[0].id);
    let args = json!({"track": track, "quality": "standard", "allowLocal": false});
    let source = dispatch::dispatch(&app, "player_open", args.clone(), None, None)
        .await
        .unwrap();
    assert_eq!(source["via"], "local");
    assert_eq!(source["bytes"], wave.len());
    assert_eq!(source["format"]["codec"], "wav");
    assert_eq!(source["format"]["lossless"], true);
    let http = tinymusic_core::http::HttpClient::new(0, 4);
    let response = http
        .get_range(source["url"].as_str().unwrap(), Some("bytes=0-11"))
        .await
        .unwrap();
    assert_eq!(response.status().as_u16(), 206);
    assert_eq!(response.headers()["content-type"], "audio/wav");
    assert_eq!(response.bytes().await.unwrap().as_ref(), &wave[..12]);
    let detail = dispatch::dispatch(
        &app, "track_detail", json!({"provider": "local", "track": track}), None, None,
    )
    .await
    .unwrap();
    assert_eq!(detail["lyrics"][0]["text"], "测试歌词");
    assert!(detail["track"]["cover"].as_str().unwrap().starts_with("http://127.0.0.1:"));

    let copy = dir.join("Music Copy");
    std::fs::create_dir(&copy).unwrap();
    local_music::copy_library(&app, &copy).unwrap();
    assert!(managed.is_file());
    assert!(copy.join("通勤/本地测试/track.json").is_file());
    assert!(copy.join("Local").join(&added[0].id).is_file());

    local_music::create_folder(&app, "工作").unwrap();
    assert!(local_music::change_folder(&app, "通勤", Some("工作")).is_err());
    let folders = local_music::change_folder(&app, "通勤", Some("路上")).unwrap();
    assert_eq!(folders.iter().find(|folder| folder.id == "路上").unwrap().tracks.len(), 1);
    let folders = local_music::change_folder(&app, "路上", None).unwrap();
    assert_eq!(folders.iter().map(|folder| folder.id.as_str()).collect::<Vec<_>>(), ["喜欢", "工作"]);
    assert!(!copy.join("路上").exists());
    let archived = std::fs::read_dir(copy.join(".tinymusic-trash")).unwrap()
        .next().unwrap().unwrap().path();
    assert!(archived.join("路上/本地测试/track.json").is_file());
    assert!(copy.join("Local").join(&added[0].id).is_file());

    dispatch::dispatch(&app, "local_music_remove", json!({"id": track["id"]}), None, None)
        .await
        .unwrap();
    assert!(audio.is_file());
    assert!(dispatch::dispatch(&app, "player_open", args, None, None).await.is_err());
}

#[tokio::test]
async fn importing_a_folder_includes_nested_audio_and_preserves_sidecars() {
    let app = state("local-music-folder").await;
    let input = tempfile::tempdir_in(app.config_dir()).unwrap();
    let nested = input.path().join("子目录");
    std::fs::create_dir(&nested).unwrap();
    let mp3 = input.path().join("第一首.MP3");
    let flac = nested.join("第二首.flac");
    std::fs::write(&mp3, b"mp3").unwrap();
    std::fs::write(&flac, b"flac").unwrap();
    std::fs::write(flac.with_extension("lrc"), b"lyrics").unwrap();
    std::fs::write(flac.with_extension("png"), b"cover").unwrap();
    let empty = nested.join("非音频");
    std::fs::create_dir(&empty).unwrap();
    std::fs::write(empty.join("README.txt"), b"ignore").unwrap();

    let folder = input.path().to_str().unwrap().to_owned();
    let added = local_music::add(&app, vec![folder.clone(), mp3.to_str().unwrap().to_owned()])
        .unwrap();
    assert_eq!(added.len(), 2);
    let local = std::path::PathBuf::from(app.settings_snapshot().music_dir).join("Local");
    assert_eq!(std::fs::read(local.join("第一首/第一首.mp3")).unwrap(), b"mp3");
    let imported = local.join("第二首/第二首.flac");
    assert_eq!(std::fs::read(&imported).unwrap(), b"flac");
    assert_eq!(std::fs::read(imported.with_extension("lrc")).unwrap(), b"lyrics");
    assert_eq!(std::fs::read(imported.with_extension("png")).unwrap(), b"cover");
    assert!(mp3.is_file() && flac.is_file() && flac.with_extension("lrc").is_file());
    local_music::add(&app, vec![folder]).unwrap();
    assert_eq!(local_music::library(&app).unwrap().len(), 2);
    assert!(local_music::add(&app, vec![empty.to_str().unwrap().to_owned()]).unwrap().is_empty());
}

#[tokio::test]
async fn fixed_local_favorites_keep_local_links_and_cloud_references() {
    let app = state("local-favorites").await;
    let source = app.config_dir().join("song.mp3");
    std::fs::write(&source, b"audio").unwrap();
    let local = local_music::add(&app, vec![source.to_string_lossy().into_owned()])
        .unwrap()
        .remove(0);
    let cloud = tinymusic_core::model::Track {
        provider: "webdav".into(),
        id: "album/song.mp3".into(),
        title: "song".into(),
        ..Default::default()
    };

    let favorites = local_music::folders(&app).unwrap().remove(0);
    assert_eq!(favorites.name, "喜欢");
    assert!(favorites.tracks.is_empty());
    assert!(local_music::create_folder(&app, "喜欢").is_err());
    assert!(local_music::change_folder(&app, "喜欢", Some("Other")).is_err());
    assert!(local_music::change_folder(&app, "喜欢", None).is_err());

    local_music::set_favorite(&app, &local, true).unwrap();
    local_music::set_favorite(&app, &cloud, true).unwrap();
    let favorites = local_music::set_favorite(&app, &cloud, true).unwrap().remove(0);
    assert_eq!(favorites.tracks.len(), 2);
    assert_eq!(favorites.cloud_tracks[0].id, cloud.id);
    assert_eq!(local_music::library(&app).unwrap().len(), 1);

    local_music::set_favorite(&app, &local, false).unwrap();
    let favorites = local_music::set_favorite(&app, &cloud, false).unwrap().remove(0);
    assert!(favorites.tracks.is_empty());
    assert!(favorites.cloud_tracks.is_empty());
    assert_eq!(local_music::library(&app).unwrap().len(), 1);
}

#[tokio::test]
async fn legacy_music_and_folder_links_are_migrated_once() {
    let app = state("legacy-music").await;
    let audio = app.config_dir().join("老歌曲.wav");
    std::fs::write(&audio, b"legacy").unwrap();
    let id = audio.canonicalize().unwrap().to_string_lossy().into_owned();
    app.storage.add_local_music(&[id.clone()]).unwrap();
    let legacy = local_music::Folder {
        id: "old-folder".into(),
        name: "通勤".into(),
        tracks: vec![json!(["local", id]).to_string()],
        cloud_tracks: Vec::new(),
    };
    local_music::migrate(&app, vec![legacy.clone()], false).unwrap();
    local_music::migrate(&app, vec![legacy], false).unwrap();
    let root = std::path::PathBuf::from(app.settings_snapshot().music_dir);
    assert!(root.join("Local/老歌曲/老歌曲.wav").is_file());
    assert!(root.join("通勤/老歌曲/track.json").is_file());
    assert!(audio.is_file());
    assert_eq!(local_music::library(&app).unwrap().len(), 1);
}

#[tokio::test]
async fn clearing_playback_cache_only_removes_managed_files() {
    let app = state("clear-cache").await;
    let settings = app.settings_snapshot();
    let cache = std::path::Path::new(&settings.cache_dir).join("TinyMusic-playback-cache");
    std::fs::create_dir_all(&cache).unwrap();
    let name = format!("{}.flac", "a".repeat(64));
    let cached = cache.join(&name);
    let unrelated = cache.join("keep.txt");
    let download = std::path::Path::new(&settings.download_dir).join(name);
    for path in [&cached, &unrelated, &download] {
        std::fs::write(path, b"fixture").unwrap();
    }

    assert!(dispatch::dispatch(
        &app, "playback_cache_clear", json!({"cacheDir": "old-directory"}), None, None,
    ).await.is_err());
    assert!(cached.is_file());

    dispatch::dispatch(&app, "playback_cache_clear", json!({"cacheDir": settings.cache_dir}), None, None)
        .await
        .unwrap();

    assert!(!cached.exists());
    assert!(unrelated.is_file());
    assert!(download.is_file());
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

