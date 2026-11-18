import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 28
    var lineWidth: CGFloat = 3
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.35), value: progress)
    }
}
