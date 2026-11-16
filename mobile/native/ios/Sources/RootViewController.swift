import UIKit

/// 唯一的一屏：整屏都是 LynxView，页面导航由 ReactLynx 内部的路由栈负责。
final class RootViewController: UIViewController {
    private var lynxView: LynxView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)

        let config = LynxConfig(provider: TemplateProvider())
        let lynxView = LynxView { builder in
            builder.config = config
            builder.screenSize = self.view.bounds.size
            builder.fontScale = 1.0
        }
        lynxView.preferredLayoutWidth = view.bounds.width
        lynxView.preferredLayoutHeight = view.bounds.height
        lynxView.layoutWidthMode = .exact
        lynxView.layoutHeightMode = .exact
        lynxView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lynxView)
        NSLayoutConstraint.activate([
            lynxView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lynxView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lynxView.topAnchor.constraint(equalTo: view.topAnchor),
            lynxView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 宿主能力通过 globalProps 交给前端：后端地址、token、主题、安全区
        lynxView.updateGlobalProps(with: globalProps())

        // 资源名带上 .lynx：TemplateProvider 会拼成 main.lynx.bundle
        lynxView.loadTemplate(fromURL: "main.lynx", initData: nil)
        self.lynxView = lynxView
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 安全区在 viewDidLoad 时可能还没算出来，出现后再补一次
        lynxView?.updateGlobalProps(with: globalProps())
    }

    private func globalProps() -> [String: Any] {
        let backend = RustBackend.shared
        let insets = view.window?.safeAreaInsets ?? view.safeAreaInsets
        let theme = traitCollection.userInterfaceStyle == .light ? "light" : "dark"
        var props: [String: Any] = [
            "platform": "ios",
            "appTheme": theme,
            "safeAreaTop": Double(insets.top),
            "safeAreaBottom": Double(insets.bottom),
            "safeAreaLeft": Double(insets.left),
            "safeAreaRight": Double(insets.right),
            "screenWidth": Double(view.bounds.width),
            "screenHeight": Double(view.bounds.height),
        ]
        if let baseUrl = backend.baseUrl { props["apiBase"] = baseUrl }
        if let token = backend.token { props["apiToken"] = token }
        if let error = backend.lastError { props["backendError"] = error }
        return props
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}
