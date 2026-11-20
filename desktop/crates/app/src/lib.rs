//! TinyMusic 业务层：AppState + 全部命令实现。
//!
//! 桌面（Tauri IPC）与 mobile（本地 HTTP）都只调这里，保证同样的命令只有一份实现。

use std::collections::HashMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};

use tinymusic_core::download::{build_filename, build_lrc, DownloadExtras, Downloader};
use tinymusic_core::http::HttpClient;
use tinymusic_core::id3;
use tinymusic_core::model::*;
use tinymusic_core::cloud::CloudLibrary;
use tinymusic_core::webdav::WebDav;
use tinymusic_core::proxy::StreamProxy;
use tinymusic_core::s3::{S3Config, S3};
use tinymusic_core::storage::{DownloadRow, FailedDownload, FailedPart, Storage};

pub mod dispatch;

/// 进度回调：桌面由 Tauri Channel 包一层，mobile 写入轮询登记表
pub type ProgressFn = Arc<dyn Fn(Progress) + Send + Sync>;
pub type S3FixFn = Arc<dyn Fn(S3FixProgress) + Send + Sync>;

/// 宿主事件出口（下载失败通知等）
pub trait Host: Send + Sync {
    fn failed(&self, failures: &[FailedDownload]);
}

/// 根目录散歌在网盘页里的伪歌单名（不是真实目录，保留名不可用来建歌单）
pub const ROOT_PLAYLIST_LABEL: &str = "未分类";

/// 不需要事件出口的宿主（测试、server 的兜底实现）
pub struct NoopHost;

impl Host for NoopHost {
    fn failed(&self, _failures: &[FailedDownload]) {}
}

#[allow(unused_imports)]
use tinymusic_core::Error as CoreError;

// ---------- 设置 ----------


#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub download_dir: String,
    pub default_quality: String,
    /// 配置结构版本：用于一次性迁移旧的 high 档语义
    #[serde(default = "default_settings_version")]
    pub settings_version: u32,
    #[serde(default = "default_concurrency")]
    pub concurrency: u32,

    // ---- 网盘（S3 兼容）----
    #[serde(default)]
    pub s3_enabled: bool,
    #[serde(default)]
    pub s3_endpoint: String,
    #[serde(default = "default_region")]
    pub s3_region: String,
    #[serde(default)]
    pub s3_bucket: String,
    #[serde(default)]
    pub s3_access_key: String,
    #[serde(default)]
    pub s3_secret_key: String,
    #[serde(default = "default_s3_prefix")]
    pub s3_prefix: String,
    #[serde(default)]
    pub s3_path_style: bool,

    #[serde(default)]
    pub webdav_enabled: bool,
    #[serde(default)]
    pub webdav_endpoint: String,
    #[serde(default = "default_webdav_root")]
    pub webdav_root: String,
    #[serde(default)]
    pub webdav_username: String,
    #[serde(default)]
    pub webdav_password: String,

    // ---- 窗口 / 托盘 ----
    #[serde(default = "default_true")]
    pub close_to_tray: bool,

    // ---- 均衡器 ----
    /// 是否启用（桌面与 mobile 共用同一份设置）
    #[serde(default)]
    pub eq_enabled: bool,
    /// 10 段增益（dB），长度固定 10；缺省用全 0
    #[serde(default)]
    pub eq_gains: Vec<f32>,
    /// 预增益（dB）
    #[serde(default)]
    pub eq_preamp: f32,

}

pub fn default_webdav_root() -> String {
    "TinyMusic".into()
}

pub fn default_concurrency() -> u32 {
    2
}


pub fn default_settings_version() -> u32 {
    1
}


pub fn default_region() -> String {
    "us-east-1".into()
}


pub fn default_s3_prefix() -> String {
    "TinyMusic".into()
}


pub fn default_true() -> bool {
    true
}


impl Default for Settings {
    fn default() -> Self {
        Self {
            download_dir: dirs_download(),
            default_quality: "super".into(),
            settings_version: 2,
            concurrency: 2,
            s3_enabled: false,
            s3_endpoint: String::new(),
            s3_region: default_region(),
            s3_bucket: String::new(),
            s3_access_key: String::new(),
            s3_secret_key: String::new(),
            s3_prefix: default_s3_prefix(),
            s3_path_style: false,
            webdav_enabled: false,
            webdav_endpoint: String::new(),
            webdav_root: default_webdav_root(),
            webdav_username: String::new(),
            webdav_password: String::new(),
            close_to_tray: true,
            eq_enabled: false,
            eq_gains: vec![0.0; 10],
            eq_preamp: 0.0,
        }
    }
}


/// 把旧沙盒容器的绝对路径改写到当前容器。
///
/// 只有在两端都落在 `/Documents/` 之下时才改写（iOS 特征）；
/// 桌面默认目录是 ~/Music/TinyMusic，不会命中，行为不变。
pub fn rebase_sandbox_path(stored: &str, current_default: &str) -> String {
    const MARK: &str = "/Documents/";
    let Some((_, tail_stored)) = stored.split_once(MARK) else {
        return stored.to_string();
    };
    let Some((head_current, _)) = current_default.split_once(MARK) else {
        return stored.to_string();
    };
    let rebased = format!("{}{}{}", head_current, MARK, tail_stored);
    if rebased != stored {
        return rebased;
    }
    stored.to_string()
}


pub fn dirs_download() -> String {
    let base = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .unwrap_or_else(|_| ".".into());
    PathBuf::from(base)
        .join("Music")
        .join("TinyMusic")
        .to_string_lossy()
        .to_string()
}

// ---------- 应用状态 ----------


pub struct AppState {
    pub http: Arc<HttpClient>,
    pub providers: Vec<Arc<dyn MusicProvider>>,
    pub proxy: StreamProxy,
    pub storage: Arc<Storage>,
    pub downloader: Arc<Downloader>,
    pub settings: Mutex<Settings>,
    pub config_dir: PathBuf,
    pub task_seq: AtomicU64,
    /// 事件出口：桌面走 Tauri emit，mobile 走进度/失败队列
    pub host: Arc<dyn Host>,
    /// 装配时写入的自引用，后台任务用它拿到 Arc<AppState>
    pub me: std::sync::OnceLock<std::sync::Weak<AppState>>,
}


impl AppState {
    pub fn provider(&self, id: &str) -> Result<Arc<dyn MusicProvider>, String> {
        self.providers
            .iter()
            .find(|p| p.id() == id)
            .cloned()
            .ok_or_else(|| format!("未知平台: {}", id))
    }

    pub fn settings_snapshot(&self) -> Settings {
        self.settings.lock().map(|s| s.clone()).unwrap_or_default()
    }
}


pub fn normalize_settings(s: &mut Settings) -> bool {
    let mut changed = false;
    if s.settings_version < 2 {
        // 旧版的 high 实际就是 128k；不迁移的话会被当成“高品质”显示错。
        if s.default_quality == "high" {
            s.default_quality = "standard".into();
        }
        s.settings_version = 2;
        changed = true;
    }
    match Quality::parse(&s.default_quality) {
        None => {
            s.default_quality = "super".into();
            changed = true;
        }
        Some(q) if q.is_advanced() => {
            // 旧配置/手改配置里的高级档当前不可播，回退到 320k
            s.default_quality = "super".into();
            changed = true;
        }
        Some(_) => {}
    }
    changed
}


pub fn load_settings(dir: &std::path::Path) -> Settings {
    let p = dir.join("settings.json");
    let mut s = std::fs::read_to_string(p)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    if normalize_settings(&mut s) {
        save_settings(dir, &s);
    }
    s
}


pub fn save_settings(dir: &std::path::Path, s: &Settings) {
    if let Ok(txt) = serde_json::to_string_pretty(s) {
        let _ = std::fs::write(dir.join("settings.json"), txt);
    }
}

// ---------- 网盘辅助 ----------


pub fn s3_client(state: &AppState) -> Result<CloudLibrary, String> {
    let s = state.settings_snapshot();
    if s.webdav_enabled {
        let client = WebDav::new(
            &s.webdav_endpoint,
            &s.webdav_root,
            s.webdav_username,
            s.webdav_password,
        ).map_err(|error| error.to_string())?;
        return Ok(CloudLibrary::WebDav(client, state.proxy.clone()));
    }
    if !s.s3_enabled {
        return Err("请先在设置中启用并配置网盘".into());
    }
    let cfg = S3Config {
        endpoint: s.s3_endpoint.trim().to_string(),
        region: s.s3_region.trim().to_string(),
        bucket: s.s3_bucket.trim().to_string(),
        access_key: s.s3_access_key.trim().to_string(),
        secret_key: s.s3_secret_key.trim().to_string(),
        prefix: s.s3_prefix.clone(),
        path_style: s.s3_path_style,
    };
    if !cfg.is_ready() {
        return Err(
            "请先在 设置 → 网盘（S3）里填写 Endpoint / Bucket / Access Key / Secret Key".into(),
        );
    }
    Ok(CloudLibrary::S3(S3::new(cfg, state.http.client().clone())))
}


fn is_cloud_provider(provider: &str) -> bool {
    matches!(provider, "s3" | "webdav")
}

fn track_cloud_client(state: &AppState, provider: &str) -> Result<CloudLibrary, String> {
    let client = s3_client(state)?;
    if client.provider() != provider {
        return Err("歌曲来自另一种网盘连接，请切换网盘后再试".into());
    }
    Ok(client)
}

pub use tinymusic_core::library::{is_audio_key, object_key, playlist_prefix, replace_ext};


pub fn audio_content_type(key: &str) -> &'static str {
    let lower = key.to_ascii_lowercase();
    if lower.ends_with(".flac") {
        "audio/flac"
    } else if lower.ends_with(".m4a") || lower.ends_with(".mp4") {
        "audio/mp4"
    } else if lower.ends_with(".ogg") {
        "audio/ogg"
    } else {
        "audio/mpeg"
    }
}


pub fn sniff_image_mime(bytes: &[u8]) -> &'static str {
    if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
        "image/png"
    } else if bytes.starts_with(b"RIFF") && bytes.len() > 12 && &bytes[8..12] == b"WEBP" {
        "image/webp"
    } else {
        "image/jpeg"
    }
}


pub fn sanitize_playlist_name(raw: &str) -> Result<String, String> {
    let name = raw.trim().replace(['/', '\\'], "-");
    let name = name.trim().to_string();
    if name.is_empty() {
        return Err("歌单名不能为空".into());
    }
    if name.chars().count() > 60 {
        return Err("歌单名太长了（最多 60 个字符）".into());
    }
    Ok(name)
}


/// 网盘里的「喜欢」歌单目录名
pub const FAVORITES_PLAYLIST: &str = "喜欢";


/// 点喜欢之后：把这首歌放进网盘「喜欢」目录（收藏就是目录里那份副本）。
/// 返回失败记录（有的话）让调用方弹窗。
pub async fn sync_favorite_track(state: &AppState, track: &Track) -> Option<FailedDownload> {
    let client = s3_client(state).ok()?;
    let settings = state.settings_snapshot();
    let q = Quality::from_str(&settings.default_quality);

    // 网盘里的歌不用重新下载：直接在桶里复制一份到「喜欢」
    if is_cloud_provider(&track.provider) {
        if track.provider != client.provider() {
            return None;
        }
        return match tinymusic_core::library::copy_into_favorites(&client, &track.id).await {
            Ok(target) => {
                remember_favorite_copy(state, track, &target);
                if client.provider() == "s3" {
                    let _ = state.storage.save_s3_playlist(FAVORITES_PLAYLIST);
                }
                None
            }
            Err(e) => {
                let failure = failure_record(
                    track,
                    q,
                    "s3",
                    FAVORITES_PLAYLIST,
                    "",
                    vec![FailedPart {
                        part: "audio".into(),
                        error: e,
                    }],
                );
                let _ = state.storage.upsert_download_failure(&failure);
                Some(failure)
            }
        };
    }

    let p = state.provider(&track.provider).ok()?;

    let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
    let task_id = format!("fav-{}-{}", seq, track.id);

    let outcome = upload_one_s3(
        state.http.clone(),
        state.storage.clone(),
        state.downloader.clone(),
        p,
        client,
        track.clone(),
        q,
        FAVORITES_PLAYLIST.to_string(),
        task_id,
        None,
    )
    .await;

    if outcome.ok {
        let _ = state.storage.save_s3_playlist(FAVORITES_PLAYLIST);
    }
    outcome.failure
}


