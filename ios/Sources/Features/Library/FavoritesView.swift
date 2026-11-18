import SwiftUI

struct FavoritesView: View {
    let model: AppModel

    private var tracks: [Track] { model.library.favorites.map(\.asTrack) }

    var body: some View {
        NavigationStack {
            Group {
                if model.library.loadingFavorites && model.library.favorites.isEmpty {
                    ProgressView("读取收藏…")
                } else if model.library.favorites.isEmpty {
                    ContentUnavailableView("还没有喜欢的歌", systemImage: "heart")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.library.favorites) { favorite in
                                TrackRow(
                                    track: favorite.asTrack,
                                    isFavorite: true,
                                    coverURL: model.cache.coverURL(for: favorite.id)?.absoluteString,
                                    isCached: model.cache.isCached(favorite.id),
                                    isCaching: model.cache.active.contains(favorite.id),
                                    cacheProgress: model.cache.progress[favorite.id],
                                    onPlay: {
                                        model.player.play(track: favorite.asTrack, in: tracks, context: "喜欢")
                                        model.player.showNowPlaying = true
                                    },
                                    onFavorite: {
                                        Task { _ = await model.library.removeFavorite(favorite.asTrack) }
                                    },
                                    onCache: {
                                        toggleCache(favorite.asTrack)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .padding(.bottom, 76)
                    }
                    .refreshable {
                        if model.settings.isConfigured {
                            await model.library.pullFavorites()
                        }
                    }
                }
            }
            .navigationTitle("喜欢")
            .task {
                if model.settings.isConfigured {
                    await model.library.pullFavorites()
                }
            }
            .overlay(alignment: .bottom) {
                if let warning = model.library.favoriteSyncWarning {
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .tmGlassCapsule()
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func toggleCache(_ track: Track) {
        if model.cache.isCached(track.key) {
            model.cache.remove(track.key)
        } else {
            Task { _ = try? await CacheManager.shared.enqueue(track: track, playlist: "喜欢") }
        }
    }
}
