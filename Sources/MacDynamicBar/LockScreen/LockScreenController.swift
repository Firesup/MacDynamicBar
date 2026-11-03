import AppKit
import Combine
import SwiftUI

struct LockScreenGeometry {
  static func playerFrame(screen: CGRect) -> CGRect {
    let width = min(860, screen.width - 40)
    let height = min(620, screen.height * 0.68)
    return CGRect(
      x: screen.midX - width / 2, y: screen.minY + max(170, screen.height * 0.19), width: width,
      height: height)
  }
  static func accepts(_ point: CGPoint, size: CGSize, expanded: Bool, lyrics: Bool) -> Bool {
    // AppKit coordinates; only the glass card and explicit artwork/lyrics controls accept clicks.
    let card = CGRect(x: (size.width - 408) / 2, y: 0, width: 408, height: 164)
    if card.contains(point) { return true }
    if expanded {
      let art: CGFloat = min(360, size.height - 190)
      let x = lyrics ? max(0, size.width / 2 - art - 15) : (size.width - art) / 2
      return CGRect(x: x, y: 184, width: art, height: art).contains(point)
    }
    return false
  }
}

private final class LockMediaPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Owns only the overlay. macOS continues to own authentication and its clock.
@MainActor final class LockScreenController {
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
  private var expanded = false
  private var lyrics = false
  private var locked = false
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
    settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }
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
    setLocked(Self.sessionLocked())
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
  private static func sessionLocked() -> Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool
      ?? false
  }
  private func setLocked(_ value: Bool) {
    locked = value
    if !value {
      expanded = false
      lyrics = false
      hide()
    }
    refresh()
    watchdog?.cancel()
    if value {
      watchdog = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
          guard let self else { return }
          // Independent unlock check handles missed distributed notifications.
          self.updateHitRegions()
          if !Self.sessionLocked() {
            self.setLocked(false)
            return
          }
        }
      }
    }
  }
  func refresh() {
    guard locked, settings.lockScreenPlayer else {
      hide()
      return
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
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
          rootView: LockScreenPlayerView(
            session: session, settings: settings, lyrics: lyricsStore,
            expansionChanged: { [weak self] expanded, lyrics in
              self?.expanded = expanded
              self?.lyrics = lyrics
              if expanded {
                self?.widgetPanel?.orderOut(nil)
              } else {
                self?.widgetPanel?.orderFrontRegardless()
              }
              self?.updateHitRegions()
            }))
        panels.append(panel)
      }
    }
    if widgetPanel == nil, let screen = selectedScreens.first {
      let strip = LockMediaPanel(
        contentRect: CGRect(
          x: screen.frame.midX - 380, y: screen.frame.maxY - 300, width: 760, height: 36),
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
    if expanded { widgetPanel?.orderOut(nil) } else { widgetPanel?.orderFrontRegardless() }
    updateHitRegions()
    panels.forEach { $0.orderFrontRegardless() }
  }
  private func updateHitRegions() {
    for panel in panels {
      let mouse = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
      panel.ignoresMouseEvents = !LockScreenGeometry.accepts(
        mouse, size: panel.frame.size, expanded: expanded, lyrics: lyrics)
    }
  }
  private func hide() {
    expanded = false
    lyrics = false
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
  }
  func resume() { setLocked(Self.sessionLocked()) }
  func suspend() { setLocked(false) }
  func stop() {
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
