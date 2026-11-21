//! Tauri 桌面外壳：窗口、托盘、更新 等桌面专属能力。
//!
//! 业务逻辑不在这里：桌面与 mobile 共用 `tinymusic_app`（同一份命令实现与 dispatch）。

use std::sync::Arc;
mod theme_pack;
use std::time::Duration;

use tauri::ipc::Channel;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
#[cfg(target_os = "macos")]
use tauri::tray::MouseButtonState;
use tauri::tray::TrayIconBuilder;
#[cfg(any(target_os = "windows", target_os = "macos"))]
use tauri::tray::{MouseButton, TrayIconEvent};
use tauri::{Emitter, Manager, State};

use tinymusic_app::{
    AppState, Host, Progress, ProgressFn, S3FixFn, S3FixProgress, S3IntegrityReport,
};
use tinymusic_core::model::*;
use tinymusic_core::storage::FailedDownload;

fn portable_directory(name: &str) -> Option<std::path::PathBuf> {
    if tauri::is_dev() {
        return None;
    }
    let exe = std::env::current_exe().ok()?;
    #[cfg(target_os = "macos")]
    let base = exe.ancestors()
        .find(|path| path.extension().is_some_and(|ext| ext == "app"))
        .unwrap_or(&exe)
        .parent()?;
    #[cfg(not(target_os = "macos"))]
    let base = exe.parent()?;
    let dir = base.join(name);
    std::fs::create_dir_all(&dir).ok()?;
    tempfile::NamedTempFile::new_in(&dir).ok()?;
    Some(dir)
}

fn prepare_input_directory(config_dir: &std::path::Path) -> std::io::Result<std::path::PathBuf> {
    if let Some(dir) = portable_directory("input") {
        return Ok(dir);
    }
    let base = if tauri::is_dev() {
        config_dir.join("dev")
    } else {
        config_dir.to_path_buf()
    };
    let dir = base.join("input");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}


/// 把后端事件转发到前端：桌面用 Tauri 事件总线（前端 `listen` 收到）
struct AppHost {
    app: tauri::AppHandle,
}

impl Host for AppHost {
    fn failed(&self, failures: &[FailedDownload]) {
        let _ = self.app.emit("download://failed", failures);
    }
}

/// 通用命令入口：前端用 `invoke('tm_invoke', { cmd, args })` 调，落到 `tinymusic_app::dispatch`
#[tauri::command]
async fn tm_invoke(
    state: State<'_, Arc<AppState>>,
    cmd: String,
    args: serde_json::Value,
) -> Result<serde_json::Value, String> {
    tinymusic_app::dispatch::dispatch(state.inner(), &cmd, args, None, None).await
}

#[tauri::command]
fn local_music_input_dir(state: State<'_, Arc<AppState>>) -> Result<String, String> {
    prepare_input_directory(state.config_dir())
        .map(|dir| dir.to_string_lossy().into_owned())
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn local_music_add(
    state: State<'_, Arc<AppState>>,
    paths: Vec<String>,
) -> Result<Vec<Track>, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || tinymusic_app::local_music::add(&state, paths))
        .await.map_err(|err| err.to_string())?
}

#[tauri::command]
async fn local_music_migrate(
    state: State<'_, Arc<AppState>>,
    legacy: Vec<tinymusic_app::local_music::Folder>,
) -> Result<Vec<tinymusic_app::local_music::Folder>, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || tinymusic_app::local_music::migrate(&state, legacy, tauri::is_dev()))
        .await.map_err(|err| err.to_string())?
}

#[tauri::command]
async fn local_music_copy_library(
    state: State<'_, Arc<AppState>>,
    destination: String,
) -> Result<String, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move ||
        tinymusic_app::local_music::copy_library(&state, std::path::Path::new(&destination))
    ).await.map_err(|err| err.to_string())?
}

/// 以下命令带进度通道（Tauri Channel 只能在类型化命令里传），
/// 逻辑仍然只有 tinymusic_app 里的那一份，这里只是把 Channel 包成 ProgressFn。
#[tauri::command]
async fn download_start(
    state: State<'_, Arc<AppState>>,
    track: Track,
    quality: Option<String>,
    on_progress: Channel<Progress>,
) -> Result<String, String> {
    let sink: ProgressFn = Arc::new(move |p: Progress| {
        let _ = on_progress.send(p);
    });
    tinymusic_app::download_start(state.inner(), track, quality, sink).await
}

#[tauri::command]
async fn download_batch(
    state: State<'_, Arc<AppState>>,
    tracks: Vec<Track>,
    quality: Option<String>,
    on_progress: Channel<Progress>,
) -> Result<Vec<String>, String> {
    let sink: ProgressFn = Arc::new(move |p: Progress| {
        let _ = on_progress.send(p);
    });
    tinymusic_app::download_batch(state.inner(), tracks, quality, sink).await
}

#[tauri::command]
async fn s3_download(
    state: State<'_, Arc<AppState>>,
    track: Track,
    quality: Option<String>,
    playlist: Option<String>,
    on_progress: Channel<Progress>,
) -> Result<String, String> {
    let sink: ProgressFn = Arc::new(move |p: Progress| {
        let _ = on_progress.send(p);
    });
    tinymusic_app::s3_download(state.inner(), track, quality, playlist, sink).await
}

