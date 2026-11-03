import Combine
import Foundation

// MARK: - Persistent App Settings

enum SourcePreference: String, CaseIterable, Identifiable {
  case auto, music, spotify
  var id: String { rawValue }
  var title: String {
    switch self {
    case .auto: "Auto"
    case .music: "Music"
    case .spotify: "Spotify"
    }
  }
  var source: MusicSource? {
    switch self {
    case .auto: nil
    case .music: .appleMusic
    case .spotify: .spotify
    }
  }
}

@MainActor
final class MinnowSettings: ObservableObject {
  static let shared = MinnowSettings()
  private let defaults: UserDefaults
  @Published var islandEnabled: Bool { didSet { save("islandEnabled", islandEnabled) } }
  @Published var source: SourcePreference {
    didSet { save("mediaSourcePreference", source.rawValue) }
  }
  @Published var openSettingsOnLaunch: Bool {
    didSet { save("openSettingsOnLaunch", openSettingsOnLaunch) }
  }
  @Published var automaticSizing: Bool { didSet { save("automaticIslandSizing", automaticSizing) } }
  @Published var compactWing: Double { didSet { save("compactWingWidth", compactWing) } }
  @Published var expandedWidth: Double { didSet { save("expandedIslandWidth", expandedWidth) } }
  @Published var expandedHeight: Double { didSet { save("expandedIslandHeight", expandedHeight) } }
  @Published var allDisplays: Bool { didSet { save("islandOnAllDisplays", allDisplays) } }
  @Published var display: String { didSet { save("islandDisplayUUID", display) } }
  @Published var islandShape: IslandShape { didSet { save("islandShape", islandShape.rawValue) } }
  @Published var appearanceLayout: IslandAppearanceLayout {
    didSet { save("islandAppearanceLayout", appearanceLayout.rawValue) }
  }
  @Published var glass: Bool { didSet { save("islandGlassAppearance", glass) } }
  @Published var gradientVisibility: Double {
    didSet { save("minnowGradientVisibility", gradientVisibility) }
  }
  @Published var opacity: Double { didSet { save("islandBackgroundOpacity", opacity) } }
  @Published var slightHover: Bool { didSet { save("minnowSlightHover", slightHover) } }
  @Published var expandOnHover: Bool { didSet { save("expandIslandOnHover", expandOnHover) } }
  @Published var haptics: Bool { didSet { save("islandHaptics", haptics) } }
  @Published var artwork: Bool { didSet { save("showAlbumArtwork", artwork) } }
  @Published var leftAction: PlayerAction {
    didSet { save("islandPlayerAction", leftAction.rawValue) }
  }
  @Published var audioReactive: Bool { didSet { save("audioReactiveWavesEnabled", audioReactive) } }
  @Published var collapseOnPause: Bool { didSet { save("collapseIslandOnPause", collapseOnPause) } }
  @Published var collapseDelay: Double { didSet { save("islandCollapseDelay", collapseDelay) } }
  @Published var hideOnPause: Bool { didSet { save("hideIslandOnPause", hideOnPause) } }
  @Published var hideDelay: Double { didSet { save("islandHideDelay", hideDelay) } }
  @Published var showMenuBar: Bool { didSet { save("showMinnowMenuBar", showMenuBar) } }
  @Published var hideFullscreen: Bool { didSet { save("hideMinnowFullscreen", hideFullscreen) } }
  @Published var backgroundBlur: Bool { didSet { save("minnowBackgroundBlur", backgroundBlur) } }
  @Published var mediaEnabled: Bool { didSet { save("minnowMediaEnabled", mediaEnabled) } }
  @Published var showLeftButton: Bool { didSet { save("minnowShowLeftButton", showLeftButton) } }
  @Published var explicitTag: Bool { didSet { save("minnowExplicitTag", explicitTag) } }
  @Published var explicitColor: Bool { didSet { save("minnowExplicitColor", explicitColor) } }
  @Published var animateArtwork: Bool { didSet { save("minnowAnimateArtwork", animateArtwork) } }
  @Published var heartSongColor: Bool { didSet { save("minnowHeartSongColor", heartSongColor) } }
  @Published var collapseAfterScrub: Bool {
    didSet { save("minnowCollapseAfterScrub", collapseAfterScrub) }
  }
  @Published var notchWidthOffset: Double {
    didSet { save("minnowNotchWidthOffset", notchWidthOffset) }
  }
  @Published var notchHeightOffset: Double {
    didSet { save("minnowNotchHeightOffset", notchHeightOffset) }
  }

