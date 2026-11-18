import SwiftUI
import UIKit
import CoreImage

/// 从封面提取一个柔和的氛围色，用于播放页/歌词页背景。
@MainActor
enum ArtworkPalette {
    private static let cache = NSCache<NSString, UIColor>()

    static func baseColor(for urlString: String?) async -> Color? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        if let cached = cache.object(forKey: urlString as NSString) {
            return Color(uiColor: cached)
        }
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        guard let color = averageColor(of: image) else { return nil }
        cache.setObject(color, forKey: urlString as NSString)
        return Color(uiColor: color)
    }

    private static func averageColor(of image: UIImage) -> UIColor? {
        guard let ciImage = CIImage(image: image) else { return nil }
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
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = CGFloat(bitmap[0]) / 255
        let g = CGFloat(bitmap[1]) / 255
        let b = CGFloat(bitmap[2]) / 255
        let raw = UIColor(red: r, green: g, blue: b, alpha: 1)
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
