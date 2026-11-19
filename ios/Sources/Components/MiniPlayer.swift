import SwiftUI

struct MiniPlayer: View {
    let player: PlayerEngine
    @State private var showQueue = false

    var body: some View {
        if let current = player.current {
            HStack(spacing: 10) {
                CoverImage(url: player.currentCoverURL, cornerRadius: 8)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(current.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? L("暂停") : L("播放"))

                Button {
                    showQueue = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("播放列表"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .tmGlassCapsule()
            .padding(.horizontal, 19)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture { player.showNowPlaying = true }
            .sheet(isPresented: $showQueue) {
                PlaybackQueueView(player: player)
            }
        }
    }
}
