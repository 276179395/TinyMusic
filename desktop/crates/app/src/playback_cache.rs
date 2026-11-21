use std::collections::HashMap;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use sha2::{Digest, Sha256};
use tokio::sync::{watch, Mutex as AsyncMutex};

use crate::{
    cloud_client_for_settings, download_cloud_sidecars, is_audio_key, local_download, AppState,
    Settings, Track,
};

const DIRECTORY: &str = "TinyMusic-playback-cache";
const EXTENSIONS: &[&str] = &[
    "flac", "mp3", "m4a", "aac", "ogg", "wav", "lrc", "jpg", "jpeg", "png", "webp", "json",
];

pub(crate) struct PlaybackCache {
    worker: AsyncMutex<()>,
    jobs: Mutex<HashMap<PathBuf, watch::Receiver<()>>>,
    manual: Mutex<Vec<PathBuf>>,
    generation: watch::Sender<u64>,
}

impl Default for PlaybackCache {
    fn default() -> Self {
        Self {
            worker: AsyncMutex::new(()),
            jobs: Mutex::new(HashMap::new()),
            manual: Mutex::new(Vec::new()),
            generation: watch::channel(0).0,
        }
    }
}

pub(crate) struct ManualDownload<'a> {
    paths: &'a Mutex<Vec<PathBuf>>,
    path: PathBuf,
}

impl Drop for ManualDownload<'_> {
    fn drop(&mut self) {
        let mut paths = self.paths.lock().unwrap();
        if let Some(index) = paths.iter().position(|path| path == &self.path) {
            paths.swap_remove(index);
        }
    }
}

pub(crate) fn manual_download<'a>(
    state: &'a AppState,
    track: &Track,
) -> Option<ManualDownload<'a>> {
    let path = path(&state.settings_snapshot(), &track.provider, &track.id)?;
    let paths = &state.playback_cache.manual;
    paths.lock().unwrap().push(path.clone());
    Some(ManualDownload { paths, path })
}

fn directory(settings: &Settings) -> PathBuf {
    Path::new(&settings.cache_dir).join(DIRECTORY)
}

pub(crate) fn default_dir(config_dir: &Path) -> String {
    std::path::absolute(config_dir)
        .unwrap_or_else(|_| config_dir.to_owned())
        .join("cache")
        .to_string_lossy()
        .into_owned()
}

fn path(settings: &Settings, provider: &str, key: &str) -> Option<PathBuf> {
    if !is_audio_key(key) || !Path::new(&settings.cache_dir).is_absolute() {
        return None;
    }
    let identity = match provider {
        "webdav" => serde_json::json!([
            provider,
            settings.webdav_endpoint.trim().trim_end_matches('/'),
            settings.webdav_root.trim().trim_matches('/'),
            settings.webdav_username,
            key
        ]),
        "s3" => serde_json::json!([
            provider,
            settings.s3_endpoint.trim().trim_end_matches('/'),
            settings.s3_region.trim(),
            settings.s3_bucket.trim(),
            settings.s3_access_key.trim(),
            key
        ]),
        _ => return None,
    };
    let ext = key.rsplit_once('.')?.1.to_ascii_lowercase();
    let digest = Sha256::digest(identity.to_string().as_bytes());
    Some(directory(settings).join(format!("{digest:x}.{ext}")))
}

fn regular_file(path: &Path) -> bool {
    path.symlink_metadata()
        .is_ok_and(|meta| meta.file_type().is_file() && meta.len() != 0)
}

pub(crate) fn cached_audio(state: &AppState, provider: &str, key: &str) -> Option<PathBuf> {
    let path = path(&state.settings_snapshot(), provider, key)?;
    let parent = path.parent()?;
    checked_directory(parent).ok().filter(|exists| *exists)?;
    regular_file(&path).then_some(path)
}

// The app owns a child of the selected directory. Refuse redirected managed directories.
fn checked_directory(dir: &Path) -> std::io::Result<bool> {
    let metadata = match dir.symlink_metadata() {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error),
    };
    if !metadata.file_type().is_dir()
        || dir.canonicalize()? != dir.parent().unwrap().canonicalize()?.join(DIRECTORY)
    {
        return Err(std::io::Error::other("缓存子目录不能是链接或普通文件"));
    }
    Ok(true)
}

pub(crate) async fn wait_for_audio(state: &AppState, track: &Track) -> Option<PathBuf> {
    let path = path(&state.settings_snapshot(), &track.provider, &track.id)?;
    let pending = state
        .playback_cache
        .jobs
        .lock()
        .unwrap()
        .get(&path)
        .cloned();
    if let Some(mut pending) = pending {
        let _ = pending.changed().await;
    }
    cached_audio(state, &track.provider, &track.id)
}

