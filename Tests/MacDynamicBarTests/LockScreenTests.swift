import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MacDynamicBar

@Test @MainActor func lockScreenPassThroughKeepsPasswordAndBackgroundOutsidePlayer() {
  let size = CGSize(width: 380, height: 164)
  #expect(LockScreenGeometry.accepts(CGPoint(x: 190, y: 80), size: size))
  #expect(!LockScreenGeometry.accepts(CGPoint(x: -1, y: 80), size: size))
  #expect(!LockScreenGeometry.accepts(CGPoint(x: 190, y: -1), size: size))
  #expect(!LockScreenGeometry.accepts(CGPoint(x: 400, y: 80), size: size))
  let panel = LockMediaPanel(contentRect: CGRect(origin: .zero, size: size),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.isReleasedWhenClosed = false
  defer { panel.close() }
  #expect(!panel.canBecomeKey && !panel.canBecomeMain)
  #expect(panel.styleMask.contains(.nonactivatingPanel))
}

@Test func lyricsRequestsEncodeMetadataAndRejectWrongRecord() throws {
  let request = LyricsRequest(title: "A & B?", artist: "Artist", album: "Album", duration: 180)
  let url = try #require(request.url)
  #expect(url.host == "lrclib.net")
  #expect(
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "A & B?")
  let record = LRCLIBRecord(
    trackName: "A & B?", artistName: "Artist", duration: 181, instrumental: false,
    syncedLyrics: "[00:01]Example", plainLyrics: nil)
  #expect(record.matches(request))
  #expect(
    !record.matches(LyricsRequest(title: "Other", artist: "Artist", album: "Album", duration: 180)))
  #expect(
    !record.matches(LyricsRequest(title: "A & B?", artist: "Artist", album: "Album", duration: 190))
  )
}

@Test @MainActor func lockScreenAndNetworkFeaturesAreExplicitOptIns() throws {
  let name = "MinnowLock.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let settings = MinnowSettings(defaults: defaults)
  #expect(!settings.lockScreenPlayer && !settings.onlineLyrics && !settings.brightnessHUD)
  settings.lockScreenPlayer = true
  settings.onlineLyrics = true
  let restored = MinnowSettings(defaults: defaults)
  #expect(restored.lockScreenPlayer && restored.onlineLyrics)
  restored.resetPreferences()
  #expect(!restored.lockScreenPlayer && !restored.onlineLyrics)
}

@Test func lockScreenLayoutAndHitRegionsFitSmallAndOffsetDisplays() {
  for screen in [
    CGRect(x: 0, y: 0, width: 800, height: 600),
    CGRect(x: -1280, y: -800, width: 1280, height: 800),
    CGRect(x: 0, y: 0, width: 360, height: 480),
    CGRect(x: 0, y: 0, width: 1470, height: 956),
  ] {
    let frame = LockScreenGeometry.playerFrame(screen: screen)
    #expect(screen.contains(frame))
    #expect(frame.minY >= screen.minY + screen.height * 0.24)
    #expect(frame.maxY <= screen.minY + screen.height * 0.74)
    #expect(frame.width <= 380 && frame.height <= 164)
    #expect(frame.midX == screen.midX)
  }
  #expect(LockScreenGeometry.progress(position: 50, duration: 100) == 0.5)
  #expect(LockScreenGeometry.progress(position: .nan, duration: 100) == 0)
  #expect(LockScreenGeometry.progress(position: 10, duration: 0) == 0)
  #expect(LockScreenGeometry.progress(position: 101, duration: 100) == 1)
  #expect(LockScreenGeometry.progress(position: -1, duration: 100) == 0)
}

@Test func lockLifecycleSurvivesSessionDeactivationAndUnknownSnapshots() {
  var state = LockScreenLifecycle()
  state.lockChanged(true)
  #expect(state.canPresent)
  // A session transition without a usable dictionary must not be interpreted as unlock.
  state.reconcile(observedLock: nil, onConsole: nil)
  #expect(state.canPresent)
  state.reconcile(observedLock: true, onConsole: true)
  #expect(state.canPresent)
  state.sessionBecameActive()
  #expect(!state.canPresent)
}

@Test func sleepAndUserSwitchHidePanelsWithoutLosingLockState() {
  var state = LockScreenLifecycle()
  state.lockChanged(true)
  state.sleep()
  #expect(state.locked && !state.canPresent)
  state.wake(observedLock: true, onConsole: true)
  #expect(state.canPresent)
  state.reconcile(observedLock: true, onConsole: false)
  #expect(state.locked && !state.canPresent)
  state.wake(observedLock: nil, onConsole: true)
  #expect(!state.canPresent)
}

@Test func explicitUnlockAndCanonicalUnlockAlwaysRemoveTheOverlay() {
  var state = LockScreenLifecycle()
  state.lockChanged(true)
  state.lockChanged(false)
  #expect(!state.canPresent)
  state.lockChanged(true)
  state.reconcile(observedLock: false, onConsole: true)
  #expect(!state.canPresent)
}

