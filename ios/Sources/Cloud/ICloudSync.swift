import Foundation
import Observation

struct CloudSettings: Codable, Sendable {
    var s3Enabled: Bool
    var s3Endpoint: String
    var s3Region: String
    var s3Bucket: String
    var s3Prefix: String
    var s3PathStyle: Bool
    var eq: EQState?
    var updatedAt: Double
    var deviceId: String

    init(
        settings: IosSettings,
        eq: EQState? = nil,
        updatedAt: Double = Date().timeIntervalSince1970,
        deviceId: String = CloudSettings.currentDeviceId
    ) {
        self.s3Enabled = settings.s3Enabled
        self.s3Endpoint = settings.s3Endpoint
        self.s3Region = settings.s3Region
        self.s3Bucket = settings.s3Bucket
        self.s3Prefix = settings.s3Prefix
        self.s3PathStyle = settings.s3PathStyle
        self.eq = eq
        self.updatedAt = updatedAt
        self.deviceId = deviceId
    }

    func shouldApply(over localUpdatedAt: TimeInterval) -> Bool {
        updatedAt >= localUpdatedAt
    }

    static let currentDeviceId: String = {
        let key = "tinymusic.deviceId"
        if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()
}

@MainActor
@Observable
final class ICloudSync {
    private static let key = "app.settings.v1"
    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    private(set) var available = FileManager.default.ubiquityIdentityToken != nil
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    var onRemote: ((CloudSettings) -> Void)?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.readRemote() }
        }
    }

    func refreshAvailability() {
        available = FileManager.default.ubiquityIdentityToken != nil
    }

    func push(_ settings: IosSettings, eq: EQState? = nil) {
        let payload = CloudSettings(settings: settings, eq: eq)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        store.set(data, forKey: Self.key)
        store.synchronize()
        lastSyncedAt = Date()
        lastError = nil
    }

    func load() -> CloudSettings? {
        guard let data = store.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(CloudSettings.self, from: data) else {
            return nil
        }
        return payload
    }

    private func readRemote() {
        guard let payload = load() else { return }
        lastSyncedAt = Date()
        onRemote?(payload)
    }

    func clear() {
        store.removeObject(forKey: Self.key)
        store.synchronize()
    }
}
