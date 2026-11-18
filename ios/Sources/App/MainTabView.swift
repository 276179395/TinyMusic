import SwiftUI

struct MainTabView: View {
    let model: AppModel
    @State private var selection = AppConfiguration.initialTab

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                tabContent(LibraryView(model: model))
                    .tabItem { Label("资料库", systemImage: "music.note.list") }
                    .tag(0)

                tabContent(FavoritesView(model: model))
                    .tabItem { Label("喜欢", systemImage: "heart") }
                    .tag(1)

                tabContent(CacheView(model: model))
                    .tabItem { Label("缓存", systemImage: "arrow.down.circle") }
                    .tag(2)

                tabContent(SettingsView(model: model))
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(3)
            }
            .tint(.accentColor)

            if model.player.showNowPlaying {
                NowPlayingView(model: model) {
                    model.player.showNowPlaying = false
                }
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .animation(.snappy(duration: 0.28), value: model.player.showNowPlaying)
    }

    /// 放在每个 tab 的内容底部，而不是 TabView 外层；
    /// 否则 mini player 会压到 iOS 26 的悬浮 tab bar 上。
    private func tabContent<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(player: model.player)
        }
    }
}
