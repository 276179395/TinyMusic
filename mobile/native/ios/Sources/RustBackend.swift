import Foundation

/// 进程内的 Rust 后端（crates/ffi → libtinymusic_ffi.a）。
///
/// 职责很薄：给 Rust 传配置目录，拿回 baseUrl 与 token。
/// 所有业务逻辑都在 Rust 里（crates/app），这里不写任何业务规则。
final class RustBackend {
    static let shared = RustBackend()

    private(set) var baseUrl: String?
    private(set) var token: String?
    private(set) var lastError: String?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tinymusic", isDirectory: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TinyMusic", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        try? fm.createDirectory(at: docs, withIntermediateDirectories: true)

        let config: [String: Any] = [
            "config_dir": support.path,
            "download_dir": docs.path,
            "bind": "127.0.0.1:0",
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: config),
            let json = String(data: data, encoding: .utf8)
        else {
            lastError = "配置序列化失败"
            return
        }

        guard let out = tm_start(json) else {
            lastError = "tm_start 返回空"
            return
        }
        let text = String(cString: out)
        tm_free(out)

        guard
            let respData = text.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any]
        else {
            lastError = text
            NSLog("[TinyMusic] 后端返回无法解析: \(text)")
            return
        }
        if let err = obj["error"] as? String {
            lastError = err
            NSLog("[TinyMusic] 后端启动失败: \(err)")
            return
        }
        baseUrl = obj["baseUrl"] as? String
        token = obj["token"] as? String
        NSLog("[TinyMusic] 后端已启动: \(baseUrl ?? "?")")
    }

    func stop() {
        tm_stop()
    }
}
