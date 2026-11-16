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

## 现状（随阶段推进更新）

- [x] P4.1 ReactLynx bundle 能构建（105 kB）
- [x] P4.2 Swift 壳 + Lynx 4.2.0 跑起来（模拟器）
- [x] P4.3 本机 Rust 后端接入（`crates/ffi` → `tm_start`），前端 `fetch` 打通
- [x] P4.4 安全区 / Hugeicons SVG / XElement blur-view / dev server 热更新 全部验证通过
- [x] P5 播放闭环（AVPlayer + 轮询状态 + 队列规则共用 shared）
- [ ] P5.2 全屏播放页 / 歌词 / 音质切换 / 均衡器
- [ ] P6 下载 / 设置
- [ ] P7 网盘 / 账号
