import AppKit
import CoreAudio
import Foundation

struct ProcessCaptureError: LocalizedError {
  let operation: String
  let status: OSStatus
  var errorDescription: String? { "\(operation) failed (\(status))" }
}

/// Per-player output capture without screen/window enumeration. Does not mute or reroute playback.
/// Hardware setup/teardown is confined to controlQueue; sample processing uses a separate serial queue.
@available(macOS 14.2, *)
final class ProcessAudioCapture: @unchecked Sendable {
  private let controlQueue = DispatchQueue(label: "com.minnow.process-audio.control")
  private let sampleQueue = DispatchQueue(label: "com.minnow.process-audio.samples", qos: .userInteractive)
  private var tap: AudioObjectID = kAudioObjectUnknown
  private var aggregate: AudioObjectID = kAudioObjectUnknown
  private var ioProc: AudioDeviceIOProcID?
  private let sink: ProcessAudioLevelSink

  init(onLevels: @escaping @Sendable ([Float]) -> Void) {
    sink = ProcessAudioLevelSink(onLevels: onLevels)
  }

  func start(source: MusicSource, pid: pid_t?) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      controlQueue.async {
        do {
          try self.configure(source: source, pid: pid)
          continuation.resume()
        } catch {
          self.cleanup()
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func stop() async {
    await withCheckedContinuation { continuation in
      controlQueue.async {
        self.cleanup()
        continuation.resume()
      }
    }
  }

  private func configure(source: MusicSource, pid: pid_t?) throws {
    let description: CATapDescription
    if #available(macOS 26.0, *) {
      description = CATapDescription(stereoMixdownOfProcesses: [])
      description.bundleIDs = [source.bundleIdentifier]
      description.isProcessRestoreEnabled = true
    } else {
      guard var pid else { throw ProcessCaptureError(operation: "Player process lookup", status: -1) }
      var address = property(kAudioHardwarePropertyTranslatePIDToProcessObject)
      var process: AudioObjectID = kAudioObjectUnknown
      var size = UInt32(MemoryLayout<AudioObjectID>.size)
      try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
        UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process), "Player audio-process lookup")
      guard process != kAudioObjectUnknown else {
        throw ProcessCaptureError(operation: "Player audio-process lookup", status: -1)
      }
      description = CATapDescription(stereoMixdownOfProcesses: [process])
    }
    description.name = "Minnow \(source.displayName) levels"
    description.isPrivate = true
    description.muteBehavior = .unmuted
    try check(AudioHardwareCreateProcessTap(description, &tap), "Create audio tap")

    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var formatAddress = property(kAudioTapPropertyFormat)
    try check(AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &size, &format), "Read audio format")
    guard format.mFormatID == kAudioFormatLinearPCM,
      format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
      throw ProcessCaptureError(operation: "Unsupported audio-tap format", status: -1)
    }

    let tapUID = description.uuid.uuidString
    let configuration: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Minnow Audio Levels",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceTapListKey: [[
        kAudioSubTapUIDKey: tapUID,
        kAudioSubTapDriftCompensationKey: true,
      ]],
    ]
    try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate),
      "Create private audio device")
    let sink = sink
    try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, sampleQueue) {
      _, input, _, _, _ in sink.consume(input)
    }, "Create audio callback")
    guard let ioProc else { throw ProcessCaptureError(operation: "Create audio callback", status: -1) }
    try check(AudioDeviceStart(aggregate, ioProc), "Start audio tap")
  }

  private func cleanup() {
    if let ioProc, aggregate != kAudioObjectUnknown {
      AudioDeviceStop(aggregate, ioProc)
      AudioDeviceDestroyIOProcID(aggregate, ioProc)
    }
    ioProc = nil
    if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
    aggregate = kAudioObjectUnknown
    if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
    tap = kAudioObjectUnknown
  }

  private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }
  private func check(_ status: OSStatus, _ operation: String) throws {
    if status != noErr { throw ProcessCaptureError(operation: operation, status: status) }
  }
}

/// Audio buffers never leave the capture callback; only measured scalar levels reach the UI.
private final class ProcessAudioLevelSink: @unchecked Sendable {
  private var envelope = AudioEnvelope()
  private var lastDelivery = 0.0
  private let onLevels: @Sendable ([Float]) -> Void
  init(onLevels: @escaping @Sendable ([Float]) -> Void) { self.onLevels = onLevels }

  func consume(_ input: UnsafePointer<AudioBufferList>) {
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastDelivery >= 1.0 / 30 else { return }
    var sum = 0.0
    var count = 0
    for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
      guard let data = buffer.mData else { continue }
      let samples = data.assumingMemoryBound(to: Float.self)
      for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
        let value = samples[index]
        guard value.isFinite else { continue }
        sum += Double(value) * Double(value)
        count += 1
      }
    }
    guard count > 0 else { return }
    lastDelivery = now
    onLevels(envelope.consume(rms: Float(sqrt(sum / Double(count)))))
  }
}