@Test func lockedPlaybackNoticesKeepStateWithoutScriptingOrGuessedDuration() throws {
  let notice = try #require(DesktopPlaybackNotice(userInfo: [
    "Player State": "Playing", "Name": "Track", "Artist": "Artist", "Album": "Album",
    "Track ID": "spotify:track:123", "Playback Position": 14.5, "Duration": 200786,
  ], source: .spotify))
  #expect(notice.playing)
  #expect(notice.track?.id == "spotify:track:123")
  #expect(notice.position == 14.5)
  #expect(notice.duration == nil)
  let music = try #require(DesktopPlaybackNotice(userInfo: [
    "Player State": "Paused", "Name": "Song", "PersistentID": NSNumber(value: 255),
    "Total Time": 180000, "Playback Position": Double.nan,
  ], source: .appleMusic))
  #expect(!music.playing && music.track?.id == "00000000000000FF")
  #expect(music.duration == 180 && music.position == nil)
  #expect(DesktopPlaybackNotice(userInfo: ["Name": "Incomplete"], source: .spotify) == nil)
}

@Test func lockPlacementRequiresPositiveSessionEvidence() {
  #expect(!LockSessionSnapshot(locked: nil, onConsole: true).permitsPlacement)
  #expect(!LockSessionSnapshot(locked: true, onConsole: nil).permitsPlacement)
  #expect(!LockSessionSnapshot(locked: true, onConsole: false).permitsPlacement)
  #expect(!LockSessionSnapshot(locked: false, onConsole: true).permitsPlacement)
  #expect(LockSessionSnapshot(locked: true, onConsole: true).permitsPlacement)
  var state = LockScreenLifecycle()
  state.wake(observedLock: true, onConsole: nil)
  #expect(!state.canPresent)
}

@Test func lockedTransportRequiresAnActualRecognizedSourceState() {
  #expect(LockedPlaybackTransport.Observation(state: "playing", position: 5)?.playing == true)
  #expect(LockedPlaybackTransport.Observation(state: "paused", position: 5)?.playing == false)
  #expect(LockedPlaybackTransport.Observation(state: "stopped", position: -1)?.position == nil)
  #expect(LockedPlaybackTransport.Observation(state: "playing", position: .nan)?.position == nil)
  #expect(LockedPlaybackTransport.Observation(state: nil, position: 0) == nil)
  #expect(LockedPlaybackTransport.Observation(state: "unknown", position: 0) == nil)
}

@MainActor private final class SkyLightFixture {
  var calls: [String] = []
  var failure: String?
  var failureCode: Int32 = -1
  func result(_ name: String) -> Int32 {
    calls.append(name)
    return failure == name ? failureCode : 0
  }
  var functions: SkyLightLockScreenPresenter.Functions {
    .init(connection: { self.calls.append("connection"); return 1 },
      create: { _, _, _ in self.calls.append("create"); return 42 },
      level: { _, space, level in
        #expect(space == 42 && level == 400)
        return self.result("level")
      },
      show: { _, _ in self.calls.append("show") },
      add: { _, _, _, selector in
        #expect(selector == 7)
        return self.result("adopt")
      },
      hide: { _, _ in self.result("hide") },
      destroy: { _, _ in self.result("destroy") })
  }
}

@Test @MainActor func skyLightPlacementReShowsTheSpaceOnWakeAndDestroysItOnUnlock() throws {
  let fixture = SkyLightFixture()
  let presenter = SkyLightLockScreenPresenter(functions: fixture.functions)
  try presenter.place(window: 123, orderWindow: { fixture.calls.append("order") })
  try presenter.place(window: 123, orderWindow: { fixture.calls.append("order") })
  #expect(fixture.calls == ["connection", "create", "level", "show", "order", "adopt", "level", "show", "order", "adopt"])
  try presenter.hide()
  #expect(Array(fixture.calls.suffix(2)) == ["hide", "destroy"])
  let count = fixture.calls.count
  try presenter.hide()
  #expect(fixture.calls.count == count)
  try presenter.place(window: 124)
  #expect(fixture.calls.filter { $0 == "create" }.count == 2)
  try presenter.hide()
}

@Test @MainActor func skyLightFailuresDoNotReportPlacementSuccessAndCleanupStillRuns() throws {
  for operation in ["level", "adopt"] {
    let fixture = SkyLightFixture()
    fixture.failure = operation
    let presenter = SkyLightLockScreenPresenter(functions: fixture.functions)
    #expect(throws: LockScreenPresentationError.self) { try presenter.place(window: 123) }
    try presenter.hide()
    #expect(Array(fixture.calls.suffix(2)) == ["hide", "destroy"])
  }
  let fixture = SkyLightFixture()
  let presenter = SkyLightLockScreenPresenter(functions: fixture.functions)
  #expect(throws: LockScreenPresentationError.self) { try presenter.place(window: 0) }
  #expect(fixture.calls.isEmpty)
  try presenter.place(window: 123)
  fixture.failure = "destroy"
  #expect(throws: LockScreenPresentationError.self) { try presenter.hide() }
  fixture.failure = nil
  try presenter.hide()
  #expect(fixture.calls.filter { $0 == "destroy" }.count == 2)
}