/// 复制到「喜欢」成功后，把本地收藏缓存换成副本的 key。
///
/// 收藏的 id 必须和「喜欢」目录里的对象一致，否则下次拉取会被当成过期收藏清掉。
fn remember_favorite_copy(state: &AppState, source: &Track, target: &str) {
    let _ = state.storage.remove_favorite(&source.provider, &source.id);
    let mut copy = source.clone();
    copy.id = target.to_string();
    copy.cover = None;
    let _ = state.storage.add_favorite(&copy);
}


/// 音频 / 歌词 / 封面失败后的自动重试次数（不含首次尝试）
pub const PART_RETRIES: u32 = 5;


/// 失败记录的稳定 id：同一首歌 + 同一个目标只留一条
pub fn failure_id(target: &str, track: &Track) -> String {
    format!("{}:{}:{}", target, track.provider, track.id)
}


pub fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}


/// 通用重试：可重试的错误再试 `PART_RETRIES` 次，指数退避。
///
/// 「不可用 / 不支持 / 已取消」是确定性结论，重试只是白等，直接返回。
pub async fn with_retries<T, F, Fut>(mut op: F) -> Result<T, String>
where
    F: FnMut(u32) -> Fut,
    Fut: Future<Output = std::result::Result<T, CoreError>>,
{
    let mut last = String::new();
    for attempt in 0..=PART_RETRIES {
        if attempt > 0 {
            tokio::time::sleep(Duration::from_millis(400 * (1u64 << attempt.min(3)))).await;
        }
        match op(attempt).await {
            Ok(v) => return Ok(v),
            Err(e) => {
                if matches!(
                    e,
                    CoreError::Unavailable | CoreError::Unsupported(_) | CoreError::Cancelled
                ) {
                    return Err(e.to_string());
                }
                last = e.to_string();
            }
        }
    }
    Err(last)
}


/// 组装一条失败记录（调用方负责写入 storage 并通知前端）
pub fn failure_record(
    track: &Track,
    quality: Quality,
    target: &str,
    playlist: &str,
    location: &str,
    parts: Vec<FailedPart>,
) -> FailedDownload {
    FailedDownload {
        id: failure_id(target, track),
        track: track.clone(),
        quality: quality.as_str().to_string(),
        target: target.into(),
        playlist: playlist.into(),
        location: location.into(),
        parts,
        created_at: now_secs(),
    }
}


/// 一次下载/上传的结果
pub struct TrackOutcome {
    /// 音频本体是否成功；歌词/封面失败不影响它
    ok: bool,
    /// 本地路径或网盘对象 key
    location: String,
    /// 有失败（哪怕只是封面）就带上，便于任务结束后弹窗
    failure: Option<FailedDownload>,
}


/// 下载时顺带准备的封面与歌词。
///
/// 两部分各自失败自动重试；仍然失败就记进 `failures` 交给上层弹窗，
/// 不阻塞音频本体。
pub async fn build_extras(
    http: Arc<HttpClient>,
    provider: Arc<dyn MusicProvider>,
    track: &Track,
    want_cover: bool,
    want_lyrics: bool,
) -> (DownloadExtras, Vec<FailedPart>) {
    let mut extras = DownloadExtras::default();
    let mut failures = Vec::new();

    if want_cover {
        if let Some(url) = track
            .cover
            .as_deref()
            .map(str::trim)
            .filter(|u| !u.is_empty())
            .map(str::to_string)
        {
            // 列表接口给的封面是缩略图（酷我 120px、网易云 param=300y300），
            // 直接内嵌进音频文件就还是糊的。下载一律尽量要原图：
            // 平台按自己 CDN 的规则给出「原图」地址，取不到再退回列表里的缩略图——
            // 升级封面不能把封面本身弄丢。
            let candidates = cover_candidates(&url, provider.cover_hires(&url));

            let mut fetched = None;
            let mut last_error = String::new();
            for candidate in candidates {
                let http = http.clone();
                let res = with_retries(move |_| {
                    let http = http.clone();
                    let url = candidate.clone();
                    async move { fetch_cover_bytes(http, url).await }
                })
                .await;
                match res {
                    Ok(bytes) => {
                        fetched = Some(bytes);
                        break;
                    }
                    Err(e) => last_error = e,
                }
            }
            match fetched {
                Some(bytes) => {
                    extras.cover_mime = sniff_image_mime(&bytes).to_string();
                    extras.cover = Some(bytes);
                }
                None => failures.push(FailedPart {
                    part: "cover".into(),
                    error: last_error,
                }),
            }
        }
    }

    if want_lyrics {
        let detail_provider = provider.clone();
        let detail_track = track.clone();
        let res = with_retries(move |_| {
            let provider = detail_provider.clone();
            let track = detail_track.clone();
            async move {
                // 详情接口容易限流/变慢：超时算失败，交给重试
                let detail =
                    tokio::time::timeout(Duration::from_secs(12), provider.detail(&track))
                        .await
                        .map_err(|_| CoreError::Http("歌词请求超时".into()))??;
                Ok(detail.lyrics)
            }
        })
        .await;
        match res {
            // 空歌词 = 这首歌本来就没有，不算失败
            Ok(lines) if !lines.is_empty() => extras.lyrics_lrc = Some(build_lrc(track, &lines)),
            Ok(_) => {}
            Err(e) => failures.push(FailedPart {
                part: "lyrics".into(),
                error: e,
            }),
        }
    }

    (extras, failures)
}


/// 封面候选地址：先原图（高清），再列表里的缩略图；两者相同只留一个。
pub fn cover_candidates(url: &str, hires: Option<String>) -> Vec<String> {
    match hires {
        Some(h) if h != url => vec![h, url.to_string()],
        _ => vec![url.to_string()],
    }
}


/// 抓一张封面图。
///
/// 原图常见 1080 / 2048 / 3000 边长、几百 KB 到 3 MB（实测酷我 2048 最大 3.4 MB、
/// 网易云 3000 约 2 MB）；上限放到 8 MB，只为挡住错误页 / 异常大文件，
/// 正常封面不会被误杀。
async fn fetch_cover_bytes(
    http: Arc<HttpClient>,
    url: String,
) -> std::result::Result<Vec<u8>, CoreError> {
    let resp = tokio::time::timeout(Duration::from_secs(10), http.get_range(&url, None))
        .await
        .map_err(|_| CoreError::Http("封面请求超时".into()))??;
    if !resp.status().is_success() {
        return Err(CoreError::Http(format!(
            "封面 HTTP {}",
            resp.status().as_u16()
        )));
    }
    let bytes = resp.bytes().await?.to_vec();
    if bytes.is_empty() || bytes.len() >= 8 * 1024 * 1024 {
        return Err(CoreError::Http("封面内容不合法".into()));
    }
    Ok(bytes)
}


pub fn cover_mime(extras: &DownloadExtras) -> &str {
    if extras.cover_mime.trim().is_empty() {
        "image/jpeg"
    } else {
        extras.cover_mime.as_str()
    }
}


/// 本地下载一首：取流 → 下载音频 → 写歌词 / 封面内嵌，每一步都自动重试。
///
/// 失败的音频 / 歌词 / 封面会写进 `download_failures`，任务结束后前端弹窗，
/// 用户可以只重试失败的部分。
pub async fn download_one_local(
    http: Arc<HttpClient>,
    storage: Arc<Storage>,
    downloader: Arc<Downloader>,
    provider: Arc<dyn MusicProvider>,
    track: Track,
    q: Quality,
    dir: PathBuf,
    task_id: String,
    on_progress: Option<ProgressFn>,
) -> TrackOutcome {
    let _ = storage.insert_download(&task_id, &track, q, "", 0, "running");

    // 1) 取流
    let (resolve_provider, resolve_track) = (provider.clone(), track.clone());
    let info = with_retries(move |_| {
        let provider = resolve_provider.clone();
        let track = resolve_track.clone();
        async move { provider.resolve(&track, q).await }
    })
    .await;

    let info = match info {
        Ok(v) => v,
        Err(e) => {
            let _ = storage.update_download(&task_id, &format!("failed: {}", e), 0);
            let failure = failure_record(
                &track,
                q,
                "local",
                "",
                "",
                vec![FailedPart {
                    part: "audio".into(),
                    error: e,
                }],
            );
            let _ = storage.upsert_download_failure(&failure);
            return TrackOutcome {
                ok: false,
                location: String::new(),
                failure: Some(failure),
            };
        }
    };

    let _ = storage.insert_download(&task_id, &track, info.quality, "", 0, "running");
    let ext = actual_ext(&info);
    let fname = build_filename(&track, ext);

    // 本地无损不写 ID3，封面没有落点，就不用抓
    let (extras, mut parts) = build_extras(
        http,
        provider,
        &track,
        !info.format.lossless,
        true,
    )
    .await;

    // 2) 音频本体（音质档位已经降好，重试时不再降）
    let res = with_retries({
        let downloader = downloader.clone();
        let track = track.clone();
        let info = info.clone();
        let dir = dir.clone();
        let fname = fname.clone();
        let extras = extras.clone();
        let ch = on_progress.clone();
        let tid = task_id.clone();
        move |_| {
            let downloader = downloader.clone();
            let track = track.clone();
            let info = info.clone();
            let dir = dir.clone();
            let fname = fname.clone();
            let extras = extras.clone();
            let ch = ch.clone();
            let tid = tid.clone();
            async move {
                downloader
                    .run(
                        &track,
                        &info,
                        &dir,
                        &fname,
                        &extras,
                        Box::new(move |downloaded, total| {
                            if let Some(ch) = &ch {
                                let _ = ch(Progress {
                                    task_id: tid.clone(),
                                    downloaded,
                                    total,
                                });
                            }
                        }),
                    )
                    .await
            }
        }
    })
    .await;

    match res {
        Ok(path) => {
            let bytes = std::fs::metadata(&path)
                .map(|m| m.len() as i64)
                .unwrap_or(0);
            let location = path.to_string_lossy().to_string();
            let _ = storage.insert_download(
                &task_id,
                &track,
                info.quality,
                &location,
                bytes,
                "done",
            );
            if parts.is_empty() {
                // 之前失败过但这次下全了：清掉旧记录，别让用户以为还坏着
                let _ = storage.remove_download_failure(&failure_id("local", &track));
                TrackOutcome {
                    ok: true,
                    location,
                    failure: None,
                }
            } else {
                let failure =
                    failure_record(&track, info.quality, "local", "", &location, parts);
                let _ = storage.upsert_download_failure(&failure);
                TrackOutcome {
                    ok: true,
                    location,
                    failure: Some(failure),
                }
            }
        }
        Err(e) => {
            let _ = storage.update_download(&task_id, &format!("failed: {}", e), 0);
            parts.insert(
                0,
                FailedPart {
                    part: "audio".into(),
                    error: e,
                },
            );
            let failure = failure_record(&track, info.quality, "local", "", "", parts);
            let _ = storage.upsert_download_failure(&failure);
            TrackOutcome {
                ok: false,
                location: String::new(),
                failure: Some(failure),
            }
        }
    }
}

// ---------- 命令 ----------


pub async fn resolve(
    state: &AppState,
    track: Track,
    quality: String,
) -> Result<StreamInfo, String> {
    let q = Quality::parse(&quality).ok_or_else(|| "未知音质".to_string())?;
    if is_cloud_provider(&track.provider) {
        let client = track_cloud_client(state, &track.provider)?;
        let (actual_quality, format) = s3_audio_format(&track.id);
        let verified = format.codec != Codec::Unknown;
        let mime = tinymusic_core::proxy::mime_for_path(Path::new(&track.id));
        let url = client.audio_url(&track.id, &state.proxy, mime).await.map_err(|e| e.to_string())?;
        return Ok(StreamInfo {
            url,
            quality: actual_quality,
            requested: q,
            bytes: None,
            availability: Availability::Available,
            content_type: mime.into(),
            format,
            via: client.provider().into(),
            degraded: false,
            verified,
        });
    }
    let p = state.provider(&track.provider)?;
    p.resolve(&track, q).await.map_err(|e| e.to_string())
}


