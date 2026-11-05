import AppKit
import Combine
import CoreMedia
import ScreenCaptureKit
import SwiftUI

// MARK: - Audio-Reactive Playback Levels

/// A short audio envelope history, measured from PCM samples rather than
/// a decorative repeating animation. Kept independent for deterministic tests.
struct AudioEnvelope {
  private(set) var levels = [Float](repeating: 0, count: 5)
  private var averageEnergy: Float = 0
  private var previousEnergy: Float = 0

  mutating func consume(rms: Float) -> [Float] {
    let safe = rms.isFinite ? max(0, rms) : 0
    let energy = min(1, max(0, safe - 0.001))
    averageEnergy += (energy - averageEnergy) * 0.06
    // Emphasize changes relative to the current song's level instead of
    // pinning loud recordings near full height. Peaks receive an extra
    // transient boost; quieter moments fall much closer to the baseline.
    let relative = min(1, energy / max(0.04, averageEnergy * 2.2))
    let transient = max(0, energy - previousEnergy) / max(0.04, averageEnergy)
    let measured = min(1, pow(relative, 1.7) + transient * 0.45)
    previousEnergy = energy
    let previous = levels.last ?? 0
    let smoothing: Float = measured > previous ? 0.92 : 0.60
    let next = previous + (measured - previous) * smoothing
    levels.removeFirst()
    levels.append(next < 0.005 ? 0 : next)
    return levels
  }
}

/// Only this serial capture queue accesses the mutable envelope and timestamp.
/// Callback payloads contain Sendable numbers, never CMSampleBuffer objects.
final class MusicAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate,
  @unchecked Sendable
{
  let onLevels: @Sendable ([Float]) -> Void
  let onStop: @Sendable (String) -> Void
  private var envelope = AudioEnvelope()
  private var lastDelivery = 0.0

  init(
    onLevels: @escaping @Sendable ([Float]) -> Void,
    onStop: @escaping @Sendable (String) -> Void
  ) {
    self.onLevels = onLevels
    self.onStop = onStop
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    onStop(error.localizedDescription)
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .audio, sampleBuffer.isValid,
      let format = CMSampleBufferGetFormatDescription(sampleBuffer),
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format),
      asbd.pointee.mFormatID == kAudioFormatLinearPCM,
      asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
      asbd.pointee.mBitsPerChannel == 32
    else { return }

    // ScreenCaptureKit supplies native-endian float PCM. The returned
    // block buffer keeps the audio storage alive until analysis finishes.
    var required = 0
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, bufferListSizeNeededOut: &required,
      bufferListOut: nil, bufferListSize: 0,
      blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
      flags: 0, blockBufferOut: nil)
    guard required > 0 else { return }
    let memory = UnsafeMutableRawPointer.allocate(
      byteCount: required, alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { memory.deallocate() }
    let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
    var block: CMBlockBuffer?
    let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, bufferListSizeNeededOut: nil,
      bufferListOut: list, bufferListSize: required,
      blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &block)
    guard result == noErr else { return }

    let now = CACurrentMediaTime()
    guard now - lastDelivery >= 1.0 / 30.0 else { return }
    lastDelivery = now
    var sum = 0.0
    var count = 0
    withExtendedLifetime(block) {
      for buffer in UnsafeMutableAudioBufferListPointer(list) {
        guard let data = buffer.mData else { continue }
        let samples = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        // Square channels separately so opposite-phase stereo does
        // not cancel out and incorrectly appear silent.
        for index in 0..<sampleCount {
          let sample = samples[index]
          guard sample.isFinite else { continue }
          sum += Double(sample) * Double(sample)
          count += 1
        }
      }
    }
    guard count > 0 else { return }
    onLevels(envelope.consume(rms: Float(sqrt(sum / Double(count)))))
  }
}

@MainActor
final class MusicAudioLevels: ObservableObject {
  @Published private(set) var levels = [Float](repeating: 0, count: 5)
  @Published private(set) var isEnabled: Bool
  @Published private(set) var hasAudioSignal = false
  @Published private(set) var status: String
  @Published private(set) var failureDetail: String?
  private var captureFailed = false

