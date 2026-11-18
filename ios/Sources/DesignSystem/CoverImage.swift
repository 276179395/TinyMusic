import SwiftUI
import UIKit

@MainActor
private final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 240
    }

    func key(for urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        components.query = nil
        components.fragment = nil
        return components.string ?? urlString
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
            } else if failed {
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
            failed = false
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
