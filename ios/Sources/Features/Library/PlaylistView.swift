import SwiftUI

struct PlaylistView: View {
    let model: AppModel
    let playlist: Playlist

    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var caching = false
    @State private var cacheMessage: String?
    @State private var showRename = false
    @State private var confirm: ConfirmAction?

    private enum ConfirmAction: Identifiable {
        case deletePlaylist
        case deleteTrack(Track)
        var id: String {
            switch self {
            case .deletePlaylist: return "playlist"
            case .deleteTrack(let track): return "track-\(track.key)"
            }
        }
    }

    private var isOffline: Bool {
        !model.settings.isConfigured || model.library.lastLoadFailed
    }

    private var tracks: [Track] {
        isOffline ? model.cache.cachedTracks(in: playlist.name) : model.library.tracks(for: playlist)
    }

    private var playableTracks: [Track] { tracks.filter(\.playable) }

    private var moveTargets: [Playlist] {
        guard !isOffline else { return [] }
        return model.library.playlists.filter { !$0.root && $0.name != playlist.name }
    }
    private var activeCacheCount: Int {
        tracks.filter { model.cache.active.contains($0.key) }.count
    }
    private var cacheOverallProgress: Double {
        let values = tracks.compactMap { model.cache.active.contains($0.key) ? (model.cache.progress[$0.key] ?? 0) : nil }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                trackList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 76)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isOffline {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Menu {
                            Button("缓存全部 \(playableTracks.count) 首") {
                                Task { await cacheTracks(playableTracks) }
                            }
                            Button("选择歌曲缓存…") { showPicker = true }
                        } label: {
                            if caching {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                        }
                        .disabled(tracks.isEmpty || caching)
                        .accessibilityLabel("缓存到本地")

                        Menu {
                            Button("重命名歌单") {
                                showRename = true
                            }
                            Button("删除歌单", role: .destructive) {
                                confirm = .deletePlaylist
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(playlist.root)
                        .accessibilityLabel("歌单操作")
                    }
                }
            }
        }
        .task {
            if !isOffline {
                await model.library.loadTracks(for: playlist)
            }
        }
        .refreshable {
            if !isOffline {
                await model.library.loadTracks(for: playlist)
            }
        }
        .sheet(isPresented: $showPicker) {
            CacheSelectionSheet(tracks: tracks, playlistName: playlist.name) { selected in
                Task { await cacheTracks(selected) }
            }
        }
        .alert("缓存", isPresented: Binding(
            get: { cacheMessage != nil },
            set: { if !$0 { cacheMessage = nil } }
        )) {
            Button("好") { cacheMessage = nil }
        } message: {
            Text(cacheMessage ?? "")
        }
        .sheet(isPresented: $showRename) {
            PlaylistNameSheet(title: "重命名歌单", initialName: playlist.name) { name in
                let ok = await model.library.renamePlaylist(playlist, to: name)
                if ok { dismiss() }
                return ok
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(
            get: { confirm != nil },
            set: { if !$0 { confirm = nil } }
        ), titleVisibility: .visible) {
            switch confirm {
            case .deletePlaylist:
                Button("删除歌单和云端歌曲", role: .destructive) {
                    Task {
                        if await model.library.deletePlaylist(playlist) { dismiss() }
                        confirm = nil
                    }
                }
            case .deleteTrack(let track):
                Button("删除歌曲", role: .destructive) {
                    Task {
                        if !(await model.library.deleteTrack(track)) {
                            cacheMessage = model.library.error
                        }
                        confirm = nil
                    }
                }
            case nil:
                EmptyView()
            }
            Button("取消", role: .cancel) { confirm = nil }
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .deletePlaylist: return "删除「\(playlist.name)」？"
        case .deleteTrack(let track): return "删除「\(track.title)」？"
        case nil: return ""
        }
    }

