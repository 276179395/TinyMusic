import Foundation

struct AppInfo: Codable, Sendable {
    let version: String
    let configDir: String
}

struct IosSettings: Codable, Equatable, Sendable {
    var s3Enabled: Bool = false
    var s3Endpoint: String = ""
    var s3Region: String = "us-east-1"
    var s3Bucket: String = ""
    var s3Prefix: String = "TinyMusic"
    var s3PathStyle: Bool = false
    var hasCredentials: Bool = false
}

struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
}

struct EmptyResponse: Codable, Sendable {}
struct OKResponse: Codable, Sendable { let ok: Bool }

struct Playlist: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let count: Int
    let cover: String?
    let root: Bool
    var id: String { name }
}

struct Track: Codable, Identifiable, Hashable, Sendable {
    let key: String
    let title: String
    let artist: String
    let cover: String?
    let missing: [String]
    let codec: String
    let quality: String
    let playable: Bool
    var id: String { key }

    var isLossless: Bool { quality == "lossless" || codec == "flac" }
    var missingLabel: String? {
        guard !missing.isEmpty else { return nil }
        return L("缺 %@", missing.joined(separator: "/"))
    }
}

struct AudioFormat: Codable, Sendable {
    let codec: String?
    let lossless: Bool?
}

struct PlayURL: Codable, Sendable {
    let url: String
    let quality: String
    let format: AudioFormat?
    let expiresAt: Int64
}

struct LyricLine: Codable, Identifiable, Sendable {
    let timeMs: Int
    let text: String
    var id: Int { timeMs }
}

struct LyricsResult: Codable, Sendable {
    let present: Bool
    let lines: [LyricLine]
}

struct FavoriteTrack: Codable, Identifiable, Sendable {
    let provider: String
    let id: String
    let title: String
    let artist: String
    let cover: String?

    var asTrack: Track {
        Track(
            key: id,
            title: title,
            artist: artist,
            cover: cover,
            missing: [],
            codec: "",
            quality: "",
            playable: true
        )
    }
}

struct FavoriteResult: Codable, Sendable {
    let synced: Bool
    let error: String?
    /// 收藏副本在「喜欢」目录里的 key（跟歌单里的原始 key 不同）
    let key: String?
}

enum JSONValue: Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var any: Any {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .object(let value): return value.mapValues(\.any)
        case .array(let value): return value.map(\.any)
        case .null: return NSNull()
        }
    }
}
