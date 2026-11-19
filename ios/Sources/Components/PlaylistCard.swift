import SwiftUI

struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: playlist.cover, cornerRadius: 14)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                Text(L("%@ 首", "\(playlist.count)"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .tmGlassCapsule()
                    .padding(8)
            }
            Text(playlist.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if playlist.root {
                Text(L("根目录"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
