import SwiftUI
import UIKit
import CoreImage
import ImageIO

/// 从封面缩略图里求一个平均色，再适当提饱和/压亮度，得到柔和的氛围色。
struct ArtworkRGB: Sendable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
}

/// 从封面提取一个柔和的氛围色，用于播放页/歌词页背景。
@MainActor
enum ArtworkPalette {
    private static let cache = NSCache<NSString, UIColor>()

    /// `CIContext` 的创建是几十毫秒级，而原来每次取色都新建一个。
    /// `CIContext` 本身线程安全，提成静态后可以跨线程复用。
    nonisolated private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    static func baseColor(for urlString: String?) async -> Color? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        if let cached = cache.object(forKey: urlString as NSString) {
            return Color(uiColor: cached)
        }
        // 读文件 / 解码 / 求均值全部离开主线程。
        // 原来这些直接跑在 `@MainActor` 上，而 `NowPlayingView` 的 `.task` 也是主 actor——
        // 切歌瞬间主线程被整段占住（读文件 + 解整张封面 + 新建 CIContext + CI 渲染）。
        let rgb = await Task.detached(priority: .userInitiated) { () -> ArtworkRGB? in
            guard let data = await loadData(url) else { return nil }
            return averageRGB(of: data)
        }.value
        guard let rgb else { return nil }
        let color = tune(rgb)
        cache.setObject(color, forKey: urlString as NSString)
        return Color(uiColor: color)
    }

    private nonisolated static func loadData(_ url: URL) async -> Data? {
        if url.isFileURL { return try? Data(contentsOf: url) }
        return try? await URLSession.shared.data(from: url).0
    }

    /// 先把封面缩到 32 px 再求均值。
    ///
    /// 原来是对原图跑 `CIAreaAverage`，也就是要解一张完整尺寸的封面。
    /// 均值对下采样不敏感（两者都是求平均），所以先缩再算，代价从「解整张图」变成「解 32×32」。
    private nonisolated static func averageRGB(of data: Data) -> ArtworkRGB? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        let ciImage = CIImage(cgImage: thumbnail)
        let extent = ciImage.extent
        guard !extent.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: extent),
              ]),
              let output = filter.outputImage else {
            return nil
        }
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return ArtworkRGB(
            r: CGFloat(bitmap[0]) / 255,
            g: CGFloat(bitmap[1]) / 255,
            b: CGFloat(bitmap[2]) / 255
        )
    }

    /// 提饱和 / 压亮度，让氛围色落在可用区间。留在主 actor（构造 UIColor，很便宜）。
    private static func tune(_ rgb: ArtworkRGB) -> UIColor {
        let raw = UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard raw.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return raw
        }
        return UIColor(
            hue: hue,
            saturation: min(0.82, max(0.30, saturation * 1.35)),
            brightness: min(0.86, max(0.38, brightness)),
            alpha: 1
        )
    }
}
