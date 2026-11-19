import Foundation
import UIKit

/// Destinations behind the three support rows in Settings: rating the app on
/// the App Store, sharing it with someone, and sending feedback by email.
///
/// Everything is derived from the App Store ID and the support inbox, so a
/// rename or a new App ID only needs editing here.
@MainActor
enum AppLinks {
    /// App Store Connect's numeric "Apple ID".
    static let appStoreID = "6835780946"

    /// Support inbox printed on the App Store page and used by the feedback row.
    static let supportEmail = "carl030101@icloud.com"

    static var appStoreURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    }

    /// A store URL that jumps straight to the review form.
    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    /// The App Store app's own scheme, so rating does not detour through Safari.
    static var writeReviewAppURL: URL {
        URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    /// Copy handed to the share sheet next to the store link.
    static var shareMessage: String {
        L("推荐一个只播放你自己的 S3 网盘音乐的播放器：TinyMusic，支持离线缓存和 10 段 EQ。")
    }

    static var feedbackSubject: String {
        L("TinyMusic 意见反馈（%@）", appVersion)
    }

    /// Pre-filled mail body with the facts support always ends up asking for.
    static var feedbackBody: String {
        [
            L("请在这里描述你遇到的问题或建议："),
            "",
            "",
            "---",
            "\(L("应用版本")): \(appVersion) (\(buildNumber))",
            "\(L("系统版本")): iOS \(UIDevice.current.systemVersion)",
            "\(L("设备型号")): \(UIDevice.current.model)",
        ].joined(separator: "\n")
    }

    /// `mailto:` URL with subject and body already percent-encoded.
    static var feedbackURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: feedbackSubject),
            URLQueryItem(name: "body", value: feedbackBody),
        ]
        return components.url
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}
