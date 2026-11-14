import SwiftUI

/// The first hardware milestone has one control, and no artwork expansion or seeking.
struct LockScreenPlayerView: View {
  @ObservedObject var player: MediaPlayer
  let useGlass: Bool
  let togglePlayback: () -> Void
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 13) {
        Group {
          if let artwork = player.artwork {
            Image(nsImage: artwork).resizable().scaledToFill()
          } else {
            Image(systemName: "music.note").font(.system(size: 24, weight: .medium))
              .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.12))
          }
        }.frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 11))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(player.track?.title ?? player.title)
            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
          Text(player.track?.artist ?? "")
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      TimelineView(.periodic(from: .now, by: 0.5)) { context in
        let progress = LockScreenGeometry.progress(
          position: player.playbackPosition(at: context.date), duration: player.duration)
        GeometryReader { geometry in
          Capsule().fill(.white.opacity(0.2))
            .overlay(alignment: .leading) {
              Capsule().fill(.white.opacity(0.9)).frame(width: geometry.size.width * progress)
            }
        }.frame(height: 3).padding(.top, 3)
          .accessibilityLabel("Playback progress")
          .accessibilityValue(player.duration > 0 ? "\(Int(progress * 100)) percent" : "Unavailable")
      }
      Button(action: togglePlayback) {
        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 23, weight: .semibold)).frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(!player.canControlPlayback)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }.padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .foregroundStyle(.white)
      .background {
        // Always retain a readable backing even if WindowServer does not composite glass.
        RoundedRectangle(cornerRadius: 24).fill(Color(white: 0.12).opacity(0.92))
        if useGlass && !reduceTransparency {
          if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
          } else {
            RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
          }
        } else if !reduceTransparency {
          RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 24))
      .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.22), lineWidth: 0.7))
      .preferredColorScheme(.dark)
  }
}
