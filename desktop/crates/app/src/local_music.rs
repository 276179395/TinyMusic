use super::*;
use std::collections::HashSet;
use std::io::{ErrorKind, Write};
use std::path::Component;

pub const PROVIDER: &str = "local";
const LOCAL: &str = "Local";
const LINK: &str = "track.json";
const HIDDEN: &str = ".tinymusic-hidden";
const MIGRATION: &str = "music-directory-v1";

#[derive(Serialize)]
pub struct Item {
    track: Track,
    source: &'static str,
}

#[derive(Clone, Deserialize, Serialize)]
pub struct Folder {
    pub id: String,
    pub name: String,
    pub tracks: Vec<String>,
}

#[derive(Deserialize, Serialize)]
struct Link {
    path: String,
}

fn io_error(error: std::io::Error) -> String {
    error.to_string()
}

fn real_dir(path: &Path) -> bool {
    path.symlink_metadata()
        .is_ok_and(|meta| meta.file_type().is_dir())
}

fn real_file(path: &Path) -> bool {
    path.symlink_metadata()
        .is_ok_and(|meta| meta.file_type().is_file())
}

fn root(state: &AppState) -> PathBuf {
    PathBuf::from(state.settings_snapshot().music_dir)
}

pub fn ensure_root(root: &Path) -> Result<PathBuf, String> {
    if !root.is_absolute() {
        return Err("音乐目录必须是绝对路径".into());
    }
    let local = root.join(LOCAL);
    std::fs::create_dir_all(&local).map_err(io_error)?;
    if !real_dir(&local) {
        return Err("Local 必须是实际目录".into());
    }
    Ok(local)
}

fn children(path: &Path) -> Result<Vec<PathBuf>, String> {
    match std::fs::read_dir(path) {
        Ok(entries) => entries
            .map(|entry| entry.map(|item| item.path()).map_err(io_error))
            .collect(),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(Vec::new()),
        Err(error) => Err(io_error(error)),
    }
}