/// 列表接口没带 MINFO 时，按曲目探测可播档位。
pub async fn track_qualities(
    state: &AppState,
    track: Track,
) -> Result<TrackQualities, String> {
    if !track.available_qualities.is_empty() {
        return Ok(TrackQualities {
            available: track.available_qualities.clone(),
            has_advanced: track.has_advanced,
            known: true,
        });
    }
    if is_cloud_provider(&track.provider) {
        let mut available = Vec::new();
        if track.id.to_ascii_lowercase().ends_with(".flac") {
            available.push(Quality::Lossless);
        }
        return Ok(TrackQualities {
            available,
            has_advanced: false,
            known: true,
        });
    }
    let p = state.provider(&track.provider)?;
    p.track_qualities(&track).await.map_err(|e| e.to_string())
}


pub async fn track_detail(
    state: &AppState,
    provider: String,
    track: Track,
) -> Result<TrackDetail, String> {
    if let Some((_, path)) = local_download(state, &provider, &track.id) {
        let lyrics = std::fs::read_to_string(path.with_extension("lrc"))
            .map(|text| parse_lrc(text.trim_start_matches('\u{feff}')))
            .unwrap_or_default();
        return Ok(TrackDetail { track, lyrics, preview_range_ms: None });
    }
    if is_cloud_provider(&provider) {
        let client = track_cloud_client(state, &provider)?;
        let lyrics = match client.get_object(&replace_ext(&track.id, "lrc")).await {
            Ok(Some(bytes)) => parse_lrc(&String::from_utf8_lossy(&bytes)),
            _ => Vec::new(),
        };
        return Ok(TrackDetail {
            track,
            lyrics,
            preview_range_ms: None,
        });
    }
    let p = state.provider(&provider)?;
    p.detail(&track).await.map_err(|e| e.to_string())
}


/// LRC 文本 → 歌词行（同一句可以挂多个时间戳）
pub fn parse_lrc(text: &str) -> Vec<LyricLine> {
    let mut out = Vec::new();
    for raw in text.lines() {
        let mut rest = raw.trim();
        let mut stamps = Vec::new();
        while let Some(tail) = rest.strip_prefix('[') {
            let Some(end) = tail.find(']') else { break };
            let tag = &tail[..end];
            match tag.split_once(':').and_then(|(m, s)| {
                let m: f64 = m.trim().parse().ok()?;
                let s: f64 = s.trim().parse().ok()?;
                Some(m * 60_000.0 + s * 1000.0)
            }) {
                Some(ms) => {
                    stamps.push(ms.max(0.0) as u32);
                    rest = &tail[end + 1..];
                }
                None => break,
            }
        }
        let line = rest.trim();
        for ms in stamps {
            out.push(LyricLine {
                time_ms: ms,
                text: line.to_string(),
            });
        }
    }
    out.sort_by_key(|l| l.time_ms);
    out
}


pub async fn player_open(
    state: &AppState,
    track: Track,
    quality: String,
    force_refresh: Option<bool>,
    allow_local: Option<bool>,
) -> Result<PlayerSource, String> {
    let q = Quality::parse(&quality).ok_or_else(|| "未知音质".to_string())?;

    // 已经下载到本地的：直接播硬盘上的文件 —— 不走网络，也就没有「直链过期」。
    // 只有当本地那份音质不低于当前选择时才优先，避免选了 320k 却悄悄播 128k。
    if allow_local.unwrap_or(true) {
        if let Some((row, path)) = local_download(state, &track.provider, &track.id) {
            let local_quality = Quality::parse(&row.quality).unwrap_or_default();
            if is_cloud_provider(&track.provider)
                || quality_rank(local_quality) >= quality_rank(q)
                || state.provider(&track.provider).is_err()
            {
                let (_, format) = s3_audio_format(&row.path);
                let verified = format.codec != Codec::Unknown;
                let mime = tinymusic_core::proxy::mime_for_path(&path);
                let url = state
                    .proxy
                    .register_file(path, Some(mime.to_string()))
                    .await;
                return Ok(PlayerSource {
                    url,
                    quality: local_quality.as_str().to_string(),
                    requested_quality: q.as_str().to_string(),
                    format,
                    bytes: Some(row.bytes.max(0) as u64),
                    degraded: false,
                    verified,
                    via: "local".into(),
                });
            }
        }
    }

    // 网盘里的歌：给一个 6 小时有效的签名直链，同样套一层本地代理 ——
    // WebView 对跨域音视频的 Content-Type / HEAD 更挑，代理统一成 Range + 明确 MIME。
    // 格式按文件后缀推断，UI 显示 FLAC/MP3，而不是笼统的“原文件”。
    if is_cloud_provider(&track.provider) {
        let info = resolve(state, track, q.as_str().into()).await?;
        return Ok(PlayerSource {
            url: info.url,
            quality: info.quality.as_str().into(),
            requested_quality: info.requested.as_str().into(),
            format: info.format,
            bytes: info.bytes,
            degraded: info.degraded,
            verified: info.verified,
            via: info.via,
        });
    }
    let p = state.provider(&track.provider)?;
    if force_refresh.unwrap_or(false) {
        p.invalidate_resolve(&track.id);
    }
    let info = p.resolve(&track, q).await.map_err(|e| e.to_string())?;
    let url = state
        .proxy
        .register(info.url.clone(), Some(info.content_type.clone()))
        .await;
    Ok(PlayerSource {
        url,
        quality: info.quality.as_str().to_string(),
        requested_quality: info.requested.as_str().to_string(),
        format: info.format,
        bytes: info.bytes,
        degraded: info.degraded,
        verified: info.verified,
        via: info.via,
    })
}


#[derive(Debug, Serialize)]
pub struct PlayerSource {
    pub url: String,
    /// 实际档位；无法识别格式的网盘文件为 "original"
    pub quality: String,
    pub requested_quality: String,
    pub format: AudioFormat,
    pub bytes: Option<u64>,
    pub degraded: bool,
    pub verified: bool,
    pub via: String,
}


#[derive(Debug, Clone, Serialize)]
pub struct Progress {
    pub task_id: String,
    pub downloaded: u64,
    pub total: Option<u64>,
}


pub async fn download_start(
    state: &AppState,
    track: Track,
    quality: Option<String>,
    on_progress: ProgressFn,
) -> Result<String, String> {
    if is_cloud_provider(&track.provider) {
        let client = track_cloud_client(state, &track.provider)?;
        let task_id = cloud_download_task_id(state, &track);
        let state = state.strong();
        let id = task_id.clone();
        tokio::spawn(async move {
            let outcome = download_cloud_track(&state, &client, &track, &id, None, Some(on_progress)).await;
            if let Some(failure) = outcome.failure {
                state.host.failed(&[failure]);
            }
        });
        return Ok(task_id);
    }
    let p = state.provider(&track.provider)?;
    let settings = state.settings_snapshot();
    let q = Quality::from_str(quality.as_deref().unwrap_or(&settings.default_quality));
    let dir = PathBuf::from(&settings.download_dir);

    let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
    let task_id = format!("t{}-{}", seq, track.id);
    let tid = task_id.clone();

    let http = state.http.clone();
    let storage = state.storage.clone();
    let downloader = state.downloader.clone();
    let provider = p.clone();
    let host = state.host.clone();

    tokio::spawn(async move {
        let outcome = download_one_local(
            http,
            storage,
            downloader,
            provider,
            track,
            q,
            dir,
            tid,
            Some(on_progress),
        )
        .await;
        if let Some(f) = outcome.failure {
            let _ = host.failed(std::slice::from_ref(&f));
        }
    });

    Ok(task_id)
}

fn cloud_download_task_id(state: &AppState, track: &Track) -> String {
    let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos();
    format!("cloud-{timestamp}-{seq}-{}", track.id)
}

async fn download_cloud_track(
    state: &AppState,
    client: &CloudLibrary,
    track: &Track,
    task_id: &str,
    existing: Option<PathBuf>,
    on_progress: Option<ProgressFn>,
) -> TrackOutcome {
    let (quality, _) = s3_audio_format(&track.id);
    let result = if let Some(path) = existing {
        Ok(path)
    } else {
        let _ = state.storage.insert_download(task_id, track, quality, "", 0, "running");
        let ext = track.id.rsplit_once('.').map(|(_, ext)| ext.to_ascii_lowercase());
        match ext.filter(|_| is_audio_key(&track.id)) {
            Some(ext) => {
                let path = PathBuf::from(state.settings_snapshot().download_dir).join(build_filename(track, &ext));
                let id = task_id.to_owned();
                client.download_object(&track.id, &path, false, Box::new(move |downloaded, total| {
                    if let Some(progress) = &on_progress {
                        let _ = progress(Progress { task_id: id.clone(), downloaded, total });
                    }
                })).await.map_err(|e| e.to_string())
            }
            None => Err("曲目路径必须指向音频文件".into()),
        }
    };
    let (location, parts) = match result {
        Ok(path) => {
            let parts = download_cloud_sidecars(client, &track.id, &path).await;
            let location = path.to_string_lossy().into_owned();
            let bytes = std::fs::metadata(&path).map(|m| m.len() as i64).unwrap_or(0);
            let _ = state.storage.insert_download(task_id, track, quality, &location, bytes, "done");
            (location, parts)
        }
        Err(error) => {
            let _ = state.storage.update_download(task_id, &format!("failed: {error}"), 0);
            (String::new(), vec![FailedPart { part: "audio".into(), error }])
        }
    };
    let failure = if parts.is_empty() {
        let _ = state.storage.remove_download_failure(&failure_id("local", track));
        None
    } else {
        let failure = failure_record(track, quality, "local", "", &location, parts);
        let _ = state.storage.upsert_download_failure(&failure);
        Some(failure)
    };
    TrackOutcome { ok: !location.is_empty(), location, failure }
}

async fn download_cloud_sidecars(client: &CloudLibrary, key: &str, path: &Path) -> Vec<FailedPart> {
    let folder = key.rfind('/').map_or("", |end| &key[..=end]);
    let entries = match client.list_keys_all(folder).await {
        Ok(keys) => keys.into_iter().map(|key| (key.to_lowercase(), key)).collect::<Vec<_>>(),
        Err(error) => return vec!["lyrics", "cover"].into_iter().map(|part| FailedPart {
            part: part.into(), error: error.to_string()
        }).collect(),
    };
    let stem = key.rsplit_once('.').map_or(key, |(stem, _)| stem);
    let mut failed = Vec::new();
    for (part, extensions) in [("lyrics", &["lrc"][..]), ("cover", &["jpg", "jpeg", "png", "webp"][..])] {
        let Some(remote) = find_sibling(&entries, stem, extensions) else { continue };
        let ext = remote.rsplit_once('.').unwrap().1.to_ascii_lowercase();
        if let Err(error) = client.download_object(&remote, &path.with_extension(ext), true, Box::new(|_, _| {})).await {
            failed.push(FailedPart { part: part.into(), error: error.to_string() });
        }
    }
    failed
}


/// 音质档位的高低，用来判断本地文件能不能顶替当前选择
pub fn quality_rank(q: Quality) -> u8 {
    match q {
        Quality::Standard => 0,
        Quality::Super => 1,
        Quality::Lossless => 2,
        Quality::HiRes => 3,
        Quality::Atmos => 4,
        Quality::Master => 5,
    }
}


/// 网盘文件按后缀推断显示格式；不解码、不探测，只用于 UI 文案。
pub fn s3_audio_format(key: &str) -> (Quality, AudioFormat) {
    let lower = key.to_ascii_lowercase();
    let (codec, lossless, quality) = if lower.ends_with(".flac") {
        (Codec::Flac, true, Quality::Lossless)
    } else if lower.ends_with(".mp3") {
        (Codec::Mp3, false, Quality::Standard)
    } else if lower.ends_with(".m4a") || lower.ends_with(".mp4") || lower.ends_with(".aac") {
        (Codec::Aac, false, Quality::Standard)
    } else if lower.ends_with(".ogg") {
        (Codec::Ogg, false, Quality::Standard)
    } else if lower.ends_with(".wav") {
        (Codec::Wav, true, Quality::Lossless)
    } else {
        return (Quality::Standard, AudioFormat::default());
    };
    (
        quality,
        AudioFormat {
            codec,
            bitrate_kbps: None,
            sample_rate_hz: None,
            bits_per_sample: None,
            channels: None,
            lossless,
            verified: false,
        },
    )
}


