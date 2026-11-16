import UIKit

/// 唯一的一屏：整屏都是 LynxView，页面导航由 ReactLynx 内部的路由栈负责。
final class RootViewController: UIViewController {
    private var lynxView: LynxView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)

        let config = LynxConfig(provider: TemplateProvider())
        let builder = LynxViewBuilder()
        builder.config = config
        builder.screenSize = view.bounds.size
        builder.fontScale = 1.0

        let lynxView = LynxView(builderBlock: { b in
            b.config = config
            b.screenSize = self.view.bounds.size
            b.fontScale = 1.0
        })
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
        lynxView.loadTemplate(fromURL: "main", initData: nil)
        self.lynxView = lynxView
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}
