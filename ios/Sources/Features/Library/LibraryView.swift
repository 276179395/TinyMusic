import SwiftUI

struct LibraryView: View {
    let model: AppModel

    @State private var showCreate = false
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?
    @State private var path = NavigationPath()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.library.loadingPlaylists && model.library.playlists.isEmpty {
                    ProgressView("读取歌单…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.library.playlists.isEmpty {
                    ContentUnavailableView("还没有歌单", systemImage: "music.note.list")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(model.library.playlists) { playlist in
                                NavigationLink(value: playlist) {
                                    PlaylistCard(playlist: playlist)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if !playlist.root {
                                        Button("重命名歌单") { renaming = playlist }
                                        Button("删除歌单", role: .destructive) { deleting = playlist }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .padding(.bottom, 76)
                    }
                    .refreshable { await model.library.refreshAll() }
                }
            }
            .navigationTitle("资料库")
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistView(model: model, playlist: playlist)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
            .task {
                if model.library.playlists.isEmpty {
                    await model.library.loadPlaylists()
                }
                if AppConfiguration.screen == "playlist", path.isEmpty,
                   let first = model.library.playlists.first {
                    path.append(first)
                }
            }
            .overlay(alignment: .bottom) {
                if let error = model.library.error {
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
}
