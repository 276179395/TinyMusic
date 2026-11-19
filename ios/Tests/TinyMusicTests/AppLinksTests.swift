import Foundation
import Testing
@testable import TinyMusic

@MainActor
struct AppLinksTests {
    private func makeLocalization() -> Localization {
        let suite = "tinymusic.tests.applinks"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Localization(defaults: defaults)
    }

    @Test func appStoreURLsPointAtTheListing() {
        #expect(AppLinks.appStoreURL.absoluteString == "https://apps.apple.com/app/id6835780946")
        #expect(AppLinks.writeReviewURL.absoluteString.hasSuffix("?action=write-review"))
        #expect(AppLinks.writeReviewAppURL.scheme == "itms-apps")
        #expect(AppLinks.writeReviewAppURL.absoluteString.contains("id6835780946"))
    }

    @Test func feedbackEmailIsPrefilled() throws {
        let url = try #require(AppLinks.feedbackURL)
        #expect(url.absoluteString.hasPrefix("mailto:carl030101@icloud.com?"))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let subject = try #require(items.first { $0.name == "subject" }?.value)
        let body = try #require(items.first { $0.name == "body" }?.value)
        #expect(subject.contains("TinyMusic"))
        #expect(subject.contains(AppLinks.appVersion))
        #expect(body.contains(AppLinks.appVersion))
        #expect(body.contains(AppLinks.buildNumber))
        #expect(body.contains("iOS"))
    }

    @Test func shareMessageCarriesTheAppName() {
        #expect(AppLinks.shareMessage.contains("TinyMusic"))
    }

    @Test func supportRowsAreLocalized() {
        let localization = makeLocalization()
        localization.select(.en)
        #expect(localization.string("去应用商店评分") == "Rate on the App Store")
        #expect(localization.string("分享应用") == "Share App")
        #expect(localization.string("意见反馈（邮件）") == "Feedback (Email)")
        #expect(localization.string("应用版本") == "App version")

        localization.select(.zh)
        #expect(localization.string("去应用商店评分") == "去应用商店评分")
        #expect(localization.string("应用版本") == "应用版本")
    }
}
