# TestFlight / 内部测试

> 状态时间：2026-11-17。App 记录：TinyMusic，Apple ID `6835780946`，Bundle ID `cn.carljoy.tinymusic`。

## 当前状态：已上传并可内部测试

- **Build 26** 已上传 TestFlight，版本 `1.0.0 (26)`，包含 **iCloud entitlement**、缓存/喜欢修复、歌单播放、播放列表面板、首启 S3 提醒和离线缓存歌单、封面加载修复、歌单播放状态。
- 内部测试群组 **「内部测试」** 已创建，自动分发已开启。
- 已邀请测试员 `carl030101@icloud.com`（孙磊，账户持有人）。
- 构建 21 的 entitlements 已核对：
  - `com.apple.developer.ubiquity-kvstore-identifier`
  - `keychain-access-groups`
  - 无 `TM_NO_ICLOUD` 编译标志，iCloud 设置入口可用。

## 测试员怎么装

1. iPhone 安装 **TestFlight**（App Store 免费）。
2. 用 `carl030101@icloud.com` 的 Apple ID 登录 TestFlight。
3. 接受 TinyMusic 的内部测试邀请，安装 **1.0.0 (26)**。
4. 如果没收到邀请邮件：App Store Connect → TestFlight → 内部测试 →「内部测试」→ 测试员，确认状态为「已邀请」，可重新发送邀请。

内部测试不需要 Beta App Review；外部测试才需要。

## 以后上传新构建

使用 App Store Connect **Team API Key（Admin）**，无需 Xcode 账号登录：

    cd ios
    ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8" \
    ASC_KEY_ID="XXXXXXXXXX" \
    ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
    BUILD_NUMBER=19 ./scripts/testflight.sh

脚本默认归档 **含 iCloud** 的 `Supporting/TinyMusic.entitlements`。上传成功会看到：

    Upload succeeded
    ** EXPORT SUCCEEDED **

随后 TestFlight 处理 10–30 分钟。

## 关键配置

- App ID `cn.carljoy.tinymusic` 的 **iCloud** capability 已开启。
- 归档 entitlements：`Supporting/TinyMusic.entitlements`。
- `TinyMusicTestFlight.entitlements` 仅作为「无 iCloud」应急包保留；正常发 TestFlight 不再使用。
- 出口合规：`Info.plist` 已写 `ITSAppUsesNonExemptEncryption=false`，通常不会再提示。

## 真机直接安装（开发签名）

    cd ios
    ./scripts/install-device.sh

脚本现在默认使用含 iCloud 的 entitlements，安装后可直接验证 iCloud 同步。

## 已知限制

- TestFlight 内部测试员必须是 App Store Connect 用户；外部测试员不需要，但要 Beta App Review。
- 新增测试员：App Store Connect → 用户和访问 添加用户，再到 TestFlight 群组里勾选。
- 构建 17–25 是旧包，仍在群组里；测试请选 **26**。
