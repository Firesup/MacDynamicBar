import SwiftUI

/// Expanded playback content. The island owns its surface and event transitions.
struct MusicView: View {
  @ObservedObject var state: IslandState
  @ObservedObject var player: MediaPlayer
  @ObservedObject var audio: MusicAudioLevels
  @ObservedObject var accessories: PlayerAccessories
  @ObservedObject var outputs: AudioOutputs
  @ObservedObject var settings: MinnowSettings
  @Environment(\.islandTextContrast) private var textContrast

  var onArtworkPress: (() -> Void)? = nil

  // MARK: Expanded Player

  var body: some View {
    VStack(spacing: 5) {
      HStack(spacing: 10) {
        if settings.artwork {
          if let onArtworkPress {
            Button(action: onArtworkPress) { cover }.buttonStyle(.plain).accessibilityLabel(
              "Expand album cover")
          } else {
            cover
          }

        }

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(player.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white).lineLimit(1)
            if settings.explicitTag, accessories.isExplicit == true {
              Text("E").font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                  settings.explicitColor ? player.artworkAccent : textContrast.secondary
                )
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
          PlayerActionButton(
            accessories: accessories, settings: settings, songColor: player.artworkAccent)
        } else {
          Color.clear.frame(width: 36, height: 40)
        }
        Spacer(minLength: 0)
        HStack(spacing: 16) {
          playbackButton(
            "backward.fill", label: "Previous track", size: 21,
            action: player.previous)
          playbackButton(
            player.isPlaying ? "pause.fill" : "play.fill",
            label: player.isPlaying ? "Pause" : "Play", size: 26,
            action: player.togglePlayback)
          playbackButton(
            "forward.fill", label: "Next track", size: 21,
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
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity)
  }

  private var cover: some View {
    AnimatedAlbumCover(
      image: player.artwork, size: 40,
      active: settings.animateArtwork && player.isPlaying && state.isExpanded)
  }

  private var artistAndSource: some View {
    HStack(spacing: 5) {
      if let track = player.track, let source = player.captureTarget.source {
        if source == .spotify {
          let artists = accessories.spotifyArtists
          if artists.isEmpty {
            Button {
              MediaNavigation.openArtist(name: track.artist, uri: nil)
            } label: {
              Text(track.artist.isEmpty ? "Unknown Artist" : track.artist).lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(track.artist.isEmpty)
            .help("Search for this artist in Spotify")
          } else {
            ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
              if index > 0 { Text(",").accessibilityHidden(true) }
              Button {
                MediaNavigation.openArtist(name: artist.name, uri: artist.uri)
              } label: {
                Text(artist.name).lineLimit(1)
              }.buttonStyle(.plain).help("Open " + artist.name + " in Spotify")
            }
          }
        } else {
          Text(track.artist.isEmpty ? "Unknown Artist" : track.artist).lineLimit(1)
        }
        Text("·").accessibilityHidden(true)
        Button {
          MediaNavigation.openSource(source)
        } label: {
          Text(source.displayName)
        }
        .buttonStyle(.plain).fixedSize().help("Open " + source.displayName)
      } else {
        Text(player.subtitle).lineLimit(1)
      }
    }
  }

  // MARK: Progress Display

  private var playbackProgress: some View {
    PlaybackScrubber(
      player: player, isExpanded: state.isExpanded,
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
