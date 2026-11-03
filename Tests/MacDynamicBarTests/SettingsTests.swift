import Foundation
import Testing

@testable import MacDynamicBar

@Test @MainActor func insetLayoutPreservesExistingAppearancePreferences() throws {
  let suite = "MinnowAppearanceTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  // An existing installation with no layout key keeps its current rendering.
  defaults.set(true, forKey: "islandGlassAppearance")
  defaults.set(true, forKey: "minnowBackgroundBlur")
  defaults.set(0.65, forKey: "islandBackgroundOpacity")
  let settings = MinnowSettings(defaults: defaults)
  #expect(settings.appearanceLayout == .standard)
  settings.appearanceLayout = .glassInset
  let restored = MinnowSettings(defaults: defaults)
  #expect(restored.appearanceLayout == .glassInset)
  restored.appearanceLayout = .standard
  #expect(restored.glass)
  #expect(restored.backgroundBlur)
  #expect(restored.opacity == 0.65)
  restored.resetPreferences()
  #expect(MinnowSettings(defaults: defaults).appearanceLayout == .standard)
  defaults.set("unknown-future-layout", forKey: "islandAppearanceLayout")
  #expect(MinnowSettings(defaults: defaults).appearanceLayout == .standard)
}

@Test func insetGlassLeavesCameraAndCompactWingsOpaque() {
  for width: CGFloat in [212, 340, 400, 600] {
    let header: CGFloat = 38
    #expect(
      InsetGlassGeometry.frame(size: CGSize(width: width, height: header), headerHeight: header)
        .isEmpty)
    #expect(
      InsetGlassGeometry.frame(size: CGSize(width: width, height: header + 8), headerHeight: header)
        .isEmpty)
    let size = CGSize(width: width, height: header + 174)
    let inset = InsetGlassGeometry.frame(size: size, headerHeight: header)
    #expect(CGRect(origin: .zero, size: size).contains(inset))
    #expect(inset.minX == 10)
    #expect(size.width - inset.maxX == 10)
    #expect(inset.minY == 10)
    #expect(size.height - inset.maxY == header + 8)
  }
}

@Test @MainActor func preferencesPersistAndChangeSizing() throws {
  let suite = "MinnowTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  settings.islandEnabled = false
  settings.source = .spotify
  settings.allDisplays = true
  settings.leftAction = .shuffle
  settings.automaticSizing = false
  settings.expandedWidth = 510
  settings.opacity = 0.6
  settings.showMenuBar = false
  settings.hideFullscreen = true
  settings.heartSongColor = true
  settings.notchWidthOffset = 14
  settings.showLeftButton = false
  let restored = MinnowSettings(defaults: defaults)
  #expect(!restored.islandEnabled)
  #expect(restored.source == .spotify)
  #expect(restored.allDisplays)
  #expect(restored.leftAction == .shuffle)
  #expect(restored.configuration.expandedWidth == 510)
  #expect(restored.opacity == 0.6)
  #expect(!restored.showMenuBar)
  #expect(restored.hideFullscreen)
  #expect(restored.heartSongColor)
  #expect(restored.notchWidthOffset == 14)
  #expect(!restored.showLeftButton)
  restored.automaticSizing = true
  #expect(restored.configuration.expandedWidth == 408)
  restored.resetPreferences()
  let reset = MinnowSettings(defaults: defaults)
  #expect(reset.showMenuBar)
  #expect(!reset.hideFullscreen)
  #expect(reset.showLeftButton)
  #expect(!reset.heartSongColor)
  #expect(reset.notchWidthOffset == 0)
}

@Test @MainActor func fullscreenMatchingDistinguishesMaximizedWindows() {
  let display = CGRect(x: 1440, y: -120, width: 1920, height: 1080)
  #expect(FullscreenVisibility.matches(window: display, display: display))
  #expect(
    !FullscreenVisibility.matches(
      window: CGRect(x: 1440, y: -92, width: 1920, height: 1052), display: display))
  #expect(
    FullscreenVisibility.matches(
      window: CGRect(x: 1440, y: -82, width: 1920, height: 1042), display: display,
      systemFullscreen: true))
  #expect(
    !FullscreenVisibility.matches(
      window: CGRect(x: 0, y: 0, width: 1920, height: 1080), display: display))
}

@Test @MainActor func scrubbingKeepsHoverPlayerOpenUntilReleased() async throws {
  let state = IslandState()
  state.configureHover(enabled: true, opensPlayer: true)
  state.setHovered(true)
  #expect(state.isExpanded)
  state.setScrubbing(true)
  state.setHovered(false)
  try await Task.sleep(for: .milliseconds(180))
  #expect(state.isExpanded)
  state.setScrubbing(false)
  try await waitForCondition { state.presentation == .compact }
  #expect(!state.isExpanded)
}

@Test func seekingClampsAndRejectsInvalidInput() throws {
  let end = try #require(
    DesktopSeek.make(
      source: .spotify, trackID: "spotify:track:test",
      position: 500, duration: 200))
  #expect(end.position == 199.95)
  #expect(
    DesktopSeek.make(
      source: .appleMusic, trackID: "test", position: .nan,
      duration: 100) == nil)
  #expect(
    DesktopSeek.make(
      source: .spotify, trackID: "", position: 10,
      duration: 100) == nil)
}
