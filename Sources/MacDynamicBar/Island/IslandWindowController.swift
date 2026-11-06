import AppKit
import Combine
import SwiftUI

// MARK: - Window Controller

@MainActor
final class IslandWindowController {
  private let panel = IslandPanel()
  private let shelf: ShelfStore
  private let today: TodayServices
  private let activities: ActivityStore
  private let capsule = ActivityCapsule()
  private let popups: PopupCoordinator
  var onInteractionChanged: (() -> Void)?
  var isInteractionBusy: Bool { state.isInteractionBusy || shelf.isInteractionBusy }
  private let state: IslandState
  private var configuration: IslandConfiguration
  private let settings: MinnowSettings
  private let displayID: CGDirectDisplayID
  private let player: MediaPlayer
  private let accessories: PlayerAccessories
  private let outputs: AudioOutputs
  private let audio: MusicAudioLevels
  private var layout: IslandLayout?
  private var hostingView: IslandHostingView?
  private var subscriptions = Set<AnyCancellable>()
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var isShown = false
  private var tuning: [Double] = []

  var audioReactiveWavesEnabled: Bool { audio.isEnabled }

  init(
    session: IslandMediaSession, settings: MinnowSettings, popups: PopupCoordinator,
    activities: ActivityStore, today: TodayServices, shelf: ShelfStore,
    displayID: CGDirectDisplayID
  ) {
    self.shelf = shelf
    self.today = today
    self.activities = activities
    self.popups = popups
    self.settings = settings
    self.displayID = displayID
    self.player = session.player
    self.accessories = session.accessories
    self.outputs = session.outputs
    self.audio = session.audio
    self.configuration = settings.configuration
    self.state = IslandState(hoverEnabled: settings.slightHover || settings.expandOnHover)
    self.state.configureHover(
      enabled: settings.slightHover || settings.expandOnHover, opensPlayer: settings.expandOnHover)
    self.state.onToggle = { [weak settings] in
      if settings?.haptics == true {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
      }
    }
    state.$presentation.removeDuplicates().sink { [weak self] presentation in
      self?.resize(presentation: presentation)
    }.store(in: &subscriptions)
    player.$track.map { $0 != nil }.removeDuplicates().sink { [weak self] visible in
      guard let self, var layout = self.layout else { return }
      layout.showsMiniPlayer =
        (visible && self.settings.mediaEnabled)
        || (self.settings.todayEnabled || self.settings.shelfEnabled)
        || (self.settings.showActivities && self.activities.primary != nil)
      self.layout = layout
      self.updateRootView()
      self.resize(presentation: self.state.presentation)
    }.store(in: &subscriptions)
    popups.$active.receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self else { return }
      self.resize(presentation: self.state.presentation)
      self.updatePointer()
    }.store(in: &subscriptions)
    state.$page.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self else { return }
      self.resize(presentation: self.state.presentation)
    }.store(in: &subscriptions)
    state.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
      self?.onInteractionChanged?()
    }.store(in: &subscriptions)
    activities.$entries.receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self else { return }
      if var layout = self.layout {
        layout.showsMiniPlayer =
          (self.player.track != nil && self.settings.mediaEnabled) || self.settings.todayEnabled
          || self.settings.shelfEnabled
          || (self.settings.showActivities && self.activities.primary != nil)
        self.layout = layout
        self.updateRootView()
        self.resize(presentation: self.state.presentation)
      }
      self.updateActivityCapsule()
    }.store(in: &subscriptions)
    player.$isPlaying.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.updateActivityCapsule()
    }.store(in: &subscriptions)
    shelf.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
      self?.onInteractionChanged?()
    }.store(in: &subscriptions)
    installMonitors()
  }

  func refreshMusic() { player.refresh() }
  var isVisible: Bool { isShown }
  func collapse() { state.collapse() }
  func collapseMedia() {
    state.collapseForPausedMedia(
      mediaEnabled: settings.mediaEnabled, todayEnabled: settings.todayEnabled,
      shelfEnabled: settings.shelfEnabled)
  }

  func applySettings(reposition: Bool = false) {
    let nextTuning = [settings.notchWidthOffset, settings.notchHeightOffset]
    let changed = configuration != settings.configuration || tuning != nextTuning
    tuning = nextTuning
    configuration = settings.configuration
    state.configureHover(
      enabled: settings.slightHover || settings.expandOnHover, opensPlayer: settings.expandOnHover)
    hostingView?.applyAppearance(
      layout: settings.appearanceLayout, glass: settings.glass,
      blur: settings.backgroundBlur, opacity: settings.opacity,
      headerHeight: layout?.headerHeight ?? 28, shape: settings.islandShape,
      gradientVisibility: settings.gradientVisibility)
    if isShown && (changed || reposition) {
      show()
    } else {
      resize(presentation: state.presentation)
    }
    updateActivityCapsule()
  }

  func toggleAudioReactiveWaves() {
    // Toggling off/on also retries capture after changing system access.
    audio.setEnabled(!audio.isEnabled)
  }

  func show() {
    guard let screen = preferredScreen else {
      hide()
      return
    }
    let hasNotch = screen.safeAreaInsets.top > 0
    let notchWidth: CGFloat
    let notchCenterX: CGFloat
    if hasNotch, let left = screen.auxiliaryTopLeftArea,
      let right = screen.auxiliaryTopRightArea
    {
      notchWidth = max(1, right.minX - left.maxX)
      notchCenterX = (left.maxX + right.minX) / 2
    } else {
      notchWidth = 160
      notchCenterX = screen.frame.midX
    }
    let layout = IslandLayout(
      screenFrame: screen.frame, notchWidth: max(80, notchWidth + settings.notchWidthOffset),
      notchHeight: max(
        20, (hasNotch ? screen.safeAreaInsets.top : 28) + settings.notchHeightOffset),
      showsMiniPlayer: (player.track != nil && settings.mediaEnabled) || settings.todayEnabled
        || settings.shelfEnabled
        || (settings.showActivities && activities.primary != nil), notchCenterX: notchCenterX,
      configuration: configuration)
    self.layout = layout
    hostingView?.stopAnimating()
    let root = IslandView(
      state: state, player: player, audio: audio,
      accessories: accessories, outputs: outputs, popups: popups, activities: activities,
      settings: settings, today: today, shelf: shelf, layout: layout
    )
    let host: IslandHostingView
    if let existing = hostingView {
      host = existing
      host.host.rootView = root
    } else {
      host = IslandHostingView(rootView: root)
      hostingView = host
      host.regionChanged = { [weak self] in self?.updatePointer() }
      panel.contentView = host
    }
    host.applyAppearance(
      layout: settings.appearanceLayout, glass: settings.glass,
      blur: settings.backgroundBlur, opacity: settings.opacity,
      headerHeight: layout.headerHeight, shape: settings.islandShape,
      gradientVisibility: settings.gradientVisibility)
    // The transparent canvas stays fixed throughout all interactions.
    var largest = layout
    largest.configuration.expandedContentHeight = max(
      settings.contentHeight(for: .music), settings.contentHeight(for: .today),
      settings.contentHeight(for: .shelf))
    let expanded = largest.size(for: .expanded)
    let hover = layout.size(for: .hover)
    let canvasSize = CGSize(
      width: max(expanded.width, hover.width),
      height: max(expanded.height, hover.height))
    let originX = min(
      max(notchCenterX - canvasSize.width / 2, screen.frame.minX),
      screen.frame.maxX - canvasSize.width)
    panel.setFrame(
      CGRect(
        x: originX, y: screen.frame.maxY - canvasSize.height,
        width: canvasSize.width, height: canvasSize.height),
      display: true)
    host.frame = CGRect(origin: .zero, size: canvasSize)
    panel.acceptsMouseMovedEvents = true
    panel.ignoresMouseEvents = true
    isShown = true
    host.move(
      to: surfaceSize(layout: layout, presentation: state.presentation),
      expanded: state.isExpanded || popups.active != nil, animated: false)
    panel.orderFrontRegardless()
    updateActivityCapsule()
    updatePointer()
  }

  func toggle() {
    if !isShown { show() }
    state.toggle()
    panel.orderFrontRegardless()
  }

  func hide() {
    capsule.hide()
    isShown = false
    state.collapse()
    hostingView?.stopAnimating()
    panel.ignoresMouseEvents = true
    panel.orderOut(nil)
  }

  func stop() {
    hide()
    subscriptions.removeAll()
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    localMonitor = nil
    globalMonitor = nil
    capsule.stop()
    panel.close()
  }

  private var preferredScreen: NSScreen? {
    NSScreen.screens.first { MinnowDisplay.from($0)?.nativeID == displayID }
  }

  private func updateRootView() {
    guard let layout else { return }
    hostingView?.host.rootView = IslandView(
      state: state, player: player, audio: audio,
      accessories: accessories, outputs: outputs, popups: popups, activities: activities,
      settings: settings, today: today, shelf: shelf, layout: layout
    )
  }

  private func surfaceSize(layout: IslandLayout, presentation: IslandPresentation) -> CGSize {
    guard popups.active != nil else {
      var pageLayout = layout
      pageLayout.configuration.expandedContentHeight = settings.contentHeight(
        for: state.effectivePage(
          mediaEnabled: settings.mediaEnabled, todayEnabled: settings.todayEnabled,
          shelfEnabled: settings.shelfEnabled))
      return pageLayout.size(for: presentation)
    }
    var size = layout.size(for: .expanded)
    size.height = min(size.height, layout.headerHeight + 88)
    return size
  }

  private func updateActivityCapsule() {
    guard isShown, settings.showActivities, settings.mediaEnabled, player.isPlaying,
      popups.active == nil,
      let activity = activities.primary, let layout, let screen = preferredScreen
    else {
      capsule.hide()
      return
    }
    capsule.show(activity, beside: layout.frame(for: state.presentation), screen: screen.frame)
  }

  private func resize(presentation: IslandPresentation) {
    guard let layout else { return }
    updateActivityCapsule()
    hostingView?.move(
      to: surfaceSize(layout: layout, presentation: presentation),
      expanded: presentation == .expanded || popups.active != nil,
      animated: isShown
        && !NSWorkspace.shared
          .accessibilityDisplayShouldReduceMotion
    )
  }

  private func updatePointer() {
    let inside =
      isShown
      && (hostingView?.containsScreenPoint(
        NSEvent.mouseLocation) ?? false)
    // Transparent canvas space must pass clicks to the application below.
    panel.ignoresMouseEvents = !inside
    if popups.active == nil { state.setHovered(inside) }
  }

  private func handleEvent(isClick: Bool, fromOtherApplication: Bool = false) {
    if capsule.containsMouse { return }
    updatePointer()
    if popups.active != nil {
      if isClick, hostingView?.containsScreenPoint(NSEvent.mouseLocation) != true {
        popups.dismiss()
      }
      return
    }
    if state.isOutputPickerOpen {
      // The transient popover handles local outside clicks. Global mouse
      // monitoring also dismisses it when a nonactivating panel loses the click.
      if isClick && fromOtherApplication { state.collapse() }
      return
    }
    if isClick, state.isExpanded,
      hostingView?.containsScreenPoint(NSEvent.mouseLocation) != true
    {
      state.collapse()
    }
  }

  private func installMonitors() {
    let mask: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
      .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      let click = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
      MainActor.assumeIsolated { self?.handleEvent(isClick: click) }
      return event
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      let click = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
      Task { @MainActor [weak self] in self?.handleEvent(isClick: click, fromOtherApplication: true)
      }
    }
  }
}
