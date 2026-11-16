# mobile/ 子树说明（ReactLynx + iOS 原生壳）

## 结构

    mobile/
    ├─ app/                  ReactLynx 前端（自带 package.json，进根 workspace）
    │  ├─ src/App.tsx        当前进度：第一屏 + 后端连通探测
    │  └─ lynx.config.ts     rspeedy 配置（不指定 engineVersion，见注释）
    └─ native/ios/           Swift 壳（xcodegen 生成工程 + CocoaPods 装 Lynx）
       ├─ project.yml        xcodegen 描述，改工程结构只改它
       ├─ Podfile            Lynx 4.2.0 / PrimJS 4.2.1 / XElement 4.2.0
       ├─ Sources/           AppDelegate / RootViewController / TemplateProvider …
       └─ Resources/         构建时从 app/dist 同步 main.lynx.bundle

## 命令

    pnpm dev:mobile                                  # rspeedy dev server（端口 3000）
    pnpm build:mobile                                # 产出 app/dist/main.lynx.bundle
    cd mobile/native/ios && xcodegen generate        # 重新生成 xcodeproj
    cd mobile/native/ios && pod install              # 装 Lynx
    cd mobile/native/ios && xcodebuild -workspace TinyMusic.xcworkspace \
        -scheme TinyMusic -sdk iphonesimulator \
        -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

## 规矩

- **UI 只写在 app/src 里**，Swift 只做壳能力（播放器、登录 WebView、分享、KV）。
- **业务逻辑不要在这里再写一遍**：调后端用 `@tinymusic/shared` 的 `api`（transport 换成 httpTransport），
  规则（音质门控、队列、播放策略）都来自公共库。
- **Lynx 双线程纪律**：碰 `NativeModules` / `fetch` 的处理函数首行 `'background only'`；
  不用 `useLayoutEffect`；长列表 `<list>`；滚动 `<scroll-view>`；纯文本包 `<text>`。
- **颜色只从 `@tinymusic/theme/lynx.css` 的令牌取**（`.tm-dark` / `.tm-light`），不要写死 oklch/color-mix。
- iOS 壳的 `Info.plist` 已经放行 `NSAllowsLocalNetworking`（本地后端 127.0.0.1）与后台音频。
