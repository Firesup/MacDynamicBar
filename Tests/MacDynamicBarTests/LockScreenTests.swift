import Foundation
import Testing

@testable import MacDynamicBar

@Test func lockScreenPassThroughKeepsPasswordAndBackgroundOutsidePlayer() {
  let size = CGSize(width: 860, height: 620)
  #expect(
    !LockScreenGeometry.accepts(CGPoint(x: 20, y: 50), size: size, expanded: false, lyrics: false))
  #expect(
    LockScreenGeometry.accepts(CGPoint(x: 430, y: 80), size: size, expanded: false, lyrics: false))
  #expect(
    !LockScreenGeometry.accepts(CGPoint(x: 430, y: 350), size: size, expanded: false, lyrics: false)
  )
  #expect(
    LockScreenGeometry.accepts(CGPoint(x: 430, y: 350), size: size, expanded: true, lyrics: false))
  #expect(
    !LockScreenGeometry.accepts(CGPoint(x: 820, y: 580), size: size, expanded: true, lyrics: false))
  let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
  let frame = LockScreenGeometry.playerFrame(screen: screen)
  #expect(screen.contains(frame))
  #expect(frame.minY >= screen.minY + 170)
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
  ] {
    let frame = LockScreenGeometry.playerFrame(screen: screen)
    #expect(screen.contains(frame))
    let bounds = CGRect(origin: .zero, size: frame.size)
    #expect(bounds.contains(LockScreenGeometry.cardFrame(size: frame.size)))
    for lyrics in [true, false] {
      let artwork = LockScreenGeometry.artworkFrame(size: frame.size, lyrics: lyrics)
      #expect(bounds.contains(artwork))
      #expect(LockScreenGeometry.accepts(CGPoint(x: artwork.midX, y: artwork.midY),
        size: frame.size, expanded: true, lyrics: lyrics))
      if lyrics {
        let text = artwork.offsetBy(dx: artwork.width + 30, dy: 0)
        #expect(bounds.contains(text))
        #expect(LockScreenGeometry.accepts(CGPoint(x: text.midX, y: text.midY),
          size: frame.size, expanded: true, lyrics: true))
        #expect(!LockScreenGeometry.accepts(CGPoint(x: artwork.maxX + 15, y: artwork.midY),
          size: frame.size, expanded: true, lyrics: true))
      }
    }
  }
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