fn folder_name(name: &str) -> bool {
    let base = name
        .split('.')
        .next()
        .unwrap_or_default()
        .to_ascii_uppercase();
    let reserved = matches!(base.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || (base.len() == 4
            && (base.starts_with("COM") || base.starts_with("LPT"))
            && base.as_bytes()[3].is_ascii_digit());
    !reserved
        && !name.starts_with('.')
        && !name.ends_with('.')
        && name == name.trim()
        && !name.is_empty()
        && !name.contains(['/', '\\', ':', '*', '?', '"', '<', '>', '|'])
        && !name.chars().any(char::is_control)
        && matches!(
            Path::new(name).components().next(),
            Some(Component::Normal(_))
        )
}

fn song_directory(local: &Path, stem: &str) -> Result<PathBuf, String> {
    let stem: String = stem.chars().take(64).collect();
    let stem = stem.trim().trim_end_matches('.');
    let stem = if folder_name(stem) {
        stem
    } else {
        "Music Track"
    };
    for index in 1.. {
        let name = if index == 1 {
            stem.to_owned()
        } else {
            format!("{stem} ({index})")
        };
        let path = local.join(name);
        match std::fs::create_dir(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == ErrorKind::AlreadyExists => {}
            Err(error) => return Err(io_error(error)),
        }
    }
    unreachable!()
}

pub(super) fn reserve_download(
    state: &AppState,
    track: &Track,
    ext: &str,
) -> Result<PathBuf, String> {
    let _guard = state.music_lock.lock().unwrap();
    let local = ensure_root(&root(state))?;
    let filename = build_filename(track, ext);
    let stem = Path::new(&filename)
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("Track");
    let dir = song_directory(&local, stem)?;
    let safe_stem = dir.file_name().unwrap().to_string_lossy();
    Ok(dir.join(format!("{safe_stem}.{ext}")))
}

fn relative(id: &str) -> Option<(&str, &str)> {
    let (song, filename) = id.split_once('/')?;
    (folder_name(song) && folder_name(filename) && is_audio_key(filename))
        .then_some((song, filename))
}

fn audio_path(local: &Path, id: &str) -> Option<PathBuf> {
    let (song, filename) = relative(id)?;
    let dir = local.join(song);
    let audio = dir.join(filename);
    (real_dir(local) && real_dir(&dir) && !dir.join(HIDDEN).exists() && real_file(&audio))
        .then_some(audio)
}

pub(super) fn resolve_download(state: &AppState, stored: &str) -> String {
    if stored.is_empty() || stored.starts_with("s3://") || Path::new(stored).is_file() {
        return stored.to_owned();
    }
    let path = Path::new(stored);
    if let (Some(filename), Some(song)) = (path.file_name(), path.parent()) {
        if song
            .parent()
            .and_then(Path::file_name)
            .is_some_and(|name| name == LOCAL)
        {
            if let Some(song) = song.file_name() {
                let candidate = root(state).join(LOCAL).join(song).join(filename);
                if candidate.is_file() {
                    return candidate.to_string_lossy().into_owned();
                }
            }
        }
    }
    resolve_download_path(stored, Path::new(&state.settings_snapshot().download_dir))
}

fn import_key(local: &Path, source: &Path) -> String {
    use sha2::{Digest, Sha256};
    let key = serde_json::json!([local.to_string_lossy(), source.to_string_lossy()]);
    format!("music-import:{:x}", Sha256::digest(key.to_string()))
}

fn managed_id(local: &Path, source: &Path) -> Option<String> {
    let local = local.canonicalize().ok()?;
    let relative_path = source.strip_prefix(&local).ok()?;
    let mut parts = relative_path.iter();
    let id = format!("{}/{}", parts.next()?.to_str()?, parts.next()?.to_str()?);
    if parts.next().is_some() {
        return None;
    }
    relative(&id)?;
    Some(id)
}

fn copy_song(
    state: &AppState,
    local: &Path,
    source: &Path,
    title: Option<&str>,
) -> Result<String, String> {
    let source = source.canonicalize().map_err(io_error)?;
    let name = source
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or("无效的音频文件名")?;
    if !real_file(&source) || !is_audio_key(name) {
        return Err(format!("不支持的本地音频文件：{}", source.display()));
    }
    if let Some(id) = managed_id(local, &source) {
        let marker = source.with_file_name(HIDDEN);
        if real_file(&marker) {
            std::fs::remove_file(marker).map_err(io_error)?;
        }
        return Ok(id);
    }
    let key = import_key(local, &source);
    if let Some(id) = state.storage.meta_get(&key) {
        if let Some((song, filename)) = relative(&id) {
            let dir = local.join(song);
            if real_dir(&dir) && real_file(&dir.join(filename)) {
                let marker = dir.join(HIDDEN);
                if real_file(&marker) {
                    std::fs::remove_file(marker).map_err(io_error)?;
                }
                return Ok(id);
            }
        }
    }

    let stem = title
        .or_else(|| source.file_stem().and_then(|stem| stem.to_str()))
        .unwrap_or("Track");
    let stem = tinymusic_core::download::sanitize_filename(stem);
    let ext = name.rsplit_once('.').unwrap().1.to_ascii_lowercase();
    let dir = song_directory(local, &stem)?;
    let song = dir.file_name().unwrap().to_str().unwrap();
    let filename = format!("{song}.{ext}");
    let result = (|| {
        for ext in ["lrc", "jpg", "jpeg", "png", "webp"] {
            let sidecar = source.with_extension(ext);
            if real_file(&sidecar) {
                std::fs::copy(sidecar, dir.join(format!("{song}.{ext}")))?;
            }
        }
        let audio = dir.join(&filename);
        let mut temp = tempfile::NamedTempFile::new_in(&dir)?;
        std::io::copy(&mut std::fs::File::open(&source)?, &mut temp)?;
        temp.persist_noclobber(audio).map_err(|error| error.error)?;
        Ok::<(), std::io::Error>(())
    })();
    if let Err(error) = result {
        for ext in ["lrc", "jpg", "jpeg", "png", "webp"] {
            let _ = std::fs::remove_file(dir.join(format!("{song}.{ext}")));
        }
        let _ = std::fs::remove_dir(&dir);
        return Err(io_error(error));
    }
    let id = format!("{song}/{filename}");
    state
        .storage
        .meta_set(&key, &id)
        .map_err(|err| err.to_string())?;
    Ok(id)
}

fn folder_audio_files(folder: PathBuf) -> Result<Vec<PathBuf>, String> {
    let mut folders = vec![folder];
    let mut files = Vec::new();
    while let Some(folder) = folders.pop() {
        for entry in std::fs::read_dir(folder).map_err(io_error)? {
            let entry = entry.map_err(io_error)?;
            let kind = entry.file_type().map_err(io_error)?;
            if kind.is_dir() {
                folders.push(entry.path());
            } else if kind.is_file() && entry.file_name().to_str().is_some_and(is_audio_key) {
                files.push(entry.path());
            }
        }
    }
    files.sort_unstable();
    Ok(files)
}

pub fn add(state: &AppState, paths: Vec<String>) -> Result<Vec<Track>, String> {
    let _guard = state.music_lock.lock().unwrap();
    let local = ensure_root(&root(state))?;
    let mut sources = Vec::new();
    for path in paths {
        let source = Path::new(&path).canonicalize().map_err(io_error)?;
        if real_dir(&source) {
            sources.extend(folder_audio_files(source)?);
        } else {
            sources.push(source);
        }
    }
    let mut added = HashSet::new();
    let mut tracks = Vec::new();
    for source in sources {
        let id = copy_song(state, &local, &source, None)?;
        if added.insert(id.clone()) {
            tracks.push(song_track(id));
        }
    }
    Ok(tracks)
}

fn song_track(id: String) -> Track {
    let title = id
        .split_once('/')
        .map_or(id.as_str(), |(song, _)| song)
        .to_owned();
    Track {
        provider: PROVIDER.into(),
        id,
        title,
        ..Track::default()
    }
}

pub fn library(state: &AppState) -> Result<Vec<Item>, String> {
    let local = root(state).join(LOCAL);
    if !real_dir(&local) {
        return Ok(Vec::new());
    }
    let downloads: std::collections::HashSet<_> = state
        .storage
        .list_downloads()
        .map_err(|err| err.to_string())?
        .into_iter()
        .filter(|row| row.status == "done")
        .filter_map(|row| {
            managed_id(
                &local,
                &PathBuf::from(resolve_download(state, &row.path))
                    .canonicalize()
                    .ok()?,
            )
        })
        .collect();
    let mut items = Vec::new();
    for dir in children(&local)? {
        if !real_dir(&dir) || dir.join(HIDDEN).exists() {
            continue;
        }
        let Some(song) = dir.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        let mut files = children(&dir)?;
        files.sort();
        for file in files {
            let Some(filename) = file.file_name().and_then(|name| name.to_str()) else {
                continue;
            };
            let id = format!("{song}/{filename}");
            if relative(&id).is_some() && real_file(&file) {
                let source = if downloads.contains(&id) {
                    "download"
                } else {
                    "imported"
                };
                items.push(Item {
                    track: song_track(id),
                    source,
                });
                break;
            }
        }
    }
    items.sort_by(|a, b| a.track.title.cmp(&b.track.title));
    Ok(items)
}

pub fn remove(state: &AppState, id: &str) -> Result<(), String> {
    let _guard = state.music_lock.lock().unwrap();
    let path = audio_path(&root(state).join(LOCAL), id).ok_or("本地歌曲不存在")?;
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path.with_file_name(HIDDEN))
        .map_err(io_error)?;
    Ok(())
}

