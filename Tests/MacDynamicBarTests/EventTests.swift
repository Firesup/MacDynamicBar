import Foundation
import Testing

@testable import MacDynamicBar

private func snapshot(_ percent: Int, plugged: Bool = false, charging: Bool = false)
  -> MacBatterySnapshot
{
  MacBatterySnapshot(percentage: percent, onExternalPower: plugged, charging: charging)
}

@Test func batteryThresholdsWarnOnceDespiteNoisyReadingsAndResetOnPower() {
  var policy = BatteryAlertPolicy()
  func update(_ s: MacBatterySnapshot) -> [IslandPopup] {
    policy.update(s, lowEnabled: true, chargingEnabled: true)
  }
  #expect(update(snapshot(40)).isEmpty)
  #expect(update(snapshot(20)).map(\.kind) == [.lowBattery])
  for percentage in [20, 19, 21, 20, 11] { #expect(update(snapshot(percentage)).isEmpty) }
  #expect(update(snapshot(10)).map(\.kind) == [.lowBattery])
  #expect(update(snapshot(9)).isEmpty)
  #expect(update(snapshot(9, plugged: true, charging: true)).map(\.kind) == [.charging])
  #expect(update(snapshot(10, plugged: true, charging: true)).isEmpty)
  #expect(update(snapshot(9)).map(\.kind) == [.lowBattery])
}

@Test func batteryLaunchJumpAndDisabledAlertsDoNotInventTransitions() {
  var policy = BatteryAlertPolicy()
  #expect(
    {
      policy.update(snapshot(80, plugged: true), lowEnabled: true, chargingEnabled: true).isEmpty
    }())
  let alerts = policy.update(snapshot(8), lowEnabled: true, chargingEnabled: true)
  #expect(alerts.count == 1)
  #expect(alerts.first?.percentage == 8)
  #expect({ policy.update(snapshot(7), lowEnabled: true, chargingEnabled: true).isEmpty }())
  #expect(
    {
      policy.update(snapshot(7, plugged: true), lowEnabled: false, chargingEnabled: false).isEmpty
    }())
  #expect({ policy.update(snapshot(5), lowEnabled: false, chargingEnabled: false).isEmpty }())
  #expect({ policy.update(snapshot(5), lowEnabled: true, chargingEnabled: false).count == 1 }())
}

@Test func powerConnectedCanReportNotChargingWithoutPretendingOtherwise() {
  var policy = BatteryAlertPolicy()
  _ = policy.update(snapshot(80), lowEnabled: true, chargingEnabled: true)
  let event = policy.update(snapshot(80, plugged: true), lowEnabled: true, chargingEnabled: true)
    .first
  #expect(event?.kind == .charging)
  #expect(event?.subtitle == "Connected · Not charging")
}

@Test func airPodsConnectionBaselineDuplicatesAndReconnectStormsAreSuppressed() throws {
  var policy = AirPodsConnectionPolicy()
  let identity = try #require(AirPodsIdentity.resolve(name: "My AirPods Pro"))
  let date = Date(timeIntervalSince1970: 100)
  policy.seed(["existing"])
  #expect(
    {
      policy.connected("existing", identity: identity, selectedForOutput: false, now: date) == nil
    }())
  let connected = policy.connected("new", identity: identity, selectedForOutput: false, now: date)
  let event = try #require(connected)
  #expect(event.subtitle == "Connected")
  #expect(event.percentage == nil)
  #expect(
    { policy.connected("new", identity: identity, selectedForOutput: true, now: date) == nil }())
  policy.disconnected("new")
  #expect(
    {
      policy.connected(
        "new", identity: identity, selectedForOutput: true, now: date.addingTimeInterval(2)) == nil
    }())
  policy.disconnected("new")
  #expect(
    {
      policy.connected(
        "new", identity: identity, selectedForOutput: true, now: date.addingTimeInterval(11))?
        .subtitle == "Connected · Audio Output"
    }())
}

@Test func airPodsArtworkOnlyMatchesRecognizedDevices() {
  #expect(AirPodsIdentity.resolve(name: "Mouse") == nil)
  #expect(AirPodsIdentity.resolve(name: "Headphones", vendor: 0x1234, product: 0x200E) == nil)
  #expect(
    AirPodsIdentity.resolve(name: "Renamed", vendor: 0x004C, product: 0x200E)?.symbol
      == "airpodspro")
  #expect(AirPodsIdentity.resolve(name: "AirPods Max")?.symbol == "airpodsmax")
  #expect(AirPodsIdentity.resolve(name: "AirPods")?.symbol == "airpods")
}