/// 下载/上传扩展名以实际格式为准；格式未知时才退回 Content-Type。
pub fn actual_ext(info: &StreamInfo) -> &'static str {
    if info.format.codec == tinymusic_core::model::Codec::Unknown {
        ext_for(&info.content_type)
    } else {
        info.format.extension()
    }
}


pub fn ext_for(content_type: &str) -> &'static str {
    let ct = content_type.to_ascii_lowercase();
    if ct.contains("flac") {
        "flac"
    } else if ct.contains("aac") || ct.contains("mp4") {
        "m4a"
    } else if ct.contains("ogg") {
        "ogg"
    } else {
        "mp3"
    }
}


pub fn download_list(state: &AppState) -> Result<Vec<DownloadRow>, String> {
    let mut rows = state.storage.list_downloads().map_err(|e| e.to_string())?;
    // iOS 的沙盒容器路径会随重装/更新变化，库里存的是当时的绝对路径。
    // 原路径不存在时，按文件名到当前下载目录里找一遍，避免"下载了却播不了"。
    for row in rows.iter_mut() {
        let dir = std::path::PathBuf::from(state.settings_snapshot().download_dir);
        row.path = resolve_download_path(&row.path, &dir);
    }
    Ok(rows)
}


/// 把库里的下载路径修到当前环境下真实存在的位置。
fn resolve_download_path(stored: &str, download_dir: &std::path::Path) -> String {
    let path = std::path::Path::new(stored);
    if path.exists() {
        return stored.to_string();
    }
    if let Some(name) = path.file_name() {
        let candidate = download_dir.join(name);
        if candidate.exists() {
            return candidate.to_string_lossy().to_string();
        }
    }
    stored.to_string()
}

fn local_download(state: &AppState, provider: &str, id: &str) -> Option<(DownloadRow, PathBuf)> {
    let row = state.storage.find_local_download(provider, id).ok()??;
    let dir = PathBuf::from(state.settings_snapshot().download_dir);
    let path = PathBuf::from(resolve_download_path(&row.path, &dir));
    path.is_file().then_some((row, path))
}


pub fn download_clear(state: &AppState) -> Result<(), String> {
    state.storage.clear_downloads().map_err(|e| e.to_string())
}

// ---------- 下载失败记录 / 手动重试 ----------


/// 下载不完整的曲目列表（音频 / 歌词 / 封面里哪部分失败、为什么失败）
pub fn download_failures(state: &AppState) -> Result<Vec<FailedDownload>, String> {
    state
        .storage
        .list_download_failures()
        .map_err(|e| e.to_string())
}


/// 忽略一条失败记录（不删已经下好的文件）
pub fn download_failure_dismiss(state: &AppState, id: String) -> Result<(), String> {
    state
        .storage
        .remove_download_failure(&id)
        .map_err(|e| e.to_string())
}


pub fn download_failures_clear(state: &AppState) -> Result<(), String> {
    state
        .storage
        .clear_download_failures()
        .map_err(|e| e.to_string())
}


/// 无损文件不写 ID3，本地封面没有落点
pub fn is_lossless_path(path: &std::path::Path) -> bool {
    matches!(
        path.extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_ascii_lowercase())
            .as_deref(),
        Some("flac") | Some("wav")
    )
}


/// 音频已经下好，只补本地的歌词 / 封面（不重新下音频）
pub async fn repair_local_extras(
    http: Arc<HttpClient>,
    provider: Arc<dyn MusicProvider>,
    track: &Track,
    path: &std::path::Path,
    parts: &[FailedPart],
) -> Vec<FailedPart> {
    let need_cover = parts.iter().any(|p| p.part == "cover") && !is_lossless_path(path);
    let need_lyrics = parts.iter().any(|p| p.part == "lyrics");
    if !need_cover && !need_lyrics {
        return Vec::new();
    }

    let (extras, mut left) = build_extras(http, provider, track, need_cover, need_lyrics).await;

    let mime = cover_mime(&extras).to_string();
    if need_cover {
        if let Some(cover) = extras.cover {
            let p = path.to_path_buf();
            let (title, artist, album) = (
                track.title.clone(),
                track.artist.clone(),
                track.album.clone(),
            );
            let res = tokio::task::spawn_blocking(move || {
                id3::write_tags_with_cover(
                    &p,
                    &title,
                    &artist,
                    &album,
                    Some((cover.as_slice(), mime.as_str())),
                )
            })
            .await
            .map_err(|_| "标签写入线程失败".to_string())
            .and_then(|r| r.map_err(|e| e.to_string()));
            if let Err(e) = res {
                left.push(FailedPart {
                    part: "cover".into(),
                    error: format!("写封面失败: {}", e),
                });
            }
        }
    }

    if need_lyrics {
        if let Some(lrc) = extras.lyrics_lrc {
            if let Err(e) = tokio::fs::write(path.with_extension("lrc"), lrc.as_bytes()).await {
                left.push(FailedPart {
                    part: "lyrics".into(),
                    error: format!("写歌词失败: {}", e),
                });
            }
        }
    }

    left
}


/// 网盘音频已经传好，只补歌词 / 封面对象
pub async fn repair_s3_extras(
    http: Arc<HttpClient>,
    provider: Arc<dyn MusicProvider>,
    s3: &CloudLibrary,
    track: &Track,
    key: &str,
    parts: &[FailedPart],
) -> Vec<FailedPart> {
    let need_cover = parts.iter().any(|p| p.part == "cover");
    let need_lyrics = parts.iter().any(|p| p.part == "lyrics");
    if !need_cover && !need_lyrics {
        return Vec::new();
    }

    let (extras, mut left) = build_extras(http, provider, track, need_cover, need_lyrics).await;
    let mime = cover_mime(&extras).to_string();

    if let Some(lrc) = extras.lyrics_lrc {
        if let Err(e) = put_object_retry(
            s3.clone(),
            replace_ext(key, "lrc"),
            lrc.into_bytes(),
            "text/plain; charset=utf-8",
        )
        .await
        {
            left.push(FailedPart {
                part: "lyrics".into(),
                error: e,
            });
        }
    }
    if let Some(cover) = extras.cover {
        if let Err(e) = put_object_retry(s3.clone(), replace_ext(key, "jpg"), cover, &mime).await {
            left.push(FailedPart {
                part: "cover".into(),
                error: e,
            });
        }
    }
    left
}


/// 重试结束后更新失败记录：补全了就删掉，没补全就原地更新
pub fn finish_repair(storage: &Storage, f: &FailedDownload, left: Vec<FailedPart>) {
    if left.is_empty() {
        let _ = storage.remove_download_failure(&f.id);
    } else {
        let mut updated = f.clone();
        updated.parts = left;
        updated.created_at = now_secs();
        let _ = storage.upsert_download_failure(&updated);
    }
}


/// 手动重试：只补失败的部分。
///
/// 音频没下成功才整首重来；只是歌词 / 封面失败时直接在原文件 / 原对象上补。
/// 返回重试之后仍然失败的记录。
pub async fn download_retry_failed(
    state: &AppState,
    ids: Vec<String>,
) -> Result<Vec<FailedDownload>, String> {
    let settings = state.settings_snapshot();
    let dir = PathBuf::from(&settings.download_dir);
    let all = state
        .storage
        .list_download_failures()
        .map_err(|e| e.to_string())?;

    for id in ids {
        let Some(f) = all.iter().find(|x| x.id == id).cloned() else {
            continue;
        };
        let q = Quality::from_str(&f.quality);
        if f.target == "local" && is_cloud_provider(&f.track.provider) {
            let Ok(client) = track_cloud_client(state, &f.track.provider) else { continue };
            let (id, existing) = match local_download(state, &f.track.provider, &f.track.id) {
                Some((row, path)) if !f.parts.iter().any(|part| part.part == "audio") => (row.task_id, Some(path)),
                _ => (cloud_download_task_id(state, &f.track), None),
            };
            download_cloud_track(state, &client, &f.track, &id, existing, None).await;
            continue;
        }
        // 网盘歌曲的收藏是桶内复制，没有平台 provider 可下载
        if f.target == "s3" && is_cloud_provider(&f.track.provider) {
            let Ok(s3) = track_cloud_client(state, &f.track.provider) else {
                continue;
            };
            if let Ok(target) =
                tinymusic_core::library::copy_into_favorites(&s3, &f.track.id).await
            {
                remember_favorite_copy(state, &f.track, &target);
                let _ = state.storage.remove_download_failure(&f.id);
            }
            continue;
        }
        let provider = match state.provider(&f.track.provider) {
            Ok(p) => p,
            Err(_) => continue,
        };
        let audio_broken =
            f.parts.iter().any(|p| p.part == "audio") || f.location.is_empty();

        if f.target == "s3" {
            let Ok(s3) = s3_client(&state) else {
                continue;
            };
            if audio_broken {
                let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
                let task_id = format!("rt{}-{}", seq, f.track.id);
                let outcome = upload_one_s3(
                    state.http.clone(),
                    state.storage.clone(),
                    state.downloader.clone(),
                    provider,
                    s3,
                    f.track.clone(),
                    q,
                    f.playlist.clone(),
                    task_id,
                    None,
                )
                .await;
                if outcome.failure.is_none() {
                    let _ = state.storage.remove_download_failure(&f.id);
                }
            } else {
                let left = repair_s3_extras(
                    state.http.clone(),
                    provider,
                    &s3,
                    &f.track,
                    &f.location,
                    &f.parts,
                )
                .await;
                finish_repair(&state.storage, &f, left);
            }
            continue;
        }

        if audio_broken {
            let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
            let task_id = format!("rt{}-{}", seq, f.track.id);
            let outcome = download_one_local(
                state.http.clone(),
                state.storage.clone(),
                state.downloader.clone(),
                provider,
                f.track.clone(),
                q,
                dir.clone(),
                task_id,
                None,
            )
            .await;
            if outcome.failure.is_none() {
                let _ = state.storage.remove_download_failure(&f.id);
            }
            continue;
        }

        let path = PathBuf::from(&f.location);
        if !path.is_file() {
            // 文件被挪走或删掉了：只能整首重下
            let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
            let task_id = format!("rt{}-{}", seq, f.track.id);
            let outcome = download_one_local(
                state.http.clone(),
                state.storage.clone(),
                state.downloader.clone(),
                provider,
                f.track.clone(),
                q,
                dir.clone(),
                task_id,
                None,
            )
            .await;
            if outcome.failure.is_none() {
                let _ = state.storage.remove_download_failure(&f.id);
            }
            continue;
        }
        let left =
            repair_local_extras(state.http.clone(), provider, &f.track, &path, &f.parts).await;
        finish_repair(&state.storage, &f, left);
    }

    state
        .storage
        .list_download_failures()
        .map_err(|e| e.to_string())
}


pub fn favorite_add(
    state: &AppState,
    track: Track,
) -> Result<(), String> {
    state
        .storage
        .add_favorite(&track)
        .map_err(|e| e.to_string())?;
    // 网络操作放后台：喜欢是即时动作，不能被下载/上传卡住
    let host = state.host.clone();
    let st = state.strong();
    let track2 = track.clone();
    tokio::spawn(async move {
        if let Some(f) = sync_favorite_track(&st, &track2).await {
            let _ = host.failed(std::slice::from_ref(&f));
        }
    });
    Ok(())
}


