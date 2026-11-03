import Foundation

/// Screen geometry in AppKit coordinates (origin at the bottom left).
struct IslandLayout {
    let screenFrame: CGRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var notchCenterX: CGFloat? = nil
    var configuration = IslandConfiguration()

    var headerHeight: CGFloat { notchHeight }

    func size(for presentation: IslandPresentation) -> CGSize {
        let width: CGFloat
        let height: CGFloat
        switch presentation {
        case .compact:
            width = notchWidth
            height = notchHeight
        case .hover:
            width = notchWidth + configuration.hoverWidthIncrease
            height = notchHeight + configuration.hoverHeightIncrease
        case .expanded:
            width = max(configuration.expandedWidth, notchWidth)
            height = notchHeight + configuration.expandedContentHeight
        }
        return CGSize(width: min(width, screenFrame.width), height: min(height, screenFrame.height))
    }

    func frame(for presentation: IslandPresentation) -> CGRect {
        let size = size(for: presentation)
        let desiredX = (notchCenterX ?? screenFrame.midX) - size.width / 2
        return CGRect(
            x: min(max(desiredX, screenFrame.minX), screenFrame.maxX - size.width),
            y: screenFrame.maxY - size.height,
            width: size.width, height: size.height
        )
    }
}
