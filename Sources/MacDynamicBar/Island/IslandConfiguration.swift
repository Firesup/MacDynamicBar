import Foundation

/// Presentation preferences kept independent of the window and ready for a settings UI.
struct IslandConfiguration {
    var hoverEnabled = true
    var hoverWidthIncrease: CGFloat = 32
    var hoverHeightIncrease: CGFloat = 8
    var expandedWidth: CGFloat = 420
    var expandedContentHeight: CGFloat = 180
    var animationDuration: TimeInterval = 0.22
}