/// 取消喜欢：删掉「喜欢」目录里那份副本（只在这个目录里删，绝不碰歌单原文件）。
///
/// 不删的话，下次 favorites_pull 又会把目录里的文件读回来。
pub async fn delete_cloud_favorite(state: &AppState, track: &Track) {
    let Ok(client) = s3_client(state) else {
        return;
    };
    if track.provider != client.provider() {
        return;
    }
    let folder = tinymusic_core::library::favorites_folder(&client.normalized_prefix());
    let mut targets = Vec::new();
    // 收藏本身的 id 就是「喜欢」目录里的对象 key
    if is_cloud_provider(&track.provider) && track.id.starts_with(&folder) {
        targets.push(track.id.clone());
    }
    // 原曲可能还在歌单里，按文件名找到「喜欢」中的副本。
    if !track.title.trim().is_empty() || !track.artist.trim().is_empty() {
        let fname = build_filename(track, "x");
        let stem = fname.strip_suffix(".x").unwrap_or(&fname);
        if let Ok(keys) = client.list_keys(&folder).await {
            for key in &keys {
                let base = key.rsplit_once('.').map(|(a, _)| a).unwrap_or(key.as_str());
                if base.rsplit('/').next() == Some(stem) {
                    targets.push(key.clone());
                }
            }
        }
    }
    targets.sort();
    targets.dedup();
    for key in targets {
        if !key.starts_with(&folder) {
            continue;
        }
        let _ = tinymusic_core::library::remove_from_favorites(&client, &key).await;
    }
}


pub fn favorite_remove(
    state: &AppState,
    provider: String,
    id: String,
    title: Option<String>,
    artist: Option<String>,
) -> Result<(), String> {
    // 「喜欢」目录里的副本和歌单里的原始 key 不是同一个；
    // 同一首歌在不同平台的条目也要一起清掉，否则下次拉取又冒出来。
    let all = state.storage.list_favorites().unwrap_or_default();
    let hit = all
        .iter()
        .find(|t| t.provider == provider && t.id == id)
        .cloned();
    let same_song = hit
        .as_ref()
        .map(tinymusic_core::library::favorite_dedupe_key)
        .or_else(|| {
            let (title, artist) = (title?, artist?);
            if title.trim().is_empty() && artist.trim().is_empty() {
                return None;
            }
            Some(tinymusic_core::library::favorite_key(&title, &artist))
        });
    let mut targets: Vec<Track> = all
        .into_iter()
        .filter(|t| {
            (t.provider == provider && t.id == id)
                || (t.provider == provider && same_song
                    .as_ref()
                    .map(|k| *k == tinymusic_core::library::favorite_dedupe_key(t))
                    .unwrap_or(false))
        })
        .collect();
    if targets.is_empty() {
        targets.push(Track {
            provider: provider.clone(),
            id: id.clone(),
            ..Track::default()
        });
    }
    for t in &targets {
        let _ = state.storage.remove_favorite(&t.provider, &t.id);
    }
    let st = state.strong();
    tokio::spawn(async move {
        for t in targets {
            delete_cloud_favorite(&st, &t).await;
        }
    });
    Ok(())
}


pub fn favorite_list(state: &AppState) -> Result<Vec<Track>, String> {
    state.storage.list_favorites().map_err(|e| e.to_string())
}


/// 是否已收藏。
///
/// 收藏存在「喜欢」目录里，id 是副本的 key，跟歌单里的原始 key 不一样；
/// 所以按 id 查不到时再按歌名+歌手认一遍（iOS 也是这么判的）。
pub fn favorite_check(
    state: &AppState,
    provider: String,
    id: String,
    title: Option<String>,
    artist: Option<String>,
) -> Result<bool, String> {
    if state
        .storage
        .is_favorite(&provider, &id)
        .map_err(|e| e.to_string())?
    {
        return Ok(true);
    }
    let (Some(title), Some(artist)) = (title, artist) else {
        return Ok(false);
    };
    if title.trim().is_empty() && artist.trim().is_empty() {
        return Ok(false);
    }
    let key = tinymusic_core::library::favorite_key(&title, &artist);
    let list = state.storage.list_favorites().map_err(|e| e.to_string())?;
    Ok(list
        .iter()
        .any(|t| t.provider == provider && tinymusic_core::library::favorite_dedupe_key(t) == key))
}


/// 从网盘拉取「喜欢」：只认「喜欢」目录里的实际音频，不再读写 favorites.json。
///
/// 歌单里删掉的歌不会因为 JSON 没同步而继续挂在喜欢里（之前的 bug 就是这么来的）。
pub async fn favorites_pull(state: &AppState) -> Result<Vec<Track>, String> {
    let client = match s3_client(state) {
        Ok(c) => c,
        Err(_) => return state.storage.list_favorites().map_err(|e| e.to_string()),
    };
    tinymusic_core::library::pull_favorites(&client, &state.storage).await
}


pub fn settings_get(state: &AppState) -> Settings {
    state.settings_snapshot()
}


pub fn settings_set(state: &AppState, mut settings: Settings) -> Result<(), String> {
    normalize_settings(&mut settings);
    match Quality::parse(&settings.default_quality) {
        Some(q) if !q.is_advanced() => {}
        Some(q) => return Err(format!("{} 当前未接入", q.label())),
        None => return Err("未知音质".into()),
    }
    if let Ok(mut s) = state.settings.lock() {
        *s = settings.clone();
    }
    save_settings(&state.config_dir, &settings);
    Ok(())
}


/// 只改默认音质（播放器菜单用），避免覆盖其他设置。
pub fn quality_set(state: &AppState, quality: String) -> Result<String, String> {
    let q = Quality::parse(&quality).ok_or_else(|| "未知音质".to_string())?;
    if q.is_advanced() {
        return Err(format!("{} 当前未接入", q.label()));
    }
    let mut settings = state.settings_snapshot();
    settings.default_quality = q.as_str().to_string();
    normalize_settings(&mut settings);
    if let Ok(mut s) = state.settings.lock() {
        *s = settings.clone();
    }
    save_settings(&state.config_dir, &settings);
    Ok(q.as_str().to_string())
}


/// 六个档位的全局可用性。前三个可播；高级三档当前只有说明。
pub fn quality_capabilities() -> Vec<QualityCapability> {
    const ALL: [Quality; 6] = [
        Quality::Standard,
        Quality::Super,
        Quality::Lossless,
        Quality::HiRes,
        Quality::Atmos,
        Quality::Master,
    ];
    ALL.iter()
        .map(|q| {
            let advanced = q.is_advanced();
            QualityCapability {
                value: *q,
                label: q.label().to_string(),
                kbps: q.nominal_kbps(),
                lossless: q.is_lossless(),
                available: !advanced,
                reason: if advanced {
                    Some("需要会员账号与加密音频解密，当前版本未接入".into())
                } else {
                    None
                },
            }
        })
        .collect()
}

// ---------- 歌单 ----------


pub async fn download_batch(
    state: &AppState,
    tracks: Vec<Track>,
    quality: Option<String>,
    on_progress: ProgressFn,
) -> Result<Vec<String>, String> {
    if tracks.is_empty() {
        return Ok(Vec::new());
    }
    let settings = state.settings_snapshot();
    let q = Quality::from_str(quality.as_deref().unwrap_or(&settings.default_quality));
    let dir = PathBuf::from(&settings.download_dir);

    let mut ids = Vec::new();
    let mut failures: Vec<FailedDownload> = Vec::new();
    let mut failed = 0usize;
    let total_n = tracks.len();

    for (i, track) in tracks.iter().enumerate() {
        // 进度先报「第 i 首 / 共 n 首」的起步态，界面能看出在动
        let _ = on_progress(Progress {
            task_id: format!("batch-{}-{}", i, track.id),
            downloaded: i as u64,
            total: Some(total_n as u64),
        });

        if is_cloud_provider(&track.provider) {
            let Ok(client) = track_cloud_client(state, &track.provider) else {
                failed += 1;
                continue;
            };
            let task_id = cloud_download_task_id(state, track);
            let outcome = download_cloud_track(state, &client, track, &task_id, None, Some(on_progress.clone())).await;
            if outcome.ok {
                ids.push(task_id);
            } else {
                failed += 1;
            }
            failures.extend(outcome.failure);
            continue;
        }
        let p = match state.provider(&track.provider) {
            Ok(p) => p,
            Err(_) => {
                failed += 1;
                continue;
            }
        };

        let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
        let task_id = format!("b{}-{}", seq, track.id);
        let outcome = download_one_local(
            state.http.clone(),
            state.storage.clone(),
            state.downloader.clone(),
            p.clone(),
            track.clone(),
            q,
            dir.clone(),
            task_id.clone(),
            Some(on_progress.clone()),
        )
        .await;

        if outcome.ok {
            ids.push(task_id);
        } else {
            failed += 1;
        }
        if let Some(f) = outcome.failure {
            failures.push(f);
        }
    }

    let _ = on_progress(Progress {
        task_id: "batch-done".into(),
        downloaded: ids.len() as u64,
        total: Some(total_n as u64),
    });
    if !failures.is_empty() {
        let _ = state.host.failed(&failures);
    }
    if ids.is_empty() && failed > 0 {
        return Err(format!("{} 首全部失败（可能都不可用）", failed));
    }
    Ok(ids)
}


pub use tinymusic_core::library::S3PlaylistInfo;


pub async fn s3_test(state: &AppState) -> Result<String, String> {
    let s3 = s3_client(&state)?;
    s3.test().await.map_err(|e| e.to_string())
}


pub use tinymusic_core::library::{
    find_sibling, is_playlist_folder, is_root_key, key_under_prefix, parse_track_filename,
    playlists_from_keys, S3TrackRow,
};

pub async fn s3_playlists(state: &AppState) -> Result<Vec<S3PlaylistInfo>, String> {
    match s3_client(state) {
        Ok(client) => tinymusic_core::library::list_s3_playlists(&client, &state.storage).await,
        Err(error) if state.settings_snapshot().webdav_enabled => Err(error),
        Err(_) => state.storage.list_s3_playlists()
            .map(|names| names.into_iter().map(|name| S3PlaylistInfo {
                name, count: 0, cover: None, root: false,
            }).collect())
            .map_err(|e| e.to_string()),
    }
}

pub async fn s3_playlist_tracks(
    state: &AppState,
    name: String,
    root: Option<bool>,
) -> Result<Vec<S3TrackRow>, String> {
    let client = s3_client(state)?;
    tinymusic_core::library::s3_playlist_tracks(&client, &name, root.unwrap_or(false)).await
}

/// 删除网盘歌单：连同云端文件一起删
pub async fn s3_playlist_purge(state: &AppState, name: String) -> Result<(), String> {
    let client = s3_client(state)?;
    let name = match &client {
        CloudLibrary::WebDav(..) => name,
        CloudLibrary::S3(_) => sanitize_playlist_name(&name)?,
    };
    if name == FAVORITES_PLAYLIST {
        return Err("「喜欢」由红心管理，不能在这里删除".into());
    }
    if name == ROOT_PLAYLIST_LABEL {
        return Err("「未分类」是根目录，不能整组删除".into());
    }
    if let CloudLibrary::WebDav(webdav, _) = &client {
        return webdav.delete_playlist(&name).await.map_err(|error| error.to_string());
    }
    let folder = playlist_prefix(&client.normalized_prefix(), &name);
    let keys = client.list_keys(&folder).await.map_err(|e| e.to_string())?;
    for key in keys {
        client
            .delete_object(&key)
            .await
            .map_err(|e| format!("删除 {} 失败：{}", key, e))?;
    }
    state
        .storage
        .remove_s3_playlist(&name)
        .map_err(|e| e.to_string())
}


