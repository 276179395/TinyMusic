import Foundation

enum AudioValidation {
    static let minimumBytes = 1024

    static func isValid(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size >= minimumBytes,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 12)
        return isAudioHeader(data)
    }

    private static func isAudioHeader(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else { return false }
        // ID3 / MPEG / AAC ADTS
        if bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 { return true }
        if bytes[0] == 0xFF, (bytes[1] & 0xE0) == 0xE0 { return true }
        // FLAC
        if bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 { return true }
        // M4A/MP4: ....ftyp
        if bytes.count >= 8,
           let tag = String(data: data.subdata(in: 4..<8), encoding: .ascii),
           tag == "ftyp" {
            return true
        }
        // WAV
        if bytes.count >= 4,
           let tag = String(data: data.subdata(in: 0..<4), encoding: .ascii),
           tag == "RIFF" {
            return true
        }
        // OGG
        if bytes.count >= 4,
           let tag = String(data: data.subdata(in: 0..<4), encoding: .ascii),
           tag == "OggS" {
            return true
        }
        return false
    }
}
