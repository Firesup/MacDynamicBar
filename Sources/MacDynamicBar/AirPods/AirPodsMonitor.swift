import AppKit
import Combine
import IOBluetooth

struct AirPodsIdentity: Equatable, Sendable {
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
final class AirPodsMonitor: ObservableObject {
  @Published private(set) var status = "AirPods connection monitoring is off"
  var onEvent: ((IslandPopup) -> Void)?
  var nameForAddress: ((String) -> String?)?
  var isSelectedForOutput: ((String) -> Bool)?
  private let worker = BluetoothMonitorWorker()
  private var wakeObserver: NSObjectProtocol?
  private var policy = AirPodsConnectionPolicy()
  private var generation = 0
  private var started = false

  func start() {
    guard !started else { return }
    started = true
    generation += 1
    let version = generation
    status = "Starting Bluetooth monitoring"
    worker.queue.async { [worker, weak self] in
      worker.onSeed = { [weak self] addresses in
        Task { @MainActor in
          guard let self, self.started, self.generation == version else { return }
          self.policy.seed(addresses)
        }
      }
      worker.onStatus = { [weak self] available in
        Task { @MainActor in
          guard let self, self.started, self.generation == version else { return }
          self.status = available ? "Listening for AirPods connections" : "Bluetooth monitoring unavailable"
        }
      }
      worker.onDevice = { [weak self] address, identity in
        Task { @MainActor in
          guard let self, self.started, self.generation == version else { return }
          guard var identity else { self.policy.disconnected(address); return }
          if let name = self.nameForAddress?(address) {
            identity = AirPodsIdentity(name: name, symbol: identity.symbol)
          }
          if let popup = self.policy.connected(address, identity: identity,
            selectedForOutput: self.isSelectedForOutput?(identity.name) ?? false) {
            self.onEvent?(popup)
          }
        }
      }
      worker.start()
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.started else { return }
        self.worker.queue.async { [worker = self.worker] in worker.seed() }
      }
    }
  }

  func stop() {
    started = false
    generation += 1
    worker.queue.async { [worker] in worker.stop() }
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    wakeObserver = nil
    policy = AirPodsConnectionPolicy()
    status = "AirPods connection monitoring is off"
  }
}

/// Registration itself can wait on IOBluetooth's internal semaphore. Every Bluetooth call,
/// including registration/unregistration, belongs to this queue, never the UI actor.
private final class BluetoothMonitorWorker: NSObject, @unchecked Sendable {
  let queue = DispatchQueue(label: "com.minnow.bluetooth-monitor")
  var onSeed: (@Sendable (Set<String>) -> Void)?
  var onStatus: (@Sendable (Bool) -> Void)?
  var onDevice: (@Sendable (String, AirPodsIdentity?) -> Void)?
  private var connection: IOBluetoothUserNotification?
  private var disconnections: [String: IOBluetoothUserNotification] = [:]
  private var revisions: [String: Int] = [:]
  private var generation = 0
  private var started = false

  func start() {
    guard !started else { return }
    started = true
    let timing = TransitionTiming("Bluetooth registration")
    defer { timing.end() }
    connection = IOBluetoothDevice.register(forConnectNotifications: self,
      selector: #selector(didConnect(_:device:)))
    onStatus?(connection != nil)
    seed()
  }

  func seed() {
    guard started else { return }
    generation += 1
    revisions.removeAll()
    disconnections.values.forEach { $0.unregister() }
    disconnections.removeAll()
    let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
    onSeed?(Set(devices.compactMap(\.addressString)))
    for device in devices { watchDisconnect(device) }
  }

  @objc private func didConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
    let box = BluetoothDeviceReference(device: device)
    queue.async { [weak self] in
      guard let self, self.started, let address = box.device.addressString else { return }
      self.watchDisconnect(box.device)
      self.revisions[address, default: 0] += 1
      let revision = self.revisions[address]
      let version = self.generation
      self.queue.asyncAfter(deadline: .now() + .milliseconds(600)) { [weak self] in
        guard let self, self.started, self.generation == version,
          self.revisions[address] == revision, box.device.isConnected(),
          let identity = AirPodsIdentity.resolve(device: box.device) else { return }
        self.onDevice?(address, identity)
      }
    }
  }

  private func watchDisconnect(_ device: IOBluetoothDevice) {
    guard let address = device.addressString, disconnections[address] == nil else { return }
    disconnections[address] = device.register(forDisconnectNotification: self,
      selector: #selector(didDisconnect(_:device:)))
  }

  @objc private func didDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
    let box = BluetoothDeviceReference(device: device)
    queue.async { [weak self] in
      guard let self, self.started, !box.device.isConnected(), let address = box.device.addressString else { return }
      self.revisions[address, default: 0] += 1
      self.disconnections.removeValue(forKey: address)?.unregister()
      self.onDevice?(address, nil)
    }
  }

  func stop() {
    started = false
    generation += 1
    connection?.unregister()
    connection = nil
    disconnections.values.forEach { $0.unregister() }
    disconnections.removeAll()
    revisions.removeAll()
  }
}

private struct BluetoothDeviceReference: @unchecked Sendable {
  let device: IOBluetoothDevice
}

extension AirPodsIdentity {
  /// Use the same cached SDP identity in both the event monitor and paired-device picker.
  static func resolve(device: IOBluetoothDevice) -> AirPodsIdentity? {
    let record = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1200))
    return resolve(
      name: device.name ?? "",
      vendor: record?.getAttributeDataElement(0x0201)?.getNumberValue()?.intValue,
      product: record?.getAttributeDataElement(0x0202)?.getNumberValue()?.intValue)
  }
}
