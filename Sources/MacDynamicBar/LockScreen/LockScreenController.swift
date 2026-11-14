import AppKit
import Combine
import SwiftUI
import os

struct LockScreenGeometry {
  /// Reserve the bottom 24% for authentication and the top 26% for macOS's clock.
  static func playerFrame(screen: CGRect) -> CGRect {
    let width = max(0, min(380, screen.width - 40))
    let height = max(0, min(164, screen.height * 0.5))
    return CGRect(x: screen.midX - width / 2, y: screen.minY + screen.height * 0.24 + 16,
                  width: width, height: height)
  }
  static func accepts(_ point: CGPoint, size: CGSize) -> Bool {
    CGRect(origin: .zero, size: size).contains(point)
  }
  static func progress(position: TimeInterval, duration: TimeInterval) -> Double {
    guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
    return min(1, max(0, position / duration))
  }
}

final class LockMediaPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class LockCardHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else { return nil }
    return super.hitTest(point)
  }
}

struct LockSessionSnapshot {
  var locked: Bool?
  var onConsole: Bool?
  static func current() -> Self {
    guard let values = CGSessionCopyCurrentDictionary() as? [String: Any] else {
      return Self(locked: nil, onConsole: nil)
    }
    let owner = (values[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value
    let signedIn = values[kCGSessionLoginDoneKey as String] as? Bool
    let console = values[kCGSessionOnConsoleKey as String] as? Bool
    return Self(locked: values["CGSSessionScreenIsLocked"] as? Bool,
                onConsole: console.map { $0 && owner == getuid() && signedIn == true })
  }
  var permitsPlacement: Bool { locked == true && onConsole == true }
}

/// Owns one compact overlay. Panel existence/order and private API success are not visibility proof.
@MainActor final class LockScreenController: ObservableObject {
  @Published private(set) var status = "Lock screen monitoring is stopped"
  var onPresentationChanged: (() -> Void)?
  private let logger = Logger(subsystem: "com.minnow.MacDynamicBar", category: "LockScreen")
  private let session: IslandMediaSession
  private let settings: MinnowSettings
  private let snapshot: () -> LockSessionSnapshot
  private let makePresenter: () throws -> any LockScreenPresenting
  private var presenter: (any LockScreenPresenting)?
  private var panel: LockMediaPanel?
  private var placed = false
  private var failure: String?
  private var lifecycle = LockScreenLifecycle()
  private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
  private var subscriptions = Set<AnyCancellable>()
  private var watchdog: Task<Void, Never>?
  private var repair: Task<Void, Never>?
  private var pendingControl: Task<Void, Never>?
  private var wasPlaced = false
  private var metadataLocked = false
  private var lastPlacement = Date.distantPast
  private var placementDeadline: Date?
  private var lastState: AudioCaptureTarget?
  var hasPlacedPlayer: Bool { placed && lifecycle.canPresent && settings.lockScreenPlayer }

  init(
    session: IslandMediaSession, settings: MinnowSettings,
    snapshot: @escaping () -> LockSessionSnapshot = LockSessionSnapshot.current,
    makePresenter: @escaping () throws -> any LockScreenPresenting = { try SkyLightLockScreenPresenter.load() }
  ) {
    self.session = session
    self.settings = settings
    self.snapshot = snapshot
    self.makePresenter = makePresenter
  }

  func start() {
    guard watchdog == nil else { return }
    observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsLocked")) {
      $0.lockChanged(true)
    }
    observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked")) {
      $0.lockChanged(false)
    }
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { $0.suspend() }
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification) { $0.resume() }
    observe(.default, NSApplication.didChangeScreenParametersNotification) {
      $0.hide(reason: "display configuration changed")
      $0.refresh()
    }
    settings.objectWillChange.debounce(for: .milliseconds(50), scheduler: RunLoop.main)
      .sink { [weak self] in
        guard let self else { return }
        self.hide(reason: "settings changed")
        self.refresh()
      }.store(in: &subscriptions)
    session.player.$track.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
      .store(in: &subscriptions)
    session.player.$captureTarget.receive(on: RunLoop.main).sink { [weak self] state in
      guard let self, state != self.lastState else { return }
      self.lastState = state
      if self.lifecycle.locked {
        self.logger.info("playback observation locked=\(self.snapshot().locked == true) source=\(state.source?.rawValue ?? "none", privacy: .public) playing=\(state.isPlaying)")
      }
    }.store(in: &subscriptions)
    // Poll even while unlocked: notifications are hints and may be missed.
    watchdog = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        self?.refresh()
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
    }
    resume()
  }

  private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                       action: @escaping @MainActor (LockScreenController) -> Void) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { if let self { action(self) } }
    }
    tokens.append((center, token))
  }

  private func lockChanged(_ locked: Bool) {
    logger.info("lock notification locked=\(locked) canonical=\(self.snapshot().locked == true)")
    lifecycle.lockChanged(locked)
    if !locked {
      repair?.cancel()
      hide(reason: "explicit unlock")
      updateMetadataLock()
      publish()
    } else {
      refresh()
      scheduleRepair()
    }
  }

  private func updateMetadataLock() {
    let unlocked = metadataLocked && !lifecycle.locked
    metadataLocked = lifecycle.locked
    session.player.setSessionLocked(lifecycle.locked)
    if unlocked { session.player.refresh() }
  }

  func refresh(repairPlacement: Bool = false) {
    let observed = snapshot()
    lifecycle.reconcile(observedLock: observed.locked, onConsole: observed.onConsole)
    updateMetadataLock()
    guard settings.lockScreenPlayer else {
      hide(reason: "opt-in disabled")
      failure = nil
      publish()
      return
    }
    // Unknown canonical state is never permission to order a high-level panel.
    guard lifecycle.canPresent, observed.permitsPlacement else {
      hide(reason: "not confirmed locked, awake, signed-in console session")
      publish()
      return
    }
    guard failure == nil, session.player.track != nil else {
      hide(reason: "unavailable or no track")
      publish()
      return
    }
    // This milestone deliberately creates only one panel, preferring the built-in display.
    guard let screen = NSScreen.screens.first(where: {
      guard let id = MinnowDisplay.from($0)?.nativeID else { return false }
      return CGDisplayIsBuiltin(id) != 0
    }) ?? NSScreen.screens.first else { return }
    if panel == nil {
      let frame = LockScreenGeometry.playerFrame(screen: screen.frame)
      let created = LockMediaPanel(
        contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered, defer: false)
      created.isReleasedWhenClosed = false
      created.canBecomeVisibleWithoutLogin = true
      created.level = .init(rawValue: Int(CGShieldingWindowLevel()) + 1)
      created.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
      created.becomesKeyOnlyIfNeeded = true
      created.isMovable = false
      created.ignoresMouseEvents = true
      created.isOpaque = false
      created.backgroundColor = .clear
      created.hasShadow = false
      created.hidesOnDeactivate = false
      created.worksWhenModal = true
      created.animationBehavior = .none
      let hosting = LockCardHostingView(rootView: LockScreenPlayerView(
        player: session.player, useGlass: settings.lockScreenGlass,
        togglePlayback: { [weak self] in self?.togglePlayback() })
        .frame(width: frame.width, height: frame.height))
      hosting.sizingOptions = []
      hosting.frame = CGRect(origin: .zero, size: frame.size)
      hosting.autoresizingMask = [.width, .height]
      created.contentView = hosting
      panel = created
      placementDeadline = .now.addingTimeInterval(2)
      logger.info("panel created window=\(created.windowNumber) frame=\(NSStringFromRect(frame), privacy: .public) locked=\(observed.locked == true)")
    }
    if placed, !repairPlacement, Date.now.timeIntervalSince(lastPlacement) < 5 {
      publish()
      return
    }
    do {
      if presenter == nil { presenter = try makePresenter() }
      guard let panel, let presenter else { return }
      // Recheck after construction. A delayed repair must never order onto the desktop.
      guard snapshot().permitsPlacement, lifecycle.canPresent else {
        hide(reason: "lock ended before placement")
        publish()
        return
      }
      try presenter.place(window: panel.windowNumber, orderWindow: {
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
      })
      if !placed {
        logger.info("panel ordered window=\(panel.windowNumber) space level and server ordering verified; private-space membership/visibility UNVERIFIED")
      }
      panel.ignoresMouseEvents = false
      placed = true
      lastPlacement = .now
    } catch {
      if let transient = error as? LockScreenPresentationError, transient.retryable,
        let deadline = placementDeadline, Date.now < deadline {
        logger.info("window transaction pending; recheck after AppKit commits the run loop")
        publish()
        return
      }
      failure = String(describing: error)
      logger.error("presenter unavailable: \(String(describing: error), privacy: .public)")
      hide(reason: "presenter failure")
    }
    publish()
  }

  private func scheduleRepair() {
    repair?.cancel()
    repair = Task { @MainActor [weak self] in
      // Re-show AND re-adopt after loginwindow rebuilds shown spaces on wake.
      for milliseconds in [120, 180, 300, 500, 900] {
        do { try await Task.sleep(for: .milliseconds(milliseconds)) } catch { return }
        guard let self, self.snapshot().permitsPlacement, self.lifecycle.canPresent else { return }
        self.logger.info("bounded lock/wake placement repair")
        self.refresh(repairPlacement: true)
      }
    }
  }

  private func togglePlayback() {
    let observed = snapshot()
    guard pendingControl == nil else { return }
    guard hasPlacedPlayer, observed.permitsPlacement, session.player.canControlPlayback,
      let source = session.player.captureTarget.source else {
      logger.info("button rejected: lock/placement/playback unavailable")
      return
    }
    let id = UUID().uuidString
    let before = session.player.isPlaying
    logger.info("button request=\(id, privacy: .public) locked=true source=\(source.rawValue, privacy: .public) playingBefore=\(before) expectedPlaying=\(!before)")
    session.player.togglePlayback()
    pendingControl?.cancel()
    pendingControl = Task { @MainActor [weak self] in
      defer { self?.pendingControl = nil }
      // Observe a real source state change; never optimistically flip the icon.
      for _ in 0..<30 {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        guard let self else { return }
        guard self.snapshot().permitsPlacement else {
          self.logger.info("button request=\(id, privacy: .public) UNCONFIRMED: session ended")
          return
        }
        if self.session.player.captureTarget.source == source, self.session.player.isPlaying != before {
          self.logger.info("button request=\(id, privacy: .public) locked=true source=\(source.rawValue, privacy: .public) resultingPlaying=\(self.session.player.isPlaying) state transition CONFIRMED")
          return
        }
      }
      self?.logger.error("button request=\(id, privacy: .public) UNCONFIRMED: no matching playback transition in 3 seconds")
    }
  }

  private func hide(reason: String) {
    let hadPanel = panel != nil
    // Order out and disable input before any space operation or async cancellation.
    panel?.ignoresMouseEvents = true
    panel?.orderOut(nil)
    panel?.level = .normal
    panel?.close()
    panel = nil
    placed = false
    placementDeadline = nil
    do { try presenter?.hide() } catch {
      if failure == nil { failure = String(describing: error) }
      logger.error("space cleanup failed: \(String(describing: error), privacy: .public)")
    }
    if hadPanel { logger.info("panel removed: \(reason, privacy: .public)") }
  }

  private func publish() {
    let updatedStatus = failure.map { "Lock Screen unavailable: \($0). Toggle off/on to retry." }
      ?? "Locked: \(lifecycle.locked) · Awake: \(lifecycle.awake) · Console: \(lifecycle.onConsole) · Placement: \(placed ? "submitted (visibility unverified)" : "none")"
    if status != updatedStatus { status = updatedStatus }
    if wasPlaced != hasPlacedPlayer {
      wasPlaced = hasPlacedPlayer
      onPresentationChanged?()
    }
  }

  func resume() {
    let observed = snapshot()
    lifecycle.wake(observedLock: observed.locked, onConsole: observed.onConsole)
    logger.info("display/system wake locked=\(observed.locked == true) console=\(observed.onConsole == true)")
    refresh()
    scheduleRepair()
  }
  func suspend() {
    lifecycle.sleep()
    repair?.cancel()
    hide(reason: "display/system sleep")
    logger.info("display/system sleep; overlay removed")
    publish()
  }
  func sessionActivityChanged(_ active: Bool) {
    logger.info("workspace session active=\(active)")
    repair?.cancel()
    hide(reason: "session activity changed")
    if active {
      lifecycle.sessionBecameActive()
      updateMetadataLock()
    }
    // Canonical console ownership distinguishes a lock transition from switching users.
    refresh()
  }
  func stop() {
    watchdog?.cancel()
    watchdog = nil
    repair?.cancel()
    pendingControl?.cancel()
    tokens.forEach { $0.0.removeObserver($0.1) }
    tokens.removeAll()
    subscriptions.removeAll()
    lifecycle = LockScreenLifecycle()
    hide(reason: "stop/quit")
    updateMetadataLock()
    publish()
  }
}

struct LockScreenStatusView: View {
  @ObservedObject var controller: LockScreenController
  var body: some View {
    Text(controller.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
  }
}
