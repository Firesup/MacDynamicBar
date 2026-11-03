import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        island = IslandWindowController()
        configureMenu()
        observe(.default, name: NSApplication.didChangeScreenParametersNotification) { $0.island?.show() }
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.sessionDidResignActiveNotification) {
            $0.island?.hide()
        }
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.sessionDidBecomeActiveNotification) {
            $0.island?.show()
        }
        island?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        island?.stop()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Minnow")
        let menu = NSMenu()
        add("Expand / Collapse Minnow", action: #selector(toggleIsland), to: menu)
        add("Reposition Island", action: #selector(repositionIsland), to: menu)
        menu.addItem(.separator())
        add("Quit Minnow", action: #selector(quit), key: "q", to: menu)
        item.menu = menu
        statusItem = item
    }

    private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name,
                         action: @escaping @MainActor (AppDelegate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    @objc private func toggleIsland() { island?.toggle() }
    @objc private func repositionIsland() { island?.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
