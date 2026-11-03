import AppKit

// MARK: - Application Entry Point

@main
@MainActor
struct MacDynamicBar {
  static func main() {
    let application: NSApplication = NSApplication.shared
    let delegate: AppDelegate = AppDelegate()

    // Runs through the menu bar without creating a Dock icon.
    application.setActivationPolicy(.accessory)
    application.delegate = delegate

    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}
