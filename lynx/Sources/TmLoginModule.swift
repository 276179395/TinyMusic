import UIKit
import WebKit

/// 登录模块：弹一个 WKWebView（和桌面一样是"网页登录"），
/// 用户登录完点「完成」，把 cookie 交给 JS，由 JS 调后端 login(method=cookie)。
///
/// 通信同样是轮询（open → state → close），原因同播放器：原生只能在 JS 线程回调。
@objcMembers
final class TmLoginModule: NSObject, LynxModule {
    @objc class var name: String { "TmLogin" }

    @objc class var methodLookup: [String: String] {
        [
            "open": NSStringFromSelector(#selector(open(_:url:))),
            "state": NSStringFromSelector(#selector(state(_:))),
            "close": NSStringFromSelector(#selector(close)),
        ]
    }

    private static var current: LoginSession?

    private var provider: String?

    override init() {
        super.init()
    }

    /// Lynx 模块协议要求（ObjC 的 initWithParam: 会变成 Swift 必需初始化器）
    init(param: Any) {
        super.init()
        _ = param
    }

    func open(_ provider: String, url: String) {
        onMain {
            guard let target = URL(string: url) else { return }
            TmLoginModule.current?.dismiss()
            let session = LoginSession(provider: provider, url: target)
            TmLoginModule.current = session
            session.present()
        }
    }

    func state(_ cb: @escaping (Any?) -> Void) {
        var payload: [String: Any] = [:]
        DispatchQueue.main.sync {
            guard let session = TmLoginModule.current else {
                payload["running"] = false
                payload["done"] = false
                cb(Self.json(payload))
                return
            }
            payload["running"] = session.running
            payload["done"] = session.finished
            payload["cancelled"] = session.cancelled
            if let cookie = session.cookie { payload["cookie"] = cookie }
            if let uid = session.uid { payload["uid"] = uid }
            payload["provider"] = session.provider
            if session.finished { TmLoginModule.current = nil }
        }
        cb(Self.json(payload))
    }

    func close() {
        onMain { TmLoginModule.current?.dismiss() }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    private static func json(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// 一次登录会话：一个带导航栏的 WKWebView 弹层
private final class LoginSession: NSObject, WKNavigationDelegate {
    let provider: String
    let url: URL
    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let controller = UIViewController()
    private var nav: UINavigationController?
    private(set) var running = false
    private(set) var finished = false
    private(set) var cancelled = false
    private(set) var cookie: String?
    private(set) var uid: String?

    init(provider: String, url: URL) {
        self.provider = provider
        self.url = url
        super.init()
    }

    func present() {
        guard let top = LoginSession.topViewController() else { return }
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        controller.view = webView
        controller.title = provider == "netease" ? "网易云音乐登录" : "酷我音乐登录"

        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .pageSheet
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "取消", style: .plain, target: self, action: #selector(onCancel)
        )
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "完成", style: .done, target: self, action: #selector(onDone)
        )
        self.nav = nav
        running = true
        top.present(nav, animated: true)
    }

    func dismiss() {
        nav?.dismiss(animated: true)
        running = false
    }

    @objc private func onCancel() {
        cancelled = true
        running = false
        finished = true
        nav?.dismiss(animated: true)
    }

    @objc private func onDone() {
        readCookies { [weak self] cookies in
            guard let self else { return }
            self.cookie = cookies.map { $0.name + "=" + $0.value }.joined(separator: "; ")
            self.uid = cookies.first(where: { $0.name.lowercased().contains("userid") })?.value
            self.running = false
            self.finished = true
            self.nav?.dismiss(animated: true)
        }
    }

    private func readCookies(completion: @escaping ([(name: String, value: String)]) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            completion(cookies.map { (name: $0.name, value: $0.value) })
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
