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

struct AnimatedAlbumCover: View {
    let image: NSImage?
    let size: CGFloat
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var enlarged = false
    private var moving: Bool { active && !reduceMotion }
    var body: some View {
        AlbumCover(image: image, size: size)
            .scaleEffect(enlarged ? 1.04 : 1)
            .rotationEffect(.degrees(moving ? (enlarged ? 1.2 : -1.2) : 0))
            .animation(moving ? .easeInOut(duration: 2.5).repeatForever(autoreverses: true) : .default, value: enlarged)
            .onAppear { enlarged = moving }
            .onChange(of: moving) { _, value in enlarged = value }
    }
}

@MainActor
enum ArtworkPalette {
    static func color(from image: NSImage?) -> Color {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .pink }
        var pixels = [UInt8](repeating: 0, count: 12 * 12 * 4)
        let success = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: 12, height: 12,
                bitsPerComponent: 8, bytesPerRow: 48, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 12, height: 12))
            return true
        }
        guard success else { return .pink }
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let importance = max(r, g, b) - min(r, g, b) + 0.05
            red += r * importance; green += g * importance; blue += b * importance; weight += importance
        }
        let color = NSColor(srgbRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(nsColor: NSColor(calibratedHue: hue, saturation: min(0.8, saturation), brightness: max(0.75, brightness), alpha: 1))
    }
}

