import Foundation

enum BackendError: LocalizedError, Sendable {
    case start(String)
    case call(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .start(let message): return message
        case .call(let message): return message
        case .decode(let message): return message
        }
    }
}

actor RustBackend {
    static let shared = RustBackend()
    private var started = false

    func start(configDir: URL) async throws -> AppInfo {
        let config: [String: String] = ["config_dir": configDir.path]
        let data = try JSONSerialization.data(withJSONObject: config)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BackendError.start("配置序列化失败")
        }
        let response = try await Task.detached(priority: .userInitiated) {
            try Self.invokeStart(text)
        }.value
        guard let info = try? Self.decode(AppInfo.self, from: response) else {
            throw BackendError.start(response)
        }
        started = true
        return info
    }

    func stop() {
        guard started else { return }
        tm_stop()
        started = false
    }

    func call<T: Decodable>(_ cmd: String, _ args: [String: JSONValue] = [:]) async throws -> T {
        let argsText: String
        if args.isEmpty {
            argsText = "{}"
        } else {
            let data = try JSONSerialization.data(withJSONObject: args.mapValues(\.any))
            argsText = String(data: data, encoding: .utf8) ?? "{}"
        }
        let response = try await Task.detached(priority: .userInitiated) {
            try Self.invoke(cmd, argsText)
        }.value
        do {
            let envelope = try Self.decoder.decode(Envelope<T>.self, from: Data(response.utf8))
            guard envelope.ok, let data = envelope.data else {
                throw BackendError.call(envelope.error ?? "未知错误")
            }
            return data
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.decode("\(response) (\(error.localizedDescription))")
        }
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let envelope = try decoder.decode(Envelope<T>.self, from: Data(text.utf8))
        guard envelope.ok, let data = envelope.data else {
            throw BackendError.start(envelope.error ?? text)
        }
        return data
    }

    private nonisolated static func invokeStart(_ config: String) throws -> String {
        let raw = config.withCString { tm_start($0) }
        guard let raw else { throw BackendError.start("tm_start 返回空") }
        defer { tm_free(raw) }
        let text = String(cString: raw)
        let envelope = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        if let ok = envelope?["ok"] as? Bool, ok == false {
            throw BackendError.start(envelope?["error"] as? String ?? text)
        }
        return text
    }

    private nonisolated static func invoke(_ cmd: String, _ args: String) throws -> String {
        let raw = cmd.withCString { cmdPtr in
            args.withCString { argsPtr in
                tm_invoke(cmdPtr, argsPtr)
            }
        }
        guard let raw else { throw BackendError.call("tm_invoke 返回空") }
        defer { tm_free(raw) }
        return String(cString: raw)
    }
}
