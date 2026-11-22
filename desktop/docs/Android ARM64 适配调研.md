# Android ARM64 适配调研

目标是 Android 的 `arm64-v8a`，对应 Rust 的 `aarch64-linux-android`。现有 Tauri 2、Svelte 和 Rust 分层适合复用。本次结论来自静态检查，尚未编译 APK 或完成真机验证。

| 模块 | 适配判断 |
| --- | --- |
| 网盘和业务 | 复用 `crates/core` 的 WebDAV、S3、流代理和 SQLite，以及 `crates/app` 的歌单、收藏、下载和缓存逻辑。保留 `dispatch.rs` 与 `packages/shared` 的契约。用 Android NDK 验证 Rustls、内置 SQLite 等依赖的完整编译链。 |
| Tauri 壳 | 已有移动端入口，但当前只生成 `rlib`。接入 Android 工程并生成 `cdylib` 时，需兼顾已有 Windows MinGW 链接限制。按平台隔离托盘、窗口关闭拦截、更新器和桌面权限。 |
| 前台播放 | 首轮沿用 WebView 的音频元素与 Rust 回环代理。真机检查 WebView 对本地 HTTP、跨域和媒体 Range 请求的行为，并验证拖动进度、连续切歌和均衡器。 |
| 后台播放 | 锁屏续播、通知栏和蓝牙控制可由 Android Media3 的 `MediaSessionService` 承担。播放服务持有播放状态，通过进度事件衔接现有的播放覆盖率与缓存逻辑。 |
| 存储 | 首版可用应用私有目录存放音乐库、缓存和 SQLite。开放用户选择共享目录时，通过 Storage Access Framework 持有文档 URI 和授权。 |
| 界面 | 复用 Svelte 页面和状态逻辑。适配窄屏导航、播放栏和列表，并给右键菜单及双击播放提供触屏入口。 |

首轮验收以一台 ARM64 真机为准：安装验证 APK，连接 WebDAV 或 S3，浏览含中文路径的歌单，播放并拖动进度，下载曲目，断网后重启并播放下载曲目。

- [Tauri Android 打包与 ABI 选择](https://v2.tauri.app/distribute/google-play/)
- [Android Media3 后台播放](https://developer.android.com/media/media3/session/background-playback)
- [Android 共享存储与文档授权](https://developer.android.com/training/data-storage/shared/documents-files)
