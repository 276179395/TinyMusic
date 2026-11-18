import SwiftUI

struct EqualizerView: View {
    let eq: EQController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用均衡器", isOn: Binding(
                        get: { eq.enabled },
                        set: { eq.setEnabled($0) }
                    ))
                    Picker("预设", selection: Binding(
                        get: { eq.presetID },
                        set: { eq.applyPreset($0) }
                    )) {
                        ForEach(EQLibrary.presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                        if eq.presetID == "custom" {
                            Text("自定义").tag("custom")
                        }
                    }
                    if let preset = EQLibrary.preset(id: eq.presetID) {
                        Text(preset.desc)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("均衡器")
                } footer: {
                    Text("10 段峰值 EQ 通过 MTAudioProcessingTap 作用于 AVPlayer；流式与离线缓存都生效。")
                }

                Section("频段") {
                    ForEach(Array(EQLibrary.bands.enumerated()), id: \.offset) { index, hz in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(label(for: hz))
                                    .font(.subheadline.monospacedDigit())
                                Spacer()
                                Text(String(format: "%+.1f dB", eq.gains[index]))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(eq.gains[index]) },
                                    set: { eq.setGain(index: index, value: Float($0)) }
                                ),
                                in: Double(EQLibrary.minDB)...Double(EQLibrary.maxDB),
                                step: 0.5
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("前级") {
                    HStack {
                        Text("Preamp")
                        Spacer()
                        Text(String(format: "%+.1f dB", eq.preamp))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(eq.preamp) },
                            set: { eq.setPreamp(Float($0)) }
                        ),
                        in: Double(EQLibrary.minDB)...Double(EQLibrary.maxDB),
                        step: 0.5
                    )
                }

                Section {
                    Button("恢复平直", role: .destructive) {
                        eq.reset()
                    }
                }

                Section {
                    Color.clear
                        .frame(height: 76)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("均衡器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func label(for hz: Float) -> String {
        if hz >= 1000 { return String(format: "%.0fk", hz / 1000) }
        return String(format: "%.0f", hz)
    }
}
