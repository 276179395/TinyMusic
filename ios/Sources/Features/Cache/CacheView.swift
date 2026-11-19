import SwiftUI

struct CacheView: View {
    let model: AppModel
    @State private var showClearConfirm = false
    @State private var pendingPlaylistClear: String?
    @State private var expanded: Set<String> = []

    private var cache: CacheStore { model.cache }

    /// 一次遍历算出全部四类条目。
    ///
    /// 原来是 4 个独立计算属性：每趟 body 扫 4 遍 `entries.values`，
    /// 再加一次 `Dictionary(grouping:)` 和两次排序。而缓存进行时这段每 250 ms 就重算一次。
    private var snapshot: CacheSnapshot {
        var done: [CacheEntry] = []
        var downloading: [CacheEntry] = []
        var failed: [CacheEntry] = []
        done.reserveCapacity(cache.entries.count)
        for entry in cache.entries.values {
            switch entry.status {
            case .done: done.append(entry)
            case .downloading: downloading.append(entry)
            case .failed: failed.append(entry)
            }
        }

        var grouped: [String: [CacheEntry]] = [:]
        for entry in done {
            grouped[entry.playlist.isEmpty ? L("未分类") : entry.playlist, default: []].append(entry)
        }
        let groups = grouped.map { name, entries in
            CacheGroup(
                name: name,
                entries: entries.sorted { $0.cachedAt > $1.cachedAt },
                bytes: entries.reduce(0) { $0 + $1.audioBytes }
            )
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        return CacheSnapshot(done: done, active: downloading, failed: failed, groups: groups)
    }

    var body: some View {
        let snap = snapshot
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(L("已占用"), systemImage: "internaldrive")
                        Spacer()
                        Text(byteText(cache.totalBytes))
                            .foregroundStyle(.secondary)
                    }
                    Picker(L("缓存上限"), selection: Binding(
                        get: { cache.limitMB },
                        set: { cache.limitMB = $0 }
                    )) {
                        Text("512 MB").tag(512)
                        Text("1 GB").tag(1024)
                        Text("2 GB").tag(2048)
                        Text("5 GB").tag(5120)
                        Text("10 GB").tag(10240)
                        Text(L("不限")).tag(0)
                    }
                    Toggle(L("仅 Wi-Fi 缓存"), isOn: Binding(
                        get: { cache.wifiOnly },
                        set: { cache.wifiOnly = $0 }
                    ))
                }

                if !snap.active.isEmpty {
                    Section {
                        ForEach(snap.active) { entry in
                            CacheRow(entry: entry, progress: cache.progressBox(for: entry.key), cache: cache)
                        }
                    }
                }

                if !snap.failed.isEmpty {
                    Section {
                        ForEach(snap.failed) { entry in
                            FailedCacheRow(entry: entry, cache: cache)
                        }
                    }
                }

                if snap.done.isEmpty && snap.active.isEmpty && snap.failed.isEmpty {
                    Section {
                        ContentUnavailableView(L("还没有缓存"), systemImage: "arrow.down.circle")
                    }
                } else if !snap.groups.isEmpty {
                    Section {
                        ForEach(snap.groups) { group in
                            groupHeader(group)
                            if expanded.contains(group.name) {
                                ForEach(group.entries) { entry in
                                    cachedRow(entry)
                                }
                            }
                        }
                    }
                }

                if !cache.entries.isEmpty {
                    Section {
                        Button(L("清除全部缓存"), role: .destructive) {
                            showClearConfirm = true
                        }
                    }
                }

                Section {
                    Color.clear
                        .frame(height: 76)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .contentMargins(.bottom, 88, for: .scrollContent)
            .navigationTitle(L("缓存"))
            .confirmationDialog(L("清除全部缓存？"), isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button(L("清除全部"), role: .destructive) { cache.clear() }
                Button(L("取消"), role: .cancel) {}
            }
            .confirmationDialog(
                L("清除「%@」的缓存？", pendingPlaylistClear ?? ""),
                isPresented: Binding(
                    get: { pendingPlaylistClear != nil },
                    set: { if !$0 { pendingPlaylistClear = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L("清除这个歌单"), role: .destructive) {
                    guard let name = pendingPlaylistClear else { return }
                    clearPlaylist(name)
                    pendingPlaylistClear = nil
                }
                Button(L("取消"), role: .cancel) { pendingPlaylistClear = nil }
            }
        }
    }

    @ViewBuilder
    private func groupHeader(_ group: CacheGroup) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if expanded.contains(group.name) {
                        expanded.remove(group.name)
                    } else {
                        expanded.insert(group.name)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expanded.contains(group.name) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.body.weight(.medium))
                        Text(L("%@ 首 · %@", "\(group.entries.count)", byteText(group.bytes)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                pendingPlaylistClear = group.name
            } label: {
                Image(systemName: "trash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.tertiarySystemFill).opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("清除这个歌单的缓存"))
        }
    }

    @ViewBuilder
    private func cachedRow(_ entry: CacheEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body).lineLimit(1)
                Text(entry.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(byteText(entry.audioBytes))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                cache.remove(entry.key)
            } label: {
                Image(systemName: "trash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("删除缓存"))
        }
        .swipeActions {
            Button(role: .destructive) {
                cache.remove(entry.key)
            } label: {
                Label(L("删除缓存"), systemImage: "trash")
            }
        }
    }

    private func clearPlaylist(_ name: String) {
        let keys = cache.entries.values
            .filter { ($0.playlist.isEmpty ? L("未分类") : $0.playlist) == name }
            .map(\.key)
        for key in keys {
            cache.remove(key)
        }
        expanded.remove(name)
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct CacheSnapshot {
    let done: [CacheEntry]
    let active: [CacheEntry]
    let failed: [CacheEntry]
    let groups: [CacheGroup]
}

private struct CacheGroup: Identifiable {
    let name: String
    let entries: [CacheEntry]
    let bytes: Int64
    var id: String { name }
}

private struct CacheRow: View {
    let entry: CacheEntry
    let progress: CacheProgress?
    let cache: CacheStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body).lineLimit(1)
                Text([entry.artist, entry.playlist].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            ProgressRing(progress: progress?.value ?? 0, size: 24)
        }
    }
}

private struct FailedCacheRow: View {
    let entry: CacheEntry
    let cache: CacheStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body).lineLimit(1)
                Text(entry.error ?? L("缓存失败"))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button(L("重试")) {
                Task { _ = try? await CacheManager.shared.enqueue(track: entry.track, playlist: entry.playlist) }
            }
            .buttonStyle(.bordered)
        }
    }
}
