# mobile（跨端 App，当前 iOS）

用 Lynx（ReactLynx）实现的跨端客户端。iOS 壳是 Swift + CocoaPods（Lynx 4.2.0），
业务逻辑通过本地 HTTP 调 Rust 后端（`crates/server`，由 `crates/ffi` 在本进程内起服务）。

## 依赖

- Xcode 16+（本项目在 Xcode 27.2 上验证）
- CocoaPods 1.16+
- Node 20.19+/22.12+ 与 pnpm
- Rust（编 iOS 目标需要 `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`）

## 首次构建

    pnpm install
    pnpm build:mobile
    cd mobile/native/ios
    xcodegen generate
    pod install
    open TinyMusic.xcworkspace

## 开发（热更新）

    pnpm dev:mobile      # 起 rspeedy dev server，产物 http://127.0.0.1:3000/main.lynx.bundle
    # 模拟器里跑 App（DEBUG 会优先从 dev server 拉 bundle，3 秒超时后回落内置）

真机上把 dev server 地址写进 UserDefaults 的 `TM_DEV_SERVER`，或改 `TemplateProvider.defaultDevServer`。

## 现状

功能对照（✅ 实测 / ⚠️ 就绪待验 / ❌ 未做）见 [docs/功能对照.md](docs/功能对照.md)，这里只列大块能力：

**已实测**
- 搜索单曲 / 搜索歌单、每日推荐、歌单详情（播放全部）、歌手页、专辑页
- 播放：AVPlayer + 本机 Range 代理，后台播放、锁屏/线控、来电与拔耳机暂停
- 全屏播放页：封面、进度、切歌、随机/循环、音质切换、歌词逐行高亮与点句跳播
- 收藏（播放页 ♡）、账号页收藏列表、我的歌单入口
- 下载（音频+歌词+封面）、下载页管理、**已下载文件离线播放**
- 均衡器：10 段 + 预设 + 持久化（MTAudioProcessingTap，流/本地都生效）
- 网盘（S3）：配置、歌单/曲目浏览、导入歌单、完整性校验与修复（用本地 S3 桩验证）
- 网页登录（WKWebView）：酷我 / 网易云

**未做 / 待验**
- 收藏与歌单的批量管理、本地音乐扫描（桌面 Library 页那套）
- 网页登录的真实回填（需要在网页里手动输账号）
- 真实云厂商桶（目前只用本地 S3 兼容桩验证过）

## 冒烟脚本

    ./mobile/scripts/smoke.sh /tmp/a.png TM_AUTOPLAY=1 TM_OPEN_PLAYER=1   # 播放页
    ./mobile/scripts/smoke.sh /tmp/b.png TM_OPEN_EQ=1                     # 均衡器
    ./mobile/scripts/smoke.sh /tmp/c.png TM_TAB=downloads                 # 下载页
    ./mobile/scripts/smoke.sh /tmp/d.png TM_SEARCH_KIND=playlist          # 搜歌单

可用环境变量（宿主会转成 globalProps）：`TM_AUTOPLAY`、`TM_OPEN_PLAYER`、`TM_TAB`、
`TM_DOWNLOAD`、`TM_PLAY_LOCAL`、`TM_SEARCH_KIND`、`TM_OPEN_ARTIST`、`TM_OPEN_ALBUM`、
`TM_OPEN_EQ`、`TM_EQ`、`TM_OPEN_S3`。

## 本地 S3 桩（网盘验收）

    cargo run -p tinymusic-server --example s3_stub -- --port 9100 --dir /tmp/tm-s3stub
    # 往 http://127.0.0.1:9100/music 里 PUT 对象，key 形如
    # TinyMusic/<歌单>/<歌手> - <标题>.mp3|.lrc|.jpg
    # 把 App 容器的 settings.json 的 s3_* 指向它即可在模拟器里看网盘页