/// 重命名歌单：按前缀把对象一个个搬到新目录
pub async fn s3_playlist_rename(
    state: &AppState,
    old: String,
    new: String,
) -> Result<String, String> {
    let client = s3_client(state)?;
    let (old, new) = match &client {
        CloudLibrary::WebDav(..) => (old, sanitize_playlist_name(&new)?),
        CloudLibrary::S3(_) => (sanitize_playlist_name(&old)?, sanitize_playlist_name(&new)?),
    };
    if old == FAVORITES_PLAYLIST {
        return Err("「喜欢」不能重命名".into());
    }
    if new == FAVORITES_PLAYLIST {
        return Err("「喜欢」是保留名".into());
    }
    if new == ROOT_PLAYLIST_LABEL {
        return Err(format!("「{}」是根目录专用名", ROOT_PLAYLIST_LABEL));
    }
    if old == new {
        return Ok(new);
    }
    if let CloudLibrary::WebDav(webdav, _) = &client {
        webdav.rename_playlist(&old, &new).await.map_err(|error| error.to_string())?;
        tinymusic_core::library::rename_webdav_playlist_in_order(&state.storage, &old, &new)?;
        return Ok(new);
    }
    let existing = state
        .storage
        .list_s3_playlists()
        .map_err(|e| e.to_string())?;
    if existing.iter().any(|p| p == &new) {
        return Err(format!("已经有叫「{}」的歌单了", new));
    }

    let prefix = client.normalized_prefix();
    let old_folder = playlist_prefix(&prefix, &old);
    let new_folder = playlist_prefix(&prefix, &new);
    let keys = client
        .list_keys(&old_folder)
        .await
        .map_err(|e| e.to_string())?;
    for key in keys {
        let suffix = key.strip_prefix(&old_folder).unwrap_or(&key);
        client
            .move_object(&key, &format!("{}{}", new_folder, suffix))
            .await
            .map_err(|e| format!("移动 {} 失败：{}", key, e))?;
    }

    state
        .storage
        .remove_s3_playlist(&old)
        .map_err(|e| e.to_string())?;
    state
        .storage
        .save_s3_playlist(&new)
        .map_err(|e| e.to_string())?;
    Ok(new)
}


/// 现签一个网盘曲目的封面直链。
///
/// 队列里的 s3 曲目可能来自几小时前的列表，内嵌的封面直链已经过期；
/// 播放时重签一次，避免播放条/歌词页显示裂图。
pub async fn s3_cover(state: &AppState, key: String, provider: Option<String>) -> Result<Option<String>, String> {
    if let Some((_, path)) = provider.as_deref().and_then(|provider| local_download(state, provider, &key)) {
        for (ext, mime) in [("jpg", "image/jpeg"), ("jpeg", "image/jpeg"), ("png", "image/png"), ("webp", "image/webp")] {
            let cover = path.with_extension(ext);
            if cover.is_file() {
                return Ok(Some(state.proxy.register_file(cover, Some(mime.into())).await));
            }
        }
    }
    let client = match provider {
        Some(provider) => track_cloud_client(state, &provider)?,
        None => s3_client(state)?,
    };
    Ok(tinymusic_core::library::signed_cover_for(&client, &key).await)
}


/// 删除歌单里的单曲（音频 + 同名歌词/封面）
pub async fn s3_track_delete(state: &AppState, key: String) -> Result<(), String> {
    if !is_audio_key(&key) {
        return Err("曲目路径必须指向音频文件".into());
    }
    let client = s3_client(&state)?;
    client
        .delete_object(&key)
        .await
        .map_err(|e| e.to_string())?;
    let stem = key.rsplit_once('.').map(|(a, _)| a).unwrap_or(key.as_str());
    for ext in ["lrc", "jpg", "jpeg", "png", "webp"] {
        let _ = client.delete_object(&format!("{}.{}", stem, ext)).await;
    }
    // 从网盘删掉的 S3 曲目，本地收藏缓存也要一起清掉（收藏只认「喜欢」目录）
    let _ = state.storage.remove_favorite(client.provider(), &key);
    Ok(())
}


/// 按拖拽后的顺序保存歌单排序
pub fn s3_playlists_reorder(state: &AppState, names: Vec<String>) -> Result<(), String> {
    if state.settings_snapshot().webdav_enabled {
        return tinymusic_core::library::reorder_webdav_playlists(&state.storage, &names);
    }
    state
        .storage
        .reorder_s3_playlists(&names)
        .map_err(|e| e.to_string())
}


pub async fn s3_playlist_create(state: &AppState, name: String) -> Result<String, String> {
    let name = sanitize_playlist_name(&name)?;
    if name == ROOT_PLAYLIST_LABEL {
        return Err(format!("「{}」是根目录专用名，换一个", ROOT_PLAYLIST_LABEL));
    }
    if state.settings_snapshot().webdav_enabled {
        let CloudLibrary::WebDav(client, _) = s3_client(state)? else {
            return Err("网盘协议已切换，请重试".into());
        };
        if name == FAVORITES_PLAYLIST {
            return Err("该歌单名已保留，请换一个名称".into());
        }
        client.create_playlist(&name).await.map_err(|error| error.to_string())?;
        return Ok(name);
    }
    state
        .storage
        .save_s3_playlist(&name)
        .map_err(|e| e.to_string())?;
    // 对象存储没有真目录：写一个 0 字节标记，别的设备连同一个桶时也能发现空歌单。
    // 失败不影响本地创建。
    if let Ok(client) = s3_client(&state) {
        let key = format!(
            "{}.keep",
            playlist_prefix(&client.normalized_prefix(), &name)
        );
        let _ = client
            .put_object(&key, Vec::new(), "application/octet-stream")
            .await;
    }
    Ok(name)
}


/// 上传一个对象，失败自动重试（歌词 / 封面这种小对象单独走一遍）
pub async fn put_object_retry(
    s3: CloudLibrary,
    key: String,
    body: Vec<u8>,
    content_type: &str,
) -> Result<(), String> {
    let ct = content_type.to_string();
    with_retries(move |_| {
        let s3 = s3.clone();
        let key = key.clone();
        let body = body.clone();
        let ct = ct.clone();
        async move { s3.put_object(&key, body, &ct).await }
    })
    .await
}


/// 网盘上传一首：取流 → 内存下载（顺带打标签）→ 上传音频 / 歌词 / 封面。
///
/// 每一步都自动重试；仍然失败的部分写进 `download_failures`，
/// 任务结束弹窗让用户手动重试。
pub async fn upload_one_s3(
    http: Arc<HttpClient>,
    storage: Arc<Storage>,
    downloader: Arc<Downloader>,
    provider: Arc<dyn MusicProvider>,
    s3: CloudLibrary,
    track: Track,
    q: Quality,
    playlist: String,
    task_id: String,
    on_progress: Option<ProgressFn>,
) -> TrackOutcome {
    let _ = storage.insert_download(&task_id, &track, q, "", 0, "running");

    // 1) 取流
    let (resolve_provider, resolve_track) = (provider.clone(), track.clone());
    let info = with_retries(move |_| {
        let provider = resolve_provider.clone();
        let track = resolve_track.clone();
        async move { provider.resolve(&track, q).await }
    })
    .await;
    let info = match info {
        Ok(v) => v,
        Err(e) => {
            let _ = storage.update_download(&task_id, &format!("failed: {}", e), 0);
            let failure = failure_record(
                &track,
                q,
                "s3",
                &playlist,
                "",
                vec![FailedPart {
                    part: "audio".into(),
                    error: e,
                }],
            );
            let _ = storage.upsert_download_failure(&failure);
            return TrackOutcome {
                ok: false,
                location: String::new(),
                failure: Some(failure),
            };
        }
    };

    let _ = storage.insert_download(&task_id, &track, info.quality, "", 0, "running");
    let key = object_key(
        &s3.normalized_prefix(),
        &playlist,
        &track,
        actual_ext(&info),
    );
    let location = format!("s3://{}/{}", s3.bucket().unwrap_or_default(), key);

    let (extras, mut parts) = build_extras(http, provider, &track, true, true).await;

    // 2) 音频字节：直接在内存里下载 + 打标签，不写临时文件
    //    （避免被杀软误判为「加密 / 删除用户音乐」）
    let bytes = with_retries({
        let downloader = downloader.clone();
        let track = track.clone();
        let info = info.clone();
        let extras = extras.clone();
        let ch = on_progress.clone();
        let tid = task_id.clone();
        move |_| {
            let downloader = downloader.clone();
            let track = track.clone();
            let info = info.clone();
            let extras = extras.clone();
            let ch = ch.clone();
            let tid = tid.clone();
            async move {
                downloader
                    .fetch_bytes(
                        &track,
                        &info,
                        &extras,
                        Box::new(move |downloaded, total| {
                            if let Some(ch) = &ch {
                                let _ = ch(Progress {
                                    task_id: tid.clone(),
                                    downloaded,
                                    total,
                                });
                            }
                        }),
                    )
                    .await
            }
        }
    })
    .await;

    let bytes = match bytes {
        Ok(b) => b,
        Err(e) => {
            let _ = storage.update_download(&task_id, &format!("failed: {}", e), 0);
            parts.insert(
                0,
                FailedPart {
                    part: "audio".into(),
                    error: e,
                },
            );
            let failure = failure_record(&track, info.quality, "s3", &playlist, "", parts);
            let _ = storage.upsert_download_failure(&failure);
            return TrackOutcome {
                ok: false,
                location: String::new(),
                failure: Some(failure),
            };
        }
    };
    let size = bytes.len() as i64;

    // 3) 音频对象
    let audio_key = key.clone();
    let s3_audio = s3.clone();
    let payload = bytes.clone();
    let uploaded = with_retries(move |_| {
        let s3 = s3_audio.clone();
        let key = audio_key.clone();
        let body = payload.clone();
        async move { s3.put_object(&key, body, audio_content_type(&key)).await }
    })
    .await;
    if let Err(e) = uploaded {
        let _ = storage.update_download(&task_id, &format!("failed: {}", e), 0);
        parts.insert(
            0,
            FailedPart {
                part: "audio".into(),
                error: e,
            },
        );
        let failure = failure_record(&track, info.quality, "s3", &playlist, "", parts);
        let _ = storage.upsert_download_failure(&failure);
        return TrackOutcome {
            ok: false,
            location: String::new(),
            failure: Some(failure),
        };
    }

    // 4) 歌词 / 封面对象：失败只记录，不影响已经上传的音频
    if let Some(lrc) = extras.lyrics_lrc.clone() {
        if let Err(e) = put_object_retry(
            s3.clone(),
            replace_ext(&key, "lrc"),
            lrc.into_bytes(),
            "text/plain; charset=utf-8",
        )
        .await
        {
            parts.push(FailedPart {
                part: "lyrics".into(),
                error: e,
            });
        }
    }
    if let Some(cover) = extras.cover.clone() {
        let mime = cover_mime(&extras).to_string();
        if let Err(e) = put_object_retry(s3.clone(), replace_ext(&key, "jpg"), cover, &mime).await {
            parts.push(FailedPart {
                part: "cover".into(),
                error: e,
            });
        }
    }

    let _ = storage.insert_download(&task_id, &track, info.quality, &location, size, "done");
    if parts.is_empty() {
        // 之前失败过但这次传全了：清掉旧记录
        let _ = storage.remove_download_failure(&failure_id("s3", &track));
        TrackOutcome {
            ok: true,
            location,
            failure: None,
        }
    } else {
        let failure = failure_record(&track, info.quality, "s3", &playlist, &location, parts);
        let _ = storage.upsert_download_failure(&failure);
        TrackOutcome {
            ok: true,
            location,
            failure: Some(failure),
        }
    }
}


pub async fn s3_download(
    state: &AppState,
    track: Track,
    quality: Option<String>,
    playlist: Option<String>,
    on_progress: ProgressFn,
) -> Result<String, String> {
    let settings = state.settings_snapshot();
    let q = Quality::from_str(quality.as_deref().unwrap_or(&settings.default_quality));
    let s3 = s3_client(&state)?;

    let raw_playlist = playlist.unwrap_or_default();
    let playlist = if raw_playlist.trim().is_empty() {
        String::new()
    } else {
        sanitize_playlist_name(&raw_playlist)?
    };

    let p = state.provider(&track.provider)?;

    let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
    let task_id = format!("s3-{}-{}", seq, track.id);

    let outcome = upload_one_s3(
        state.http.clone(),
        state.storage.clone(),
        state.downloader.clone(),
        p,
        s3,
        track,
        q,
        playlist.clone(),
        task_id,
        Some(on_progress),
    )
    .await;

    if let Some(f) = &outcome.failure {
        let _ = state.host.failed(std::slice::from_ref(&f));
    }
    if !playlist.is_empty() {
        let _ = state.storage.save_s3_playlist(&playlist);
    }
    if outcome.ok {
        Ok(outcome.location)
    } else {
        Err(outcome
            .failure
            .and_then(|f| f.parts.first().map(|p| p.error.clone()))
            .unwrap_or_else(|| "上传失败".into()))
    }
}


