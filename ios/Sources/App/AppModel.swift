import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var status = "正在启动…"
    private(set) var ready = false
    private(set) var error: String?
    private(set) var appInfo: AppInfo?

    let backend: RustBackend
    let settings: SettingsStore
    let library: LibraryStore
    let player: PlayerEngine
    let cache: CacheStore

    init(
        backend: RustBackend = .shared,
        settings: SettingsStore? = nil,
        library: LibraryStore? = nil,
        player: PlayerEngine? = nil
    ) {
        self.backend = backend
        self.settings = settings ?? SettingsStore(backend: backend)
        self.library = library ?? LibraryStore(backend: backend)
        self.cache = CacheStore.shared
        self.player = player ?? PlayerEngine(backend: backend, cache: CacheStore.shared)

        let playerRef = self.player
        let settingsRef = self.settings
        settingsRef.eqProvider = { [weak playerRef] in playerRef?.eq.state }
        settingsRef.onRemoteEQ = { [weak playerRef] state in playerRef?.eq.apply(state) }
        playerRef.eq.onChange = { [weak settingsRef] state in settingsRef?.pushCurrent(eq: state) }
    }

    func boot() async {
        guard !ready else { return }
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("tinymusic", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let info = try await backend.start(configDir: support)
            appInfo = info
            await settings.load()
            ready = true
            status = "就绪"
            error = nil
            if AppConfiguration.eqTest {
                player.eq.applyPreset("rock")
            }
            if settings.isConfigured {
                await reloadLibrary()
            }
            if AppConfiguration.playCached {
                playFirstCached()
            }
        } catch {
            status = "启动失败"
            self.error = error.localizedDescription
        }
    }

    func reloadLibrary() async {
        await library.refreshAll()
        if let first = library.playlists.first {
            await library.loadTracks(for: first)
            let tracks = library.tracks(for: first)
            if let track = tracks.first {
                if AppConfiguration.autoPlay {
                    player.play(track: track, in: tracks, context: first.name)
                    player.showNowPlaying = ["player", "eq", "lyrics"].contains(AppConfiguration.screen ?? "")
                }
                if AppConfiguration.autoCache {
                    _ = try? await CacheManager.shared.enqueue(track: track, playlist: first.name)
                }
            }
        }
    }

    private func playFirstCached() {
        let entries = cache.entries.values
            .filter { $0.status == .done }
            .sorted { $0.cachedAt > $1.cachedAt }
        guard let first = entries.first else { return }
        let tracks = entries.map(\.track)
        guard let track = tracks.first(where: { $0.key == first.key }) else { return }
        player.play(track: track, in: tracks)
        player.showNowPlaying = true
    }

    func refreshAll() async {
        await settings.refreshCredentials()
        await reloadLibrary()
    }
}
