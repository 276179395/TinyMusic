import SwiftUI

/// 当前播放队列：从底部弹出，支持切歌、删除单曲和清空。
struct PlaybackQueueView: View {
    let player: PlayerEngine

    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if player.queue.isEmpty {
                    ContentUnavailableView(L("播放列表为空"), systemImage: "list.bullet")
                } else {
                    List {
                        Section {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { _, track in
                                queueRow(track)
                            }
                        } header: {
                            Text(L("%@ 首", "\(player.queue.count)"))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L("播放列表"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("关闭")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("清空"), role: .destructive) {
                        showClearConfirm = true
                    }
                    .disabled(player.queue.isEmpty)
                }
            }
            .confirmationDialog(L("清空播放列表？"), isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button(L("清空"), role: .destructive) {
                    player.clearQueue()
                    dismiss()
                }
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("会停止播放并移除整个当前播放列表，不会删除歌单或 S3 文件。"))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func queueRow(_ track: Track) -> some View {
        HStack(spacing: 10) {
            Button {
                player.jump(to: track)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: player.current?.key == track.key ? "waveform" : "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(player.current?.key == track.key ? Color.accentColor : Color.secondary)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(player.current?.key == track.key ? .semibold : .regular))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("播放 %@", track.title))

            Button(role: .destructive) {
                player.removeFromQueue(track)
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("从播放列表移除 %@", track.title))
        }
        .swipeActions {
            Button(role: .destructive) {
                player.removeFromQueue(track)
            } label: {
                Label(L("移除"), systemImage: "trash")
            }
        }
    }
}
