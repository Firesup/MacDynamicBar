import AppKit
import Combine
import IOBluetooth

struct AirPodsIdentity: Equatable {
  let name: String
  let symbol: String

  /// SDP Device ID is used when cached; names are a fallback for unavailable records.
  /// Unknown products are ignored rather than presenting every Bluetooth device as AirPods.
  static func resolve(name: String, vendor: Int? = nil, product: Int? = nil) -> AirPodsIdentity? {
    let normalized = name.lowercased().filter { !$0.isWhitespace }
    let appleProduct = vendor == 0x004C || vendor == 0x05AC
    // Known Bluetooth product IDs. New devices can still resolve through their name.
    let symbols: [Int: String] = [
      0x2002: "airpods", 0x200F: "airpods", 0x2013: "airpods.gen3",
      0x200E: "airpodspro", 0x2014: "airpodspro", 0x2024: "airpodspro",
      0x200A: "airpodsmax", 0x201F: "airpodsmax",
    ]
    let symbol: String?
    if appleProduct, let product, let known = symbols[product] {
      symbol = known
    } else if normalized.contains("airpodsmax") {
      symbol = "airpodsmax"
    } else if normalized.contains("airpodspro") {
      symbol = "airpodspro"
    } else if normalized.contains("airpods") {
      symbol = "airpods"
    } else {
      symbol = nil
    }
    guard let symbol else { return nil }
    return AirPodsIdentity(name: name.isEmpty ? "AirPods" : name, symbol: symbol)
  }
}

/// Suppresses startup, duplicate connect callbacks, and reconnect storms.
struct AirPodsConnectionPolicy {
  private var connected = Set<String>()
  private var lastShown: [String: Date] = [:]

  mutating func seed(_ addresses: Set<String>) { connected = addresses }
  mutating func disconnected(_ address: String) { connected.remove(address) }
  mutating func connected(
    _ address: String, identity: AirPodsIdentity, selectedForOutput: Bool,
    now: Date = .now
  ) -> IslandPopup? {
    guard connected.insert(address).inserted else { return nil }
    lastShown = lastShown.filter { now.timeIntervalSince($0.value) < 10 }
    if let date = lastShown[address], now.timeIntervalSince(date) < 10 { return nil }
    lastShown[address] = now
    return IslandPopup(
      kind: .airPods, key: "airpods." + address, title: identity.name,
      subtitle: selectedForOutput ? "Connected · Audio Output" : "Connected",
      symbol: identity.symbol, createdAt: now)
  }
}

@MainActor
final class AirPodsMonitor: NSObject, ObservableObject {
  @Published private(set) var status = "AirPods connection monitoring is off"
  var onEvent: ((IslandPopup) -> Void)?
  var nameForAddress: ((String) -> String?)?
  var isSelectedForOutput: ((String) -> Bool)?
  private var connection: IOBluetoothUserNotification?
  private var disconnections: [String: IOBluetoothUserNotification] = [:]
  private var settleTasks: [String: Task<Void, Never>] = [:]
  private var wakeObserver: NSObjectProtocol?
  private var policy = AirPodsConnectionPolicy()
  private var started = false

  func start() {
    guard !started else { return }
    started = true
    seedConnectedDevices()
    connection = IOBluetoothDevice.register(
      forConnectNotifications: self, selector: #selector(didConnect(_:device:)))
    status =
      connection == nil
      ? "Bluetooth monitoring unavailable. Check macOS Privacy & Security → Bluetooth."
      : "Listening for AirPods connections"
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.seedConnectedDevices() }
    }
  }

  private func seedConnectedDevices() {
    settleTasks.values.forEach { $0.cancel() }
    settleTasks.removeAll()
    disconnections.values.forEach { $0.unregister() }
    disconnections.removeAll()
    let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
      $0.isConnected()
    }
    policy.seed(Set(devices.compactMap(\.addressString)))
    for device in devices { watchDisconnect(device) }
  }

  @objc nonisolated private func didConnect(
    _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    // IOBluetooth callbacks need not arrive on the main thread.
    let box = BluetoothDeviceReference(device: device)
    Task { @MainActor [weak self] in self?.connected(box.device) }
  }

  private func connected(_ device: IOBluetoothDevice) {
    guard started, let address = device.addressString else { return }
    watchDisconnect(device)
    settleTasks[address]?.cancel()
    let box = BluetoothDeviceReference(device: device)
    settleTasks[address] = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
      guard let self, self.started, box.device.isConnected() else { return }
      defer { self.settleTasks.removeValue(forKey: address) }
      guard var identity = AirPodsIdentity.resolve(device: box.device)
      else { return }
      if let name = self.nameForAddress?(address) {
        identity = AirPodsIdentity(name: name, symbol: identity.symbol)
      }
      if let popup = self.policy.connected(
        address, identity: identity,
        selectedForOutput: self.isSelectedForOutput?(identity.name) ?? false)
      {
        self.onEvent?(popup)
      }
    }
  }

  private func watchDisconnect(_ device: IOBluetoothDevice) {
    guard let address = device.addressString, disconnections[address] == nil else { return }
    disconnections[address] = device.register(
      forDisconnectNotification: self, selector: #selector(didDisconnect(_:device:)))
  }

  @objc nonisolated private func didDisconnect(
    _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    let address = device.addressString
    Task { @MainActor [weak self] in
      guard let self, let address else { return }
      self.policy.disconnected(address)
      self.settleTasks.removeValue(forKey: address)?.cancel()
      self.disconnections.removeValue(forKey: address)?.unregister()
    }
  }

  func stop() {
    started = false
    connection?.unregister()
    connection = nil
    disconnections.values.forEach { $0.unregister() }
    disconnections.removeAll()
    settleTasks.values.forEach { $0.cancel() }
    settleTasks.removeAll()
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    wakeObserver = nil
    policy = AirPodsConnectionPolicy()
    status = "AirPods connection monitoring is off"
  }
}

/// Only transfers the Objective-C reference to the main actor; all device operations
/// after callback handoff happen there. IOBluetooth manages the object's lifetime.
private struct BluetoothDeviceReference: @unchecked Sendable {
  let device: IOBluetoothDevice
}

@MainActor extension AirPodsIdentity {
  /// Use the same cached SDP identity in both the event monitor and paired-device picker.
  static func resolve(device: IOBluetoothDevice) -> AirPodsIdentity? {
    let record = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1200))
    return resolve(name: device.name ?? "",
      vendor: record?.getAttributeDataElement(0x0201)?.getNumberValue()?.intValue,
      product: record?.getAttributeDataElement(0x0202)?.getNumberValue()?.intValue)
  }
}
