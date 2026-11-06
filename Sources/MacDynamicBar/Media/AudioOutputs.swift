import AppKit
import Combine
import CoreAudio
import IOBluetooth
import SwiftUI

// MARK: - System Audio Outputs

/// Match the audio route to its paired device by address, never by a similar model name.
struct BluetoothOutputNaming {
  static func address(in identifier: String) -> String? {
    let pattern = "(?i)^(?:(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}|[0-9a-f]{12})(?=$|:output$|:input$)"
    guard let range = identifier.range(of: pattern, options: .regularExpression) else { return nil }
    return identifier[range].lowercased().filter { $0.isHexDigit }
  }

  static func name(audioName: String, uid: String, pairedNames: [String: String]) -> String {
    guard let address = address(in: uid), let name = pairedNames[address],
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return audioName }
    return preferredName(audioName: audioName, bluetoothName: name)
  }

  static func preferredName(audioName: String, bluetoothName: String) -> String {
    // Bluetooth can revert to a model label on connection while Core Audio keeps the user's name.
    let generic: Set<String> = [
      "airpods", "airpods2", "airpods3", "airpods4", "airpods4anc",
      "airpods4withactivenoisecancellation", "airpodspro", "airpodspro2", "airpodspro3",
      "airpodsmax",
    ]
    func modelName(_ name: String) -> Bool {
      generic.contains(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    let audioName = audioName.trimmingCharacters(in: .whitespacesAndNewlines)
    let bluetoothName = bluetoothName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !audioName.isEmpty && !modelName(audioName) { return audioName }
    if !bluetoothName.isEmpty && !modelName(bluetoothName) { return bluetoothName }
    return audioName.isEmpty ? bluetoothName : audioName
  }
}

struct AudioOutputDevice: Identifiable, @unchecked Sendable {
  let id: AudioDeviceID
  let name: String
  let symbol: String
  let nativeIcon: NSImage?
  var bluetoothAddress: String? = nil
}

@MainActor
final class AudioOutputs: ObservableObject {
  @Published private(set) var devices: [AudioOutputDevice] = []
  @Published private(set) var selectedID: AudioDeviceID = 0
  @Published private(set) var error: String?
  private let worker = AudioOutputWorker()
  private var generation = 0
  private var selectionGeneration = 0
  private var selectionError: String?
  private var refreshing = false
  private var notificationTask: Task<Void, Never>?
  private var started = false
  var current: AudioOutputDevice? { devices.first { $0.id == selectedID } }
  func start() {
    guard !started else { return }
    started = true
    worker.queue.async { [worker, weak self] in
      worker.onChange = { [weak self] in Task { @MainActor in self?.outputNotice() } }
      worker.start()
    }
    reload()
  }
  func stop() {
    notificationTask?.cancel()
    notificationTask = nil
    started = false
    generation += 1
    selectionGeneration += 1
    worker.queue.async { [worker] in worker.stop() }
  }
  func finishStopping() async {
    await withCheckedContinuation { continuation in
      worker.queue.async { continuation.resume() }
    }
  }
  private func outputNotice() {
    guard started else { return }
    generation += 1
    notificationTask?.cancel()
    notificationTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
      self?.reload()
    }
  }
  func reload() {
    guard started else { return }
    generation += 1
    guard !refreshing else { return }
    refreshing = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      repeat {
        let version = generation
        let snapshot = await withCheckedContinuation { continuation in
          worker.queue.async { [worker] in
            worker.reload()
            continuation.resume(
              returning: OutputSnapshot(
                devices: worker.devices,
                selectedID: worker.selectedID, error: worker.error))
          }
        }
        if version == generation {
          if started {
            devices = snapshot.devices
            selectedID = snapshot.selectedID
            error = snapshot.error ?? selectionError
          }
          break
        }
      } while started
      refreshing = false
    }
  }
  func select(_ device: AudioOutputDevice) {
    guard started else { return }
    generation += 1
    selectionGeneration += 1
    let version = selectionGeneration
    selectionError = nil
    error = nil
    worker.queue.async { [worker, weak self] in
      worker.select(device)
      let failure = worker.error
      Task { @MainActor in
        guard let self, self.started, version == self.selectionGeneration else { return }
        self.selectionError = failure
        self.reload()
      }
    }
  }
  static func symbol(name: String, model: String, transport: UInt32) -> String {
    AudioOutputWorker.symbol(name: name, model: model, transport: transport)
  }
}
private struct OutputSnapshot: @unchecked Sendable {
  let devices: [AudioOutputDevice]
  let selectedID: AudioDeviceID
  let error: String?
}

