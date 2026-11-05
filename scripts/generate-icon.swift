import AppKit

// Reproducible native icon artwork; no external assets or downloads.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let side = CGFloat(pixels)
    let tile = NSBezierPath(roundedRect: CGRect(x: side * 0.08, y: side * 0.08,
      width: side * 0.84, height: side * 0.84), xRadius: side * 0.19, yRadius: side * 0.19)
    NSGradient(starting: NSColor(srgbRed: 0.05, green: 0.65, blue: 0.78, alpha: 1),
      ending: NSColor(srgbRed: 0.08, green: 0.21, blue: 0.48, alpha: 1))!.draw(in: tile, angle: -75)
    let fish = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: nil)!
      .withSymbolConfiguration(.init(pointSize: side * 0.6, weight: .medium))!
    let tinted = NSImage(size: fish.size, flipped: false) { rect in
      fish.draw(in: rect)
      NSColor.white.setFill()
      rect.fill(using: .sourceIn)
      return true
    }
    tinted.draw(in: CGRect(x: side * 0.22, y: side * 0.30, width: side * 0.56, height: side * 0.40))
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
  }
}
