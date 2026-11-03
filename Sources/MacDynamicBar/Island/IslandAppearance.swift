import AppKit
import CoreMedia
import CoreAudio
import CryptoKit
import Network
import Security
import ServiceManagement
import ScreenCaptureKit
import Combine
import QuartzCore
import SwiftUI

// MARK: - Island Appearance Layout

enum IslandAppearanceLayout: String, CaseIterable, Identifiable {
    case standard, glassInset, softGradient
    var id: String { rawValue }
    var title: String { switch self { case .standard: "Standard"; case .glassInset: "Glass Inset"; case .softGradient: "Soft Gradient" } }
}

/// AppKit coordinates inside the surface run from the bottom left.
/// Keep a solid camera header and ten-point outer frame during resizing.
struct InsetGlassGeometry {
    static func frame(size: CGSize, headerHeight: CGFloat, sideInset: CGFloat = 10) -> CGRect {
        let width = size.width - sideInset * 2
        let height = size.height - headerHeight - 18
        guard width > 0, height > 0 else { return .zero }
        return CGRect(x: sideInset, y: 10, width: width, height: height)
    }
    static func cornerRadius(for frame: CGRect) -> CGFloat {
        min(22, frame.width / 2, frame.height / 2)
    }
}


// MARK: - Automatic Text Contrast

struct IslandTextContrast {
    let secondaryOpacity: Double
    let shadowOpacity: Double
    var secondary: Color { .white.opacity(secondaryOpacity) }

    /// Brighter, heavier lettering and a subtle glyph shadow, never text plates.
    static func resolve(translucent: Bool, tint: Double, increased: Bool) -> Self {
        let bounded = tint.isFinite ? min(1, max(0, tint)) : 1
        let clarity = 1 - bounded
        return Self(secondaryOpacity: increased ? 1 : (translucent ? 0.96 : 0.90),
                    shadowOpacity: increased ? 0.7 : (translucent ? 0.35 + clarity * 0.25 : 0.25))
    }
}

private struct IslandTextContrastKey: EnvironmentKey {
    static let defaultValue = IslandTextContrast.resolve(translucent: false, tint: 1, increased: false)
}

extension EnvironmentValues {
    var islandTextContrast: IslandTextContrast {
        get { self[IslandTextContrastKey.self] }
        set { self[IslandTextContrastKey.self] = newValue }
    }
}


