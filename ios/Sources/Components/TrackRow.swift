import SwiftUI

struct TrackRow: View {
    let track: Track
    let isFavorite: Bool
    var coverURL: String? = nil
    var isCached: Bool = false
    var isCaching: Bool = false
    var cacheProgress: Double? = nil
    var onPlay: (() -> Void)?
    var onFavorite: (() -> Void)?
    var onCache: (() -> Void)?
    var onPlayNext: (() -> Void)?
    var onDelete: (() -> Void)?
    var moveTargets: [Playlist] = []
    var onMove: ((Playlist) -> Void)?
    @State private var confirmUnfavorite = false

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 8) {
            Button {
                onPlay?()
            } label: {
                HStack(spacing: 12) {
                    CoverImage(url: coverURL ?? track.cover, cornerRadius: 8)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(track.artist.isEmpty ? "未知艺人" : track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if track.isLossless {
                                Text("无损")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                            }
                            if let missing = track.missingLabel {
                                Text(missing)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TrackRowButtonStyle())
            .disabled(!track.playable)
            .contextMenu { contextMenu }

            if let onCache {
                Button(action: onCache) {
                    ZStack {
                        Circle().fill(Color(.tertiarySystemFill).opacity(0.55))
                        if isCaching {
                            ProgressRing(progress: cacheProgress ?? 0, size: 22, lineWidth: 2.5)
                        } else {
                            Image(systemName: isCached ? "checkmark.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isCached ? Color.green : Color.secondary)
                        }
                    }
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCaching ? "正在缓存" : (isCached ? "删除缓存" : "缓存到本地"))
            }

            if let onFavorite {
                Button {
                    if isFavorite {
                        confirmUnfavorite = true
                    } else {
                        onFavorite()
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.red : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(.tertiarySystemFill).opacity(0.55)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "取消喜欢" : "喜欢")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 7)

        if isCaching {
            ProgressView(value: cacheProgress ?? 0)
                .tint(.accentColor)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
                .transition(.opacity)
        }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contextMenu { contextMenu }
        .alert("取消喜欢？", isPresented: $confirmUnfavorite) {
            Button("取消喜欢", role: .destructive) { onFavorite?() }
            Button("保留", role: .cancel) {}
        } message: {
            Text("会从喜欢歌单移除这首歌，但不会删除 S3 上的文件。")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let onPlayNext {
            Button(action: onPlayNext) {
                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
        }
        if let onFavorite {
            Button {
                if isFavorite {
                    confirmUnfavorite = true
                } else {
                    onFavorite()
                }
            } label: {
                Label(isFavorite ? "取消喜欢" : "喜欢", systemImage: isFavorite ? "heart.slash" : "heart")
            }
        }
        if let onCache {
            Button(action: onCache) {
                Label(isCached ? "删除缓存" : "缓存到本地", systemImage: isCached ? "trash" : "arrow.down.circle")
            }
        }
        if !moveTargets.isEmpty, let onMove {
            Menu {
                ForEach(moveTargets) { target in
                    Button("移动到 \(target.name)") { onMove(target) }
                }
            } label: {
                Label("移动到歌单", systemImage: "folder")
            }
        }
        if let onDelete {
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("删除歌曲", systemImage: "trash")
            }
        }
    }
}
