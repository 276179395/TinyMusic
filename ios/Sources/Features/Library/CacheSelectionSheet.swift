import SwiftUI

struct CacheSelectionSheet: View {
    let tracks: [Track]
    let playlistName: String
    var onConfirm: ([Track]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tracks) { track in
                        Button {
                            if selected.contains(track.key) {
                                selected.remove(track.key)
                            } else {
                                selected.insert(track.key)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(track.key) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(track.key) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).foregroundStyle(.primary).lineLimit(1)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!track.playable)
                    }
                } footer: {
                    if !tracks.isEmpty {
                        Text(L("已选 %@ / %@ 首", "\(selected.count)", "\(tracks.count)"))
                    }
                }
            }
            .navigationTitle(L("选择要缓存的歌曲"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("缓存")) {
                        let chosen = tracks.filter { selected.contains($0.key) }
                        onConfirm(chosen)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(selected.count == tracks.count ? L("取消全选") : L("全选")) {
                        if selected.count == tracks.count {
                            selected.removeAll()
                        } else {
                            selected = Set(tracks.filter(\.playable).map(\.key))
                        }
                    }
                }
            }
        }
    }
}
