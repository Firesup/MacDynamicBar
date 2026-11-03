import AppKit
import SwiftUI
import Testing

@testable import MacDynamicBar

@Test(.enabled(if: ProcessInfo.processInfo.environment["MINNOW_RENDER_SCENE"] == "1")) @MainActor
func musicSceneRendersWithoutStartingPlaybackOrDeviceMonitoring() throws {
  let suite = "MinnowScene.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let renderer = ImageRenderer(
    content: MusicSceneView(
      session: IslandMediaSession(), settings: MinnowSettings(defaults: defaults),
      widgets: MusicSceneWidgets()
    ).frame(width: 1100, height: 760))
  renderer.scale = 1
  let image = try #require(renderer.cgImage)
  #expect(image.width == 1100 && image.height == 760)
  let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
      ".build/ui-checks/music-scene.png")
  try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
  let png = try #require(
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
  try png.write(to: output)
}