pub(super) fn path(state: &AppState, id: &str) -> Result<PathBuf, String> {
    let local = root(state).join(LOCAL);
    if let Some(path) = audio_path(&local, id) {
        return Ok(path);
    }
    // 恢复旧版本播放队列时，经过迁移映射读取已入库的副本。
    if state
        .storage
        .has_local_music(id)
        .map_err(|err| err.to_string())?
    {
        if let Ok(source) = Path::new(id).canonicalize() {
            if let Some(mapped) = state.storage.meta_get(&import_key(&local, &source)) {
                return audio_path(&local, &mapped).ok_or_else(|| "找不到已入库的本地歌曲".into());
            }
            if real_file(&source) {
                return Ok(source);
            }
        }
    }
    Err(format!("找不到本地音频文件：{id}"))
}

fn folder_path(root: &Path, id: &str) -> Result<PathBuf, String> {
    if !folder_name(id) || id.eq_ignore_ascii_case(LOCAL) {
        return Err("收藏夹名称不可用".into());
    }
    Ok(root.join(id))
}

pub fn folders(state: &AppState) -> Result<Vec<Folder>, String> {
    let root = root(state);
    let mut folders = Vec::new();
    for dir in children(&root)? {
        let Some(name) = dir.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if folder_path(&root, name).is_err() || !real_dir(&dir) {
            continue;
        }
        let mut tracks = Vec::new();
        for entry in children(&dir)? {
            let link = entry.join(LINK);
            if !real_dir(&entry) || !real_file(&link) {
                continue;
            }
            if let Some(id) = std::fs::read(&link)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Link>(&bytes).ok())
                .and_then(|link| link.path.strip_prefix("Local/").map(str::to_owned))
                .filter(|id| relative(id).is_some())
            {
                tracks.push(serde_json::json!([PROVIDER, id]).to_string());
            }
        }
        folders.push(Folder {
            id: name.into(),
            name: name.into(),
            tracks,
        });
    }
    folders.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(folders)
}

