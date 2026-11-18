import Foundation

enum CacheStatus: String, Codable, Sendable {
    case downloading
    case done
    case failed
}

struct CacheEntry: Codable, Identifiable, Sendable {
    let key: String
    let title: String
    let artist: String
    let playlist: String
    let audioFile: String
    var audioBytes: Int64
    let codec: String
    let quality: String
    var lyricsFile: String?
    var artworkFile: String?
    let cachedAt: Date
    var lastPlayedAt: Date?
    var status: CacheStatus
    var error: String?

    var id: String { key }

    var track: Track {
        Track(
            key: key,
            title: title,
            artist: artist,
            cover: nil,
            missing: [],
            codec: codec,
            quality: quality,
            playable: true
        )
    }
}

struct CacheIndex: Codable, Sendable {
    var version: Int = 1
    var entries: [String: CacheEntry] = [:]
}

struct CacheTaskInfo: Codable, Sendable {
    let key: String
    let title: String
    let artist: String
    let playlist: String
}
