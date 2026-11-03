import AppKit
import CoreMedia
import CoreAudio
import CryptoKit
import Network
import Security
import ServiceManagement
import ScreenCaptureKit
import Combine
import QuartzCore
import SwiftUI

// MARK: - Island Interface

// MARK: - Album Cover

struct AlbumCover: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(.white.opacity(0.1))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: size * 0.2)
        )
        .accessibilityLabel("Album artwork")
    }
}

// MARK: - Island Interface

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var player: MediaPlayer
    @ObservedObject var audio: MusicAudioLevels
    @ObservedObject var accessories: PlayerAccessories
    @ObservedObject var outputs: AudioOutputs
    @ObservedObject var settings: MinnowSettings

    let layout: IslandLayout

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.colorSchemeContrast) private var systemContrast
    private var textContrast: IslandTextContrast {
        IslandTextContrast.resolve(
            translucent: settings.appearanceLayout != .standard
                || (settings.appearanceLayout == .standard && (settings.glass || settings.backgroundBlur)),
            tint: settings.appearanceLayout == .softGradient ? 1 - settings.gradientVisibility : settings.opacity,
            increased: systemContrast == .increased)
    }

    var body: some View {
        VStack(spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            // Overlay keeps the expanded content's fixed width from forcing
            // the compact header wider than the actual visible surface.
            expandedPlayer
                .frame(width: layout.size(for: .expanded).width,
                       height: layout.configuration.expandedContentHeight)
                .padding(.top, layout.headerHeight)
                .opacity(state.isExpanded ? 1 : 0)
                .allowsHitTesting(state.isExpanded)
                .accessibilityHidden(!state.isExpanded)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                           value: state.isExpanded)
        }
        .environment(\.islandTextContrast, textContrast)
        .preferredColorScheme(.dark)
        .onChange(of: state.isExpanded) { _, expanded in
            if expanded { accessories.refresh() }
        }
    }

    // MARK: Compact Player / Header

    private var header: some View {
        Button(action: state.toggle) {
            HStack(spacing: 0) {
                // Left section.
                if !state.isExpanded, player.track != nil, settings.artwork {
                    AlbumCover(
                        image: player.artwork,
                        size: min(20, layout.notchHeight - 6)
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                }

                // Reserve the camera housing area.
                Color.clear
                    .frame(width: layout.notchWidth)

                // Right section.
                Group {
                    if !state.isExpanded, player.track != nil {
                        PlaybackIndicator(
                            isPlaying: player.isPlaying, audio: audio
                        )
                    } else if state.isExpanded {
                        Image(systemName: "chevron.up")
                            .font(
                                .system(size: 11, weight: .semibold)
                            )
                            .foregroundStyle(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            state.isExpanded ? "Collapse Minnow" : "Expand Minnow"
        )
        .help(
            player.track == nil
                ? "Expand Minnow"
                : "\(player.title) — \(player.subtitle)"
        )
    }

    private var headerHeight: CGFloat {
        state.presentation == .hover
            ? layout.size(for: .hover).height
            : layout.headerHeight
    }

    // MARK: Expanded Player

    private var expandedPlayer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if settings.artwork {
                    AnimatedAlbumCover(image: player.artwork, size: 46,
                                       active: settings.animateArtwork && player.isPlaying && state.isExpanded)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(player.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white).lineLimit(1)
                        if settings.explicitTag, accessories.isExplicit == true {
                            Text("E").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(settings.explicitColor ? player.artworkAccent : textContrast.secondary)
                                .padding(3).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel("Explicit")
                        }
                    }

                    artistAndSource
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textContrast.secondary)
                        .lineLimit(1)

                    if let error = accessories.error {
                        Text(error).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange).lineLimit(1).help(error)
                    } else if player.isPlaying && !audio.hasAudioSignal {
                        Text(audio.status)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(textContrast.secondary)
                            .lineLimit(1)
                            .help(audio.status)
                    }
                }
                .shadow(color: .black.opacity(textContrast.shadowOpacity), radius: 1.5, y: 1)

                Spacer(minLength: 8)

                PlaybackIndicator(
                    isPlaying: player.isPlaying, audio: audio
                )
            }

            playbackProgress

            HStack(spacing: 8) {
                if settings.showLeftButton {
                    PlayerActionButton(accessories: accessories, settings: settings, songColor: player.artworkAccent)
                } else { Color.clear.frame(width: 36, height: 40) }
                Spacer(minLength: 0)
                HStack(spacing: 16) {
                    playbackButton("backward.fill", label: "Previous track", size: 21,
                                   action: player.previous)
                    playbackButton(player.isPlaying ? "pause.fill" : "play.fill",
                                   label: player.isPlaying ? "Pause" : "Play", size: 26,
                                   action: player.togglePlayback)
                    playbackButton("forward.fill", label: "Next track", size: 21,
                                   action: player.next)
                }
                .disabled(!player.canControlPlayback)
                .opacity(player.canControlPlayback ? 1 : 0.35)
                Spacer(minLength: 0)
                OutputPickerButton(outputs: outputs, isPresented: $state.isOutputPickerOpen)
                    .frame(width: 36, height: 40)

            }
        }
        .padding(.horizontal, settings.islandShape == .notch ? 30 : 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var artistAndSource: some View {
        HStack(spacing: 5) {
            if let track = player.track, let source = player.captureTarget.source {
                if source == .spotify {
                    let artists = accessories.spotifyArtists
                    if artists.isEmpty {
                        Button {
                            MediaNavigation.openArtist(name: track.artist, uri: nil)
                        } label: { Text(track.artist.isEmpty ? "Unknown Artist" : track.artist).lineLimit(1) }
                        .buttonStyle(.plain)
                        .disabled(track.artist.isEmpty)
                        .help("Search for this artist in Spotify")
                    } else {
                        ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                            if index > 0 { Text(",").accessibilityHidden(true) }
                            Button { MediaNavigation.openArtist(name: artist.name, uri: artist.uri) } label: {
                                Text(artist.name).lineLimit(1)
                            }.buttonStyle(.plain).help("Open " + artist.name + " in Spotify")
                        }
                    }
                } else { Text(track.artist.isEmpty ? "Unknown Artist" : track.artist).lineLimit(1) }
                Text("·").accessibilityHidden(true)
                Button { MediaNavigation.openSource(source) } label: { Text(source.displayName) }
                    .buttonStyle(.plain).fixedSize().help("Open " + source.displayName)
            } else { Text(player.subtitle).lineLimit(1) }
        }
    }

    // MARK: Progress Display

    private var playbackProgress: some View {
        PlaybackScrubber(player: player, isExpanded: state.isExpanded,
                         onEditingChange: { editing in
                             state.setScrubbing(editing)
                             if !editing, settings.collapseAfterScrub { state.collapse() }
                         })
    }

    // MARK: Helpers

    private func playbackButton(
        _ symbol: String,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .font(
                    .system(size: size, weight: .semibold)
                )
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func progress(at position: TimeInterval) -> CGFloat {
        guard player.duration > 0 else { return 0 }

        return CGFloat(
            min(1, max(0, position / player.duration))
        )
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let value = Int(
            max(0, seconds.isFinite ? seconds : 0)
        )

        return "\(value / 60):"
            + String(format: "%02d", value % 60)
    }
}

