import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Lynx 引擎的全局初始化必须先于任何 LynxView 创建
        LynxEnv.sharedInstance()

        #if DEBUG
        // 调试开关：接上 Lynx DevTool 后可以看元素树 / console / 截图
        LynxEnv.prepareDevToolForDevelopmentBeforeInit()
        LynxEnv.sharedInstance().devtoolEnabled = true
        LynxEnv.sharedInstance().logBoxEnabled = true
        #endif

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
