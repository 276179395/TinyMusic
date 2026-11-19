import SwiftUI

struct NowPlayingView: View {
    let model: AppModel
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var lyrics = LyricsStore()
    @State private var showLyrics = false
    @State private var showEQ = false
    @State private var paletteColor: Color?

    private var player: PlayerEngine { model.player }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                VStack(spacing: 18) {
                    if showLyrics {
                        InlineLyricsView(store: lyrics, player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 10)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        Spacer(minLength: 8)

                        CoverImage(url: currentCoverURL, cornerRadius: 22)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 330)
                            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                            .padding(.horizontal, 36)
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showLyrics = true
                                }
                            }
                            .accessibilityElement()
                            .accessibilityLabel(L("歌词"))
                            .accessibilityAddTraits(.isButton)

                        titleBlock
                            .padding(.top, 2)
                            .transition(.opacity)

                        Spacer(minLength: 8)
                    }

                    HStack(spacing: 12) {
                        if showLyrics {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showLyrics = false
                                }
                            } label: {
                                CoverImage(url: currentCoverURL, cornerRadius: 10)
                                    .frame(width: 36, height: 36)
                                    .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("返回封面"))
                        }

                        VStack(spacing: 8) {
                            SeekBar(
                                value: player.duration > 0 ? min(player.position, player.duration) : 0,
                                total: max(1, player.duration)
                            ) { target in
                                player.seek(to: target)
                            }
                            HStack {
                                Text(timeText(player.position))
                                Spacer()
                                Text(timeText(player.duration))
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 280)
                        }
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 30) {
                        Button {
                            player.shuffle.toggle()
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(player.shuffle ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("随机播放"))

                        Button { player.previous() } label: {
                            Image(systemName: "backward.fill").font(.system(size: 26))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("上一首"))

                        Button {
                            player.toggle()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 34, weight: .bold))
                                .frame(width: 68, height: 68)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .tmGlassCircle()
                        .accessibilityLabel(player.isPlaying ? L("暂停") : L("播放"))

                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.system(size: 26))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("下一首"))

                        Button {
                            cycleRepeat()
                        } label: {
                            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("循环模式"))
                    }
                    .padding(.bottom, 8)

                    if let error = player.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 30)
                .animation(.easeInOut(duration: 0.3), value: showLyrics)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .background {
                WindowSwipeBack(action: goBack)
                    .frame(width: 0, height: 0)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: showLyrics ? "chevron.left" : "chevron.down")
                    }
                    .accessibilityLabel(showLyrics ? L("返回封面") : L("关闭播放器"))
                }
            }
            .navigationTitle(showLyrics ? (player.current?.title ?? L("歌词")) : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEQ) {
                EqualizerView(eq: player.eq)
            }
            .task(id: player.current?.key) {
                if let track = player.current {
                    await lyrics.load(for: track)
                }
                if let color = await ArtworkPalette.baseColor(for: currentCoverURL) {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        paletteColor = color
                    }
                }
                if AppConfiguration.screen == "eq" { showEQ = true }
                if AppConfiguration.screen == "lyrics" { showLyrics = true }
            }
            .onChange(of: player.position) { _, position in
                lyrics.update(position: position)
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(player.current?.title ?? L("未在播放"))
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(player.current?.artist ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
    }

    private var currentCoverURL: String? {
        guard let current = player.current else { return nil }
        return model.cache.coverURL(for: current.key)?.absoluteString ?? current.cover
    }

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            if let paletteColor {
                LinearGradient(
                    colors: [
                        paletteColor.opacity(colorScheme == .dark ? 0.68 : 0.52),
                        paletteColor.opacity(0.16),
                        Color(.systemBackground).opacity(0.96),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            if let cover = currentCoverURL, let url = URL(string: cover) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .blur(radius: 55)
                .opacity(0.38)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.05), Color(.systemBackground).opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func goBack() {
        if showLyrics {
            withAnimation(.easeInOut(duration: 0.3)) {
                showLyrics = false
            }
        } else {
            close()
        }
    }

    private func close() {
        onClose?()
        dismiss()
    }

    private func cycleRepeat() {
        switch player.repeatMode {
        case .off: player.repeatMode = .all
        case .all: player.repeatMode = .one
        case .one: player.repeatMode = .off
        }
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
