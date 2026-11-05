import AppKit
import Combine
import SwiftUI
import os

struct LockScreenGeometry {
  static func playerFrame(screen: CGRect) -> CGRect {
    let width = max(0, min(860, screen.width - 40))
    let bottom = min(170, max(0, screen.height * 0.19))
    let height = max(0, min(620, screen.height * 0.68, screen.height - bottom - 20))
    return CGRect(x: screen.midX - width / 2, y: screen.minY + bottom,
                  width: width, height: height)
  }

  static func cardFrame(size: CGSize) -> CGRect {
    let width = max(0, min(408, size.width))
    return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: 164 * width / 408)
  }

  static func artworkFrame(size: CGSize, lyrics: Bool) -> CGRect {
    let card = cardFrame(size: size)
    let art = max(0, min(360, size.height - card.height - 20,
                         lyrics ? (size.width - 30) / 2 : size.width))
    let width = lyrics ? art * 2 + 30 : art
    return CGRect(x: (size.width - width) / 2, y: card.height + 20, width: art, height: art)
  }

  static func accepts(_ point: CGPoint, size: CGSize, expanded: Bool, lyrics: Bool) -> Bool {
    if cardFrame(size: size).contains(point) { return true }
    guard expanded else { return false }
    let art = artworkFrame(size: size, lyrics: lyrics)
    if art.contains(point) { return true }
    return lyrics && art.offsetBy(dx: art.width + 30, dy: 0).contains(point)
  }
}

private final class LockMediaPanel: NSPanel {
  var artworkExpanded = false
  var lyricsVisible = false
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Owns only the overlay. macOS continues to own authentication and its clock.
@MainActor final class LockScreenController: ObservableObject {
  @Published private(set) var status = "Lockscreen monitoring is stopped"
  var onPresentationChanged: (() -> Void)?
  private let logger = Logger(subsystem: "com.minnow.MacDynamicBar", category: "LockScreen")
  private let session: IslandMediaSession
  private let widgets: WidgetServices
  private let readings: MusicSceneWidgets
  private var widgetPanel: LockMediaPanel?
  private let settings: MinnowSettings
  private var panels: [LockMediaPanel] = []
  private var screenObserver: NSObjectProtocol?
  private var tokens: [NSObjectProtocol] = []
  private var watchdog: Task<Void, Never>?
  private var subscriptions = Set<AnyCancellable>()
  private var monitors: [Any] = []
  private var displayFrames: [CGRect] = []
  private var lifecycle = LockScreenLifecycle()
  private var sessionCheck: Task<Void, Never>?
  private var wasPresenting = false
  private var metadataSessionLocked = false
  var isPresentingPlayer: Bool { lifecycle.canPresent && settings.lockScreenPlayer && !panels.isEmpty }
  let lyricsStore = LyricsStore()

