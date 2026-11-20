# TinyMusic 仓库协作说明（面向 coding agent）

## 这是什么

一个轻量桌面音乐播放器（Svelte 5 + Tauri 2），使用 WebDAV 或 S3 兼容存储。

- `desktop/crates/core` — 网盘协议、歌单、收藏、流代理、流式下载、SQLite、ID3。
- `desktop/crates/app` — 桌面业务层（AppState 与 dispatch）。
- `desktop/crates/server` — 本地 HTTP 调试入口与 S3 测试桩。
- `desktop/packages/shared` — 框架无关的 TS 类型、API 契约、transport、播放队列与纯逻辑。
- `desktop/packages/theme` — 设计令牌生成器。
- `desktop/site`、`desktop/tools`、`desktop/docs` — 官网、开发工具与项目文档。

## 铁律

1. **一个 bug 只修一处**：网盘歌单与收藏规则在 `desktop/crates/core::library`，「喜欢」目录就是收藏本体。协议细节分别放在 WebDAV 与 S3 客户端。桌面业务规则在 `desktop/crates/app` 或 `desktop/packages/shared`。
2. **桌面端行为锁定**：改动后执行 `desktop/docs/桌面回归清单.md`，保持改动范围外的 UI 与交互。
3. **JSON 契约唯一**：桌面命令以 `desktop/packages/shared/src/api.ts`、`desktop/packages/shared/src/types.ts` 和 `desktop/crates/app/src/dispatch.rs` 为准。

## 网盘播放与下载

- 单曲、批量和失败重试共用 `desktop/crates/app` 的网盘下载逻辑。协议请求由 `core::cloud` 分派，`core::download` 将完整的原始字节从临时文件移入下载目录。
- 同目录同名歌词和封面随音频保存；源端缺少附属文件时，音频仍可完成下载。音频取回失败时保留可重试的失败记录。
- 播放时优先读取可用的本地下载。在线播放使用本地流代理按需读取，播放令牌和临时缓冲只服务于当次播放。后台预取与自动回收策略待确定。
- 当前构建目标是 Windows 和 macOS 桌面端。旧音源数据用于兼容已有本地下载。

## 常用命令

    cd desktop && pnpm install                 # desktop 是 pnpm workspace 根
    cd desktop && pnpm dev                     # 桌面前端（vite，:1420）
    cd desktop && pnpm tauri dev               # 桌面完整应用
    cd desktop && pnpm build                   # 桌面前端产物
    cd desktop && cargo build -p tinymusic     # 桌面壳（Tauri）
    cd desktop && cargo test -p tinymusic-core # 协议层测试
    cd desktop && cargo run -p tinymusic-server --example s3_stub -- --port 9100 --dir /tmp/tm-s3stub
