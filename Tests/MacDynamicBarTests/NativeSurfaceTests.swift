import Foundation
import Testing

@testable import MacDynamicBar

@Test func connectedCompactNotchCoversCameraAndTouchesTop() {
  let size = CGSize(width: 196, height: 38)
  let path = IslandShapeGeometry.path(size: size, radius: 14, shape: .notch, expansion: 0)
  #expect(path.contains(CGPoint(x: 8, y: 37.9)))
  #expect(path.contains(CGPoint(x: size.width - 8, y: 37.9)))
  #expect(path.contains(CGPoint(x: size.width / 2, y: 1)))
  #expect(!path.contains(CGPoint(x: 1, y: 1)))
  let layout = IslandLayout(
    screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), notchWidth: 180, notchHeight: 38)
  #expect(layout.size(for: .compact).width - 16 >= 180)
  #expect(layout.size(for: .expanded).height == 174)
  #expect(layout.size(for: .expanded).width == 408)
}

@Test @MainActor func activitiesFollowPowerAndDoNotFabricatePercentages() {
  let store = ActivityStore()
  #expect(store.entries.isEmpty)
  store.preview()
  #expect(store.primary?.isPreview == true)
  store.clear()
}

@Test func syncedLyricsHandleFractionsOffsetsRepeatsAndMalformedInput() {
  let lines = SyncedLyrics.parse(
    "[offset:-500]\n[00:01.50][00:03.250]Example line\n[bad]ignored\n[00:99.00]bad\n[00:03.250]Replacement"
  )
  #expect(lines.count == 2)
  #expect(lines[0].time == 1)
  #expect(lines[1].time == 2.75)
  #expect(lines[1].text == "Replacement")
  #expect(SyncedLyrics.currentIndex(in: lines, at: 0) == nil)
  #expect(SyncedLyrics.currentIndex(in: lines, at: 1) == 0)
  #expect(SyncedLyrics.currentIndex(in: lines, at: 10) == 1)
  #expect(SyncedLyrics.currentIndex(in: lines, at: .nan) == nil)
  #expect(SyncedLyrics.parse("[ar:Artist]\nNo timestamp").isEmpty)
}

@Test @MainActor func popupDurationDefaultsToTwoSecondsAndPreferencesPersist() throws {
  let suite = "MinnowNative.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  #expect(settings.popupDuration == 2)
  #expect(settings.showActivities)
  settings.popupDuration = 5
  settings.showActivities = false
  let restored = MinnowSettings(defaults: defaults)
  #expect(restored.popupDuration == 5)
  #expect(!restored.showActivities)
}

@Test @MainActor func volumeHUDRefreshesDuringRapidChanges() {
  let popups = PopupCoordinator(automaticallyDismiss: false)
  popups.submit(
    IslandPopup(
      kind: .hud, key: "hud.volume", title: "Volume", subtitle: "", symbol: "speaker.wave.2.fill",
      percentage: 20))
  popups.submit(
    IslandPopup(
      kind: .hud, key: "hud.volume", title: "Volume", subtitle: "", symbol: "speaker.wave.2.fill",
      percentage: 40))
  #expect(popups.active?.percentage == 40)
  #expect(popups.pending.isEmpty)
}
