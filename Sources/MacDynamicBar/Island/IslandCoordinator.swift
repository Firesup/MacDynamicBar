import AppKit
import Combine

// MARK: - Display and Visibility Coordination

@MainActor
final class IslandCoordinator {
  let settings: MinnowSettings
  let session = IslandMediaSession()
  let popups = PopupCoordinator()
  let activities = ActivityStore()
  let sceneWidgets = MusicSceneWidgets()
  let shelf = ShelfStore()
  let widgets: WidgetServices
  lazy var lockScreen = LockScreenController(
    session: session, settings: settings, widgets: widgets, readings: sceneWidgets)
  private var musicScene: MusicSceneWindow?
  let airPods = AirPodsMonitor()
  private let battery = BatteryMonitor()
  private let brightnessHUD = BrightnessHUDMonitor()
  private let volumeHUD = VolumeHUDMonitor()
  private var started = false
  private var controllers: [CGDirectDisplayID: IslandWindowController] = [:]
  private var subscriptions = Set<AnyCancellable>()
  private var pauseTask: Task<Void, Never>?
  private var sessionActive = true
  private var systemAwake = true
  private var hiddenAfterPause = false
  private var previouslyEnabled = true
  private var visibilityTask: Task<Void, Never>?

  init(settings: MinnowSettings) {
    self.settings = settings
    widgets = WidgetServices(settings: settings)
    battery.onSnapshot = { [weak self] in
      self?.sceneWidgets.battery = $0
    }
    brightnessHUD.onEvent = { [weak self] in self?.submit($0) }
    volumeHUD.onEvent = { [weak self] in self?.submit($0) }

    airPods.onEvent = { [weak self] event in self?.submit(event) }
    airPods.nameForAddress = { [weak self] rawAddress in
      guard let address = BluetoothOutputNaming.address(in: rawAddress) else { return nil }
      return self?.session.outputs.devices.first { $0.bluetoothAddress == address }?.name
    }
    airPods.isSelectedForOutput = { [weak self] name in
      guard !name.isEmpty else { return false }
      return self?.session.outputs.current?.name.localizedCaseInsensitiveCompare(name)
        == .orderedSame
    }
    activities.$entries.receive(on: RunLoop.main).sink { [weak self] _ in self?.reconcileDisplays()
    }.store(in: &subscriptions)
    popups.$active.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.reconcileDisplays()
    }.store(in: &subscriptions)
  }

  func start() {
    guard !started else { return }
    started = true
    popups.displayDuration = settings.popupDuration
    session.apply(settings)
    settings.objectWillChange
      .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
      .sink { [weak self] in self?.applySettings() }
      .store(in: &subscriptions)
    session.player.$captureTarget.removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.playbackChanged() }
      .store(in: &subscriptions)
    shelf.setEnabled(settings.shelfEnabled)
    widgets.today.start()
    session.start()
    volumeHUD.start()
    lockScreen.onPresentationChanged = { [weak self] in self?.reconcileDisplays() }
    lockScreen.start()
    reconcileDisplays()
    applyEventSettings()
  }

  func applySettings() {
    popups.displayDuration = settings.popupDuration
    session.apply(settings)
    shelf.setEnabled(settings.shelfEnabled)
    widgets.today.applySettings()
    if settings.islandEnabled && !previouslyEnabled { hiddenAfterPause = false }
    previouslyEnabled = settings.islandEnabled
    if !settings.hideOnPause { hiddenAfterPause = false }
    reconcileDisplays()
    schedulePauseActions()
    applyEventSettings()
  }

  private func applyEventSettings() {
    guard started else { return }
    if settings.brightnessHUD { brightnessHUD.start() } else { brightnessHUD.stop() }
    battery.lowEnabled = false
    battery.chargingEnabled = false
    if settings.lowBatteryPopups || settings.chargingPopups || settings.showActivities {
      battery.start()
      battery.refresh()
    } else {
      battery.stop()
    }
    if settings.airPodsPopups {
      airPods.start()
    } else {
      airPods.stop()
      popups.discard(kind: .airPods)
    }
    if !settings.lowBatteryPopups { popups.discard(kind: .lowBattery) }
    if !settings.chargingPopups { popups.discard(kind: .charging) }
  }

  private func submit(_ event: IslandPopup) {
    updatePopupPolicy()
    popups.submit(event)
  }

  func openMusicScene() {
    if musicScene == nil {
      musicScene = MusicSceneWindow(session: session, settings: settings, widgets: sceneWidgets)
    }
    musicScene?.open()
  }
  func previewActivity() { activities.preview() }
  func preview(_ kind: IslandPopup.Kind) { submit(.preview(kind)) }

  private func updatePopupPolicy() {
    let allowed =
      settings.islandEnabled && sessionActive && systemAwake
      && chosenScreens().contains {
        !(settings.hideFullscreen && FullscreenVisibility.covers($0))
      }
    popups.setAllowed(allowed)
    popups.setBusy(controllers.values.contains { $0.isInteractionBusy })
  }

  func reconcileDisplays(reposition: Bool = false) {
    let timing = TransitionTiming("island state reconciliation")
    defer { timing.end() }
    guard started || popups.active != nil || activities.primary != nil else {
      controllers.values.forEach { $0.hide() }
      return
    }
    updatePopupPolicy()
    let screens = chosenScreens()
    let ids = Set(screens.compactMap { MinnowDisplay.from($0)?.nativeID })
    for id in Array(controllers.keys) where !ids.contains(id) {
      controllers.removeValue(forKey: id)?.stop()
    }
    let visible =
      settings.islandEnabled && sessionActive && systemAwake
      && IslandContentPolicy.hasContent(
        mediaEnabled: settings.mediaEnabled,
        hiddenAfterPause: hiddenAfterPause, todayEnabled: settings.todayEnabled,
        hasPopup: popups.active != nil,
        hasActivity: settings.showActivities && activities.primary != nil,
        shelfEnabled: settings.shelfEnabled)
    var anyVisible = false
    for screen in screens {
      guard let id = MinnowDisplay.from(screen)?.nativeID else { continue }
      if controllers[id] == nil {
        controllers[id] = IslandWindowController(
          session: session, settings: settings, popups: popups, activities: activities,
          today: widgets.today, shelf: shelf,
          displayID: id)
        controllers[id]?.onInteractionChanged = { [weak self] in self?.updatePopupPolicy() }
      }
      guard let controller = controllers[id] else { continue }
      controller.applySettings(reposition: reposition)
      if visible && !(settings.hideFullscreen && FullscreenVisibility.covers(screen)) {
        anyVisible = true
        if !controller.isVisible { controller.show() }
      } else {
        controller.hide()
      }
    }
    let desktopAudio = anyVisible && settings.mediaEnabled && !hiddenAfterPause
    session.audio.setSuspended(!(desktopAudio || lockScreen.isPresentingPlayer))
  }

  func refreshVisibility() {
    widgets.today.refresh()
    session.audio.retryAfterPermissionChange()
    visibilityTask?.cancel()
    visibilityTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      self?.reconcileDisplays()
    }
  }

  func setSystemAwake(_ awake: Bool) {
    systemAwake = awake
    session.setSystemAwake(awake)
    if !awake {
      popups.clear()
      lockScreen.suspend()
    } else {
      lockScreen.resume()
    }
    reconcileDisplays()
  }

  func setSessionActive(_ active: Bool) {
    sessionActive = active
    if !active { popups.clear() }
    lockScreen.sessionActivityChanged(active)
    reconcileDisplays()
  }

  func reposition() { reconcileDisplays(reposition: true) }
  func refresh() {
    session.player.refresh()
    session.accessories.refresh()
  }
  func retryCapture() {
    guard settings.audioReactive else { return }
    session.audio.retry()
    reconcileDisplays()
  }
  func stop() {
    started = false
    lockScreen.stop()
    widgets.stop()
    shelf.stop()
    activities.clear()
    musicScene?.close()
    battery.stop()
    volumeHUD.stop()
    brightnessHUD.stop()
    airPods.stop()
    popups.clear()
    pauseTask?.cancel()
    visibilityTask?.cancel()
    subscriptions.removeAll()
    controllers.values.forEach { $0.stop() }
    controllers.removeAll()
    session.stop()
  }

  private func chosenScreens() -> [NSScreen] {
    if settings.allDisplays { return NSScreen.screens }
    if settings.display == "main",
      let main = NSScreen.screens.first(where: {
        MinnowDisplay.from($0)?.nativeID == CGMainDisplayID()
      })
    {
      return [main]
    }
    if settings.display != "automatic",
      let selected = NSScreen.screens.first(where: {
        MinnowDisplay.from($0)?.id == settings.display
      })
    {
      return [selected]
    }
    let builtIn = NSScreen.screens.first { screen in
      guard let id = MinnowDisplay.from(screen)?.nativeID else { return false }
      return CGDisplayIsBuiltin(id) != 0
    }
    return (builtIn ?? NSScreen.screens.first).map { [$0] } ?? []
  }

  private func playbackChanged() {
    // Visibility rules apply equally to playing and paused tracks.
    reconcileDisplays()
    if session.player.isPlaying {
      pauseTask?.cancel()
      hiddenAfterPause = false
      reconcileDisplays()
    } else {
      schedulePauseActions()
    }
  }

  private func schedulePauseActions() {
    pauseTask?.cancel()
    guard !session.player.isPlaying, session.player.track != nil,
      settings.islandEnabled, settings.collapseOnPause || settings.hideOnPause
    else { return }
    let collapse = settings.collapseOnPause ? settings.collapseDelay : Double.infinity
    let hide = settings.hideOnPause ? settings.hideDelay : Double.infinity
    pauseTask = Task { @MainActor [weak self] in
      let first = min(collapse, hide)
      do { try await Task.sleep(for: .seconds(first)) } catch { return }
      guard let self, !self.session.player.isPlaying else { return }
      if collapse <= hide { self.controllers.values.forEach { $0.collapseMedia() } }
      if hide <= collapse {
        self.hiddenAfterPause = true
        self.reconcileDisplays()
        return
      }
      guard hide.isFinite else { return }
      do { try await Task.sleep(for: .seconds(max(0, hide - collapse))) } catch { return }
      guard !self.session.player.isPlaying else { return }
      self.hiddenAfterPause = true
      self.reconcileDisplays()
    }
  }
}
