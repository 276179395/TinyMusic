import SwiftUI

struct PlaylistNameSheet: View {
    let title: String
    let initialName: String
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var busy = false
    @State private var error: String?

    init(title: String, initialName: String = "", onSave: @escaping (String) async -> Bool) {
        self.title = title
        self.initialName = initialName
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("歌单名"), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                        .disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text(L("保存")) }
                    }
                    .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        let ok = await onSave(name)
        if ok {
            dismiss()
        } else {
            error = L("保存失败，请检查名称或 S3 写权限")
        }
    }
}
