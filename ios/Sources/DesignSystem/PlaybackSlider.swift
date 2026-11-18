import SwiftUI

struct PlaybackSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    private var progress: Double {
        let clamped = min(max(dragValue ?? value, range.lowerBound), range.upperBound)
        let span = max(0.001, range.upperBound - range.lowerBound)
        return (clamped - range.lowerBound) / span
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(4, width * progress), height: 4)
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .offset(x: max(0, min(width - 16, width * progress - 8)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        let span = range.upperBound - range.lowerBound
                        dragValue = range.lowerBound + Double(fraction) * span
                    }
                    .onEnded { gesture in
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        let span = range.upperBound - range.lowerBound
                        let target = range.lowerBound + Double(fraction) * span
                        dragValue = nil
                        onSeek(target)
                    }
            )
        }
        .frame(height: 24)
    }
}
