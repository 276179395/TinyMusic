import SwiftUI

struct MainTabView: View {
    let model: AppModel
    @Binding var selection: Int

    var body: some View {
        // 读一下当前语言：标签文字随语言变化，TabView 必须跟着重算。
        let _ = Localization.shared.language
        ZStack {
            TabView(selection: $selection) {
                tabContent(FavoritesView(model: model))
                    .tabItem { Label(L("喜欢"), systemImage: "heart") }
                    .tag(0)

                tabContent(LibraryView(model: model))
                    .tabItem { Label(L("歌单"), systemImage: "music.note.list") }
                    .tag(1)

                tabContent(CacheView(model: model))
                    .tabItem { Label(L("缓存"), systemImage: "arrow.down.circle") }
                    .tag(2)

                tabContent(SettingsView(model: model))
                    .tabItem { Label(L("设置"), systemImage: "gearshape") }
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