    private var confirmMessage: String {
        switch confirm {
        case .deletePlaylist: return "会删除 S3 上的歌单目录和里面的歌曲，无法撤销。"
        case .deleteTrack: return "会删除 S3 上的音频、歌词和封面。"
        case nil: return ""
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                CoverImage(url: playlist.cover, cornerRadius: 14)
                    .frame(width: 82, height: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text(playlist.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(isOffline ? "离线缓存 · \(tracks.count) 首" : "\(tracks.count) 首")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    playAll()
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(playableTracks.isEmpty)

                if !isOffline {
                    Menu {
                        Button("缓存全部 \(playableTracks.count) 首") {
                            Task { await cacheTracks(playableTracks) }
                        }
                        Button("选择歌曲缓存…") { showPicker = true }
                    } label: {
                        Label("缓存", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(tracks.isEmpty || caching)
                }
            }

            if activeCacheCount > 0 {
                VStack(spacing: 5) {
                    HStack {
                        Text("正在缓存 \(activeCacheCount) 首")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(cacheOverallProgress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: cacheOverallProgress)
                        .tint(.accentColor)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var trackList: some View {
        if !isOffline && model.library.loadingTracks && tracks.isEmpty {
            ProgressView("读取曲目…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if tracks.isEmpty {
            ContentUnavailableView(
                isOffline ? "这个歌单没有缓存歌曲" : "这个歌单是空的",
                systemImage: "music.note"
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(tracks) { track in
                    TrackRow(
                        track: track,
                        isFavorite: !isOffline && model.library.isFavorite(track),
                        coverURL: model.cache.coverURL(for: track.key)?.absoluteString,
                        isCached: model.cache.isCached(track.key),
                        isCaching: model.cache.active.contains(track.key),
                        cacheProgress: model.cache.progress[track.key],
                        onPlay: {
                            model.player.play(track: track, in: tracks, context: playlist.name)
                            model.player.showNowPlaying = true
                        },
                        onFavorite: isOffline ? nil : {
                            Task {
                                if model.library.isFavorite(track) {
                                    _ = await model.library.removeFavorite(track)
                                } else {
                                    _ = await model.library.addFavorite(track)
                                }
                            }
                        },
                        onCache: isOffline ? nil : {
                            toggleCache(track)
                        },
                        onPlayNext: {
                            model.player.playNext(track)
                        },
                        onDelete: isOffline ? nil : {
                            confirm = .deleteTrack(track)
                        },
                        moveTargets: moveTargets,
                        onMove: { target in
                            Task {
                                if await model.library.moveTrack(track, to: target) {
                                    cacheMessage = "已移动到「\(target.name)」"
                                } else {
                                    cacheMessage = model.library.error
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private func playAll() {
        guard let first = playableTracks.first else { return }
        model.player.play(track: first, in: playableTracks, context: playlist.name)
        model.player.showNowPlaying = true
    }

    private func toggleCache(_ track: Track) {
        if model.cache.isCached(track.key) {
            model.cache.remove(track.key)
            return
        }
        Task {
            do {
                let queued = try await CacheManager.shared.enqueue(track: track, playlist: playlist.name)
                if queued {
                    cacheMessage = "已加入缓存队列：\(track.title)"
                }
            } catch {
                cacheMessage = "缓存失败：\(error.localizedDescription)"
            }
        }
    }

    private func cacheTracks(_ selected: [Track]) async {
        let targets = selected.filter(\.playable)
        guard !targets.isEmpty else {
            cacheMessage = "没有可缓存的歌曲"
            return
        }
        caching = true
        defer { caching = false }
        var queued = 0
        for track in targets where !model.cache.isCached(track.key) {
            if (try? await CacheManager.shared.enqueue(track: track, playlist: playlist.name)) == true {
                queued += 1
            }
        }
        cacheMessage = queued > 0
            ? "已加入缓存队列：\(queued) 首"
            : "所选歌曲都已在本地"
    }
}
