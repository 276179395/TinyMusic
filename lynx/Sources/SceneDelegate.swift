import UIKit

/// 窗口在这里创建（iOS 13+ 的 Scene 生命周期）。
///
/// 之前是 AppDelegate 直接 makeKeyAndVisible，iOS 27 上会被
/// `_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` 判为致命问题（SIGTRAP）。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
