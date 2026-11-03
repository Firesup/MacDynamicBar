import Foundation
import Testing

@testable import MacDynamicBar

@Test @MainActor func subtleHoverIsDefaultAndFullHoverTakesPriority() throws {
  let suite = "MinnowHover.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  #expect(settings.slightHover)
  #expect(!settings.expandOnHover)
  let state = IslandState(hoverEnabled: settings.configuration.hoverEnabled)
  state.configureHover(
    enabled: settings.configuration.hoverEnabled, opensPlayer: settings.expandOnHover)
  state.setHovered(true)
  #expect(state.presentation == .hover)
  settings.expandOnHover = true
  state.configureHover(
    enabled: settings.configuration.hoverEnabled, opensPlayer: settings.expandOnHover)
  #expect(state.isExpanded)
  settings.expandOnHover = false
  state.configureHover(
    enabled: settings.configuration.hoverEnabled, opensPlayer: settings.expandOnHover)
  #expect(state.presentation == .hover)
  settings.slightHover = false
  state.configureHover(
    enabled: settings.configuration.hoverEnabled, opensPlayer: settings.expandOnHover)
  #expect(state.presentation == .compact)
}

@Test func clearGlassGetsStrongerAutomaticTextContrast() {
  let opaque = IslandTextContrast.resolve(translucent: false, tint: 1, increased: false)
  let darkGlass = IslandTextContrast.resolve(translucent: true, tint: 1, increased: false)
  let clearGlass = IslandTextContrast.resolve(translucent: true, tint: 0.35, increased: false)
  let accessible = IslandTextContrast.resolve(translucent: true, tint: 0.35, increased: true)
  #expect(clearGlass.shadowOpacity > darkGlass.shadowOpacity)
  #expect(clearGlass.secondaryOpacity > opaque.secondaryOpacity)
  #expect(accessible.shadowOpacity > clearGlass.shadowOpacity)
  #expect(accessible.secondaryOpacity == 1)
  #expect(
    IslandTextContrast.resolve(translucent: true, tint: .nan, increased: false).shadowOpacity
      .isFinite)
}

@Test func spotifyArtistRoutesAreValidatedAndSearchIsEncoded() throws {
  let id = "1234567890abcdefghijkl"
  let exact = try #require(MediaNavigation.artistURL(name: "Artist", uri: "spotify:artist:" + id))
  #expect(exact.absoluteString == "spotify:artist:" + id)
  #expect(
    MediaNavigation.artistURL(name: "Artist", uri: "spotify:artist:" + id, web: true)?.host
      == "open.spotify.com")
  #expect(MediaNavigation.artistID(from: "javascript:alert(1)") == nil)
  #expect(MediaNavigation.artistID(from: "spotify:artist:../../bad") == nil)
  #expect(MediaNavigation.artistURL(name: "  ", uri: nil) == nil)
  let search = try #require(
    MediaNavigation.artistURL(name: "AC/DC & Friends?", uri: nil, web: true))
  #expect(search.host == "open.spotify.com")
  #expect(search.query == nil)
  #expect(search.fragment == nil)
  #expect(search.absoluteString.contains("AC%2FDC%20%26%20Friends%3F"))
}

@Test func spotifyMetadataNeverLinksToADifferentTracksArtist() throws {
  let data = Data(
    #"{"repeat_state":"off","item":{"uri":"spotify:track:abc","explicit":true,"artists":[{"name":"Artist","uri":"spotify:artist:1234567890abcdefghijkl"}]}}"#
      .utf8)
  let details = try JSONDecoder().decode(SpotifyPlaybackDetails.self, from: data)
  #expect(details.artists(matching: "spotify:track:abc").count == 1)
  #expect(details.artists(matching: "spotify:track:different").isEmpty)
  #expect(details.artists(matching: nil).isEmpty)
  let episode = try JSONDecoder().decode(
    SpotifyPlaybackDetails.self,
    from: Data(#"{"item":{"uri":"spotify:episode:abc"}}"#.utf8))
  #expect(episode.artists(matching: "spotify:episode:abc").isEmpty)
}

@Test func notchConnectsToTopAndKeepsCompactShape() {
  let size = CGSize(width: 400, height: 212)
  let pill = IslandShapeGeometry.path(size: size, radius: 32, shape: .applePill, expansion: 1)
  let notch = IslandShapeGeometry.path(size: size, radius: 32, shape: .notch, expansion: 1)
  #expect(!pill.contains(CGPoint(x: 10, y: 211.9)))
  #expect(notch.contains(CGPoint(x: 10, y: 211.9)))
  #expect(!notch.contains(CGPoint(x: 1, y: 100)))
  #expect(notch.contains(CGPoint(x: 200, y: 100)))
  let compact = IslandShapeGeometry.path(
    size: CGSize(width: 232, height: 38), radius: 14, shape: .notch, expansion: 0)
  #expect(compact.contains(CGPoint(x: 8, y: 37.9)))
  let shoulder = IslandShapeGeometry.shoulder(size: size, expansion: 1)
  let glass = InsetGlassGeometry.frame(size: size, headerHeight: 38, sideInset: 10 + shoulder)
  #expect(glass.minX - shoulder == 10)
  #expect(size.width - shoulder - glass.maxX == 10)
}

@Test @MainActor func appearanceShapeAndGradientPersistWithoutChangingDefaults() throws {
  let suite = "MinnowShape.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  #expect(settings.islandShape == .notch)
  #expect(settings.appearanceLayout == .standard)
  settings.islandShape = .notch
  settings.appearanceLayout = .softGradient
  let restored = MinnowSettings(defaults: defaults)
  #expect(restored.islandShape == .notch)
  #expect(restored.configuration.shape == .notch)
  #expect(restored.appearanceLayout == .softGradient)
  restored.resetPreferences()
  #expect(restored.islandShape == .notch)
  #expect(restored.appearanceLayout == .standard)
  #expect(restored.slightHover)
}

@Test @MainActor func closingIslandAlsoDismissesOutputPicker() {
  let state = IslandState()
  state.toggle()
  state.isOutputPickerOpen = true
  state.collapse()
  #expect(!state.isOutputPickerOpen)
  #expect(state.presentation == .compact)
}

@Test func gradientRevealsBackgroundWithoutFadingTheCompactHeader() {
  #expect(
    SoftGradientAppearance.bottomOpacity(visibility: 0, expansion: 1, reduceTransparency: false)
      == 1)
  #expect(
    abs(
      SoftGradientAppearance.bottomOpacity(
        visibility: 0.45, expansion: 1, reduceTransparency: false) - 0.55) < 0.001)
  #expect(
    SoftGradientAppearance.bottomOpacity(visibility: 0.85, expansion: 0, reduceTransparency: false)
      == 1)
  #expect(
    SoftGradientAppearance.bottomOpacity(visibility: 0.85, expansion: 1, reduceTransparency: true)
      == 1)
  #expect(
    SoftGradientAppearance.bottomOpacity(
      visibility: .nan, expansion: .infinity, reduceTransparency: false
    ).isFinite)
}

@Test @MainActor func gradientVisibilityPersistsIndependentlyFromGlassTint() throws {
  let suite = "MinnowGradient.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  settings.opacity = 0.8
  settings.gradientVisibility = 0.7
  let restored = MinnowSettings(defaults: defaults)
  #expect(restored.opacity == 0.8)
  #expect(restored.gradientVisibility == 0.7)
  #expect(restored.configuration.expandedWidth == 408)
  #expect(restored.configuration.expandedContentHeight == 136)
}
