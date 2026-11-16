# P4 Spike 结论（Lynx 4.2.0 在 iOS 上跑通）

日期：2026-11-16 · 设备：iPhone 16 Pro (iOS 18.5) 模拟器 · Xcode 27.2

## 已验证

| 项 | 结果 | 备注 |
|---|---|---|
| Lynx 4.2.0 Pod 安装 | ✅ | 13 个 pod：Lynx/LynxBase/LynxService/LynxServiceAPI/PrimJS 4.2.1/XElement 4.2.0/SDWebImage/ServalSVG… |
| 模拟器编译 | ✅ | Xcode 27.2 + 官方 `post_install` 告警降级 |
| ReactLynx bundle 加载 | ✅ | 105.7 kB，DEBUG 先试 dev server（3s 超时）再回落内置 |
| 页面渲染 | ✅ | 见 `docs/screenshots/p4-first-screen.png`（令牌色、圆角、边框都生效） |
| 设计令牌生效 | ✅ | `@tinymusic/theme/lynx.css` 的 `.tm-dark` 变量在 Lynx 里可用 |
| 构建产物打包 | ✅ | 用 Build Phase 拷贝 bundle（生成工程时文件还不存在，不能写死 file reference） |

## 已踩到并解决的坑

1. **engineVersion 不能写 4.2**：rspeedy 当前的主线程字节码编码器只支持 bundle 版本 1.0–3.9。
   宿主 Lynx 4.2.0 向后兼容，所以不显式设置 `engineVersion`。
2. **bundle 找不到**：`loadTemplate(fromURL: "main")` → 会找 `main.bundle`；正确写法是 `"main.lynx"`（拼出 `main.lynx.bundle`）。
3. **Resources 目录里没有产物**：xcodegen 生成工程时 `app/dist` 还没有 bundle，资源引用会丢；改成编译期脚本拷进 `BUILT_PRODUCTS_DIR`。
4. `color-scheme` 属性 Lynx 模板编码器不认，生成令牌时已剔除。

## P4 后半段：未知项全部验证完（同日）

| 项 | 结果 | 做法 |
|---|---|---|
| 本地 Rust 后端 | ✅ | `cargo build -p tinymusic-ffi --target aarch64-apple-ios-sim` → Xcode Build Phase 编库并拷到 `Rust/lib`，链接 `-ltinymusic_ffi` + Security/SystemConfiguration/CFNetwork |
| 后端启动与握手 | ✅ | `RustBackend.shared.start()` 调 `tm_start(config)`，拿回 `baseUrl/token`；日志可见 `后端已启动: http://127.0.0.1:54061` |
| JS 调后端 | ✅ | 前端 `fetch(apiBase + '/api/health')` 带 `X-Tm-Token`，页面显示「后端 OK · v0.7.2」 |
| 安全区 | ✅ | 原生 `updateGlobalProps` 注入 `safeAreaTop/Bottom`，页面顶部留白，标题不再压状态栏 |
| 图标 | ✅ | Hugeicons IconNode → SVG 字符串 → `<svg content={...}>`，4 个图标清晰渲染（见 `p4-icons-blur.png`） |
| 玻璃材质 | ✅ | XElement `<blur-view blur-effect="dark" blur-radius="18">` 压在专辑封面上，真实模糊（iOS 18 模拟器） |
| 开发热更新 | ✅ | `pnpm dev:mobile` 起服务后重开 App，日志显示 bundle 来自 `http://127.0.0.1:3000/main.lynx.bundle`（1.09 MB dev 包） |

## 结论

Lynx 4.2 + ReactLynx 这条路线在 iOS 上完全可用：UI、原生模块、Rust 后端、图标、模糊材质都没踩到硬墙。
P4 结束，进入 P5（播放闭环）。


## P5 播放闭环（同日）

| 项 | 结果 | 关键点 |
|---|---|---|
| 原生模块可达性 | ✅ | 全局 `NativeModules` 在 ReactLynx 里是 undefined；正确入口是 `lynx.getNativeApp().nativeModuleProxy.TmAudio` |
| 音频播放 | ✅ | `TmAudio.load/play` 走 AVPlayer，代理流 `127.0.0.1:PORT/stream/...` 正常播放（日志实测） |
| 进度/状态回传 | ✅ | **轮询**而非推送：JS 每 400ms 调 `state(cb)` 拿 {status,position,duration,ended,error,command}，绕开「原生主线程不能直接调 JS 回调」的限制 |
| 播放 UI | ✅ | 底部播放条：封面、标题、歌手、进度、上一首/播放暂停/下一首（见 `p5-playback.png`，0:16 / 5:15） |
| 队列规则 | ✅ | 下一首/随机/循环走 `packages/shared/player/queue`（桌面同一份，34 个单测覆盖） |
| globalProps 布尔 | ⚠️ | Lynx 会把 boolean 转成 1/0，前端要归一化 |

### 踩坑总结（给后来的人）

1. `NativeModules` 全局在 ReactLynx + rspeedy 的 bundle 里不存在（引擎只把它注入原生模块作用域），要从 `lynx.getNativeApp().nativeModuleProxy` 拿。
2. 原生模块的方法只能在 **JS 线程**上回调 JS；AVPlayer 的 KVO/通知都在主线程 → 用轮询状态替代推送。
3. `LynxModule` 协议必须实现 `init(param:)`（ObjC 的 optional 初始器会变成 Swift 必需）。
4. `config.register(Module.self)` 配 `LynxEnv.prepareConfig(config)` 才进全局模块表；视图里再传 config 会覆盖。


## P5.2 全屏播放页 + 歌词 + 音质（同日）

| 项 | 结果 | 说明 |
|---|---|---|
| useGlobalProps | ✅ | 改用官方钩子，globalProps 变化会重渲染；boolean 仍要归一化（1/0） |
| 全屏播放页 | ✅ | 封面 / 标题歌手 / 进度条 / 随机-上一首-播放-下一首-循环 / 音质条 / 歌词（见 `p5-player-page.png`） |
| 音质切换 | ✅ | 档位门控来自 `packages/shared/quality`（与桌面同一份）；高级三档禁用，切档保留进度重新取流 |
| 歌词 | ✅ | `api.detail()` 拿 LRC，逐行高亮 + 自动滚动 + 点句跳播（行定位逻辑后续可切到 shared/lyrics） |
| 自动化钩子 | ✅ | `TM_AUTOPLAY=1` 自动播第一首、`TM_OPEN_PLAYER=1` 自动展开播放页，便于无人值守验证 |
