import Foundation
import Testing
@testable import TinyMusic

@MainActor
struct LocalizationTests {
    private func makeLocalization() -> (Localization, UserDefaults) {
        let suite = "tinymusic.tests.localization"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (Localization(defaults: defaults), defaults)
    }

    @Test func defaultsToSystemAndResolvesToAZhOrEn() {
        let (loc, defaults) = makeLocalization()
        #expect(loc.setting == .system)
        #expect(defaults.string(forKey: Localization.defaultsKey) == nil)
        #expect(loc.language == .zh || loc.language == .en)
    }

    @Test func switchingLanguageTakesEffectAndPersists() {
        let (loc, defaults) = makeLocalization()
        loc.select(.en)
        #expect(loc.language == .en)
        #expect(defaults.string(forKey: Localization.defaultsKey) == "en")
        #expect(loc.string("设置") == "Settings")
        #expect(loc.string("缓存上限") == "Cache limit")

        loc.select(.zh)
        #expect(loc.language == .zh)
        #expect(defaults.string(forKey: Localization.defaultsKey) == "zh")
        // 中文就是 key 本身，逐字不变。
        #expect(loc.string("设置") == "设置")
        #expect(loc.string("缓存上限") == "缓存上限")
    }

    @Test func settingPropertyIsBindable() {
        let (loc, _) = makeLocalization()
        loc.setting = .en
        #expect(loc.setting == .en)
        #expect(loc.string("语言") == "Language")
        loc.setting = .system
        #expect(loc.setting == .system)
    }

    @Test func formattedLookupUsesArguments() {
        let (loc, _) = makeLocalization()
        loc.select(.en)
        #expect(loc.string("%@ 首", ["12"]) == "12 tracks")
        #expect(loc.string("删除「%@」？", ["Road Trip"]) == "Delete “Road Trip”?")
        loc.select(.zh)
        #expect(loc.string("%@ 首", ["12"]) == "12 首")
    }

    @Test func unknownKeyFallsBackToItself() {
        let (loc, _) = makeLocalization()
        loc.select(.en)
        #expect(loc.string("不在词典里的键") == "不在词典里的键")
    }

    @Test func englishTableCoversEveryChineseKey() throws {
        let (loc, _) = makeLocalization()
        let zhBundle = try #require(loc.localizedBundle(for: .zh))
        let enBundle = try #require(loc.localizedBundle(for: .en))
        let zhKeys = try tableKeys(in: zhBundle)
        let enKeys = try tableKeys(in: enBundle)
        #expect(!zhKeys.isEmpty)
        #expect(zhKeys == enKeys)
        // 键里带中文的条目，英文值不能还是同一句中文（「简体中文」这种母语写法除外）。
        for (key, value) in try table(in: enBundle) where key.contains(where: { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }) {
            if key == "简体中文" { continue }
            #expect(value != key, "缺少英文译文: \(key)")
        }
        // 英文里的弯引号必须成对，避免 strings 文件被写坏（plutil -lint 也会因此失败）。
        for (key, value) in try table(in: enBundle) {
            let opens = value.filter { $0 == "“" }.count
            let closes = value.filter { $0 == "”" }.count
            #expect(opens == closes, "引号不成对: \(key) => \(value)")
        }
    }

    private func table(in bundle: Bundle) throws -> [String: String] {
        let path = try #require(bundle.path(forResource: "Localizable", ofType: "strings"))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return plist as? [String: String] ?? [:]
    }

    private func tableKeys(in bundle: Bundle) throws -> Set<String> {
        Set(try table(in: bundle).keys)
    }
}
