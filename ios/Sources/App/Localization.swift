import Foundation
import Observation

/// App 内语言。`system` 跟随系统，其余为设置页手动选择。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zh
    case en

    var id: String { rawValue }

    /// 选项名用各自母语写法；`system` 跟随当前界面语言。
    var displayName: String {
        switch self {
        case .system: return L("跟随系统")
        case .zh: return L("简体中文")
        case .en: return "English"
        }
    }
}

/// 轻量本地化层：按设置里的语言读取对应 `.lproj/Localizable.strings`。
///
/// - 语言选择存在 `UserDefaults` 的 `tinymusic.language`，值 `system` / `zh` / `en`。
/// - view body 里通过全局函数 `L(...)` 取文案，读取会经过 Observation 追踪，
///   所以切换语言后界面会立即刷新，无需重启。
/// - 词典里查不到的 key 原样返回（key 就是中文原文），因此中文输出与改造前逐字一致。
/// - 后端（Rust）返回的错误原文不翻译，也不会进词典。
@Observable
final class Localization {
    /// 全局单例。
    nonisolated(unsafe) static let shared = Localization()

    /// 语言设置在 `UserDefaults` 里的 key。
    static let defaultsKey = "tinymusic.language"

    /// 词典里键=中文原文；`zh-Hans` 与 `en` 两份表都在 App bundle 里。
    private static let zhBundleName = "zh-Hans"
    private static let enBundleName = "en"

    @ObservationIgnored private let defaults: UserDefaults
    /// 用户选择。读它会触发 Observation，从而让界面跟着刷新。
    private var selection: AppLanguage
    /// DEBUG 启动参数 `-uiTestLanguage` 指定的初始语言；只在本次启动里覆盖已存设置，不写入 UserDefaults，
    /// 用户手动切换后即失效（见 `select(_:)`）。
    @ObservationIgnored private var forced: AppLanguage?
    /// 已加载的 `.lproj` bundle。`@ObservationIgnored`：避免在 body 求值时写观察属性。
    @ObservationIgnored private var bundles: [AppLanguage: Bundle] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.defaultsKey),
           let stored = AppLanguage(rawValue: raw) {
            selection = stored
        } else {
            selection = .system
        }
        #if DEBUG
        if let raw = AppConfiguration.uiTestLanguage, let language = AppLanguage(rawValue: raw) {
            forced = language
            selection = language
        }
        #endif
        loadBundles()
    }

    /// 设置页绑定的选择项；写入立即生效并持久化。
    var setting: AppLanguage {
        get { selection }
        set { select(newValue) }
    }

    /// 实际生效的语言，只会是 `zh` 或 `en`。
    ///
    /// 先无条件读一次 `selection`：否则带上 `-uiTestLanguage` 强制值时，
    /// `forced ?? selection` 会短路，Observation 就登记不到依赖，界面不刷新。
    var language: AppLanguage {
        let stored = selection
        switch forced ?? stored {
        case .zh: return .zh
        case .en: return .en
        case .system: return Self.systemLanguage
        }
    }

    /// 当前语言的 `Locale`：交给 SwiftUI 的 `environment(\.locale)`，
    /// 让系统组件（导航栏、日期/数字格式、系统菜单）跟界面语言一起切换。
    var locale: Locale {
        Self.formatLocale(for: language)
    }

    /// 系统首选语言以 `zh` 开头 → 中文，其余 → 英文。
    static var systemLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("zh") ? .zh : .en
    }

    /// 切换语言：立刻刷新界面并写入 UserDefaults。
    /// 用户一旦手动选择，`-uiTestLanguage` 的强制值就不再压着它（UI 测试可以验证即时切换）。
    func select(_ value: AppLanguage) {
        forced = nil
        guard value != selection else { return }
        selection = value
        defaults.set(value.rawValue, forKey: Self.defaultsKey)
    }

    /// 按 key 取当前语言文案；查不到时回落 key 本身（即中文原文）。
    func string(_ key: String) -> String {
        guard let bundle = bundles[language] else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    /// 带格式参数的文案，例如 `string("已加入缓存队列：%@", [track.title])`。
    /// 参数类型要和占位符对上（`%@` 传 String，数字先转成 String）。
    func string(_ key: String, _ args: [CVarArg]) -> String {
        let template = string(key)
        guard !args.isEmpty else { return template }
        return String(format: template, locale: Self.formatLocale(for: language), arguments: args)
    }

    /// 指定语言的资源 bundle（测试用）。
    func localizedBundle(for language: AppLanguage) -> Bundle? {
        bundles[language]
    }

    private func loadBundles() {
        bundles[.zh] = Self.loadBundle(named: Self.zhBundleName)
        bundles[.en] = Self.loadBundle(named: Self.enBundleName)
    }

    private static func loadBundle(named name: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: name, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return bundle
    }

    private static func formatLocale(for language: AppLanguage) -> Locale {
        Locale(identifier: language == .zh ? "zh_Hans_CN" : "en_US")
    }
}

/// 取当前语言的文案。所有 view body 都用它，语言切换会被 Observation 追踪并立即刷新。
func L(_ key: String) -> String {
    Localization.shared.string(key)
}

/// 带格式参数的文案，例如 `L("已加入缓存队列：%@", track.title)`。
func L(_ key: String, _ args: CVarArg...) -> String {
    Localization.shared.string(key, args)
}
