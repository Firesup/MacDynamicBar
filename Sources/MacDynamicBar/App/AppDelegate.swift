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

// MARK: - Application Lifecycle

enum LaunchOptions {
    static var settingsPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--settings-preview")
            || Bundle.main.object(forInfoDictionaryKey: "MinnowSettingsPreview") as? Bool == true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = LaunchOptions.settingsPreview
        ? MinnowSettings(defaults: UserDefaults(suiteName: "com.minnow.settings-preview") ?? .standard)
        : MinnowSettings.shared
    private var island: IslandCoordinator?
    private var settingsWindow: MinnowSettingsWindow?
    private var statusItem: NSStatusItem?
    private var menuSubscription: AnyCancellable?
    private var presentationObservation: NSKeyValueObservation?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = IslandCoordinator(settings: settings)
        island = coordinator
        settingsWindow = MinnowSettingsWindow(settings: settings, coordinator: coordinator)
        configureMenu()
        configureApplicationMenu()
        presentationObservation = NSApp.observe(\.currentSystemPresentationOptions, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.island?.refreshVisibility() }
        }
        menuSubscription = settings.$showMenuBar.receive(on: RunLoop.main).sink { [weak self] visible in
            self?.statusItem?.isVisible = visible
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observe(NSWorkspace.shared.notificationCenter, name: name) { delegate in
                delegate.island?.refreshVisibility()
            }
        }
        observe(.default, name: NSApplication.didChangeScreenParametersNotification) {
            $0.island?.reconcileDisplays(reposition: true)
        }
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.sessionDidResignActiveNotification) {
            $0.island?.setSessionActive(false)
        }
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.sessionDidBecomeActiveNotification) {
            $0.island?.setSessionActive(true)
        }
        if LaunchOptions.settingsPreview {
            settingsWindow?.open()
            return
        }
        coordinator.start()
        if settings.openSettingsOnLaunch { settingsWindow?.open() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        island?.stop()
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.open()
        return true
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Minnow")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        add("Hide Island", #selector(toggleVisibility), to: menu)
        let sourceItem = NSMenuItem(title: "Source", action: nil, keyEquivalent: "")
        let sourceMenu = NSMenu(title: "Source")
        for source in SourcePreference.allCases {
            let choice = NSMenuItem(title: source.title, action: #selector(chooseSource), keyEquivalent: "")
            choice.target = self
            choice.representedObject = source.rawValue
            sourceMenu.addItem(choice)
        }
        sourceItem.submenu = sourceMenu
        menu.addItem(sourceItem)
        add("Audio-Reactive Waves", #selector(toggleAudioReactiveWaves), to: menu)
        add("Refresh Playback", #selector(refreshMusic), to: menu)
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings), key: ",", to: menu)
        menu.addItem(.separator())
        add("Quit Minnow", #selector(quit), key: "q", to: menu)
        item.menu = menu
        statusItem = item
        item.isVisible = settings.showMenuBar
    }

    private func add(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func configureApplicationMenu() {
        let main = NSMenu()
        let app = NSMenu(title: "Minnow")
        add("Settings…", #selector(openSettings), key: ",", to: app)
        app.addItem(.separator())
        add("Quit Minnow", #selector(quit), key: "q", to: app)
        let appItem = NSMenuItem(title: "Minnow", action: nil, keyEquivalent: "")
        appItem.submenu = app
        main.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                      ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                      ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggleVisibility) }?.title =
            settings.islandEnabled ? "Hide Island" : "Show Island"
        menu.items.first { $0.submenu != nil }?.title = "Source: " + settings.source.title
        for item in menu.items.flatMap({ $0.submenu?.items ?? [] }) {
            if let raw = item.representedObject as? String {
                item.state = raw == settings.source.rawValue ? .on : .off
            }
        }
        menu.items.first { $0.action == #selector(toggleAudioReactiveWaves) }?.state =
            settings.audioReactive ? .on : .off
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name,
                         action: @escaping @MainActor (AppDelegate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, token))
    }

    @objc private func toggleVisibility() { settings.islandEnabled.toggle() }
    @objc private func chooseSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = SourcePreference(rawValue: raw) else { return }
        settings.source = source
    }
    @objc private func toggleAudioReactiveWaves() { settings.audioReactive.toggle() }
    @objc private func refreshMusic() { island?.refresh() }
    @objc private func openSettings() { settingsWindow?.open() }
    @objc private func quit() { NSApp.terminate(nil) }
}


