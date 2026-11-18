import Foundation

/// UI 测试 / 截图用的启动参数。Release 构建永远走生产配置。
enum AppConfiguration {
    #if DEBUG
    static var s3Endpoint: String? { value(for: "-uiTestS3Endpoint") }
    static var s3Region: String? { value(for: "-uiTestS3Region") }
    static var s3Bucket: String? { value(for: "-uiTestS3Bucket") }
    static var s3Prefix: String? { value(for: "-uiTestS3Prefix") }
    static var s3AccessKey: String? { value(for: "-uiTestS3AK") }
    static var s3SecretKey: String? { value(for: "-uiTestS3SK") }
    static var keychainService: String { value(for: "-uiTestKeychainService") ?? KeychainStore.defaultService }
    static var cacheDirectoryName: String { value(for: "-uiTestCacheDir") ?? "Offline" }
    static var demoLibrary: Bool { ProcessInfo.processInfo.arguments.contains("-demoLibrary") }
    static var autoPlay: Bool { ProcessInfo.processInfo.arguments.contains("-autoPlay") }
    static var autoCache: Bool { ProcessInfo.processInfo.arguments.contains("-autoCache") }
    static var eqTest: Bool { ProcessInfo.processInfo.arguments.contains("-eqTest") }
    static var playCached: Bool { ProcessInfo.processInfo.arguments.contains("-playCached") }
    static var screen: String? { value(for: "-screen") }
    static var initialTab: Int {
        switch screen {
        case "favorites": return 0
        case "library": return 1
        case "cache": return 2
        case "settings": return 3
        default: return 1
        }
    }
    static var isAutomatedRun: Bool {
        s3Endpoint != nil || demoLibrary || ProcessInfo.processInfo.arguments.contains("-uiTestKeychainService")
    }
    #else
    static let s3Endpoint: String? = nil
    static let s3Region: String? = nil
    static let s3Bucket: String? = nil
    static let s3Prefix: String? = nil
    static let s3AccessKey: String? = nil
    static let s3SecretKey: String? = nil
    static let keychainService = KeychainStore.defaultService
    static let cacheDirectoryName = "Offline"
    static let demoLibrary = false
    static let autoPlay = false
    static let autoCache = false
    static let eqTest = false
    static let playCached = false
    static let screen: String? = nil
    static let initialTab = 1
    static let isAutomatedRun = false
    #endif

    /// 没有 iCloud 登录时不同步；TestFlight 无 entitlement 构建由 Keychain 本地 fallback 保证可用。
    static var hasICloudAccount: Bool {
        #if TM_NO_ICLOUD
        return false
        #else
        return FileManager.default.ubiquityIdentityToken != nil
        #endif
    }

    #if DEBUG
    private static func value(for flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }
    #endif
}