  init(
    session: IslandMediaSession, settings: MinnowSettings, widgets: WidgetServices,
    readings: MusicSceneWidgets
  ) {
    self.widgets = widgets
    self.readings = readings
    self.session = session
    self.settings = settings
  }
  func start() {
    guard tokens.isEmpty else { return }
    for (name, value) in [
      ("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false),
    ] {
      tokens.append(
        DistributedNotificationCenter.default().addObserver(
          forName: .init(name), object: nil, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.setLocked(value) }
        })
    }
    settings.objectWillChange.debounce(for: .milliseconds(50), scheduler: RunLoop.main).sink { [weak self] in self?.refresh() }
      .store(in: &subscriptions)
    session.player.$duration.receive(on: RunLoop.main).sink { [weak self] duration in
      guard let self, self.settings.onlineLyrics else { return }
      self.lyricsStore.fetch(for: self.session.player.track, duration: duration)
    }.store(in: &subscriptions)
    session.player.$track.receive(on: RunLoop.main).sink { [weak self] track in
      guard let self else { return }
      if self.settings.onlineLyrics {
        self.lyricsStore.fetch(for: track, duration: self.session.player.duration)
      } else {
        self.lyricsStore.trackChanged(track)
      }
      self.refresh()
    }.store(in: &subscriptions)
    let mask: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseDown, .leftMouseDragged, .scrollWheel,
    ]
    if let monitor = NSEvent.addGlobalMonitorForEvents(
      matching: mask,
      handler: { [weak self] _ in MainActor.assumeIsolated { self?.updateHitRegions() } })
    {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: mask,
      handler: { [weak self] event in
        MainActor.assumeIsolated { self?.updateHitRegions() }
        return event
      })
    {
      monitors.append(monitor)
    }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.hide()
        self?.refresh()
      }
    }
    resume()
  }
  private var selectedScreens: [NSScreen] {
    if settings.allDisplays { return NSScreen.screens }
    if settings.display != "automatic", settings.display != "main",
      let screen = NSScreen.screens.first(where: { MinnowDisplay.from($0)?.id == settings.display })
    {
      return [screen]
    }
    if settings.display == "main",
      let screen = NSScreen.screens.first(where: {
        MinnowDisplay.from($0)?.nativeID == CGMainDisplayID()
      })
    {
      return [screen]
    }
    let screen =
      NSScreen.screens.first(where: { screen in
        guard let id = MinnowDisplay.from(screen)?.nativeID else { return false }
        return CGDisplayIsBuiltin(id) != 0
      }) ?? NSScreen.screens.first
    return screen.map { [$0] } ?? []
  }
  private static func sessionSnapshot() -> (locked: Bool?, onConsole: Bool?) {
    let values = CGSessionCopyCurrentDictionary() as? [String: Any]
    return (values?["CGSSessionScreenIsLocked"] as? Bool,
      values?[kCGSessionOnConsoleKey as String] as? Bool)
  }
  private func setLocked(_ value: Bool) {
    logger.info("Lock notification: \(value)")
    sessionCheck?.cancel()
    lifecycle.lockChanged(value)
    if !value { hide() }
    refresh()
    updateWatchdog()
  }

  private func updateWatchdog() {
    watchdog?.cancel()
    watchdog = nil
    guard lifecycle.locked, lifecycle.awake else { return }
    watchdog = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard let self else { return }
        let snapshot = Self.sessionSnapshot()
        self.lifecycle.reconcile(observedLock: snapshot.locked, onConsole: snapshot.onConsole)
        if !self.lifecycle.canPresent {
          self.refresh()
          return
        }
        self.updateHitRegions()
        // Reorder after loginwindow has completed its transition; do not rebuild the shared session.
        self.refresh()
      }
    }
  }

  private func publishPresentation() {
    let showing = isPresentingPlayer
    status = "Locked: \(lifecycle.locked) · Awake: \(lifecycle.awake) · Console: \(lifecycle.onConsole) · Player panels: \(panels.count)"
    if showing != wasPresenting {
      wasPresenting = showing
      logger.info("Player overlay visible: \(showing, privacy: .public)")
      onPresentationChanged?()
    }
  }

  func refresh() {
    let justUnlocked = metadataSessionLocked && !lifecycle.locked
    metadataSessionLocked = lifecycle.locked
    session.player.setSessionLocked(lifecycle.locked)
    if justUnlocked { session.player.refresh() }
    guard lifecycle.canPresent, settings.lockScreenPlayer else {
      hide()
      return
    }
    let frames = selectedScreens.map { $0.frame }
    if frames != displayFrames {
      hide()
      displayFrames = frames
    }
    if settings.onlineLyrics {
      lyricsStore.fetch(for: session.player.track, duration: session.player.duration)
    } else {
      lyricsStore.cancelOnline()
    }
    if session.player.track == nil {
      panels.forEach {
        $0.orderOut(nil)
        $0.level = .normal
        $0.close()
      }
      panels.removeAll()
    }
    if panels.isEmpty, session.player.track != nil {
      for screen in selectedScreens {
        let panel = LockMediaPanel(
          contentRect: LockScreenGeometry.playerFrame(screen: screen.frame),
          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = .init(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [
          .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
          rootView: LockScreenPlayerView(
            session: session, settings: settings, lyrics: lyricsStore,
            expansionChanged: { [weak self, weak panel] expanded, lyrics in
              panel?.artworkExpanded = expanded
              panel?.lyricsVisible = lyrics
              self?.updateWidgetVisibility()
              self?.updateHitRegions()
            }))
        panels.append(panel)
      }
    }
    if widgetPanel == nil, let screen = selectedScreens.first {
      let width = max(0, min(760, screen.frame.width - 40))
      let strip = LockMediaPanel(
        contentRect: CGRect(
          x: screen.frame.midX - width / 2, y: screen.frame.maxY - min(300, screen.frame.height / 3),
          width: width, height: 36),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      strip.isReleasedWhenClosed = false
      strip.hidesOnDeactivate = false
      strip.canBecomeVisibleWithoutLogin = true
      strip.level = .init(rawValue: Int(CGShieldingWindowLevel()))
      strip.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
      strip.backgroundColor = .clear
      strip.isOpaque = false
      strip.hasShadow = false
      strip.ignoresMouseEvents = true
      strip.contentView = NSHostingView(
        rootView: LockWidgetStrip(widgets: widgets, readings: readings, settings: settings))
      widgetPanel = strip
    }
    updateWidgetVisibility()
    updateHitRegions()
    panels.forEach { $0.orderFrontRegardless() }
    publishPresentation()
  }
  private func updateWidgetVisibility() {
    if panels.contains(where: { $0.artworkExpanded }) {
      widgetPanel?.orderOut(nil)
    } else {
      widgetPanel?.orderFrontRegardless()
    }
  }
  private func updateHitRegions() {
    for panel in panels {
      let mouse = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
      panel.ignoresMouseEvents = !LockScreenGeometry.accepts(
        mouse, size: panel.frame.size, expanded: panel.artworkExpanded, lyrics: panel.lyricsVisible)
    }
  }
  private func hide() {
    widgetPanel?.orderOut(nil)
    widgetPanel?.level = .normal
    widgetPanel?.close()
    widgetPanel = nil
    for panel in panels {
      panel.orderOut(nil)
      panel.level = .normal
      panel.close()
    }
    panels.removeAll()
    publishPresentation()
  }
  func resume() {
    let snapshot = Self.sessionSnapshot()
    lifecycle.wake(observedLock: snapshot.locked, onConsole: snapshot.onConsole)
    logger.info("Wake/resume; locked: \(self.lifecycle.locked)")
    refresh()
    updateWatchdog()
  }
  func suspend() {
    lifecycle.sleep()
    logger.info("System sleeping; hiding panels")
    watchdog?.cancel()
    sessionCheck?.cancel()
    refresh()
  }
  func sessionActivityChanged(_ active: Bool) {
    logger.info("Workspace session active: \(active)")
    sessionCheck?.cancel()
    if active {
      lifecycle.sessionBecameActive()
      watchdog?.cancel()
      refresh()
    } else {
      // Lock and session notifications can arrive in either order. Let the lock state settle.
      sessionCheck = Task { @MainActor [weak self] in
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        guard let self else { return }
        let snapshot = Self.sessionSnapshot()
        self.lifecycle.reconcile(observedLock: snapshot.locked, onConsole: snapshot.onConsole)
        self.refresh()
        self.updateWatchdog()
      }
    }
  }
  func stop() {
    lifecycle = LockScreenLifecycle()
    sessionCheck?.cancel()
    sessionCheck = nil
    displayFrames = []
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    hide()
    watchdog?.cancel()
    watchdog = nil
    tokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    tokens.removeAll()
    monitors.forEach { NSEvent.removeMonitor($0) }
    monitors.removeAll()
    subscriptions.removeAll()
    lyricsStore.clear()
  }
}


struct LockScreenStatusView: View {
  @ObservedObject var controller: LockScreenController
  var body: some View {
    Text(controller.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
  }
}