private final class AudioOutputWorker: @unchecked Sendable {
  let queue = DispatchQueue(label: "com.minnow.outputs")
  var onChange: (@Sendable () -> Void)?
  var devices: [AudioOutputDevice] = []
  var selectedID: AudioDeviceID = 0
  var error: String?
  private var started = false
  private var listeners:
    [(
      AudioObjectID, AudioObjectPropertyAddress,
      AudioObjectPropertyListenerBlock
    )] = []
  private let system = AudioObjectID(kAudioObjectSystemObject)
  var current: AudioOutputDevice? { devices.first { $0.id == selectedID } }

  func start() {
    guard !started else { return }
    started = true
    observe(system, kAudioHardwarePropertyDevices)
    observe(system, kAudioHardwarePropertyDefaultOutputDevice)
  }
  func stop() {
    started = false
    removeListeners()
  }

  func reload() {
    error = nil
    let timing = TransitionTiming("output enumeration")
    defer { timing.end() }
    selectedID = integer(system, kAudioHardwarePropertyDefaultOutputDevice) ?? 0
    var address = property(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      devices = []
      error = "Could not read audio outputs"
      return
    }
    guard size > 0 else {
      updateObservedDevices([])
      devices = []
      return
    }
    var ids = [AudioDeviceID](
      repeating: 0,
      count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let status = ids.withUnsafeMutableBytes { bytes in
      AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
    }
    guard status == noErr else {
      error = "Could not read audio outputs (\(status))"
      return
    }
    updateObservedDevices(ids)
    var pairedNames: [String: String] = [:]
    for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
      if let rawAddress = device.addressString,
        let address = BluetoothOutputNaming.address(in: rawAddress), let name = device.name
      {
        pairedNames[address] = name
      }
    }
    devices = ids.filter { id in
      outputChannels(id) > 0 && integer(id, kAudioDevicePropertyDeviceIsAlive) != 0
        && integer(id, kAudioDevicePropertyIsHidden) != 1
        && integer(
          id, kAudioDevicePropertyDeviceCanBeDefaultDevice,
          scope: kAudioDevicePropertyScopeOutput) != 0
    }.map { id in
      let audioName = string(id, kAudioObjectPropertyName) ?? "Audio output"
      let uid = string(id, kAudioDevicePropertyDeviceUID) ?? ""
      let name = BluetoothOutputNaming.name(
        audioName: audioName, uid: uid, pairedNames: pairedNames)
      let model = string(id, kAudioDevicePropertyModelUID) ?? ""
      let transport = integer(id, kAudioDevicePropertyTransportType) ?? 0
      return AudioOutputDevice(
        id: id, name: name,
        symbol: Self.symbol(name: name, model: model, transport: transport),
        nativeIcon: icon(id), bluetoothAddress: BluetoothOutputNaming.address(in: uid))
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  func select(_ device: AudioOutputDevice) {
    let timing = TransitionTiming("output selection")
    defer { timing.end() }
    var address = property(kAudioHardwarePropertyDefaultOutputDevice)
    var settable: DarwinBoolean = false
    guard AudioObjectIsPropertySettable(system, &address, &settable) == noErr,
      settable.boolValue
    else {
      error = "The system output cannot be changed"
      return
    }
    var id = device.id
    let status = AudioObjectSetPropertyData(
      system, &address, 0, nil,
      UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    guard status == noErr else {
      error = "Could not select \(device.name) (\(status))"
      return
    }
    error = nil
  }

  static func symbol(name: String, model: String, transport: UInt32) -> String {
    let identity = (model + " " + name).lowercased().replacingOccurrences(of: " ", with: "")
    if identity.contains("airpodsmax") { return "airpodsmax" }
    if identity.contains("airpodspro") { return "airpodspro" }
    if identity.contains("airpods") { return "airpods" }
    if identity.contains("headphone") || identity.contains("headset") { return "headphones" }
    if transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
    {
      return "wave.3.right"  // Unknown Bluetooth model: use a neutral audio-route icon.
    }
    if transport == kAudioDeviceTransportTypeAirPlay { return "airplay.audio" }
    if transport == kAudioDeviceTransportTypeHDMI
      || transport == kAudioDeviceTransportTypeDisplayPort
    {
      return "display"
    }
    return "speaker.wave.2"
  }

  private func property(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  )
    -> AudioObjectPropertyAddress
  {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope,
      mElement: kAudioObjectPropertyElementMain)
  }

  private func integer(
    _ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> UInt32? {
    var address = property(selector, scope: scope)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value
  }

  private func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = property(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value?.takeRetainedValue() as String?
  }

  private func icon(_ id: AudioObjectID) -> NSImage? {
    var address = property(kAudioDevicePropertyIcon)
    var value: Unmanaged<CFURL>?
    var size = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
      let url = value?.takeRetainedValue()
    else { return nil }
    return NSImage(contentsOf: url as URL)
  }

  private func outputChannels(_ id: AudioDeviceID) -> Int {
    var address = property(
      kAudioDevicePropertyStreamConfiguration,
      scope: kAudioDevicePropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
      size >= MemoryLayout<AudioBufferList>.size
    else { return 0 }
    let memory = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size),
      alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { memory.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory) == noErr else { return 0 }
    let list = memory.assumingMemoryBound(to: AudioBufferList.self)
    return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
  }

  private func observe(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) {
    var address = property(selector, scope: scope)
    guard AudioObjectHasProperty(object, &address) else { return }
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self, self.started else { return }
      self.onChange?()
    }
    if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
      listeners.append((object, address, block))
    }
  }

  private func updateObservedDevices(_ ids: [AudioObjectID]) {
    guard started else { return }
    let wanted = Set(ids)
    let existing = Set(listeners.map { $0.0 }).subtracting([system])
    for (object, original, block) in listeners where object != system && !wanted.contains(object) {
      var address = original
      AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
    listeners.removeAll { $0.0 != system && !wanted.contains($0.0) }
    for id in wanted.subtracting(existing) {
      observe(id, kAudioObjectPropertyName)
      observe(id, kAudioDevicePropertyDeviceIsAlive)
      observe(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
      observe(id, kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
    }
  }

  private func removeListeners() {
    for (object, original, block) in listeners {
      var address = original
      AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
    listeners.removeAll()
  }
}

struct AudioOutputIcon: View {
  let device: AudioOutputDevice?
  var body: some View {
    Group {
      if let device, let icon = device.nativeIcon,
        !device.symbol.hasPrefix("airpods")
      {
        Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit()
      } else {
        Image(systemName: device?.symbol ?? "speaker.wave.2")
          .resizable().scaledToFit()
      }
    }.foregroundStyle(.white).frame(width: 20, height: 20)
  }
}

struct AudioOutputList: View {
  @ObservedObject var outputs: AudioOutputs
  let close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Sound Output").font(.headline)
      ScrollView {
        VStack(spacing: 2) {
          ForEach(outputs.devices) { device in
            Button {
              outputs.select(device)
              if outputs.error == nil { close() }
            } label: {
              HStack(spacing: 10) {
                AudioOutputIcon(device: device)
                Text(device.name).lineLimit(1)
                Spacer()
                if device.id == outputs.selectedID { Image(systemName: "checkmark") }
              }.padding(8).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }
      }.frame(maxHeight: 220)
      if outputs.devices.isEmpty { Text("No connected outputs found").foregroundStyle(.secondary) }
      if let error = outputs.error { Text(error).font(.caption).foregroundStyle(.red) }
    }.padding(14).frame(width: 280).onAppear { outputs.reload() }
  }
}
