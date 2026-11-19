import SwiftUI
import UIKit

@MainActor
private final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, UIImage>()
    /// `key(for:)` 的解析结果缓存。
    ///
    /// `CoverImage.init` 在父视图每趟求值时都会跑一次（结果会被 SwiftUI 丢掉），
    /// 而 `URLComponents(string:)` 每次都是一次完整解析。播放页 4 Hz × 3 个封面
    /// 就是每秒 12 次纯浪费。presigned URL 的 query 每次都不同，所以直接按原串做 key。
    private let keys = NSCache<NSString, NSString>()

    init() {
        cache.countLimit = 240
        keys.countLimit = 400
    }

    func key(for urlString: String) -> String {
        if let cached = keys.object(forKey: urlString as NSString) { return cached as String }
        guard var components = URLComponents(string: urlString) else { return urlString }
        components.query = nil
        components.fragment = nil
        let key = components.string ?? urlString
        keys.setObject(key as NSString, forKey: urlString as NSString)
        return key
    }

    func image(for urlString: String?) -> UIImage? {
        guard let urlString else { return nil }
        return cache.object(forKey: key(for: urlString) as NSString)
    }

    func store(_ image: UIImage, for urlString: String) {
        cache.setObject(image, forKey: key(for: urlString) as NSString)
    }
}

struct CoverImage: View {
    let url: String?
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?
    @State private var failed = false

    init(url: String?, cornerRadius: CGFloat = 10) {
        self.url = url
        self.cornerRadius = cornerRadius
        _image = State(initialValue: CoverImageCache.shared.image(for: url))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
            } else if failed || url == nil {
                placeholder
            } else {
                placeholder.overlay(ProgressView().controlSize(.small))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            await load()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.tertiarySystemFill), Color(.secondarySystemFill)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func load() async {
        guard let url, let parsed = URL(string: url) else {
            image = nil
            failed = true
            return
        }
        if let cached = CoverImageCache.shared.image(for: url) {
            image = cached
            failed = false
            return
        }
        failed = false
        let data: Data?
        if parsed.isFileURL {
            data = try? Data(contentsOf: parsed)
        } else {
            data = try? await URLSession.shared.data(from: parsed).0
        }
        guard !Task.isCancelled else { return }
        guard let data, let decoded = UIImage(data: data) else {
            failed = true
            return
        }
        CoverImageCache.shared.store(decoded, for: url)
        image = decoded
    }
}
