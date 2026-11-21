# TinyMusic

适用于 Windows 和 macOS 的桌面音乐播放器，支持播放自建 WebDAV 和 S3 兼容存储中的音乐。

**[源码](https://github.com/276179395/TinyMusic)** · **[问题反馈](https://github.com/276179395/TinyMusic/issues)** · **[上游官网](https://redcarl.github.io/TinyMusic/)**

## 连接 WebDAV

1. 在 WebDAV 服务中准备音乐根目录，例如 `TinyMusic`，在里面按歌单建立子目录。
2. 打开「设置 → 网盘」，选择 **WebDAV**，填写服务地址（例如 `https://nas.example.com/dav/`）、音乐根目录（例如 `TinyMusic`）、WebDAV 用户名和密码。
3. 点击「测试连接」，然后在「网盘」页打开歌单。服务地址已指向音乐根目录时，可以把「音乐根目录」留空。

```text
TinyMusic/
  通勤/
    歌手 - 歌名.flac
    歌手 - 歌名.lrc
    歌手 - 歌名.jpg
  喜欢/
```

同名歌词和封面可选。「喜欢」目录中的音频就是网盘收藏。WebDAV 使用 HTTP Basic 认证，有凭据的服务地址请使用 HTTPS。浏览、播放需要读取权限，创建歌单、删除和同步收藏需要相应的写入权限。

使用 S3 时，在同一处选择 **S3**，填写端点、桶名、区域和访问密钥。音乐前缀下同样按歌单分目录。

## 下载与离线播放

- 在「网盘」歌单中点单曲右侧的下载按钮，或点「下载全部」。WebDAV 和 S3 都会把原始音频写入设置里的下载目录，同时保存网盘已有的同名歌词和封面。
- 下载完成后，在「下载记录」双击曲目即可离线播放。仍保存在磁盘上的旧下载也能继续播放。

## 播放缓存

- 在线曲目实际播放覆盖三分之一后，应用在后台取回原文件和已有的同名歌词、封面。拖动跳过的部分和暂停时间不计入。
- 后台一次取回一首，切歌后已触发的任务可以继续。缓存任务不出现在下载记录里。
- 播放依次查找本地下载、完整缓存和网盘。手动下载命中缓存时可直接复用本地文件。
- 在「设置 → 播放缓存」选择目录，或确认后清空当前目录的缓存。清空会取消正在运行和排队的缓存任务，保留手动下载和其他文件。缓存不会自动清理。

## 仓库结构

    desktop/                 桌面端（Svelte 5 + Tauri 2）
    desktop/crates/core      平台无关底座（WebDAV / S3 / 下载 / 流代理 / SQLite / ID3）
    desktop/crates/app       桌面业务层：AppState + dispatch
    desktop/crates/server    本地 HTTP API（桌面调试 / S3 桩）
    desktop/packages/shared  前端公共库（类型 / API 契约 / 队列 / 格式化 / 歌词 / EQ 预设）
    desktop/packages/theme   设计令牌单源（desktop/src/app.css）
    desktop/site             官网与隐私政策（GitHub Pages）
    desktop/tools            开发脚本
    desktop/docs             项目文档

一个 bug 只修一处：业务规则在 desktop/crates/app 或 desktop/packages/shared，窗口与命令入口只做适配。

---

## 能做什么

### 播放

- 悬浮播放器栏：随机、循环、音量、播放队列
- 全屏歌词页：逐行高亮，点任意一句从那里开始播
- 歌词、队列、歌曲详情都在右键菜单里
- 重开应用会恢复上次的曲目和进度，但不会突然出声

### 均衡器

- 10 段图形均衡，32 Hz – 16 kHz，实时作用于当前播放
- 内置平直、流行、摇滚、爵士、古典、电子、嘻哈、人声、原声、低音增强、高音增强、响度 12 种预设
- 前级增益、双击滑块归零，手动调整后自动记为「自定义」并保存

### 网盘（可选）

- 支持 WebDAV 以及 AWS S3、MinIO、Cloudflare R2 等 S3 兼容服务
- 每个歌单对应音乐根目录下的一个目录，可新建、重命名、排序、删除、整张播放
- 「喜欢」的歌曲会同步到网盘，换电脑后自动合并

### 其他

- 关闭窗口默认收进系统托盘，播放不中断（可以在设置里改）
- 跟随系统的浅色 / 深色主题，也可以手动指定
- 「设置 → 外观」提供跟随系统、深色、浅色和自定义四种主题。选择「自定义」后可导入本地 CSS 主题包，或为应用外观选择纯色或本地图片背景。格式与示例见 [主题包指南](<desktop/docs/CSS 主题包.md>)
- 主题包可指定浅色或深色底板，当前底板会显示在「主题包」旁。星夜、樱花和 35 套 MusicFree 静态主题可从 [GitHub Releases](https://github.com/276179395/TinyMusic/releases/latest) 下载。
- Windows 安装版把导入的原始 ZIP 保存在 `%APPDATA%\com.tinymusic.app\theme`。从 v0.7.7 升级后，旧主题请用原 ZIP 重新导入。
- 应用内更新沿用上游更新源，本仓库的安装包从 Releases 手动下载
- 常用操作都能右键找到，不用记路径

---

## 下载与安装

本仓库的发布见 [GitHub Releases](https://github.com/276179395/TinyMusic/releases)。上游历史安装包见 [上游官网](https://redcarl.github.io/TinyMusic/)。

| 平台 | 要求 |
|---|---|
| Windows | Windows 10 / 11，64 位 |
| macOS | macOS 11 及以上，Apple 芯片或 Intel |

- macOS 13 以下（11 / 12）会自动改用**边框材质**：去掉毛玻璃、卡片换成实色 + 1px 边框，
  界面结构与新版完全一致。也可以在「设置 → 外观 → 玻璃材质」手动切换
- macOS 首次打开若提示「已损坏」，在 Finder 里右键选择「打开」即可（安装包没有做 Apple 公证）
- Windows 安装包暂未做代码签名，SmartScreen 若提示「未知发布者」，选择「仍要运行」

---

## 本地数据

应用把网盘连接信息、下载记录和收藏缓存保存在本机。下载的音乐和同名附属文件保存在设置里的下载目录。启用网盘后，同步的收藏存放在自己配置的存储服务上。

## 免责声明

- 音频、封面、歌词的版权归各权利人所有。本软件仅供学习、研究与个人使用，**不得用于商业用途**，也不得用于传播或再分发相关内容。
- 使用本软件产生的任何后果由使用者自行承担。

## 更多

- 源码与问题反馈：<https://github.com/276179395/TinyMusic>
- 如果它好用，欢迎点个 Star。
- 给开发者看的技术细节在 [`desktop/docs/`](desktop/docs/)。

<details>
<summary>开发与构建</summary>

```bash
cd desktop
pnpm install
pnpm tauri dev          # 开发
pnpm tauri build        # 打包

cargo test -p tinymusic-core   # 协议层测试，不需要 Tauri
```

需要 Node.js、pnpm 和 Rust 工具链。

</details>