#[tauri::command]
async fn s3_download_batch(
    state: State<'_, Arc<AppState>>,
    tracks: Vec<Track>,
    quality: Option<String>,
    playlist: Option<String>,
    on_progress: Channel<Progress>,
) -> Result<Vec<String>, String> {
    let sink: ProgressFn = Arc::new(move |p: Progress| {
        let _ = on_progress.send(p);
    });
    tinymusic_app::s3_download_batch(state.inner(), tracks, quality, playlist, sink).await
}

#[tauri::command]
async fn s3_integrity_fix(
    state: State<'_, Arc<AppState>>,
    playlist: Option<String>,
    ids: Vec<String>,
    on_progress: Channel<S3FixProgress>,
) -> Result<S3IntegrityReport, String> {
    let sink: S3FixFn = Arc::new(move |p: S3FixProgress| {
        let _ = on_progress.send(p);
    });
    tinymusic_app::s3_integrity_fix(state.inner(), playlist, ids, sink).await
}

#[tauri::command]
fn set_window_theme(window: tauri::WebviewWindow, theme: Option<String>) -> Result<(), String> {
    let t = match theme.as_deref() {
        Some("light") => Some(tauri::Theme::Light),
        Some("dark") => Some(tauri::Theme::Dark),
        _ => None,
    };
    window.set_theme(t).map_err(|e| e.to_string())
}


/// 系统版本：玻璃材质要按系统降级（macOS 11/12 的 WKWebView 太旧，
/// 模糊与 oklch 都靠不住，整页会用「边框材质」）。
///
/// 只在桌面壳里实现：前端拿不到这条命令时，只有能力检测兜底。
#[derive(serde::Serialize)]
struct SystemInfo {
    os: String,
    /// macOS 是 "12.7.6" 这种；Windows/Linux 留空（WebView2 是常青的，不用按系统降级）
    #[serde(rename = "osVersion")]
    os_version: String,
}

#[tauri::command]
fn system_info() -> SystemInfo {
    SystemInfo {
        os: std::env::consts::OS.to_string(),
        os_version: os_version(),
    }
}

#[cfg(target_os = "macos")]
fn os_version() -> String {
    use std::sync::OnceLock;
    // 启动后只问一次系统；sw_vers 是一次几十毫秒的子进程，别每帧都问
    static CACHE: OnceLock<String> = OnceLock::new();
    CACHE
        .get_or_init(|| {
            std::process::Command::new("sw_vers")
                .arg("-productVersion")
                .output()
                .ok()
                .and_then(|out| String::from_utf8(out.stdout).ok())
                .map(|s| s.trim().to_string())
                .unwrap_or_default()
        })
        .clone()
}

#[cfg(not(target_os = "macos"))]
fn os_version() -> String {
    String::new()
}

#[tauri::command]
fn open_download_dir(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    let dir = std::path::absolute(state.settings_snapshot().music_dir)
        .map(|path| path.join("Local"))
        .map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    let opener = "open";
    #[cfg(target_os = "windows")]
    let opener = "explorer.exe";
    #[cfg(target_os = "linux")]
    let opener = "xdg-open";
    std::process::Command::new(opener)
        .arg(&dir)
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

// ---------- 网盘（S3）----------


/// 根目录散歌在网盘页里的伪歌单名（不是真实目录，保留名不可用来建歌单）



fn show_main(app: &tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
    }
}


/// 托盘菜单文案：跟随界面语言（前端启动和切换语言时都会调 set_ui_language）
fn tray_menu_for(app: &tauri::AppHandle, lang: &str) -> tauri::Result<Menu<tauri::Wry>> {
    let (show_t, toggle_t, prev_t, next_t, quit_t) = if lang == "en" {
        (
            "Show TinyMusic",
            "Play / Pause",
            "Previous",
            "Next",
            "Quit TinyMusic",
        )
    } else {
        ("显示主界面", "播放 / 暂停", "上一首", "下一首", "退出 TinyMusic")
    };
    let show = MenuItem::with_id(app, "show", show_t, true, None::<&str>)?;
    let toggle = MenuItem::with_id(app, "toggle", toggle_t, true, None::<&str>)?;
    let prev_i = MenuItem::with_id(app, "prev", prev_t, true, None::<&str>)?;
    let next_i = MenuItem::with_id(app, "next", next_t, true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", quit_t, true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let sep2 = PredefinedMenuItem::separator(app)?;

    Menu::with_items(
        app,
        &[&show, &sep1, &toggle, &prev_i, &next_i, &sep2, &quit],
    )
}

fn build_tray(app: &mut tauri::App) -> tauri::Result<()> {
    let menu = tray_menu_for(app.handle(), "zh")?;

    let mut builder = TrayIconBuilder::with_id("main")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .tooltip("TinyMusic")
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => show_main(app),
            "toggle" => {
                let _ = app.emit("tray://action", "toggle");
            }
            "prev" => {
                let _ = app.emit("tray://action", "prev");
            }
            "next" => {
                let _ = app.emit("tray://action", "next");
            }
            "quit" => app.exit(0),
            _ => {}
        });

    #[cfg(target_os = "windows")]
    {
        builder = builder.on_tray_icon_event(|tray, event| {
            if matches!(event, TrayIconEvent::DoubleClick { button: MouseButton::Left, .. }) {
                show_main(tray.app_handle());
            }
        });
    }

    #[cfg(target_os = "macos")]
    {
        let last_click = std::sync::Mutex::new(None::<std::time::Instant>);
        builder = builder.on_tray_icon_event(move |tray, event| {
            // Tauri 在 macOS 只提供单次点击事件。
            if let TrayIconEvent::Click { button, button_state: MouseButtonState::Down, .. } = event {
                let mut last = last_click.lock().unwrap();
                if button != MouseButton::Left {
                    *last = None;
                    return;
                }
                let now = std::time::Instant::now();
                let double = last.take().is_some_and(|previous| now.duration_since(previous) <= Duration::from_millis(500));
                if !double {
                    *last = Some(now);
                }
                drop(last);
                if double {
                    show_main(tray.app_handle());
                }
            }
        });
    }

    // 托盘使用简化的小尺寸图标，开发模式也直接加载内置资源。
    let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray.png"))
        .ok()
        .or_else(|| app.default_window_icon().cloned());
    if let Some(icon) = icon {
        builder = builder.icon(icon);
    }
    builder.build(app)?;
    Ok(())
}


