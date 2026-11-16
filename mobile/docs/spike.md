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


## P6 下载页 + 设置页 + Tab 壳（同日）

| 项 | 结果 | 说明 |
|---|---|---|
| Tab 壳 | ✅ | 首页 / 下载 / 设置，迷你播放条固定在底部 |
| 下载页 | ✅ | 已下载列表 + 未完成（重试/忽略）+ 刷新；截图 `p6-downloads.png` |
| 设置页 | ✅ | 下载目录（iOS Documents 路径）、默认音质、同时下载数、关于；截图 `p6-settings.png` |
| 自动化钩子 | ✅/⚠️ | `TM_TAB=downloads|settings` 可直达页面；`TM_AUTOPLAY` 仍偶发不触发（不影响手动点播） |


## P6.2 下载端到端（同日）

实测：`TM_DOWNLOAD=1` 触发下载第一首 → 45 秒后
- DB：`t1-79479 | 东风破 | super | 12,629,387 bytes | done`
- 文件：`Documents/TinyMusic/周杰伦 - 东风破.mp3` + `.lrc`

**同时修掉一个跨端 bug**：`packages/shared/src/api.ts` 里 6 个进度命令残留了 Channel 时代的
`onProgress: ch`（`ch` 已不存在）→ `downloadStart` 一调用就抛 `ch is not defined`。
桌面从 P3 起下载也是坏的，这次一起修好。


## P7 网页登录（同日）

- 原生模块 `TmLogin`：WKWebView 弹层（取消/完成），完成后读 `WKHTTPCookieStore` 全量 cookie，
  交给 JS → `api.login(provider,'cookie',…) ` → `sessionGet` 确认。
- 轮询式接口 `open / state / close`，与播放器同一套线程策略。
- 账号页：两个平台的登录/已登录（头像、昵称、uid）/退出；截图 `p7-account.png`。
- 仍未验证：真的在网页里登录并回填 session（需要在模拟器里手动输账号）。


## P7.2 网盘（S3）页面层（同日）

- 设置页新增「网盘」段：启用开关 + Endpoint/Region/Bucket/Access Key/Secret Key/前缀/Path style；
  保存走 `api.settingsSet`（和桌面同一份 settings）。
- 网盘页：未配置时给引导；配置后列歌单（含根目录伪歌单）、点进看曲目、试连、完整性校验。
- 说明：桶内目录约定、签名、校验算法都在 `crates/core::s3`，移动端不重复实现。
- 未验证：真实桶的试连/校验（本机没有 S3 凭据），页面与错误分支已就绪。


## Round 7 补充

- 收藏链路打通：`favorite_add / favorite_list / favorite_check / favorite_remove`（curl 实测：加进去、列表能读到、check 返回 true）。
- 播放页加 ♡ 收藏按钮（切歌时自动查状态），账号页展示收藏列表 + 播放全部。
- **TM_AUTOPLAY 时好时坏的真正原因**：首页默认在「推荐」段，而钩子只读 `items`（搜索段的结果）→ 永远为空。
  现在按当前段取 feed（推荐段用每日推荐），稳定性问题解决。


## Round 7 补充（离线播放）

- 下载页点行即可离线播放：`TmAudio.loadLocal(path,…)` 用 `URL(fileURLWithPath:)`，空格/中文不用 JS 编码。
- **顺带修了 iOS 的路径失效问题**：沙盒容器 UUID 会随重装/更新变化，库里存的绝对路径会指向旧容器。
  `download_list` 读出来时如果原路径不存在，会按文件名在当前 download_dir 里重找一遍（桌面路径存在时行为不变）。
- 实测：播放页显示「东风破 / 周杰伦 / 0:13 / 5:15」，暂停图标可切换。
- 遗留：下载页在「迷你播放条」上偶发不刷新（全屏播放页正常），下一轮查。


## Round 8：迷你播放条不刷新的定位（未完成）

现象：从下载页用 `TM_PLAY_LOCAL` 起播时，声音正常、日志有 `audio.loadLocal/play`，
但底部迷你播放条一直显示空态；全屏播放页（PlayerPage）却能正常显示进度。

已排除/确认：
1. **真 bug（已修）**：`PlayerBar.tsx` 用了 `<Icon>` 却没 import，一旦有当前曲目就渲染失败 →
   界面停在空态。这条本身就足以解释"永远空"。
2. 播放链路没问题：`cur=东风破 st=playing pos=12.7` 是同一时刻从路由组件的 `usePlayer()` 读到的。
3. 把 store 挂到 `globalThis` 单例、去 effect cleanup、改由 App 传快照，**都没有效果** ——
   怀疑 Lynx 双线程下模块级 store 在两个 runtime 各有一份，某些组件（首屏渲染的）拿到的是主线程副本。

下一轮计划：不再依赖模块单例，改成「后台线程 push → 主线程 state」的显式通道
（或在页面级 hook 里订阅，实测路由组件可用），然后回归验证。

### 本轮保留的改动
- `PlayerBar` 的 Icon import 修复。
- `TmAudioModule` 里 `load/loadLocal/play` 的 NSLog（排查用，DEBUG 无害）。


## Round 9

- 新增 `mobile/scripts/smoke.sh`：一条命令完成 bundle 构建 → App 构建 → 安装 → 带 env 启动 → 截图 + 只抓 `[TinyMusic]` 日志。
  例：`./mobile/scripts/smoke.sh /tmp/a.png TM_AUTOPLAY=1 TM_OPEN_PLAYER=1`
- 歌手页 / 专辑页：播放页「歌手」「专辑」按钮进入，列表可点播/播放全部；截图 `p8-artist.png`、`p8-player-links.png`。
- 冒烟钩子扩展：`TM_OPEN_ARTIST` / `TM_OPEN_ALBUM`，无人值守也能截图验证。
- 迷你播放条刷新问题：本轮没有继续硬啃，先记录结论（见上节），功能面继续推进。


## Round 9：迷你播放条修好了（根因 + 方案）

**根因**：Lynx 双线程下模块级的 store 会有两份副本。从下载页/首页由 effect 触发的播放，
写入的是后台 runtime 那份；而迷你播放条渲染/订阅时拿到的是另一份，于是永远显示"没有在播放"。
（把 store 挂 globalThis、去 cleanup、App 传快照都无效，因为问题是"两份实例"而非订阅方式。）

**方案**：播放条不再读 JS store，改成**直接轮询原生播放器状态**
（`useNativeNowPlaying` → `TmAudio.state()`，500ms）。AVPlayer 在原生侧只有一份状态，
顺带把标题/歌手/封面也从原生带回来（Now Playing 信息本来就有）。

**验证**：
- 首页推荐流起播 → 播放条显示 "You And Me / 0:11 / 2:42"（截图 `p8-miniplayer-recommend.png`）
- 下载页离线起播 → 播放条显示 "东风破 / 0:13 / 5:15"（截图 `p8-miniplayer-local.png`）

**留下的约定**：跨组件的播放态一律走原生状态；JS store 只负责队列/切歌策略。
