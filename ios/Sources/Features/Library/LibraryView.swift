import SwiftUI

struct LibraryView: View {
    let model: AppModel

    @State private var showCreate = false
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?
    @State private var startingPlaylist: String?
    @State private var path = NavigationPath()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)]

    private var isOffline: Bool {
        !model.settings.isConfigured || model.library.lastLoadFailed
    }

    private var playlists: [Playlist] {
        isOffline ? model.cache.cachedPlaylists : model.library.playlists
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.library.loadingPlaylists && playlists.isEmpty && !isOffline {
                    ProgressView("读取歌单…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    ContentUnavailableView(
                        isOffline ? "还没有缓存歌单" : "还没有歌单",
                        systemImage: "music.note.list"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(playlists) { playlist in
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink(value: playlist) {
                                        PlaylistCard(playlist: playlist)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if !isOffline && !playlist.root {
                                            Button("重命名歌单") { renaming = playlist }
                                            Button("删除歌单", role: .destructive) { deleting = playlist }
                                        }
                                    }

                                    playlistPlayButton(playlist)
                                        .padding(9)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .padding(.bottom, 76)
                    }
                    .refreshable {
                        if model.settings.isConfigured {
                            await model.library.refreshAll()
                        }
                    }
                }
            }
            .navigationTitle("歌单")
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistView(model: model, playlist: playlist)
            }
            .toolbar {
                if model.settings.isConfigured {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isOffline)
                        .accessibilityLabel("新建歌单")

                        Button {
                            Task { await model.library.refreshAll() }
                        } label: {
                            if model.library.loadingPlaylists {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(model.library.loadingPlaylists)
                        .accessibilityLabel("刷新歌单")
                    }
                }
            }
            .task {
                if model.settings.isConfigured && model.library.playlists.isEmpty {
                    await model.library.loadPlaylists()
                }
                if AppConfiguration.screen == "playlist", path.isEmpty,
                   let first = playlists.first {
                    path.append(first)
                }
            }
            .overlay(alignment: .bottom) {
                if let error = model.library.error, !isOffline {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .tmGlassCapsule()
                        .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $showCreate) {
                PlaylistNameSheet(title: "新建歌单") { name in
                    await model.library.createPlaylist(named: name)
                }
            }
            .sheet(item: $renaming) { playlist in
                PlaylistNameSheet(title: "重命名歌单", initialName: playlist.name) { name in
                    await model.library.renamePlaylist(playlist, to: name)
                }
            }
            .confirmationDialog("删除「\(deleting?.name ?? "")」？", isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("删除歌单和云端歌曲", role: .destructive) {
                    guard let playlist = deleting else { return }
                    Task { _ = await model.library.deletePlaylist(playlist) }
                    deleting = nil
                }
                Button("取消", role: .cancel) { deleting = nil }
            } message: {
                Text("会删除 S3 上的歌单目录和里面的歌曲，无法撤销。")
            }
        }
    }

    private func isCurrentPlaylist(_ playlist: Playlist) -> Bool {
        model.player.playlistContext == playlist.name && model.player.current != nil
    }

    @ViewBuilder
    private func playlistPlayButton(_ playlist: Playlist) -> some View {
        let isCurrent = isCurrentPlaylist(playlist)
        Button {
            if isCurrent {
                model.player.toggle()
            } else {
                playPlaylist(playlist)
            }
        } label: {
            Group {
                if startingPlaylist == playlist.name {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isCurrent && model.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .offset(x: isCurrent && model.player.isPlaying ? 0 : 1)
                }
            }
            .frame(width: 36, height: 36)
            .foregroundStyle(isCurrent ? Color.white : Color.primary)
            .background {
                Circle()
                    .fill(isCurrent ? Color.accentColor.opacity(0.94) : Color.clear)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .overlay(Circle().stroke(.white.opacity(isCurrent ? 0.4 : 0.28), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(playlist.count == 0 || startingPlaylist != nil)
        .accessibilityLabel(isCurrent ? (model.player.isPlaying ? "暂停歌单" : "继续播放歌单") : "播放整个歌单")
        .accessibilityIdentifier("playlist-play-\(playlist.name)")
    }

    private func playPlaylist(_ playlist: Playlist) {
        guard startingPlaylist == nil, playlist.count > 0 else { return }
        startingPlaylist = playlist.name
        Task {
            var tracks: [Track]
            if isOffline {
                tracks = model.cache.cachedTracks(in: playlist.name)
            } else {
                if model.library.tracks(for: playlist).isEmpty {
                    await model.library.loadTracks(for: playlist)
                }
                tracks = model.library.tracks(for: playlist)
                if tracks.isEmpty {
                    tracks = model.cache.cachedTracks(in: playlist.name)
                }
            }
            startingPlaylist = nil
            guard let first = tracks.first else { return }
            model.player.play(track: first, in: tracks, context: playlist.name)
        }
    }
}