pub async fn s3_download_batch(
    state: &AppState,
    tracks: Vec<Track>,
    quality: Option<String>,
    playlist: Option<String>,
    on_progress: ProgressFn,
) -> Result<Vec<String>, String> {
    if tracks.is_empty() {
        return Ok(Vec::new());
    }
    let settings = state.settings_snapshot();
    let q = Quality::from_str(quality.as_deref().unwrap_or(&settings.default_quality));
    let s3 = s3_client(&state)?;

    let raw_playlist = playlist.unwrap_or_default();
    let playlist = if raw_playlist.trim().is_empty() {
        String::new()
    } else {
        sanitize_playlist_name(&raw_playlist)?
    };

    let total = tracks.len();
    let mut keys = Vec::new();
    let mut failures: Vec<FailedDownload> = Vec::new();
    let mut failed = 0usize;

    for (i, track) in tracks.iter().enumerate() {
        let _ = on_progress(Progress {
            task_id: format!("batch-{}-{}", i, track.id),
            downloaded: i as u64,
            total: Some(total as u64),
        });

        let p = match state.provider(&track.provider) {
            Ok(p) => p,
            Err(_) => {
                failed += 1;
                continue;
            }
        };

        let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
        let task_id = format!("s3b-{}-{}", seq, track.id);
        let outcome = upload_one_s3(
            state.http.clone(),
            state.storage.clone(),
            state.downloader.clone(),
            p,
            s3.clone(),
            track.clone(),
            q,
            playlist.clone(),
            task_id,
            None,
        )
        .await;

        if outcome.ok {
            keys.push(outcome.location);
        } else {
            failed += 1;
        }
        if let Some(f) = outcome.failure {
            failures.push(f);
        }
    }

    let _ = on_progress(Progress {
        task_id: "batch-done".into(),
        downloaded: keys.len() as u64,
        total: Some(total as u64),
    });

    if !playlist.is_empty() {
        let _ = state.storage.save_s3_playlist(&playlist);
    }
    if !failures.is_empty() {
        let _ = state.host.failed(&failures);
    }
    if keys.is_empty() && failed > 0 {
        return Err(format!(
            "{} 首全部失败（可能都不可用，或网盘配置有问题）",
            failed
        ));
    }
    Ok(keys)
}

// ---------- 网盘完整性检测 ----------


/// 网盘里一首歌缺了哪一部分
#[derive(Debug, Clone, Serialize)]
pub struct S3IntegrityIssue {
    /// 稳定 id：歌单 + 文件主干（stem）
    pub id: String,
    /// 歌单（相对 prefix 的目录名）
    pub playlist: String,
    /// 音频 key 去掉扩展名后的完整路径
    pub stem: String,
    /// 现存音频 key；音频本身缺失时为空
    pub key: String,
    pub title: String,
    pub artist: String,
    /// `audio` / `lyrics` / `cover`
    pub missing: Vec<String>,
    /// 能用来补齐的来源平台（kuwo / netease）；找不到来源时为空
    pub source: String,
    pub can_fix: bool,
}


#[derive(Debug, Clone, Serialize)]
pub struct S3IntegrityReport {
    /// 实际检查了多少个条目（含只剩歌词/封面的残留）
    pub checked: u32,
    pub issues: Vec<S3IntegrityIssue>,
}


/// 补齐过程中逐步推给前端的进度：让列表能实时显示「正在补哪一个 / 谁好了 / 谁失败」
#[derive(Debug, Clone, Serialize)]
pub struct S3FixProgress {
    pub id: String,
    /// `running` / `done` / `failed`
    pub status: String,
    /// 这次之后仍然缺的部分；`done` 时为空
    pub missing: Vec<String>,
    pub error: String,
    /// 已处理数量（running 时是当前项的序号，done/failed 时含本项）
    pub done: u32,
    pub total: u32,
}


pub struct S3SourceIndex {
    by_key: HashMap<String, Track>,
    by_stem: HashMap<String, Track>,
}


/// 上传记录 → 源曲目索引。
///
/// `by_key` 用完整对象 key；`by_stem` 去掉扩展名，用于「音频被删、只剩 sidecar」
/// 的情况也能找回原平台信息。
pub fn s3_source_index(storage: &Storage, bucket: &str) -> S3SourceIndex {
    let mut by_key = HashMap::new();
    let mut by_stem = HashMap::new();
    if let Ok(rows) = storage.list_s3_sources() {
        for (path, track) in rows {
            let Some(rest) = path.strip_prefix("s3://") else {
                continue;
            };
            let Some((b, key)) = rest.split_once('/') else {
                continue;
            };
            if b != bucket {
                continue;
            }
            by_stem
                .entry(stem_of(key).to_string())
                .or_insert_with(|| track.clone());
            by_key.entry(key.to_string()).or_insert(track);
        }
    }
    S3SourceIndex { by_key, by_stem }
}


pub fn stem_of(key: &str) -> &str {
    key.rsplit_once('.').map(|(a, _)| a).unwrap_or(key)
}


pub fn is_image_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    [".jpg", ".jpeg", ".png", ".webp"]
        .iter()
        .any(|e| lower.ends_with(e))
}


pub fn is_lrc_key(key: &str) -> bool {
    key.to_ascii_lowercase().ends_with(".lrc")
}


/// 常见的「整张专辑/文件夹一张图」文件名，别当成某首歌的封面去报缺音频
pub fn is_folder_art(stem: &str) -> bool {
    let name = stem.rsplit('/').next().unwrap_or(stem).to_ascii_lowercase();
    matches!(
        name.as_str(),
        "cover" | "folder" | "album" | "albumart" | "album_art" | "front" | "artwork" | "thumb"
    )
}


/// 目录 → 歌单名（prefix 之下的一级目录；根目录里的散歌为空）
pub fn folder_playlist(prefix: &str, folder: &str) -> String {
    let p = prefix.trim_matches('/');
    if p.is_empty() {
        folder.trim_matches('/').to_string()
    } else {
        folder
            .strip_prefix(p)
            .unwrap_or(folder)
            .trim_matches('/')
            .to_string()
    }
}


/// 扫描网盘（整库或单个歌单），找出缺音频 / 歌词 / 封面的条目
pub async fn check_s3_integrity(
    storage: &Storage,
    s3: &CloudLibrary,
    only: Option<&str>,
) -> Result<S3IntegrityReport, String> {
    let prefix = s3.normalized_prefix();
    let scope = match only.filter(|s| !s.trim().is_empty()) {
        Some(pl) => s3.playlist_prefix(pl),
        None => {
            if prefix.is_empty() {
                String::new()
            } else {
                format!("{}/", prefix)
            }
        }
    };
    let keys = s3
        .list_keys_all(&scope)
        .await
        .map_err(|e| e.to_string())?;
    let sources = s3_source_index(storage, s3.bucket().unwrap_or_default());
    Ok(analyze_s3_keys(&keys, &prefix, &sources))
}


/// 纯逻辑：把对象清单按「目录 + 文件主干」分组，找缺失的部分。
///
/// 抽出来是为了能不开网盘直接测：音频在、缺歌词/封面；只剩 sidecar 的算缺音频。
pub fn analyze_s3_keys(keys: &[String], prefix: &str, sources: &S3SourceIndex) -> S3IntegrityReport {
    // 目录 → 小写 stem → 这一组里有哪些文件
    #[derive(Default)]
    struct Group {
        stem: String,
        audio: Option<String>,
        lrc: bool,
        cover: bool,
    }
    let mut folders: HashMap<String, HashMap<String, Group>> = HashMap::new();
    for key in keys {
        let folder = key
            .rsplit_once('/')
            .map(|(f, _)| f.to_string())
            .unwrap_or_default();
        let stem = stem_of(key).to_string();
        let entry = folders
            .entry(folder)
            .or_default()
            .entry(stem.to_ascii_lowercase())
            .or_insert_with(|| Group {
                stem,
                ..Default::default()
            });
        if is_audio_key(key) {
            entry.audio = Some(key.clone());
        } else if is_lrc_key(key) {
            entry.lrc = true;
        } else if is_image_key(key) {
            entry.cover = true;
        }
    }

    let mut checked = 0u32;
    let mut issues = Vec::new();
    for (folder, groups) in folders {
        let playlist = folder_playlist(prefix, &folder);
        for group in groups.into_values() {
            // 既不是音频、也不是歌词/封面（比如 favorites.json）就跳过
            if group.audio.is_none() && !group.lrc && !group.cover {
                continue;
            }
            // 文件夹级的 cover.jpg / folder.jpg 不是某首歌的附属文件
            if group.audio.is_none() && is_folder_art(&group.stem) {
                continue;
            }
            checked += 1;
            let mut missing = Vec::new();
            if group.audio.is_none() {
                missing.push("audio".to_string());
            }
            if group.audio.is_some() && !group.lrc {
                missing.push("lyrics".to_string());
            }
            if group.audio.is_some() && !group.cover {
                missing.push("cover".to_string());
            }
            if missing.is_empty() {
                continue;
            }
            let (artist, title) = parse_track_filename(&group.stem);
            let source = match &group.audio {
                Some(key) => sources.by_key.get(key),
                None => sources.by_stem.get(&group.stem),
            };
            issues.push(S3IntegrityIssue {
                id: format!("{}:{}", playlist, group.stem),
                playlist: playlist.clone(),
                stem: group.stem.clone(),
                key: group.audio.unwrap_or_default(),
                title,
                artist,
                missing,
                source: source.map(|t| t.provider.clone()).unwrap_or_default(),
                can_fix: source.is_some(),
            });
        }
    }
    issues.sort_by(|a, b| a.playlist.cmp(&b.playlist).then(a.stem.cmp(&b.stem)));
    S3IntegrityReport { checked, issues }
}


/// 老上传记录没有封面地址：按「标题 + 歌手」搜一次，优先取同一个曲目 id
pub async fn lookup_cover(state: &AppState, track: &Track) -> Option<String> {
    if track
        .cover
        .as_deref()
        .map(str::trim)
        .is_some_and(|u| !u.is_empty())
    {
        return track.cover.clone();
    }
    let provider = state.provider(&track.provider).ok()?;
    let page = provider
        .search(&format!("{} {}", track.title, track.artist), 1, 20)
        .await
        .ok()?;
    page.items
        .iter()
        .find(|t| t.id == track.id)
        .or_else(|| {
            page.items
                .iter()
                .find(|t| t.title == track.title && t.artist == track.artist)
        })
        .and_then(|t| t.cover.clone())
}


pub async fn s3_integrity_check(
    state: &AppState,
    playlist: Option<String>,
) -> Result<S3IntegrityReport, String> {
    let s3 = s3_client(&state)?;
    check_s3_integrity(&state.storage, &s3, playlist.as_deref()).await
}


/// 补齐选中的条目：缺音频就整首重传，只缺歌词/封面就补对象。
/// 返回补齐后重新扫描的结果。
pub async fn s3_integrity_fix(
    state: &AppState,
    playlist: Option<String>,
    ids: Vec<String>,
    on_progress: S3FixFn,
) -> Result<S3IntegrityReport, String> {
    let s3 = s3_client(&state)?;
    let report = check_s3_integrity(&state.storage, &s3, playlist.as_deref()).await?;
    let sources = s3_source_index(&state.storage, s3.bucket().unwrap_or_default());
    let settings = state.settings_snapshot();
    let q = Quality::from_str(&settings.default_quality);
    let total = ids.len() as u32;

    for (i, id) in ids.iter().enumerate() {
        let Some(issue) = report.issues.iter().find(|x| &x.id == id) else {
            // 列表过期了（比如刚被别的设备补过）：当作已完成
            let _ = on_progress(S3FixProgress {
                id: id.clone(),
                status: "done".into(),
                missing: Vec::new(),
                error: String::new(),
                done: i as u32 + 1,
                total,
            });
            continue;
        };
        let _ = on_progress(S3FixProgress {
            id: id.clone(),
            status: "running".into(),
            missing: issue.missing.clone(),
            error: String::new(),
            done: i as u32,
            total,
        });

        let (missing, error) =
            fix_integrity_issue(&state, &s3, &sources, issue, q).await;
        let _ = on_progress(S3FixProgress {
            id: id.clone(),
            status: if missing.is_empty() { "done" } else { "failed" }.into(),
            missing,
            error,
            done: i as u32 + 1,
            total,
        });
    }

    // 以重新扫描的结果为准（补齐中途失败 / 上传了但服务端仍看不到的都以它为准）
    check_s3_integrity(&state.storage, &s3, playlist.as_deref()).await
}


