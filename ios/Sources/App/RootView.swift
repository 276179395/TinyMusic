import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if !model.ready {
                LaunchView(status: model.status, error: model.error)
            } else if !model.settings.isConfigured {
                S3SetupView(model: model, isOnboarding: true)
            } else {
                MainTabView(model: model)
            }
        }
        .task { await model.boot() }
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
