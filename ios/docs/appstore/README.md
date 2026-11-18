# App Store 材料

- [元数据与审核备注](metadata.md)
- 截图目录：screenshots/6.9、screenshots/6.7、screenshots/6.1

重新生成截图：

    cd ios
    ./scripts/appstore-screenshots.sh

归档：

    ./scripts/archive.sh

上传前需要 Apple Developer Team、签名证书、provisioning profile 和只读演示桶。
