import Foundation

/// Lynx 引擎自己不加载资源，由宿主提供 bundle 字节。
///
/// DEBUG：优先从 rspeedy dev server 拿（热更新），失败回落内置；
/// RELEASE：只读打包进 App 的 main.lynx.bundle。
final class TemplateProvider: NSObject, LynxTemplateProvider {
    static let devServerEnvKey = "TM_DEV_SERVER"
    static let defaultDevServer = "http://127.0.0.1:3000/main.lynx.bundle"

    func loadTemplate(withUrl url: String!, onComplete callback: LynxTemplateLoadBlock!) {
        #if DEBUG
        if let devUrl = Self.devServerUrl(), let data = Self.fetchSync(devUrl) {
            NSLog("[TinyMusic] Lynx bundle 来自 dev server: \(devUrl.absoluteString) (\(data.count) bytes)")
            callback(data, nil)
            return
        }
        #endif

        guard let path = Bundle.main.path(forResource: url, ofType: "bundle") else {
            let err = NSError(
                domain: "com.tinymusic",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "找不到 \(url ?? "main").bundle"]
            )
            callback(nil, err)
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            callback(data, nil)
        } catch {
            callback(nil, error)
        }
    }

    // MARK: - DEBUG helpers

    private static func devServerUrl() -> URL? {
        let raw = ProcessInfo.processInfo.environment[devServerEnvKey] ?? UserDefaults.standard.string(forKey: devServerEnvKey) ?? defaultDevServer
        return URL(string: raw)
    }

    /// bundle 加载是同步回调，这里用信号量把异步请求拉平（仅 DEBUG 用）
    private static func fetchSync(_ url: URL) -> Data? {
        var result: Data?
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error { NSLog("[TinyMusic] dev server 拉取失败: \(error.localizedDescription)") }
            result = data
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        return result
    }
}
