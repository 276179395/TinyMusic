import SwiftUI

/// 播放页内嵌歌词：参考 Apple Music，当前行放大加粗，上下文逐级淡出。
struct InlineLyricsView: View {
    let store: LyricsStore
    let player: PlayerEngine

    private let lyricWidth: CGFloat = 330

    var body: some View {
        ZStack {
            if store.loading {
                ProgressView()
                    .tint(.primary)
            } else if !store.present {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.title3)
                    Text(L("暂无歌词"))
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(.systemBackground).opacity(0.0),
                                Color(.systemBackground).opacity(0.42),
                                Color(.systemBackground).opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 20) {
                                ForEach(Array(store.lines.enumerated()), id: \.offset) { index, line in
                                    lyricLine(index: index, line: line)
                                        .id(index)
                                }
                            }
                            .frame(maxWidth: lyricWidth)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 170)
                        }
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.14),
                                    .init(color: .black, location: 0.86),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onChange(of: store.activeIndex) { _, index in
                            guard index >= 0 else { return }
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lyricLine(index: Int, line: LyricLine) -> some View {
        let active = index == store.activeIndex
        let distance = abs(index - store.activeIndex)
        Button {
            player.seek(to: Double(line.timeMs) / 1000)
        } label: {
            Text(line.text.isEmpty ? " " : line.text)
                .font(active ? .title3.weight(.bold) : (distance == 1 ? .body.weight(.semibold) : .subheadline))
                .foregroundStyle(active ? Color.primary : Color.primary.opacity(opacity(for: distance)))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: lyricWidth)
                .scaleEffect(active ? 1 : 0.98)
                .animation(.easeInOut(duration: 0.25), value: store.activeIndex)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func opacity(for distance: Int) -> Double {
        switch distance {
        case 0: return 1
        case 1: return 0.55
        case 2: return 0.36
        case 3: return 0.24
        default: return 0.16
        }
    }
}
