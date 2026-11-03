import AppKit
import IOKit.ps

struct MacBatterySnapshot: Equatable {
  let percentage: Int
  let onExternalPower: Bool
  let charging: Bool

  static func read() -> MacBatterySnapshot? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard
        let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        let snapshot = parse(values)
      else { continue }
      return snapshot
    }
    return nil  // Desktop Macs and unavailable readings do not generate invented percentages.
  }

  static func parse(_ values: [String: Any]) -> MacBatterySnapshot? {
    guard values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
      let current = values[kIOPSCurrentCapacityKey] as? Int, current >= 0,
      let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0,
      let state = values[kIOPSPowerSourceStateKey] as? String,
      state == kIOPSACPowerValue || state == kIOPSBatteryPowerValue
    else { return nil }
    return MacBatterySnapshot(
      percentage: min(100, Int(Double(current) / Double(maximum) * 100)),
      onExternalPower: state == kIOPSACPowerValue,
      charging: values[kIOPSIsChargingKey] as? Bool ?? false)
  }

}

/// Tracks a discharge cycle. Once a threshold is warned, bouncing around it cannot retrigger it.
struct BatteryAlertPolicy {
  private(set) var previous: MacBatterySnapshot?
  private var warned = Set<Int>()

  mutating func update(_ snapshot: MacBatterySnapshot, lowEnabled: Bool, chargingEnabled: Bool)
    -> [IslandPopup]
  {
    let old = previous
    previous = snapshot
    if snapshot.onExternalPower { warned.removeAll() }
    var result: [IslandPopup] = []
    if chargingEnabled, let old, !old.onExternalPower, snapshot.onExternalPower {
      result.append(
        IslandPopup(
          kind: .charging, key: "mac.charging", title: "Power Connected",
          subtitle: snapshot.charging ? "Charging" : "Connected · Not charging",
          symbol: "battery.100percent.bolt", percentage: snapshot.percentage))
    }
    guard lowEnabled, !snapshot.onExternalPower else { return result }
    // A jump past both thresholds produces only the more urgent warning.
    let threshold = [10, 20].first { snapshot.percentage <= $0 && !warned.contains($0) }
    if let threshold {
      for crossed in [10, 20] where snapshot.percentage <= crossed { warned.insert(crossed) }
      result.append(
        IslandPopup(
          kind: .lowBattery, key: "mac.low.\(threshold)", title: "Low Battery",
          subtitle: "Connect your Mac to power",
          symbol: snapshot.percentage <= 10 ? "battery.0percent" : "battery.25percent",
          percentage: snapshot.percentage))
    }
    return result
  }
}

@MainActor
final class BatteryMonitor {
  var onSnapshot: ((MacBatterySnapshot) -> Void)?
  var onEvent: ((IslandPopup) -> Void)?
  var lowEnabled = true
  var chargingEnabled = true
  private var source: CFRunLoopSource?
  private var wakeObserver: NSObjectProtocol?
  private var policy = BatteryAlertPolicy()

  func start() {
    guard source == nil else { return }
    let context = Unmanaged.passUnretained(self).toOpaque()
    source = IOPSNotificationCreateRunLoopSource(
      { context in
        guard let context else { return }
        // The source is installed on the main run loop in common modes.
        MainActor.assumeIsolated {
          Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }
      }, context)?.takeRetainedValue()
    if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    refresh()
  }

  func refresh() {
    guard let snapshot = MacBatterySnapshot.read() else { return }
    onSnapshot?(snapshot)
    for event in policy.update(snapshot, lowEnabled: lowEnabled, chargingEnabled: chargingEnabled) {
      onEvent?(event)
    }
  }

  func stop() {
    if let source {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      CFRunLoopSourceInvalidate(source)
    }
    source = nil
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    wakeObserver = nil
    policy = BatteryAlertPolicy()
  }
}
