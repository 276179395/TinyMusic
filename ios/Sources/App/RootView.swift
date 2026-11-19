import SwiftUI

struct RootView: View {
    let model: AppModel

    @State private var selectedTab = AppConfiguration.initialTab
    @State private var showS3Reminder = false

    var body: some View {
        Group {
            if !model.ready {
                LaunchView(status: model.status, error: model.error)
            } else {
                MainTabView(model: model, selection: $selectedTab)
            }
        }
        // 语言一改，locale 也跟着换：SwiftUI 会重配导航栏/标签栏等系统 chrome，
        // 界面文案由 L() 的 Observation 刷新。
        .environment(\.locale, Localization.shared.locale)
        .task {
            await model.boot()
            if model.ready && !model.settings.isConfigured && !model.player.showNowPlaying {
                showS3Reminder = true
            }
        }
        .alert(L("添加 S3 网盘"), isPresented: $showS3Reminder) {
            Button(L("去设置")) { selectedTab = 3 }
            Button(L("先逛逛"), role: .cancel) {}
        } message: {
            Text(L("TinyMusic 播放的是你自己的 S3 网盘音乐。请先在设置里填写网盘地址和密钥；也可以先随便逛逛，随时再去添加。"))
        }
        .onChange(of: model.player.showNowPlaying) { _, showing in
            if showing { showS3Reminder = false }
        }
        .animation(.easeInOut(duration: 0.2), value: model.ready)
    }
}

private struct LaunchView: View {
    let status: String
    let error: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.tint)
            Text("TinyMusic")
                .font(.largeTitle.weight(.bold))
            ProgressView()
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
