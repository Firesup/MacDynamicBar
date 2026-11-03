import AppKit
import SwiftUI
import Testing

@testable import MacDynamicBar

/// Offscreen rendering verifies native symbols and provides images for visual QA
/// without opening windows, starting capture, or accessing Bluetooth.
@Test @MainActor func popupViewsRenderAtSmallestSupportedWidth() throws {
  let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
      ".build/ui-checks")
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  for kind: IslandPopup.Kind in [.airPods, .lowBattery, .charging] {
    let popup = IslandPopup.preview(kind)
    #expect(NSImage(systemSymbolName: popup.symbol, accessibilityDescription: nil) != nil)
    let renderer = ImageRenderer(
      content: IslandPopupView(popup: popup, dismiss: {})
        .frame(width: 320, height: 122).background(.black).preferredColorScheme(.dark))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    #expect(image.width == 640 && image.height == 244)
    let representation = NSBitmapImageRep(cgImage: image)
    let png = try #require(representation.representation(using: .png, properties: [:]))
    try png.write(to: output.appendingPathComponent(kind.rawValue + ".png"))
  }
}