pub fn create_folder(state: &AppState, name: &str) -> Result<Vec<Folder>, String> {
    let _guard = state.music_lock.lock().unwrap();
    let root = root(state);
    ensure_root(&root)?;
    let dir = folder_path(&root, name)?;
    std::fs::create_dir(&dir).map_err(io_error)?;
    folders(state)
}

fn write_link(root: &Path, folder: &str, id: &str, included: bool) -> Result<(), String> {
    let (song, _) = relative(id).ok_or("无效的本地歌曲路径")?;
    let folder = folder_path(root, folder)?;
    if !real_dir(&folder) {
        return Err("收藏夹不存在".into());
    }
    let entry = folder.join(song);
    let link = entry.join(LINK);
    if included {
        if audio_path(&root.join(LOCAL), id).is_none() {
            return Err("本地歌曲不存在".into());
        }
        match std::fs::create_dir(&entry) {
            Ok(()) => {}
            Err(err) if err.kind() == ErrorKind::AlreadyExists && real_dir(&entry) => {}
            Err(err) => return Err(io_error(err)),
        }
        let path = format!("Local/{id}");
        if real_file(&link)
            && std::fs::read(&link)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Link>(&bytes).ok())
                .is_some_and(|existing| existing.path == path)
        {
            return Ok(());
        }
        let mut temp = tempfile::NamedTempFile::new_in(&entry).map_err(io_error)?;
        serde_json::to_writer_pretty(&mut temp, &Link { path }).map_err(|err| err.to_string())?;
        temp.write_all(b"\n").map_err(io_error)?;
        temp.persist_noclobber(link)
            .map_err(|err| io_error(err.error))?;
    } else if real_dir(&entry) && real_file(&link) {
        std::fs::remove_file(link).map_err(io_error)?;
        let _ = std::fs::remove_dir(entry);
    }
    Ok(())
}

pub fn set_folder_track(
    state: &AppState,
    folder: &str,
    id: &str,
    included: bool,
) -> Result<Vec<Folder>, String> {
    let _guard = state.music_lock.lock().unwrap();
    let root = root(state);
    write_link(&root, folder, id, included)?;
    folders(state)
}

fn copy_tree(source: &Path, target: &Path) -> Result<(), String> {
    std::fs::create_dir(target).map_err(io_error)?;
    for path in children(source)? {
        let name = path.file_name().unwrap();
        if name.to_string_lossy().starts_with('.') && name != HIDDEN {
            continue;
        }
        let dest = target.join(name);
        if real_dir(&path) {
            copy_tree(&path, &dest)?;
        } else if real_file(&path) {
            std::fs::copy(path, dest).map_err(io_error)?;
        }
    }
    Ok(())
}

