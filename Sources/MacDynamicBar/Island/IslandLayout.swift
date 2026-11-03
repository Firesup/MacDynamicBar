import Foundation

// MARK: - Layout Calculations

/// Geometry only. Does not depend on native windows or music playback.
/// AppKit screen coordinates start at the bottom left.
struct IslandLayout {
  let screenFrame: CGRect
  let notchWidth: CGFloat
  let notchHeight: CGFloat
  var showsMiniPlayer = false
  var notchCenterX: CGFloat? = nil
  var configuration = IslandConfiguration()

  var headerHeight: CGFloat {
    notchHeight
  }

  func size(for presentation: IslandPresentation) -> CGSize {
    let wingsWidth =
      showsMiniPlayer
      ? configuration.miniPlayerWingWidth * 2
      : 0

    let shoulders: CGFloat = configuration.shape == .notch ? 16 : 0
    let compactWidth = notchWidth + wingsWidth + shoulders

    let width: CGFloat
    let height: CGFloat

    switch presentation {
    case .compact:
      width = compactWidth
      height = notchHeight

    case .hover:
      width = compactWidth + configuration.hoverWidthIncrease
      height = notchHeight + configuration.hoverHeightIncrease

    case .expanded:
      width = max(configuration.expandedWidth, compactWidth)
      height = notchHeight + configuration.expandedContentHeight
    }

    return CGSize(
      width: min(width, screenFrame.width),
      height: min(height, screenFrame.height)
    )
  }

  func frame(for presentation: IslandPresentation) -> CGRect {
    let size = size(for: presentation)
    let centerX = notchCenterX ?? screenFrame.midX
    let desiredX = centerX - size.width / 2

    // Keep the island within the display's horizontal bounds.
    let originX = min(
      max(desiredX, screenFrame.minX),
      screenFrame.maxX - size.width
    )

    return CGRect(
      x: originX,
      y: screenFrame.maxY - size.height,
      width: size.width,
      height: size.height
    )
  }
}