  static func failureStatus(domain: String, code: Int) -> String {
    if domain == SCStreamErrorDomain && code == -3801 {
      return "Capture permission needs refreshing — see Media settings"
    }
    return "Audio capture unavailable — see Media settings"
  }
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // First launch should request capture when Music plays. Respect an
    // explicit saved choice to turn the feature off.
    let enabled = defaults.object(forKey: "audioReactiveWavesEnabled") as? Bool ?? true
    isEnabled = enabled
    status = enabled ? "Waiting for audio" : "Audio-reactive waves off"
  }

  private var processCapture: AnyObject?
  @Published private(set) var backend = "Not capturing"
  private var stream: SCStream?
  private var output: MusicAudioOutput?
  private let audioQueue = DispatchQueue(
    label: "com.minnow.audio-levels",
    qos: .userInteractive)
  private var wantsPlayback = false
  private var captureSource: MusicSource?
  private var sourceName: String { captureSource?.displayName ?? "player" }
  private var suspended = false
  private var generation = 0
  private var reconcileTask: Task<Void, Never>?
  private var silenceTask: Task<Void, Never>?
  private var firstSampleTask: Task<Void, Never>?

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    defaults.set(enabled, forKey: "audioReactiveWavesEnabled")
    status = enabled ? "Waiting for playback" : "Audio-reactive waves off"
    requestUpdate()
  }

  func setPlayback(_ target: AudioCaptureTarget) {
    guard wantsPlayback != target.isPlaying || captureSource != target.source else { return }
    wantsPlayback = target.isPlaying
    captureSource = target.source
    requestUpdate()
  }

  func setSuspended(_ value: Bool) {
    guard suspended != value else { return }
    suspended = value
    requestUpdate()
  }

  func retry() {
    guard isEnabled else { return }
    requestUpdate()
  }

  /// Recheck after a permission change without restarting a healthy capture stream.
  func retryAfterPermissionChange() {
    guard captureFailed, CGPreflightScreenCaptureAccess() else { return }
    retry()
  }

  func stop() {
    isEnabled = false  // Does not change the saved user preference.
    wantsPlayback = false
    requestUpdate()
  }

  private var shouldCapture: Bool {
    isEnabled && wantsPlayback && captureSource != nil && !suspended
  }

  private func requestUpdate() {
    generation += 1
    silenceTask?.cancel()
    firstSampleTask?.cancel()
    hasAudioSignal = false
    levels = Array(repeating: 0, count: 5)
    // Serialize asynchronous start/stop operations. A changed generation
    // causes the in-flight setup to be discarded before it can publish.
    guard reconcileTask == nil else { return }
    reconcileTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while true {
        let version = self.generation
        await self.reconcile(version: version)
        if version == self.generation { break }
      }
      self.reconcileTask = nil
    }
  }

  private func reconcile(version: Int) async {
    if #available(macOS 14.2, *), let oldCapture = processCapture as? ProcessAudioCapture {
      processCapture = nil
      await oldCapture.stop()
    }
    if let oldStream = stream {
      stream = nil
      try? await oldStream.stopCapture()
      output = nil
    }
    guard version == generation else { return }
    guard shouldCapture else {
      captureFailed = false
      failureDetail = nil
      status = isEnabled ? "Waiting for playback" : "Audio-reactive waves off"
      return
    }
    captureFailed = false
    failureDetail = nil
    status = "Starting audio capture…"
    do {
      if #available(macOS 14.2, *) {
        guard let source = captureSource else { return }
        backend = "Core Audio process tap"
        let candidate = ProcessAudioCapture { [weak self] values in
          Task { @MainActor [weak self] in
            guard let self, self.generation == version, self.shouldCapture else { return }
            self.receive(values)
          }
        }
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier)
          .first?.processIdentifier
        try await candidate.start(source: source, pid: pid)
        guard version == generation, shouldCapture else {
          await candidate.stop()
          return
        }
        processCapture = candidate
        status = "Waiting for audio"
        scheduleFirstSampleCheck(version: version)
        return
      }
      backend = "ScreenCaptureKit (macOS 14.0–14.1)"
      // macOS handles capture consent here. Audio follows the active app;
      // no microphone, screen output handler or file writer is added.
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
      guard version == generation, shouldCapture else { return }
      guard let source = captureSource,
        let display = content.displays.first,
        let application = content.applications.first(where: {
          $0.bundleIdentifier == source.bundleIdentifier
        })
      else {
        status = "Active player's audio is not available"
        return
      }
      let filter = SCContentFilter(
        display: display, including: [application],
        exceptingWindows: [])
      let configuration = SCStreamConfiguration()
      configuration.capturesAudio = true
      configuration.excludesCurrentProcessAudio = true
      configuration.sampleRate = 48000
      configuration.channelCount = 2
      configuration.width = 2
      configuration.height = 2
      configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
      configuration.showsCursor = false

      let sink = MusicAudioOutput(
        onLevels: { [weak self] values in
          Task { @MainActor [weak self] in
            guard let self, self.generation == version,
              self.shouldCapture
            else { return }
            self.receive(values)
          }
        },
        onStop: { [weak self] message in
          Task { @MainActor [weak self] in
            guard let self, self.generation == version else { return }
            self.levels = Array(repeating: 0, count: 5)
            self.hasAudioSignal = false
            self.firstSampleTask?.cancel()
            self.silenceTask?.cancel()
            self.captureFailed = true
            self.failureDetail = message
            self.status = "Audio capture stopped — retry in Media settings"
          }
        })
      let candidate = SCStream(
        filter: filter, configuration: configuration,
        delegate: sink)
      try candidate.addStreamOutput(
        sink, type: .audio,
        sampleHandlerQueue: audioQueue)
      try await candidate.startCapture()
      guard version == generation, shouldCapture else {
        try? await candidate.stopCapture()
        return
      }
      output = sink
      stream = candidate
      status = "Waiting for audio"
      scheduleFirstSampleCheck(version: version)
    } catch {
      guard version == generation else { return }
      let detail = error as NSError
      captureFailed = true
      failureDetail = "\(detail.domain) (\(detail.code)): \(detail.localizedDescription)"
      status = Self.failureStatus(domain: detail.domain, code: detail.code)
      levels = Array(repeating: 0, count: 5)
    }
  }

  private func scheduleFirstSampleCheck(version: Int) {
    firstSampleTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      guard let self, self.generation == version else { return }
      self.status = "No player audio received — see Media settings"
    }
  }

  private func receive(_ values: [Float]) {
    firstSampleTask?.cancel()
    firstSampleTask = nil
    levels = values
    hasAudioSignal = values.contains { $0 > 0.01 }
    status = hasAudioSignal ? "Listening to \(sourceName)" : "\(sourceName) is sending silent audio"
    silenceTask?.cancel()
    // Some sources stop sending samples during silence. A one-shot reset
    // prevents frozen bars; it does not poll Music or the capture stream.
    silenceTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      self?.levels = Array(repeating: 0, count: 5)
      self?.hasAudioSignal = false
      self?.status = "Waiting for audio"
    }
  }
}