pub fn copy_library(state: &AppState, destination: &Path) -> Result<String, String> {
    let _guard = state.music_lock.lock().unwrap();
    let source = root(state).canonicalize().map_err(io_error)?;
    if !real_dir(destination) || !children(destination)?.is_empty() {
        return Err("请选择一个空的音乐库目录".into());
    }
    let selected = destination.to_string_lossy().into_owned();
    let destination = destination.canonicalize().map_err(io_error)?;
    if destination.starts_with(&source) || source.starts_with(&destination) {
        return Err("新旧音乐库目录不能互相包含".into());
    }
    let parent = destination.parent().ok_or("不能使用卷根目录")?;
    let stage = tempfile::tempdir_in(parent).map_err(io_error)?;
    for dir in children(&source)? {
        let Some(name) = dir.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if folder_name(name) && real_dir(&dir) {
            copy_tree(&dir, &stage.path().join(name))?;
        }
    }
    ensure_root(stage.path())?;
    std::fs::remove_dir(&destination).map_err(io_error)?;
    if let Err(error) = std::fs::rename(stage.path(), &destination) {
        let _ = std::fs::create_dir(&destination);
        return Err(io_error(error));
    }
    for row in state
        .storage
        .list_downloads()
        .map_err(|err| err.to_string())?
    {
        let Ok(path) = PathBuf::from(row.path).canonicalize() else {
            continue;
        };
        if let Ok(relative) = path.strip_prefix(source.join(LOCAL)) {
            let copy = Path::new(&selected).join(LOCAL).join(relative);
            if copy.is_file() {
                state
                    .storage
                    .update_download_path(&row.task_id, &copy.to_string_lossy())
                    .map_err(|err| err.to_string())?;
            }
        }
    }
    let mut settings = state.settings.lock().unwrap();
    settings.music_dir.clone_from(&selected);
    save_settings(&state.config_dir, &settings);
    Ok(selected)
}

pub fn migrate(
    state: &AppState,
    legacy: Vec<Folder>,
    development: bool,
) -> Result<Vec<Folder>, String> {
    let _guard = state.music_lock.lock().unwrap();
    let root = root(state);
    let local = ensure_root(&root)?;
    let marker = if development {
        "music-directory-v1-dev"
    } else {
        MIGRATION
    };
    if state.storage.meta_get(marker).is_some() {
        return folders(state);
    }
    let mut mapped = std::collections::HashMap::new();
    for path in state
        .storage
        .list_local_music()
        .map_err(|err| err.to_string())?
    {
        if Path::new(&path).is_file() {
            let id = copy_song(state, &local, Path::new(&path), None)?;
            mapped.insert((PROVIDER.to_owned(), path), id);
        }
    }
    let settings = state.settings_snapshot();
    for row in state
        .storage
        .list_downloads()
        .map_err(|err| err.to_string())?
    {
        if row.status != "done" || row.path.starts_with("s3://") {
            continue;
        }
        let path = resolve_download_path(&row.path, Path::new(&settings.download_dir));
        if is_audio_key(&path) && Path::new(&path).is_file() {
            let id = copy_song(state, &local, Path::new(&path), None)?;
            if !development {
                let path = local.join(&id);
                state
                    .storage
                    .update_download_path(&row.task_id, &path.to_string_lossy())
                    .map_err(|err| err.to_string())?;
            }
            mapped.entry((row.provider, row.id)).or_insert(id);
        }
    }
    for folder in legacy {
        let name = folder.name.trim();
        let valid_name = if folder_path(&root, name).is_ok() {
            name.to_owned()
        } else {
            format!(
                "收藏夹 {}",
                folder
                    .id
                    .chars()
                    .filter(char::is_ascii_alphanumeric)
                    .take(12)
                    .collect::<String>()
            )
        };
        let dir = folder_path(&root, &valid_name)?;
        match std::fs::create_dir(&dir) {
            Ok(()) => {}
            Err(err) if err.kind() == ErrorKind::AlreadyExists && real_dir(&dir) => {}
            Err(err) => return Err(io_error(err)),
        }
        for key in folder.tracks {
            let Ok(key) = serde_json::from_str::<(String, String)>(&key) else {
                continue;
            };
            if let Some(id) = mapped.get(&key) {
                write_link(&root, &valid_name, id, true)?;
            } else if let Some(cached) = playback_cache::cached_audio(state, &key.0, &key.1) {
                let title = key
                    .1
                    .rsplit('/')
                    .next()
                    .and_then(|name| name.rsplit_once('.'))
                    .map(|(name, _)| name);
                let id = copy_song(state, &local, &cached, title)?;
                write_link(&root, &valid_name, &id, true)?;
            }
        }
    }
    state
        .storage
        .meta_set(marker, "1")
        .map_err(|err| err.to_string())?;
    folders(state)
}

pub(super) async fn open(
    state: &AppState,
    id: &str,
    requested: Quality,
) -> Result<PlayerSource, String> {
    open_audio_file(state, path(state, id)?, requested, PROVIDER).await
}
