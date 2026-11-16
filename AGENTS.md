# TinyMusic 仓库协作说明（面向 coding agent）

## 这是什么

一个轻量音乐客户端，现在是一个 monorepo：

- `desktop/` — 现有桌面端：Svelte 5（runes）+ Tauri 2，UI 与交互是产品基线，**行为不能退化**。
- `mobile/` — 跨端 App：ReactLynx + 原生壳（当前 iOS）+ 本地 Rust 后端。Lynx 支持多端，不叫 ios。
- `crates/core` — 平台无关的协议层（酷我/网易云、S3、下载、SQLite、Range 代理、ID3）。
- `crates/app` — 唯一业务层：AppState + dispatch(cmd, args)，桌面与 mobile 共用。
- `crates/server` / `crates/ffi` — 给 mobile 用的本地 HTTP API 与 C ABI。
- `packages/shared` — TS 公共库：类型、api 契约、transport、进度、纯逻辑、PlayerController。
- `packages/theme` — 设计令牌单一来源与生成器。

## 铁律

1. **一个 bug 只修一处**：业务规则写进 `crates/app` 或 `packages/shared`，不要在 desktop/mobile 各写一份。
   - `packages/shared` 只放框架无关代码：可以 import，不要 import svelte 或 @lynx-js/react。
   - 平台差异用注入解决（transport、ProgressSink、KV、播放引擎），不要用 `if (isMobile)` 散在主逻辑里。
2. **桌面端行为锁定**：改 desktop 内部接线可以，UI/交互/文案不能变。改完跑 `docs/桌面回归清单.md`。
3. **JSON 契约唯一**：命令名与字段名以 `packages/shared/src/api/types.ts` + `crates/app/src/dispatch.rs` 为准，任一端新增命令要同时改这两处（并在 `mobile/docs/后端对照表.md` 记一行）。
4. **mobile 的 Lynx 代码**必须遵守双线程纪律：碰 NativeModules/fetch 的处理函数首行标 `'background only'`；不用 `useLayoutEffect`；长列表用 `<list>`；滚动用 `<scroll-view>`；纯文本包 `<text>`。

## 常用命令

    pnpm install                        # 根目录，workspace 安装
    pnpm dev:desktop                    # 桌面前端（vite，:1420）
    pnpm tauri:dev                      # 桌面完整应用
    pnpm build:desktop                  # 桌面前端产物
    cargo build -p tinymusic            # 桌面壳（Tauri）
    cargo test -p tinymusic-core        # 协议层测试
    pnpm dev:mobile                     # mobile 的 rspeedy dev server
    cargo run -p tinymusic-server -- --config-dir /tmp/tm   # 本地后端（curl 验收）
    cargo build --target aarch64-apple-ios-sim -p tinymusic-ffi

## Lynx 开发前必读

- 文档入口：https://lynxjs.org/llms.txt（**MUST** 先读；需要具体页面时把 .html 换成 .md 取原文）。
- 已安装技能：`lynx-api-docs`、`reactlynx-best-practices`、`lynx-typescript`、`lynx-check-css-support`、`lynx-ui`、`lynx-devtool`、`rspeedy-bundle-size`、`vanilla-lynx`。
  写/改 ReactLynx 代码前先加载 `reactlynx-best-practices`；查 CSS/元素支持先加载 `lynx-api-docs` 或 `lynx-check-css-support`。
- 引擎版本对齐：pod Lynx 4.2.0 ↔ rspeedy `engineVersion: '4.2'`。

## 已知约束

- Lynx 不支持 `oklch()` / `color-mix()` / `backdrop-filter`；mobile 的令牌由 `packages/theme` 从 desktop 的 app.css 生成 hex/rgba，不要手改生成物。
- Lynx 没有 `<audio>`、没有 `localStorage`；分别用原生播放器与 KV 注入接口。
- mobile 的后端只绑 127.0.0.1，带每次启动的随机 token；不要把它暴露到 0.0.0.0。
