# App Store 审核要点（iOS 原生）

## 定位

TinyMusic iOS 是**用户自有 S3 存储的播放器**：没有在线曲库、没有搜索、没有平台下载、没有登录。
离线缓存只用于 App 内播放，不可导出/分享/在文件 App 可见，也不进入 iCloud 备份。

## 提交前检查

- Bundle ID：cn.carljoy.tinymusic；版本 1.0.0；iPhone；iOS 18+。
- App ID 开启 iCloud Key-value storage；entitlements 只含 keychain group + ubiquity-kvstore。
- Info.plist：后台音频、本地网络、ATS 仅 NSAllowsLocalNetworking、ITSAppUsesNonExemptEncryption=false、UIFileSharingEnabled=false。
- PrivacyInfo.xcprivacy：不跟踪、不采集数据、UserDefaults 理由 CA92.1。
- 隐私政策/支持页：https://redcarl.github.io/TinyMusic/tinymusic/privacy.html、support.html、terms.html（已部署，200）。
- 截图与元数据：ios/docs/appstore/（6.9 / 6.7 / 6.1 三套，含描述、关键词、审核备注）。
- 审核备注：提供只读演示 S3 桶（公版/CC0 音频）的 endpoint/bucket/AK/SK 和操作步骤。
- 大陆区：ICP/音乐资质不确定，首发建议不勾选中国大陆。

## 归档

    cd ios
    ./scripts/archive.sh

无签名 archive 已验证：/tmp/TinyMusic.xcarchive，arm64，无 Lynx bundle，无 provider 字符串。
正式上传时去掉 CODE_SIGNING_ALLOWED=NO，配置 Development Team / provisioning profile，再用 ExportOptions.plist 导出。

签名前置（当前机器实测会卡在这里）：

- Xcode → Settings → Accounts 登录 Apple ID；
- App ID cn.carljoy.tinymusic 开启 iCloud Key-value storage；
- Provisioning profile 必须包含 com.apple.developer.ubiquity-kvstore-identifier；
- 当前仅有一张 Apple Development 证书（Team BCRZR3P4AP），自动签名报 No Accounts，且 iOS Team Provisioning Profile 不含 iCloud capability；需要先在开发者后台补 capability 并重新生成 profile。

## 审核话术

- This app is a player for the user's own S3-compatible storage. It contains no catalog, search, download, or login.
- Offline cache is for the user's own content only. Files stay in the app sandbox, are excluded from iCloud backup, and cannot be exported or shared.
- A read-only demo bucket is provided in the review notes. Favorites are stored locally when the key is read-only.

## 已知风险

- 5.2.3：通用播放器可能被质疑；用无曲库/无搜索/无平台下载 + 权利声明 + 演示桶降低风险。
- 4.2：必须能完成播放/缓存/EQ/歌词等原生功能；EQ 已接入，提交前做一次真机听感/崩溃验收。
- 5.2.1：首次启动必须显示“只播放你拥有或有权使用的存储内容”。
