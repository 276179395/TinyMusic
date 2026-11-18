import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // iOS 13+ 起窗口由 SceneDelegate 建；这里不再持有 window。
    // 不采用 Scene 生命周期的 App 在 iOS 26/27 上会直接被系统 SIGTRAP 掉。

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Lynx 引擎的全局初始化必须先于任何 LynxView 创建
        LynxEnv.sharedInstance()

        // 按官方文档：config（provider + 原生模块）准备好后交给 LynxEnv，
        // 之后创建 LynxView 不传 config，直接用这份全局配置。
        let config = LynxConfig(provider: TemplateProvider())
        config.register(TmAudioModule.self)
        config.register(TmLoginModule.self)
        LynxEnv.sharedInstance().prepareConfig(config)
        NSLog("[TinyMusic] Lynx 全局配置已准备（含 TmAudio）")

        #if DEBUG
        // 调试开关：接上 Lynx DevTool 后可以看元素树 / console / 截图
        LynxEnv.prepareDevToolForDevelopmentBeforeInit()
        LynxEnv.sharedInstance().devtoolEnabled = true
        LynxEnv.sharedInstance().logBoxEnabled = true
        #endif

        // 起本地 Rust 后端（业务逻辑全在 crates/app，这里只拿 baseUrl/token）
        RustBackend.shared.start()

        return true
    }

    // 告诉系统用我们的 SceneDelegate（Info.plist 里也配了一份）
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
