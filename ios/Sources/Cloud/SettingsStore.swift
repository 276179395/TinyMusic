import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private(set) var settings = IosSettings()
    private(set) var hasCredentials = false
    private(set) var status: String?
    private(set) var error: String?
    private(set) var busy = false
    var iCloudEnabled = true

    var eqProvider: (() -> EQState?)?
    var onRemoteEQ: ((EQState) -> Void)?

    private let backend: RustBackend
    private let keychain: KeychainStore
    private let cloud: ICloudSync
    private var eqPushTask: Task<Void, Never>?
    private var localUpdatedAt: TimeInterval = 0

    init(
        backend: RustBackend = .shared,
        keychain: KeychainStore = KeychainStore(service: AppConfiguration.keychainService),
        cloud: ICloudSync = ICloudSync()
    ) {
        self.backend = backend
        self.keychain = keychain
        self.cloud = cloud
        self.iCloudEnabled = !AppConfiguration.isAutomatedRun && AppConfiguration.hasICloudAccount
        self.cloud.onRemote = { [weak self] remote in
            Task { @MainActor in await self?.applyRemote(remote) }
        }
    }

    var isConfigured: Bool {
        !settings.s3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.s3Bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasCredentials
    }

    var iCloudAvailable: Bool { cloud.available }
    var lastSyncedAt: Date? { cloud.lastSyncedAt }

    func load() async {
        do {
            let loaded: IosSettings = try await backend.call("settings_get")
            settings = loaded
            await applyDebugOverridesIfNeeded()
            if let credentials = keychain.load() {
                let _: OKResponse = try await backend.call("s3_set_credentials", [
                    "accessKey": .string(credentials.accessKey),
                    "secretKey": .string(credentials.secretKey),
                ])
                hasCredentials = true
            }
            cloud.start()
            cloud.refreshAvailability()
            if iCloudEnabled, !AppConfiguration.isAutomatedRun, let remote = cloud.load(), remote.updatedAt > 0 {
                await applyRemote(remote)
            }
            status = nil
            error = nil
        } catch {
            status = "读取设置失败"
            self.error = error.localizedDescription
        }
    }

    func save(
        endpoint: String,
        region: String,
        bucket: String,
        prefix: String,
        pathStyle: Bool,
        accessKey: String,
        secretKey: String
    ) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let normalizedEndpoint = try validateEndpoint(endpoint)
            let normalizedBucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedBucket.isEmpty else { throw SettingsError.message("Bucket 不能为空") }
            let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAccess = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSecret = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedAccess.isEmpty, !normalizedSecret.isEmpty else {
                throw SettingsError.message("Access Key / Secret Key 不能为空")
            }

            let credentials = S3Credentials(accessKey: normalizedAccess, secretKey: normalizedSecret)
            try keychain.save(credentials, synchronizable: iCloudEnabled)
            let _: OKResponse = try await backend.call("s3_set_credentials", [
                "accessKey": .string(normalizedAccess),
                "secretKey": .string(normalizedSecret),
            ])

            var next = settings
            next.s3Enabled = true
            next.s3Endpoint = normalizedEndpoint
            next.s3Region = region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "us-east-1" : region.trimmingCharacters(in: .whitespacesAndNewlines)
            next.s3Bucket = normalizedBucket
            next.s3Prefix = normalizedPrefix
            next.s3PathStyle = pathStyle
            next.hasCredentials = true
            let _: OKResponse = try await backend.call("settings_set", [
                "settings": .object(settingsObject(next)),
            ])
            settings = next
            hasCredentials = true
            localUpdatedAt = Date().timeIntervalSince1970
            if iCloudEnabled { cloud.push(next, eq: eqProvider?()) }
            status = "已保存"
            error = nil
            return true
        } catch {
            status = "保存失败"
            self.error = error.localizedDescription
            return false
        }
    }

    func testConnection() async -> String? {
        busy = true
        defer { busy = false }
        do {
            let message: String = try await backend.call("s3_test")
            status = message
            error = nil
            return message
        } catch {
            status = "连接失败"
            self.error = error.localizedDescription
            return nil
        }
    }

    func disconnect() async {
        keychain.delete()
        let _: OKResponse? = try? await backend.call("s3_clear_credentials")
        hasCredentials = false
        settings.s3Enabled = false
        settings.hasCredentials = false
        if let _: OKResponse = try? await backend.call("settings_set", [
            "settings": .object(settingsObject(settings)),
        ]) {}
        localUpdatedAt = Date().timeIntervalSince1970
        if iCloudEnabled { cloud.push(settings, eq: eqProvider?()) }
        status = "已断开"
    }

    func setICloudEnabled(_ enabled: Bool) async {
        iCloudEnabled = enabled
        guard enabled else { return }
        if let credentials = keychain.load() {
            try? keychain.save(credentials, synchronizable: true)
        }
        localUpdatedAt = Date().timeIntervalSince1970
        cloud.push(settings, eq: eqProvider?())
    }

    func pushCurrent(eq: EQState) {
        guard iCloudEnabled else { return }
        eqPushTask?.cancel()
        eqPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled, self.iCloudEnabled else { return }
            self.localUpdatedAt = Date().timeIntervalSince1970
            self.cloud.push(self.settings, eq: eq)
        }
    }

    func refreshCredentials() async {
        guard let credentials = keychain.load() else {
            hasCredentials = false
            return
        }
        if let _: OKResponse = try? await backend.call("s3_set_credentials", [
            "accessKey": .string(credentials.accessKey),
            "secretKey": .string(credentials.secretKey),
        ]) {
            hasCredentials = true
        }
    }

    private func applyRemote(_ remote: CloudSettings) async {
        guard remote.updatedAt > 0, remote.shouldApply(over: localUpdatedAt) else { return }
        var next = settings
        next.s3Enabled = remote.s3Enabled
        next.s3Endpoint = remote.s3Endpoint
        next.s3Region = remote.s3Region
        next.s3Bucket = remote.s3Bucket
        next.s3Prefix = remote.s3Prefix
        next.s3PathStyle = remote.s3PathStyle
        settings = next
        if let _: OKResponse = try? await backend.call("settings_set", [
            "settings": .object(settingsObject(next)),
        ]) {}
        if let eq = remote.eq {
            onRemoteEQ?(eq)
        }
    }

    private func applyDebugOverridesIfNeeded() async {
        #if DEBUG
        guard let endpoint = AppConfiguration.s3Endpoint,
              let bucket = AppConfiguration.s3Bucket,
              let accessKey = AppConfiguration.s3AccessKey,
              let secretKey = AppConfiguration.s3SecretKey else {
            return
        }
        settings.s3Enabled = true
        settings.s3Endpoint = endpoint
        settings.s3Region = AppConfiguration.s3Region ?? settings.s3Region
        settings.s3Bucket = bucket
        settings.s3Prefix = AppConfiguration.s3Prefix ?? settings.s3Prefix
        settings.s3PathStyle = true
        _ = try? keychain.save(S3Credentials(accessKey: accessKey, secretKey: secretKey), synchronizable: false)
        let _: OKResponse? = try? await backend.call("s3_set_credentials", [
            "accessKey": .string(accessKey),
            "secretKey": .string(secretKey),
        ])
        let _: OKResponse? = try? await backend.call("settings_set", [
            "settings": .object(settingsObject(settings)),
        ])
        hasCredentials = true
        #endif
    }

    private func settingsObject(_ settings: IosSettings) -> [String: JSONValue] {
        [
            "s3Enabled": .bool(settings.s3Enabled),
            "s3Endpoint": .string(settings.s3Endpoint),
            "s3Region": .string(settings.s3Region),
            "s3Bucket": .string(settings.s3Bucket),
            "s3Prefix": .string(settings.s3Prefix),
            "s3PathStyle": .bool(settings.s3PathStyle),
        ]
    }

    private func validateEndpoint(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SettingsError.message("Endpoint 不能为空") }
        let normalized = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: normalized), let scheme = url.scheme?.lowercased(), let host = url.host else {
            throw SettingsError.message("Endpoint 不是合法 URL")
        }
        guard scheme == "https" || scheme == "http" else {
            throw SettingsError.message("Endpoint 只支持 http/https")
        }
        if scheme == "http" && !isLocalHost(host) {
            throw SettingsError.message("公网 Endpoint 必须使用 HTTPS；本机/局域网地址才允许 HTTP")
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10
            || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 169 && parts[1] == 254)
    }
}

enum SettingsError: LocalizedError, Sendable {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
