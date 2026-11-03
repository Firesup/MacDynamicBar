import SwiftUI

// MARK: - Island Interface

// MARK: - Island Interface

struct IslandView: View {
  @ObservedObject var state: IslandState
  @ObservedObject var player: MediaPlayer
  @ObservedObject var audio: MusicAudioLevels
  @ObservedObject var accessories: PlayerAccessories
  @ObservedObject var outputs: AudioOutputs
  @ObservedObject var popups: PopupCoordinator
  @ObservedObject var activities: ActivityStore
  @ObservedObject var settings: MinnowSettings

  let layout: IslandLayout

  @Environment(\.accessibilityReduceMotion)
  private var reduceMotion

  @Environment(\.colorSchemeContrast) private var systemContrast
  private var textContrast: IslandTextContrast {
    IslandTextContrast.resolve(
      translucent: settings.appearanceLayout != .standard
        || (settings.appearanceLayout == .standard && (settings.glass || settings.backgroundBlur)),
      tint: settings.appearanceLayout == .softGradient
        ? 1 - settings.gradientVisibility : settings.opacity,
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
      Group {
        if let popup = popups.active {
          IslandPopupView(popup: popup, dismiss: popups.dismiss)
            .frame(
              width: layout.size(for: .expanded).width,
              height: min(88, layout.configuration.expandedContentHeight))
        } else if settings.showActivities, !player.isPlaying || !settings.mediaEnabled,
          let activity = activities.primary
        {
          ActivityDetailView(activity: activity)
            .frame(
              width: layout.size(for: .expanded).width,
              height: layout.configuration.expandedContentHeight
            )
            .opacity(state.isExpanded ? 1 : 0).allowsHitTesting(state.isExpanded)
            .accessibilityHidden(!state.isExpanded)
        } else {
          MusicView(
            state: state, player: player, audio: audio, accessories: accessories,
            outputs: outputs, settings: settings
          )
          .frame(
            width: layout.size(for: .expanded).width,
            height: layout.configuration.expandedContentHeight
          )
          .opacity(state.isExpanded ? 1 : 0)
          .allowsHitTesting(state.isExpanded)
          .accessibilityHidden(!state.isExpanded)
        }
      }
      .padding(.top, layout.headerHeight)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: state.isExpanded)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: popups.active?.id)
    }
    .environment(\.islandTextContrast, textContrast)
    .preferredColorScheme(.dark)
    .onChange(of: state.isExpanded) { _, expanded in
      if expanded { accessories.refresh() }
    }
  }

  // MARK: Compact Player / Header

  private var header: some View {
    Button(action: { if popups.active != nil { popups.dismiss() } else { state.toggle() } }) {
      HStack(spacing: 0) {
        // Left section.
        if popups.active == nil, !state.isExpanded, settings.showActivities,
          !player.isPlaying || !settings.mediaEnabled, let activity = activities.primary
        {
          Image(systemName: activity.symbol).font(.system(size: 13)).foregroundStyle(.green).frame(
            maxWidth: .infinity)
        } else if popups.active == nil, !state.isExpanded, player.track != nil, settings.artwork {
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
          if popups.active == nil, !state.isExpanded, player.track != nil, player.isPlaying,
            settings.mediaEnabled
          {
            PlaybackIndicator(
              isPlaying: player.isPlaying, audio: audio
            )
          } else if settings.showActivities, !player.isPlaying || !settings.mediaEnabled,
            let activity = activities.primary
          {
            Text(activity.compact).font(.system(size: 10, weight: .semibold)).monospacedDigit()
              .lineLimit(1).foregroundStyle(.white)
          } else if state.isExpanded || popups.active != nil {
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
      popups.active != nil
        ? "Dismiss popup" : (state.isExpanded ? "Collapse Minnow" : "Expand Minnow")
    )
    .help(
      player.track == nil
        ? "Expand Minnow"
        : "\(player.title) — \(player.subtitle)"
    )
  }

  private var headerHeight: CGFloat {
    popups.active == nil && state.presentation == .hover
      ? layout.size(for: .hover).height
      : layout.headerHeight
  }

}
