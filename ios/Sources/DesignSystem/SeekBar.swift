import SwiftUI

/// 固定宽度的可拖动进度条。避免 GeometryReader 在 VStack 里被撑满。
struct SeekBar: View {
    let value: Double
    let total: Double
    let width: CGFloat
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    init(value: Double, total: Double, width: CGFloat = 280, onSeek: @escaping (Double) -> Void) {
        self.value = value
        self.total = total
        self.width = width
        self.onSeek = onSeek
    }

    var body: some View {
        let shown = dragValue ?? value
        let progress = total > 0 ? min(max(shown / total, 0), 1) : 0
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(height: 4)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: max(0, width * progress), height: 4)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .offset(x: max(0, width * progress - 6))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(width: width, height: 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let fraction = min(max(gesture.location.x / width, 0), 1)
                    dragValue = fraction * max(total, 0)
                }
                .onEnded { gesture in
                    let fraction = min(max(gesture.location.x / width, 0), 1)
                    let target = fraction * max(total, 0)
                    dragValue = nil
                    onSeek(target)
                }
        )
        .accessibilityElement()
        .accessibilityLabel(L("播放进度"))
        .accessibilityValue(String(format: "%d%%", Int(progress * 100)))
    }
}
