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

// MARK: - Expanded Island Shape

enum IslandShape: String, CaseIterable, Identifiable {
    case applePill, notch
    var id: String { rawValue }
    var title: String { self == .applePill ? "Apple Pill" : "Notch" }
}

struct IslandShapeGeometry {
    static func shoulder(size: CGSize, expansion: Double) -> CGFloat {
        min(14 * min(1, max(0, expansion)), size.width / 8, size.height / 3)
    }
    static func path(size: CGSize, radius: CGFloat, shape: IslandShape, expansion: Double) -> CGPath {
        let rect = CGRect(origin: .zero, size: size)
        let r = min(radius, size.height / 2, size.width / 2)
        let s = shoulder(size: size, expansion: expansion)
        guard shape == .notch, s > 0.01 else {
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
        let w = size.width, h = size.height
        let bottom = min(r, (w - 2 * s) / 2, (h - s) / 2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addCurve(to: CGPoint(x: w - s, y: h - s), control1: CGPoint(x: w - s, y: h), control2: CGPoint(x: w - s, y: h))
        p.addLine(to: CGPoint(x: w - s, y: bottom))
        p.addQuadCurve(to: CGPoint(x: w - s - bottom, y: 0), control: CGPoint(x: w - s, y: 0))
        p.addLine(to: CGPoint(x: s + bottom, y: 0))
        p.addQuadCurve(to: CGPoint(x: s, y: bottom), control: CGPoint(x: s, y: 0))
        p.addLine(to: CGPoint(x: s, y: h - s))
        p.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: s, y: h), control2: CGPoint(x: s, y: h))
        p.closeSubpath()
        return p
    }
}

struct IslandPreviewOutline: Shape {
    let shape: IslandShape
    func path(in rect: CGRect) -> Path {
        let path = IslandShapeGeometry.path(size: rect.size, radius: 24, shape: shape, expansion: 1)
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: rect.minX, ty: rect.maxY)
        return Path(path.copy(using: &flip) ?? path)
    }
}