  @Published var airPodsPopups: Bool { didSet { save("minnowAirPodsPopups", airPodsPopups) } }
  @Published var lowBatteryPopups: Bool {
    didSet { save("minnowLowBatteryPopups", lowBatteryPopups) }
  }
  @Published var chargingPopups: Bool { didSet { save("minnowChargingPopups", chargingPopups) } }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    func bool(_ key: String, _ fallback: Bool) -> Bool {
      defaults.object(forKey: key) as? Bool ?? fallback
    }
    func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
      let value = defaults.object(forKey: key) as? Double ?? fallback
      return value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
    airPodsPopups = bool("minnowAirPodsPopups", true)
    lowBatteryPopups = bool("minnowLowBatteryPopups", true)
    chargingPopups = bool("minnowChargingPopups", true)
    showMenuBar = bool("showMinnowMenuBar", true)
    hideFullscreen = bool("hideMinnowFullscreen", false)
    backgroundBlur = bool("minnowBackgroundBlur", false)
    mediaEnabled = bool("minnowMediaEnabled", true)
    showLeftButton = bool("minnowShowLeftButton", true)
    explicitTag = bool("minnowExplicitTag", true)
    explicitColor = bool("minnowExplicitColor", false)
    animateArtwork = bool("minnowAnimateArtwork", false)
    heartSongColor = bool("minnowHeartSongColor", false)
    collapseAfterScrub = bool("minnowCollapseAfterScrub", false)
    notchWidthOffset = number("minnowNotchWidthOffset", 0, -40...120)
    notchHeightOffset = number("minnowNotchHeightOffset", 0, -8...30)
    islandEnabled = bool("islandEnabled", true)
    source =
      SourcePreference(rawValue: defaults.string(forKey: "mediaSourcePreference") ?? "") ?? .auto
    openSettingsOnLaunch = bool("openSettingsOnLaunch", true)
    automaticSizing = bool("automaticIslandSizing", true)
    compactWing = number("compactWingWidth", 26, 20...60)
    expandedWidth = number("expandedIslandWidth", 380, 320...600)
    expandedHeight = number("expandedIslandHeight", 154, 154...280)
    allDisplays = bool("islandOnAllDisplays", false)
    display = defaults.string(forKey: "islandDisplayUUID") ?? "automatic"
    islandShape = IslandShape(rawValue: defaults.string(forKey: "islandShape") ?? "") ?? .applePill
    appearanceLayout =
      IslandAppearanceLayout(rawValue: defaults.string(forKey: "islandAppearanceLayout") ?? "")
      ?? .standard
    glass = bool("islandGlassAppearance", false)
    opacity = number("islandBackgroundOpacity", 1, 0.35...1)
    gradientVisibility = number("minnowGradientVisibility", 0.45, 0...0.85)
    slightHover = bool("minnowSlightHover", true)
    expandOnHover = bool("expandIslandOnHover", false)
    haptics = bool("islandHaptics", false)
    artwork = bool("showAlbumArtwork", true)
    leftAction =
      PlayerAction(rawValue: defaults.string(forKey: "islandPlayerAction") ?? "") ?? .like
    audioReactive = bool("audioReactiveWavesEnabled", true)
    collapseOnPause = bool("collapseIslandOnPause", false)
    collapseDelay = number("islandCollapseDelay", 3, 0...30)
    hideOnPause = bool("hideIslandOnPause", false)
    hideDelay = number("islandHideDelay", 15, 0...120)
  }

  var configuration: IslandConfiguration {
    var value = IslandConfiguration()
    value.hoverEnabled = slightHover || expandOnHover
    value.shape = islandShape
    if !automaticSizing {
      value.miniPlayerWingWidth = compactWing
      value.expandedWidth = expandedWidth
      value.expandedContentHeight = expandedHeight
    }
    return value
  }

  func resetPreferences() {
    airPodsPopups = true
    lowBatteryPopups = true
    chargingPopups = true
    islandEnabled = true
    source = .auto
    openSettingsOnLaunch = true
    automaticSizing = true
    compactWing = 26
    expandedWidth = 380
    expandedHeight = 154
    allDisplays = false
    display = "automatic"
    glass = false
    opacity = 1
    appearanceLayout = .standard
    gradientVisibility = 0.45
    islandShape = .applePill
    slightHover = true
    expandOnHover = false
    haptics = false
    artwork = true
    leftAction = .like
    audioReactive = true
    collapseOnPause = false
    collapseDelay = 3
    hideOnPause = false
    hideDelay = 15
    showMenuBar = true
    hideFullscreen = false
    backgroundBlur = false
    mediaEnabled = true
    showLeftButton = true
    explicitTag = true
    explicitColor = false
    animateArtwork = false
    heartSongColor = false
    collapseAfterScrub = false
    notchWidthOffset = 0
    notchHeightOffset = 0
  }

  private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }
}
