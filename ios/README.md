# ios（原生 iOS：S3 网盘播放器 + 离线缓存）

当前 iOS 端已从 ReactLynx 重做为 SwiftUI 原生 App：

- 只播放用户自己的 S3 兼容存储；没有平台曲库、搜索、推荐、登录。
- 浏览 S3 歌单/曲目、AVPlayer 流式播放、后台音频、锁屏/线控。
- 指定歌曲/歌单离线缓存（URLSession background），缓存优先播放。
- 收藏元数据写 favorites.json；只读 key 时降级为仅本机收藏。
- iCloud：Keychain 同步 S3 密钥，KVS 同步非敏感配置；缓存不同步/不备份。
- Liquid Glass：iOS 26+ 原生 glassEffect，iOS 18–25 系统材质退路。

## 构建

    cd ios
    ./scripts/bootstrap.sh
    ./scripts/build.sh
    ./scripts/archive.sh      # 无签名 Release archive
    ./scripts/install-device.sh  # 开发签名，直接装到已配对 iPhone
    ./scripts/testflight.sh      # 签名并上传 TestFlight（需 Xcode 账号）

Rust 静态库由 Xcode Build Phase 自动编译。不需要 CocoaPods，也不需要 rspeedy。

## 测试

    cd ios
    ./scripts/test.sh

- 单元测试：TinyMusicTests（Swift Testing），覆盖队列、LRC 高亮、设置等。
- UI 测试：TinyMusicUITests，默认使用本地 S3 桩（127.0.0.1:9100）和 Debug 启动参数。
- 手动验收：缓存歌单 → 开飞行模式播放；两设备 iCloud；只读 key；过期 URL。

## 本地 S3 桩

    cargo run -p tinymusic-server --example s3_stub -- --port 9100 --dir /tmp/tm-s3stub
    ./scripts/seed-s3-stub.sh          # 单曲最小样例
    ./scripts/seed-demo-library.sh     # 两套演示歌单（截图/审核用）
    # 启动参数：
    # -uiTestS3Endpoint http://127.0.0.1:9100
    # -uiTestS3Bucket music -uiTestS3Prefix TinyMusic
    # -uiTestS3AK test -uiTestS3SK test

## 目录约定

S3 桶内按 前缀/歌单/歌手 - 歌名.ext 放文件；同名 .lrc 与 .jpg/.png/.webp 作为歌词和封面。