@Test @MainActor func popupPriorityCoalescingAndCriticalPreemption() {
  let popups = PopupCoordinator(automaticallyDismiss: false)
  popups.setBusy(true)
  popups.submit(.preview(.airPods))
  popups.submit(.preview(.charging))
  popups.submit(.preview(.airPods))
  #expect(popups.active == nil)
  #expect(popups.pending.count == 2)
  popups.setBusy(false)
  #expect(popups.active?.kind == .charging)
  popups.submit(.preview(.lowBattery))
  #expect(popups.active?.kind == .lowBattery)
  popups.dismiss()
  #expect(popups.active?.kind == .airPods)
  popups.dismiss()
  #expect(popups.active == nil)
}

@Test @MainActor func popupDedupExpiryAndBoundedQueue() {
  var now = Date(timeIntervalSince1970: 100)
  let popups = PopupCoordinator(clock: { now }, automaticallyDismiss: false)
  popups.setBusy(true)
  let event = IslandPopup(
    kind: .charging, key: "power", title: "Power", subtitle: "", symbol: "bolt", createdAt: now)
  popups.submit(event)
  popups.submit(event)
  #expect(popups.pending.count == 1)
  now = now.addingTimeInterval(20)
  popups.setBusy(false)
  #expect(popups.active == nil)
  popups.setBusy(true)
  for index in 0..<20 {
    popups.submit(
      IslandPopup(
        kind: .airPods, key: "\(index)", title: "AirPods", subtitle: "", symbol: "airpods",
        createdAt: now))
  }
  #expect(popups.pending.count == 8)
  popups.clear()
}

@Test @MainActor func popupSuppressionClearsBothVisibleAndQueuedEvents() {
  let popups = PopupCoordinator(automaticallyDismiss: false)
  popups.submit(.preview(.lowBattery))
  popups.submit(.preview(.airPods))
  popups.setAllowed(false)
  #expect(popups.active == nil)
  #expect(popups.pending.isEmpty)
  popups.submit(.preview(.charging))
  #expect(popups.active == nil)
  popups.setAllowed(true)
  #expect(popups.active == nil)  // No stale replay when leaving fullscreen or unlocking.
  popups.submit(.preview(.charging))
  #expect(popups.active?.kind == .charging)
  popups.discard(kind: .charging)
  #expect(popups.active == nil)
}

@Test @MainActor func popupsWaitForPlaybackInteractionAndPreservePinnedMusicState() {
  let state = IslandState()
  let popups = PopupCoordinator(automaticallyDismiss: false)
  state.toggle()
  state.setScrubbing(true)
  popups.setBusy(state.isInteractionBusy)
  popups.submit(.preview(.airPods))
  #expect(popups.active == nil)
  state.setScrubbing(false)
  state.isOutputPickerOpen = true
  popups.setBusy(state.isInteractionBusy)
  #expect(popups.active == nil)
  state.isOutputPickerOpen = false
  popups.setBusy(state.isInteractionBusy)
  #expect(popups.active?.kind == .airPods)
  #expect(state.isExpanded)
  popups.dismiss()
  #expect(state.isExpanded)
  state.collapse()
}

@Test @MainActor func eventPreferencesPersistAndReset() throws {
  let suite = "MinnowEvents.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  #expect(settings.airPodsPopups && settings.lowBatteryPopups && settings.chargingPopups)
  settings.airPodsPopups = false
  settings.lowBatteryPopups = false
  settings.chargingPopups = false
  let restored = MinnowSettings(defaults: defaults)
  #expect(!restored.airPodsPopups && !restored.lowBatteryPopups && !restored.chargingPopups)
  restored.resetPreferences()
  #expect(restored.airPodsPopups && restored.lowBatteryPopups && restored.chargingPopups)
}

@Test @MainActor func popupAutomaticallyDismissesAfterItsDisplayDuration() async throws {
  let popups = PopupCoordinator()
  popups.submit(.preview(.airPods))
  #expect(popups.active?.kind == .airPods)
  try await waitForCondition(timeout: .seconds(6)) { popups.active == nil }
  #expect(popups.active == nil)
}