@Test @MainActor func missingSkyLightSymbolsFailClosed() {
  #expect(throws: LockScreenPresentationError.self) {
    try SkyLightLockScreenPresenter.load(resolveSymbol: { _, _ in nil })
  }
}

@MainActor private final class LockPlaybackFixture: DesktopPlayback {
  var track: MusicTrack? = MusicTrack(title: "Compact player", artist: "Layout verification", album: "")
  var isPlaying = true
  var artwork: NSImage?
  var duration: TimeInterval = 180
  var title = "Compact player"
  var subtitle = "Layout verification"
  var canControlPlayback = true
  var lastError: String?
  var onChange: (@MainActor () -> Void)?
  func start() { onChange?() }
  func stop() {}
  func refresh() {}
  func togglePlayback() { isPlaying.toggle(); onChange?() }
  func next() {}
  func previous() {}
  func playbackPosition(at date: Date) -> TimeInterval { 60 }
  func seek(to position: TimeInterval, expectedTrackID: String) {}
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MINNOW_RENDER_LOCK_CARD"] == "1")) @MainActor
func compactLockCardRendersGlassAndFrostedWithoutStartingAnotherMediaSession() async throws {
  let music = LockPlaybackFixture()
  let spotify = LockPlaybackFixture()
  spotify.track = nil
  spotify.isPlaying = false
  let player = MediaPlayer(appleMusic: music, spotify: spotify)
  player.start()
  defer { player.stop() }
  let view = HStack(spacing: 20) {
    ForEach([true, false], id: \.self) { glass in
      LockScreenPlayerView(player: player, useGlass: glass, togglePlayback: {})
        .frame(width: 380, height: 164)
    }
  }.padding(20).background(Color.gray)
  let host = NSHostingView(rootView: view)
  let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 820, height: 204),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  window.contentView = host
  try await Task.sleep(for: .milliseconds(100))
  host.layoutSubtreeIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/ui-checks")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try #require(bitmap.representation(using: .png, properties: [:]))
    .write(to: directory.appendingPathComponent("lock-card.png"))
}

@Test func staleCanonicalLockAfterUnlockCannotRecreateThePanel() {
  var state = LockScreenLifecycle()
  state.lockChanged(true)
  state.lockChanged(false)
  state.reconcile(observedLock: true, onConsole: true)
  #expect(!state.canPresent)
  #expect(state.awaitingUnlockConfirmation)
  state.reconcile(observedLock: false, onConsole: true)
  #expect(!state.canPresent && !state.awaitingUnlockConfirmation)
  state.reconcile(observedLock: true, onConsole: true)
  #expect(state.canPresent) // A later lock can be discovered by polling.
  state.sessionBecameActive()
  state.reconcile(observedLock: true, onConsole: true)
  #expect(!state.canPresent)
}

@Test @MainActor func windowOrderingCanSettleWithoutTurningPendingIntoSuccess() throws {
  let fixture = SkyLightFixture()
  fixture.failure = "adopt"
  fixture.failureCode = -2
  let presenter = SkyLightLockScreenPresenter(functions: fixture.functions)
  do {
    try presenter.place(window: 123)
    Issue.record("Unordered window must not be reported as placed")
  } catch let error as LockScreenPresentationError {
    #expect(error.retryable)
  }
  fixture.failure = nil
  try presenter.place(window: 123)
  #expect(fixture.calls.filter { $0 == "create" }.count == 1)
  try presenter.hide()
}

@MainActor private func playbackResult(_ playing: Bool) -> ScriptResult {
  let value = NSAppleEventDescriptor.list()
  value.insert(NSAppleEventDescriptor(string: playing ? "playing" : "paused"), at: 1)
  value.insert(NSAppleEventDescriptor(int32: 60), at: 2)
  return ScriptResult(value: value, errorCode: nil)
}

@Test @MainActor func lockedTransportSendsOneToggleAndWaitsForAnActualTransition() async {
  for source in MusicSource.allCases {
    for before in [true, false] {
      var scripts: [String] = []
      let result = await LockedPlaybackTransport.toggle(source, before: before, execute: { script in
        scripts.append(script)
        return playbackResult(scripts.count < 3 ? before : !before)
      }, pause: {})
      #expect(result?.playing == !before)
      #expect(scripts.count == 3)
      #expect(scripts.filter { $0.contains("playpause") }.count == 1)
      #expect(scripts.allSatisfy { $0.contains(source.bundleIdentifier) })
    }
  }
}

@Test @MainActor func lockedTransportDoesNotInventSuccessFromAnUnchangedStateOrScriptError() async {
  var reads = 0
  let unchanged = await LockedPlaybackTransport.toggle(.spotify, before: true, execute: { _ in
    reads += 1
    return playbackResult(true)
  }, pause: {})
  #expect(unchanged == nil && reads == 10)
  let denied = await LockedPlaybackTransport.toggle(.appleMusic, before: false, execute: { _ in
    ScriptResult(value: NSAppleEventDescriptor(), errorCode: -1743)
  }, pause: {})
  #expect(denied == nil)
}
