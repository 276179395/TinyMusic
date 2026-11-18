import SwiftUI

struct S3SetupView: View {
    let model: AppModel
    var isOnboarding = false

    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var region = "us-east-1"
    @State private var bucket = ""
    @State private var prefix = "TinyMusic"
    @State private var pathStyle = false
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var busy = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if isOnboarding {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("只播放你自己的音乐", systemImage: "lock.shield")
                                .font(.headline)
                            Text("TinyMusic 不提供在线曲库、搜索或平台下载。你只能播放自己拥有或有权使用的 S3 兼容存储中的音乐。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    TextField("https://s3.example.com", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("s3.endpoint")
                    TextField("Region（R2 可填 auto）", text: $region)
                        .textInputAutocapitalization(.never)
                    TextField("Bucket", text: $bucket)
                        .textInputAutocapitalization(.never)
                    TextField("前缀目录（如 TinyMusic）", text: $prefix)
                        .textInputAutocapitalization(.never)
                    Toggle("Path style 寻址", isOn: $pathStyle)
                } header: {
                    Text("S3 连接")
                }

                Section {
                    TextField("Access Key", text: $accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Secret Key", text: $secretKey)
                        .textInputAutocapitalization(.never)
                    Toggle("通过 iCloud 钥匙串同步密钥", isOn: Binding(
                        get: { model.settings.iCloudEnabled },
                        set: { value in
                            Task { await model.settings.setICloudEnabled(value) }
                        }
                    ))
                    .disabled(!AppConfiguration.hasICloudAccount)
                } header: {
                    Text("凭据")
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isOnboarding ? "连接 S3 网盘" : "S3 连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("s3.save")
                }
            }
            .task { loadCurrent() }
        }
        .interactiveDismissDisabled(isOnboarding)
    }

    private func loadCurrent() {
        guard endpoint.isEmpty, bucket.isEmpty else { return }
        let current = model.settings.settings
        endpoint = current.s3Endpoint
        region = current.s3Region
        bucket = current.s3Bucket
        prefix = current.s3Prefix
        pathStyle = current.s3PathStyle
    }

    private func save() async {
        busy = true
        defer { busy = false }
        error = nil
        message = nil
        let ok = await model.settings.save(
            endpoint: endpoint,
            region: region,
            bucket: bucket,
            prefix: prefix,
            pathStyle: pathStyle,
            accessKey: accessKey,
            secretKey: secretKey
        )
        if ok {
            message = "已保存"
            await model.reloadLibrary()
            if !isOnboarding {
                dismiss()
            }
        } else {
            error = model.settings.error
        }
    }
}
