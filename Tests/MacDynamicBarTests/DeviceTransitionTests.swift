import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MacDynamicBar

private actor CaptureFixture: ProcessCapturing {
  private(set) var starts = 0
  private(set) var stops = 0
  var pending: CheckedContinuation<Void, Error>?
  func start(source: MusicSource, pid: pid_t?) async throws {
    starts += 1
    try await withCheckedThrowingContinuation { pending = $0 }
  }
  func finish(failing: Bool = false) {
    let continuation = pending
    pending = nil
    if failing {
      continuation?.resume(throwing: ProcessCaptureError(operation: "fixture", status: -1))
    } else {
      continuation?.resume()
    }
  }
  func stop() async { stops += 1 }
}

@MainActor private func eventually(_ condition: () async -> Bool) async throws {
  for _ in 0..<200 {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("Transition did not settle")
}

@Test @MainActor func supersededCaptureStartStopsBeforeNewStartAndInteractionKeepsWorking()
  async throws
{
  let suite = "MinnowTransitions.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(true, forKey: "audioReactiveWavesEnabled")
  let first = CaptureFixture()
  let second = CaptureFixture()
  var creations = 0
  let audio = MusicAudioLevels(defaults: defaults) { _ in
    creations += 1
    return creations == 1 ? first : second
  }
  audio.setPlayback(AudioCaptureTarget(source: .spotify, isPlaying: true))
  try await eventually { await first.starts == 1 }
  // Duplicate notices must not invalidate a setup that's already in flight.
  for _ in 0..<20 { audio.setPlayback(AudioCaptureTarget(source: .spotify, isPlaying: true)) }
  let state = IslandState()
  state.toggle()
  state.setScrubbing(true)
  state.page = .today
  state.collapse()
  state.toggle()
  #expect(state.isExpanded && !state.isInteractionBusy)
  audio.setPlayback(AudioCaptureTarget(source: .appleMusic, isPlaying: true))
  await first.finish()
  try await eventually { await second.starts == 1 }
  #expect(await first.stops == 1)
  #expect(creations == 2)
  await second.finish()
  try await eventually { audio.status == "Waiting for audio" }
  audio.stop()
  try await eventually { await second.stops == 1 }
  #expect(defaults.bool(forKey: "audioReactiveWavesEnabled"))
}

@Test @MainActor func captureStopDuringSetupAndFailureCanRecover() async throws {
  let suite = "MinnowCaptureRecovery.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(true, forKey: "audioReactiveWavesEnabled")
  let fixture = CaptureFixture()
  let audio = MusicAudioLevels(defaults: defaults) { _ in fixture }
  audio.setPlayback(AudioCaptureTarget(source: .spotify, isPlaying: true))
  try await eventually { await fixture.starts == 1 }
  audio.setSuspended(true)
  await fixture.finish()
  try await eventually { await fixture.stops == 1 }
  #expect(audio.failureDetail == nil)
  audio.setSuspended(false)
  try await eventually { await fixture.starts == 2 }
  await fixture.finish(failing: true)
  try await eventually { audio.failureDetail != nil }
  audio.retry()
  try await eventually { await fixture.starts == 3 }
  await fixture.finish()
  try await eventually { audio.failureDetail == nil && audio.status == "Waiting for audio" }
  audio.setSpotifyLocation(.remote("Test phone"))
  try await eventually { await fixture.stops == 2 }
  #expect(audio.remotePlaybackName == "Test phone")
  audio.setSpotifyLocation(.local)
  try await eventually { await fixture.starts == 4 }
  audio.stop()
  await fixture.finish()
  try await eventually { await fixture.stops == 3 }
}

@Test func spotifyIdentityNeverUsesComputerTypeNameOrSilenceAsLocalEvidence() throws {
  func details(_ json: String) throws -> SpotifyPlaybackDetails {
    try JSONDecoder().decode(SpotifyPlaybackDetails.self, from: Data(json.utf8))
  }
  let desktop = try details(
    #"{"is_playing":true,"device":{"id":"a","name":"This Mac","type":"Computer"}}"#)
  #expect(SpotifyPlaybackLocation.resolve(desktop) == .unknown)
  #expect(SpotifyPlaybackLocation.resolve(desktop, localDeviceID: "a") == .local)
  #expect(SpotifyPlaybackLocation.resolve(desktop, localDeviceID: "b") == .remote("This Mac"))
  let phone = try details(
    #"{"is_playing":true,"device":{"id":"b","name":"Test phone","type":"Smartphone"}}"#)
  #expect(SpotifyPlaybackLocation.resolve(phone) == .remote("Test phone"))
  let paused = try details(
    #"{"is_playing":false,"device":{"id":"b","name":"Test phone","type":"Smartphone"}}"#)
  #expect(SpotifyPlaybackLocation.resolve(paused) == .unknown)
  #expect(
    SpotifyPlaybackLocation.resolve(SpotifyPlaybackDetails(repeatMode: nil, item: nil)) == .unknown)
}

@Test @MainActor func allInteractionFlagsClearOnCollapse() {
  let state = IslandState()
  state.toggle()
  state.isOutputPickerOpen = true
  state.setScrubbing(true)
  state.setCompletingReminder(true)
  state.beginShelfDrop()
  state.collapse()
  #expect(!state.isInteractionBusy)
  state.toggle()
  #expect(state.isExpanded)
}

@Test @MainActor func musicKeepsCompactHeightWhileOtherPagesHaveTheirOwnBounds() throws {
  let suite = "MinnowPageSize.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  let music = settings.configuration.expandedContentHeight
  settings.calendarEnabled = true
  settings.shelfEnabled = true
  #expect(settings.configuration.expandedContentHeight == music)
  #expect(settings.contentHeight(for: .music) == music + 28)  // navigation only
  #expect(settings.contentHeight(for: .today) == 232)
  #expect(settings.contentHeight(for: .shelf) == 232)
  settings.automaticSizing = false
  settings.expandedHeight = 400
  #expect(settings.contentHeight(for: .today) <= 360)
  #expect(settings.contentHeight(for: .shelf) == 428)
}

@Test @MainActor func savedWaveformPreferenceWinsOverBuildDefault() throws {
  let suite = "MinnowWaveformDefault.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  #if DEBUG
  #expect(WaveformDefaults.enabled)
  #else
  #expect(!WaveformDefaults.enabled)
  #endif
  #expect(MusicAudioLevels(defaults: defaults).isEnabled == WaveformDefaults.enabled)
  for saved in [false, true] {
    defaults.set(saved, forKey: "audioReactiveWavesEnabled")
    #expect(MusicAudioLevels(defaults: defaults).isEnabled == saved)
    #expect(MinnowSettings(defaults: defaults).audioReactive == saved)
  }
}

@Test @MainActor func duplicateOutputNoticesDoNotRestartCaptureAndLateSamplesAreIgnored()
  async throws
{
  let suite = "MinnowOutputDuplicates.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(true, forKey: "audioReactiveWavesEnabled")
  let fixture = CaptureFixture()
  var deliver: (@Sendable ([Float]) -> Void)?
  let audio = MusicAudioLevels(defaults: defaults) { onLevels in
    deliver = onLevels
    return fixture
  }
  audio.outputChanged(1)
  audio.setPlayback(AudioCaptureTarget(source: .spotify, isPlaying: true))
  try await eventually { await fixture.starts == 1 }
  await fixture.finish()
  try await eventually { audio.status == "Waiting for audio" }
  for _ in 0..<100 { audio.outputChanged(1) }
  #expect(await fixture.starts == 1)
  audio.outputChanged(2)
  try await eventually { await fixture.starts == 2 }
  let obsoleteDelivery = deliver
  audio.setSuspended(true)
  obsoleteDelivery?([1, 1, 1, 1, 1])
  await fixture.finish()
  try await eventually { await fixture.stops == 2 }
  #expect(!audio.hasAudioSignal && audio.levels.allSatisfy { $0 == 0 })
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MINNOW_TIMING_CHECK"] == "1"))
@MainActor func blockingScriptWorkerLeavesMainActorAvailable() async throws {
  _ = NSApplication.shared
  let clock = ContinuousClock()
  let start = clock.now
  let task = Task { await PlaybackScriptWorker.shared.execute("delay 0.25\nreturn 42") }
  try await Task.sleep(for: .milliseconds(30))
  let state = IslandState()
  state.toggle()
  let interaction = start.duration(to: clock.now)
  let result = await task.value
  #expect(state.isExpanded)
  #expect(result.errorCode == nil && result.value.int32Value == 42)
  #expect(interaction < .milliseconds(200))
  let workerCompletion = start.duration(to: clock.now)
  let baselineStart = clock.now
  var baselineError: NSDictionary?
  _ = NSAppleScript(source: "delay 0.25\nreturn 42")?.executeAndReturnError(&baselineError)
  #expect(baselineError == nil)
  print("Legacy inline script blocks main actor for \(baselineStart.duration(to: clock.now))")
  print(
    "Script-worker responsiveness: UI interaction at \(interaction), worker completed at \(workerCompletion)"
  )
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MINNOW_RENDER_TABS"] == "1"))
@MainActor func tabsRenderOnDarkSurfaceUnderBothSystemAppearancesAndContrastSettings() throws
{
  let suite = "MinnowTabAppearance.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  settings.calendarEnabled = true
  settings.shelfEnabled = true
  let state = IslandState()
  let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
      ".build/ui-checks")
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  for scheme in [ColorScheme.light, .dark] {
    for contrast in [ColorSchemeContrast.standard, .increased] {
      for page in [IslandPage.music, .today, .shelf] {
        state.page = page
        let host = NSHostingView(
          rootView: TodayPageSwitch(state: state, settings: settings)
            .frame(width: 408, height: 40).background(.black))
        let appearance: NSAppearance.Name =
          contrast == .increased
          ? (scheme == .light ? .accessibilityHighContrastAqua : .accessibilityHighContrastDarkAqua)
          : (scheme == .light ? .aqua : .darkAqua)
        host.appearance = NSAppearance(named: appearance)
        host.frame = CGRect(x: 0, y: 0, width: 408, height: 40)
        let window = NSWindow(
          contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var readablePixels = 0
        for y in 0..<bitmap.pixelsHigh {
          for x in 0..<bitmap.pixelsWide {
            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
              min(color.redComponent, color.greenComponent, color.blueComponent) > 0.7
            {
              readablePixels += 1
            }
          }
        }
        #expect(readablePixels > 150)
        let name = "tabs-\(scheme)-\(contrast)-\(page.rawValue).png"
        try #require(bitmap.representation(using: .png, properties: [:])).write(
          to: output.appendingPathComponent(name))
      }
    }
  }
}