struct PlaybackIndicator: View {
  let isPlaying: Bool
  @ObservedObject var audio: MusicAudioLevels
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .center, spacing: 1.5) {
      ForEach(0..<5, id: \.self) { index in
        Capsule()
          .fill(isPlaying ? Color.pink : Color.gray)
          .frame(width: 2.5, height: barHeight(index))
      }
    }
    .frame(width: 18.5, height: 22)
    .animation(reduceMotion ? nil : .linear(duration: 0.045), value: audio.levels)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    .help(audio.status)
  }

  private func barHeight(_ index: Int) -> CGFloat {
    guard isPlaying, !reduceMotion else { return 4 }
    // Uneven visual weighting creates stronger high/low contrast between
    // neighbours while every bar remains driven by captured audio.
    let emphasis: [CGFloat] = [0.65, 1, 0.80, 1, 0.60]
    return 2 + CGFloat(audio.levels[index]) * 20 * emphasis[index]
  }
}


struct AudioCaptureStatusView: View {
  @ObservedObject var audio: MusicAudioLevels
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(audio.backend + " · " + audio.status).font(.caption).foregroundStyle(.secondary)
      if let detail = audio.failureDetail {
        Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        Text("If Minnow is already enabled in Screen & System Audio Recording, the permission may belong to an earlier development build. Remove that Minnow entry, add this workspace's .build/Minnow.app again, then quit and reopen Minnow. Rebuilding an ad-hoc signed app can invalidate its capture permission. On macOS 14.2 and later, Minnow uses System Audio Recording access for a per-player Core Audio tap.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Open Capture Settings…") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
          }
        }
      }
    }
  }
}