/// 补一条：缺音频就整首重传，只缺歌词/封面就补对象。
/// 返回（仍然缺的部分, 错误说明）。
pub async fn fix_integrity_issue(
    state: &AppState,
    s3: &CloudLibrary,
    sources: &S3SourceIndex,
    issue: &S3IntegrityIssue,
    q: Quality,
) -> (Vec<String>, String) {
    let source = if issue.key.is_empty() {
        sources.by_stem.get(&issue.stem)
    } else {
        sources.by_key.get(&issue.key)
    };
    let Some(source) = source.cloned() else {
        return (issue.missing.clone(), "找不到来源平台信息".into());
    };
    let provider = match state.provider(&source.provider) {
        Ok(p) => p,
        Err(e) => return (issue.missing.clone(), e),
    };
    let mut track = source;
    let has_cover = track
        .cover
        .as_deref()
        .map(str::trim)
        .is_some_and(|u| !u.is_empty());
    if issue.missing.iter().any(|p| p == "cover") && !has_cover {
        if let Some(cover) = lookup_cover(state, &track).await {
            track.cover = Some(cover);
        }
    }

    if issue.missing.iter().any(|p| p == "audio") {
        let seq = state.task_seq.fetch_add(1, Ordering::Relaxed);
        let task_id = format!("fx{}-{}", seq, track.id);
        let outcome = upload_one_s3(
            state.http.clone(),
            state.storage.clone(),
            state.downloader.clone(),
            provider,
            s3.clone(),
            track,
            q,
            issue.playlist.clone(),
            task_id,
            None,
        )
        .await;
        return match outcome.failure {
            None => (Vec::new(), String::new()),
            Some(f) => (
                f.parts.iter().map(|p| p.part.clone()).collect(),
                f.parts
                    .first()
                    .map(|p| p.error.clone())
                    .unwrap_or_default(),
            ),
        };
    }

    let parts: Vec<FailedPart> = issue
        .missing
        .iter()
        .filter(|p| p.as_str() != "audio")
        .map(|p| FailedPart {
            part: p.clone(),
            error: "网盘里缺失".into(),
        })
        .collect();
    let left = repair_s3_extras(state.http.clone(), provider, s3, &track, &issue.key, &parts).await;
    (
        left.iter().map(|p| p.part.clone()).collect(),
        left.first().map(|p| p.error.clone()).unwrap_or_default(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicU32;

    /// 失败一次、第二次成功：重试按预期收手
    #[tokio::test]
    async fn retries_until_success() {
        let calls = Arc::new(AtomicU32::new(0));
        let c = calls.clone();
        let res: Result<u32, String> = with_retries(move |_| {
            let c = c.clone();
            async move {
                let n = c.fetch_add(1, Ordering::SeqCst) + 1;
                if n < 2 {
                    Err(CoreError::Http("boom".into()))
                } else {
                    Ok(n)
                }
            }
        })
        .await;
        assert_eq!(res.unwrap(), 2);
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    /// 下载内嵌封面：先试高清，失败再退回列表里的缩略图
    #[test]
    fn cover_candidates_prefer_hires() {
        assert_eq!(
            cover_candidates("https://a/120.jpg", Some("https://a/1080.jpg".into())),
            vec!["https://a/1080.jpg", "https://a/120.jpg"]
        );
        // 平台不升级 / 升级后地址没变时只抓一次
        assert_eq!(
            cover_candidates("https://a/1.jpg", None),
            vec!["https://a/1.jpg"]
        );
        assert_eq!(
            cover_candidates("https://a/1.jpg", Some("https://a/1.jpg".into())),
            vec!["https://a/1.jpg"]
        );
    }

    /// 换设备后靠对象目录把歌单找回来：只取前缀下的一级目录
    #[test]
    fn discovers_playlists_from_object_keys() {
        let keys: Vec<String> = [
            "TinyMusic/周杰伦精选/七里香.flac",
            "TinyMusic/喜欢/周杰伦 - 稻香.mp3",
            "TinyMusic/喜欢/周杰伦 - 稻香.jpg",
            "TinyMusic/喜欢/2024/旧歌.mp3",
            "TinyMusic/favorites.json",
            "TinyMusic/散歌.mp3",
            "NotMine/x.mp3",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        assert_eq!(
            playlists_from_keys(&keys, "TinyMusic"),
            vec!["周杰伦精选".to_string(), "喜欢".to_string()]
        );
        // 前缀对不上时不会把别人的目录算进来
        assert!(playlists_from_keys(&keys, "NotMine").is_empty());
        // 没配前缀时按桶的一级目录
        assert_eq!(
            playlists_from_keys(&["A/x.mp3".to_string(), "root.mp3".to_string()], ""),
            vec!["A".to_string()]
        );
    }

    /// 根目录散歌的识别
    #[test]
    fn detects_root_keys() {
        let p = "TinyMusic";
        assert!(is_root_key("TinyMusic/周杰伦 - 稻香.mp3", p));
        assert!(is_root_key("TinyMusic/favorites.json", p));
        assert!(!is_root_key("TinyMusic/喜欢/周杰伦 - 稻香.mp3", p));
        assert!(!is_root_key("Other/x.mp3", p));
        assert!(is_root_key("x.mp3", ""));
        assert!(!is_root_key("a/x.mp3", ""));
    }

    /// 只有音频或空歌单标记的目录才算歌单
    #[test]
    fn playlist_folder_filter() {
        let with_song = vec!["TinyMusic/喜欢/周杰伦 - 稻香.mp3".to_string()];
        let with_marker = vec!["TinyMusic/空歌单/.keep".to_string()];
        let only_cover = vec!["TinyMusic/相册/a.jpg".to_string()];
        let hidden = vec!["TinyMusic/.Trash/a.jpg".to_string()];
        assert!(is_playlist_folder("喜欢", &with_song));
        assert!(is_playlist_folder("空歌单", &with_marker));
        assert!(!is_playlist_folder("相册", &only_cover));
        assert!(!is_playlist_folder(".Trash", &hidden));
    }

    /// 完整 / 缺歌词封面 / 只剩 sidecar（音频没了）三种情况
    #[test]
    fn integrity_flags_missing_parts() {
        let keys: Vec<String> = [
            "TinyMusic/喜欢/周杰伦 - 稻香.mp3",
            "TinyMusic/喜欢/周杰伦 - 稻香.lrc",
            "TinyMusic/喜欢/周杰伦 - 稻香.jpg",
            "TinyMusic/喜欢/林俊杰 - 江南.mp3",
            "TinyMusic/喜欢/王菲 - 红豆.lrc",
            "TinyMusic/喜欢/王菲 - 红豆.jpg",
            "TinyMusic/favorites.json",
            "TinyMusic/喜欢/cover.jpg",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        let sources = S3SourceIndex {
            by_key: HashMap::new(),
            by_stem: HashMap::new(),
        };
        let report = analyze_s3_keys(&keys, "TinyMusic", &sources);
        assert_eq!(report.checked, 3, "favorites.json 不该被算成一首歌");
        assert_eq!(report.issues.len(), 2);

        let jiangnan = report
            .issues
            .iter()
            .find(|i| i.title == "江南")
            .expect("缺歌词和封面应该报出来");
        assert_eq!(jiangnan.artist, "林俊杰");
        assert_eq!(jiangnan.playlist, "喜欢");
        assert_eq!(jiangnan.missing, vec!["lyrics", "cover"]);
        assert!(!jiangnan.can_fix);

        let hongdou = report
            .issues
            .iter()
            .find(|i| i.title == "红豆")
            .expect("只剩歌词/封面应该报缺音频");
        assert_eq!(hongdou.missing, vec!["audio"]);
        assert!(hongdou.key.is_empty());

        assert!(!report.issues.iter().any(|i| i.title == "稻香"));
    }

    /// 有本机上传记录 → 能补齐，并带上来源平台
    #[test]
    fn integrity_marks_fixable_with_source() {
        let keys: Vec<String> = ["TinyMusic/喜欢/林俊杰 - 江南.mp3"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let mut by_key = HashMap::new();
        by_key.insert(
            "TinyMusic/喜欢/林俊杰 - 江南.mp3".to_string(),
            Track {
                provider: "kuwo".into(),
                id: "42".into(),
                ..Default::default()
            },
        );
        let sources = S3SourceIndex {
            by_key,
            by_stem: HashMap::new(),
        };
        let report = analyze_s3_keys(&keys, "TinyMusic", &sources);
        assert_eq!(report.issues.len(), 1);
        assert!(report.issues[0].can_fix);
        assert_eq!(report.issues[0].source, "kuwo");
        assert_eq!(report.issues[0].missing, vec!["lyrics", "cover"]);
    }

    /// 「不可用」是确定性结论，不重试，免得白等
    #[tokio::test]
    async fn unavailable_is_not_retried() {
        let calls = Arc::new(AtomicU32::new(0));
        let c = calls.clone();
        let res: Result<u32, String> = with_retries(move |_| {
            let c = c.clone();
            async move {
                c.fetch_add(1, Ordering::SeqCst);
                Err(CoreError::Unavailable)
            }
        })
        .await;
        assert!(res.is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
}

impl AppState {
    /// 装配后端：桌面传 app_config_dir，mobile 传 Application Support；
    /// `default_download_dir` 只在设置里还没有下载目录时使用。
    pub async fn new(
        config_dir: PathBuf,
        default_download_dir: PathBuf,
        host: Arc<dyn Host>,
    ) -> Result<Arc<Self>, String> {
        std::fs::create_dir_all(&config_dir).map_err(|e| format!("创建配置目录失败: {e}"))?;
        let _ = std::fs::remove_dir(config_dir.join("s3tmp"));

        let http = Arc::new(HttpClient::new(700, 3));
        let proxy = StreamProxy::start(http.clone())
            .await
            .map_err(|e| format!("启动本地流代理失败: {e}"))?;

        let storage = Arc::new(
            Storage::open(config_dir.join("tinymusic.db")).map_err(|e| format!("打开数据库失败: {e}"))?,
        );
        let has_settings_file = config_dir.join("settings.json").exists();
        let mut settings = load_settings(&config_dir);
        // 第一次启动（没有 settings.json）时用平台约定的下载目录：
        // 桌面是 ~/Music/TinyMusic，mobile 是 App 容器里的 Documents/TinyMusic。
        if !has_settings_file || settings.download_dir.trim().is_empty() {
            settings.download_dir = default_download_dir.to_string_lossy().to_string();
        }
        // iOS 的沙盒容器 UUID 会随重装变化，settings.json 里存的是旧容器的绝对路径。
        // 这里把它改写到当前容器，否则新下载会写进一个"已经不存在于本次安装"的目录。
        settings.download_dir = rebase_sandbox_path(
            &settings.download_dir,
            &default_download_dir.to_string_lossy(),
        );
        let _ = std::fs::create_dir_all(&settings.download_dir);

        let state = Arc::new(AppState {
            http: http.clone(),
            providers: Vec::new(),
            proxy,
            storage,
            downloader: Arc::new(Downloader::new(http)),
            settings: Mutex::new(settings),
            config_dir,
            task_seq: AtomicU64::new(1),
            host,
            me: std::sync::OnceLock::new(),
        });
        let _ = state.me.set(Arc::downgrade(&state));
        Ok(state)
    }

    /// 桌面托盘/前端「打开下载目录」等场景会用到的配置目录
    pub fn config_dir(&self) -> &Path {
        &self.config_dir
    }

    /// 后台任务需要持有 Arc 时用它（装配时写入的弱引用）
    pub fn strong(&self) -> Arc<AppState> {
        self.me
            .get()
            .and_then(|w| w.upgrade())
            .unwrap_or_else(|| panic!("AppState 尚未装配完成或已释放"))
    }
}
