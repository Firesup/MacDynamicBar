import Foundation

// MARK: - Configuration

/// Defaults used by automatic sizing; custom values come from MinnowSettings.
/// Dimensions are measured in macOS points.
struct IslandConfiguration: Equatable {
  var hoverEnabled = true
  var shape: IslandShape = .notch

  // Space on each side of the physical notch when displaying music.
  var miniPlayerWingWidth: CGFloat = 38

  var hoverWidthIncrease: CGFloat = 32
  var hoverHeightIncrease: CGFloat = 8

  var expandedWidth: CGFloat = 408
  var expandedContentHeight: CGFloat = 136

}
