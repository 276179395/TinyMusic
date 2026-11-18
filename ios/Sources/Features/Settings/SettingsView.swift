import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @State private var showS3 = false
    @State private var testing = false
    @State private var alert: SettingsAlert?

    private enum SettingsAlert: Identifiable {
        case test(String)
        case iCloudUnavailable

        var id: String {
            switch self {
            case .test: return "test"
            case .iCloudUnavailable: return "icloud"
            }
        }
    }

    private var connectionColor: Color {
        if model.settings.error != nil { return .red }
        return model.settings.isConfigured ? .green : .orange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .font(.title3)
                                .frame(width: 28, height: 28)
                            Circle()
                                .fill(connectionColor)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                                .offset(x: 3, y: -2)
                        }
                        Text("S3 网盘")
                        Spacer()
                        Button {
                            showS3 = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑连接")

                        Button {
                            Task { await runTest() }
                        } label: {
                            Group {
                                if testing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                            }
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.settings.isConfigured || testing)
                        .accessibilityLabel("测试连接")
                    }
                }

                Section {
                    Toggle("iCloud 同步配置", isOn: Binding(
                        get: { model.settings.iCloudEnabled },
                        set: { value in
                            guard AppConfiguration.hasICloudAccount else {
                                alert = .iCloudUnavailable
                                return
                            }
                            Task { await model.settings.setICloudEnabled(value) }
                        }
                    ))
                }

                Section {
                    NavigationLink {
                        EqualizerView(eq: model.player.eq)
                    } label: {
                        Label("均衡器", systemImage: "slider.horizontal.3")
                    }
                }

                Section {
                    Button("断开 S3 连接", role: .destructive) {
                        Task {
                            await model.settings.disconnect()
                            model.library.clear()
                        }
                    }
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(versionText)
                            .foregroundStyle(.secondary)
                    }
                    Link("隐私政策", destination: URL(string: "https://cn.carljoy/tinymusic/privacy.html")!)
                }

                Section {
                    Color.clear
                        .frame(height: 76)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .contentMargins(.bottom, 88, for: .scrollContent)
            .navigationTitle("设置")
            .sheet(isPresented: $showS3) {
                S3SetupView(model: model, isOnboarding: false)
            }
            .alert(item: $alert) { item in
                switch item {
                case .test(let message):
                    return Alert(
                        title: Text("连接测试"),
                        message: Text(message),
                        dismissButton: .default(Text("好"))
                    )
                case .iCloudUnavailable:
                    return Alert(
                        title: Text("iCloud 不可用"),
                        message: Text("当前构建或 Apple ID 未启用 iCloud 同步。"),
                        dismissButton: .default(Text("好"))
                    )
                }
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        let result = await model.settings.testConnection()
        alert = .test(result ?? model.settings.error ?? "连接失败")
    }
}