pub(crate) fn queue(state: &AppState, track: Track) {
    if local_download(state, &track.provider, &track.id).is_some() {
        return;
    }
    let settings = state.settings_snapshot();
    let Some(path) = path(&settings, &track.provider, &track.id) else {
        return;
    };
    if state.playback_cache.manual.lock().unwrap().contains(&path) {
        return;
    }
    let mut generation = state.playback_cache.generation.subscribe();
    let (completed, receiver) = watch::channel(());
    {
        let mut jobs = state.playback_cache.jobs.lock().unwrap();
        if jobs.contains_key(&path) {
            return;
        }
        jobs.insert(path.clone(), receiver);
    }
    let state = state.strong();
    tokio::spawn(async move {
        let cache = &state.playback_cache;
        let _worker = cache.worker.lock().await;
        if !generation.has_changed().unwrap_or(true) {
            tokio::select! {
                biased;
                _ = generation.changed() => {},
                _ = fill(&state, settings, &track, &path) => {},
            }
        }
        cache.jobs.lock().unwrap().remove(&path);
        drop(completed);
    });
}

async fn fill(
    state: &AppState,
    settings: Settings,
    track: &Track,
    path: &Path,
) -> Result<(), String> {
    if local_download(state, &track.provider, &track.id).is_some()
        || state
            .playback_cache
            .manual
            .lock()
            .unwrap()
            .iter()
            .any(|item| item == path)
    {
        return Ok(());
    }
    let client = cloud_client_for_settings(state, settings)?;
    if client.provider() != track.provider {
        return Ok(());
    }
    let dir = path.parent().unwrap();
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    checked_directory(dir).map_err(|e| e.to_string())?;
    if !regular_file(path) {
        client
            .download_object(&track.id, path, true, Box::new(|_, _| {}))
            .await
            .map_err(|e| e.to_string())?;
        download_cloud_sidecars(&client, &track.id, path).await;
    }
    Ok(())
}

pub(crate) async fn clear(state: &AppState, expected_dir: Option<&str>) -> Result<(), String> {
    let settings = state.settings_snapshot();
    if expected_dir.is_some_and(|dir| dir != settings.cache_dir) {
        return Err("缓存目录已改变，请重新确认".into());
    }
    if !Path::new(&settings.cache_dir).is_absolute() {
        return Err("缓存目录必须是绝对路径".into());
    }
    let dir = directory(&settings);
    let downloads = Path::new(&settings.download_dir);
    if downloads == dir
        || downloads.canonicalize().ok().is_some_and(|downloads| {
            dir.canonicalize()
                .is_ok_and(|directory| downloads == directory)
        })
    {
        return Err("请将下载目录和播放缓存目录分开".into());
    }
    state
        .playback_cache
        .generation
        .send_modify(|generation| *generation = generation.wrapping_add(1));
    let _worker = state.playback_cache.worker.lock().await;
    if !checked_directory(&dir).map_err(|e| e.to_string())? {
        return Ok(());
    }
    let mut entries = tokio::fs::read_dir(&dir).await.map_err(|e| e.to_string())?;
    let mut failure = None;
    while let Some(entry) = entries.next_entry().await.map_err(|e| e.to_string())? {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        let managed = name.rsplit_once('.').is_some_and(|(stem, ext)| {
            (stem.len() == 64
                && stem.bytes().all(|c| c.is_ascii_hexdigit())
                && EXTENSIONS.contains(&ext))
                || (stem.starts_with(".tinymusic-") && ext == "part")
        });
        if managed
            && entry
                .file_type()
                .await
                .map_err(|e| e.to_string())?
                .is_file()
        {
            if let Err(error) = tokio::fs::remove_file(entry.path()).await {
                failure = Some(error.to_string());
            }
        }
    }
    failure.map_or(Ok(()), Err)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn playback_cache_stays_outside_music_library() {
        let dir = tempfile::tempdir().unwrap();
        let app = AppState::new(
            dir.path().join("config"), dir.path().join("Music"), std::sync::Arc::new(crate::NoopHost),
        ).await.unwrap();
        let settings = app.settings_snapshot();
        let track = Track {
            provider: "webdav".into(),
            id: "音乐/测试.wav".into(),
            title: "测试".into(),
            ..Track::default()
        };
        let cache = path(&settings, &track.provider, &track.id).unwrap();
        std::fs::create_dir_all(cache.parent().unwrap()).unwrap();
        std::fs::write(&cache, b"cached audio").unwrap();
        assert!(crate::local_music::library(&app).unwrap().is_empty());

        let download = crate::local_music::reserve_download(&app, &track, "wav").unwrap();
        std::fs::write(&download, b"downloaded audio").unwrap();
        app.storage.insert_download(
            "download", &track, crate::Quality::Lossless, download.to_str().unwrap(), 16, "done",
        ).unwrap();
        let items = serde_json::to_value(crate::local_music::library(&app).unwrap()).unwrap();
        assert_eq!(items.as_array().unwrap().len(), 1);
        assert_eq!(items[0]["source"], "download");

        clear(&app, Some(&settings.cache_dir)).await.unwrap();
        assert!(!cache.exists());
        assert!(download.is_file());
    }
}