/// 界面语言变化时重画托盘菜单（前端 initI18n / setLanguage 会调用）
#[tauri::command]
fn set_ui_language(app: tauri::AppHandle, lang: String) -> Result<(), String> {
    let Some(tray) = app.tray_by_id("main") else {
        return Ok(());
    };
    let menu = tray_menu_for(&app, &lang).map_err(|e| e.to_string())?;
    tray.set_menu(Some(menu)).map_err(|e| e.to_string())
}


/// 前端主动把窗口收进托盘（设置页/快捷键都能用）
#[tauri::command]
fn hide_to_tray(app: tauri::AppHandle) -> Result<(), String> {
    let w = app
        .get_webview_window("main")
        .ok_or_else(|| "主窗口不存在".to_string())?;
    w.hide().map_err(|e| e.to_string())
}

// ---------- 启动 ----------

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let config_dir = app
                .path()
                .app_config_dir()
                .unwrap_or_else(|_| std::env::temp_dir().join("tinymusic"));
            let host = Arc::new(AppHost {
                app: app.handle().clone(),
            });
            let music_dir = portable_directory("Music").unwrap_or_else(|| {
                if tauri::is_dev() { config_dir.join("dev").join("Music") } else { config_dir.join("Music") }
            });
            let state = tauri::async_runtime::block_on(tinymusic_app::AppState::new(
                config_dir,
                music_dir,
                host,
            ))
            .map_err(|e| -> Box<dyn std::error::Error> { e.into() })?;
            println!("[tinymusic] 流代理: {}", state.proxy.base_url());
            if let Err(error) = prepare_input_directory(state.config_dir()) {
                eprintln!("[tinymusic] 无法创建 input 目录: {error}");
            }
            app.manage(state);
            if let Err(error) = theme_pack::prepare_directory(app.handle()) {
                eprintln!("[tinymusic] 无法创建主题目录: {error}");
            }

            #[cfg(target_os = "windows")]
            if let Some(window) = app.get_webview_window("main") {
                window.set_icon(tauri::image::Image::from_bytes(include_bytes!(
                    "../icons/128x128.png"
                ))?)?;
            }

            // 托盘图标 + 右键菜单：关窗口后还能控制播放
            build_tray(app)?;
            Ok(())
        })
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_dialog::init())
        .on_window_event(|window, event| {
            // 只有主窗口「关闭」才收进托盘。
            if window.label() != "main" {
                return;
            }
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let state = window.state::<Arc<AppState>>();
                if state.settings_snapshot().close_to_tray {
                    api.prevent_close();
                    let _ = window.hide();
                } else {
                    // 关掉「最小化到托盘」时，关闭窗口就是退出，
                    // 否则 macOS 会留下一个没有窗口也没有托盘的进程。
                    let app = window.app_handle().clone();
                    std::thread::spawn(move || {
                        std::thread::sleep(Duration::from_millis(120));
                        app.exit(0);
                    });
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            tm_invoke,
            local_music_input_dir,
            local_music_add,
            local_music_migrate,
            local_music_copy_library,
            download_start,
            download_batch,
            s3_download,
            s3_download_batch,
            s3_integrity_fix,
            open_download_dir,
            theme_pack::read_theme_pack,
            theme_pack::list_theme_packs,
            theme_pack::save_theme_pack,
            set_window_theme,
            set_ui_language,
            system_info,
            hide_to_tray,
        ])
        .build(tauri::generate_context!())
        .expect("Tauri 启动失败")
        .run(|_app, _event| {
            // macOS：点 Dock 图标把隐藏的窗口叫回来
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Reopen { .. } = _event {
                show_main(_app);
            }
        });
}
