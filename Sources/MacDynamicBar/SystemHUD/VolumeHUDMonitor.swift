import CoreAudio
import Foundation

/// Observes changes; never intercepts keys or changes system volume.
@MainActor final class VolumeHUDMonitor {
  var onEvent: ((IslandPopup) -> Void)?
  private let worker = VolumeHUDWorker()
  private var generation = 0
  func start() {
    let version = generation
    worker.queue.async { [worker, weak self] in
      worker.onEvent = { [weak self] event in
        Task { @MainActor in
          guard let self, self.generation == version else { return }
          self.onEvent?(event)
        }
      }
      worker.start()
    }
  }
  func stop() {
    generation += 1
    worker.queue.async { [worker] in worker.stop() }
  }
}

private final class VolumeHUDWorker: @unchecked Sendable {
  let queue = DispatchQueue(label: "com.minnow.volume-monitor")
  var onEvent: (@Sendable (IslandPopup) -> Void)?
  private var listeners:
    [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
  private var started = false
  private var last: Int?
  private var device: AudioObjectID = 0
  func start() {
    guard !started else { return }
    started = true
    watch(
      AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice,
      scope: kAudioObjectPropertyScopeGlobal)
    bindDevice()
  }
  private func bindDevice() {
    for (id, var address, block) in listeners where id != AudioObjectID(kAudioObjectSystemObject) {
      AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
    }
    listeners.removeAll { $0.0 != AudioObjectID(kAudioObjectSystemObject) }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
    else { return }
    last = read()
    watch(
      device, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
    watch(device, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
  }
  private func watch(
    _ id: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope
  ) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      do {
        guard let self, self.started else { return }
        if selector == kAudioHardwarePropertyDefaultOutputDevice {
          self.bindDevice()
          return
        }
        guard let value = self.read(), value != self.last else { return }
        self.last = value
        self.onEvent?(
          IslandPopup(
            kind: .hud, key: "hud.volume", title: "Volume",
            subtitle: value == 0 ? "Muted" : "Sound output",
            symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", percentage: value))
      }
    }
    if AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr {
      listeners.append((id, address, block))
    }
  }
  private func read() -> Int? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain)
    var mute: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr, mute != 0 {
      return 0
    }
    address.mSelector = kAudioDevicePropertyVolumeScalar
    var value: Float32 = 0
    size = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
      value.isFinite
    else { return nil }
    return Int((min(1, max(0, value)) * 100).rounded())
  }
  func stop() {
    started = false
    for (id, var address, block) in listeners {
      AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
    }
    listeners.removeAll()
    last = nil
  }
}
