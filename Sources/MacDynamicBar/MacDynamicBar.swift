
import AppKit
import SwiftUI

// The contents of our window.
struct PrototypeView: View {
    @State private var clickCount = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(.mint)

            Text("Mac Dynamic Bar")
                .font(.title2.bold())

            Text("Your first native macOS window.")
                .foregroundStyle(.secondary)

            Button("Test interaction") {
                clickCount += 1
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)

            Text("Clicks: \(clickCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

// Manages the application's lifecycle and window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 480,
                height: 320
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "Mac Dynamic Bar"
        window.minSize = NSSize(width: 380, height: 280)
        window.isReleasedWhenClosed = false

        // Place our SwiftUI interface inside the AppKit window.
        window.contentView = NSHostingView(
            rootView: PrototypeView()
        )

        self.window = window

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // For this initial prototype, closing the window quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

// Starts the application.
@main
@MainActor
struct MacDynamicBar {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = delegate

        // Keep the delegate alive while the application runs.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
