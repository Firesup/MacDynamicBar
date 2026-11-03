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
