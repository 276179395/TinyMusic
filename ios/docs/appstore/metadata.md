# App Store 元数据（TinyMusic iOS）

## 基本

- App 名称：TinyMusic
- 副标题：播放你自己的 S3 音乐库
- Bundle ID：cn.carljoy.tinymusic
- 版本：1.0.0 (1)
- 类别：音乐（Music）
- 年龄分级：4+（无广告、无账号、无平台曲库）
- 价格：免费
- 版权：© 2026 TinyMusic

## 推广文本

把音乐放在自己的 S3 兼容存储里，TinyMusic 负责浏览、播放、离线缓存和 10 段 EQ。没有曲库、没有搜索、没有广告。

## 描述

TinyMusic 是一个只播放你自己 S3 存储内容的原生 iOS 播放器。

- 连接 AWS S3、Cloudflare R2、MinIO 等 S3 兼容存储
- 按“前缀/歌单/歌手 - 歌名”浏览和播放
- 缓存指定歌曲或整张歌单，断网也能听
- 10 段 EQ、12 套预设、前级增益
- 歌词、封面、播放队列、后台音频、锁屏控制
- Liquid Glass 界面，支持浅色/深色
- iCloud 同步 S3 配置和 EQ；密钥走 iCloud 钥匙串

TinyMusic 不提供在线曲库、搜索、推荐、平台下载或账号登录。你只能播放自己拥有或有权使用的音频。

## 关键词

S3, 音乐播放器, 网盘音乐, 离线缓存, EQ, 自建音乐, R2, MinIO, 无损, 歌词

## 链接

- 支持：https://redcarl.github.io/TinyMusic/tinymusic/support.html
- 隐私政策：https://redcarl.github.io/TinyMusic/tinymusic/privacy.html
- 内容声明：https://redcarl.github.io/TinyMusic/tinymusic/terms.html

## 审核备注

TinyMusic 是用户自有 S3 存储的播放器，不包含曲库、搜索、下载或登录。

审核演示桶（只读）：

- Endpoint: 待填
- Region: 待填
- Bucket: 待填
- Prefix: 待填
- Access Key: 待填，只读
- Secret Key: 待填，只读

步骤：

1. 首次启动填上述 endpoint/region/bucket/prefix/AK/SK，保存。
2. 回到歌单，打开任意歌单，点“播放全部”。
3. 在“缓存”标签点一首已缓存歌曲，验证离线播放。
4. 在播放页点 EQ，切换“摇滚”预设。
5. 只读密钥下收藏会退回本机，不会写 favorites.json。

## 截图

目录：docs/appstore/screenshots/

- 6.9：1320 × 2868
- 6.7：1290 × 2796
- 6.1：1179 × 2556

顺序建议：首次连接、歌单、播放页、内嵌歌词、缓存、离线播放、均衡器、设置。共 9 张，三套尺寸均无 alpha。

## App 隐私

- 不收集数据（Data Not Collected）
- 不跟踪（No Tracking）
- 不使用第三方广告/统计 SDK
- 仅使用 UserDefaults（CA92.1）、Keychain、iCloud KVS

## 出口合规

- ITSAppUsesNonExemptEncryption = false
- 仅使用系统 HTTPS/TLS，不实现自有加密
