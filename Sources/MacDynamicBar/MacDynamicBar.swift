import AppKit
import Combine
import QuartzCore
import SwiftUI

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

// MARK: - Application Lifecycle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandWindowController?
    private var statusItem: NSStatusItem?

    private var observers: [
        (center: NotificationCenter, token: NSObjectProtocol)
    ] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        island = IslandWindowController()

        configureMenu()

        observe(
            .default,
            name: NSApplication.didChangeScreenParametersNotification
        ) {
            $0.island?.show()
        }

        observe(
            NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.sessionDidResignActiveNotification
        ) {
            $0.island?.hide()
        }

        observe(
            NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.sessionDidBecomeActiveNotification
        ) {
            $0.island?.show()
        }

        island?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        island?.stop()

        for observer in observers {
            observer.center.removeObserver(observer.token)
        }

        observers.removeAll()

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        item.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Minnow"
        )

        let menu = NSMenu()

        addMenuItem(
            "Expand / Collapse Minnow",
            action: #selector(toggleIsland),
            to: menu
        )

        addMenuItem(
            "Reposition Island",
            action: #selector(repositionIsland),
            to: menu
        )

        menu.addItem(.separator())

        addMenuItem(
            "Quit Minnow",
            action: #selector(quit),
            key: "q",
            to: menu
        )

        item.menu = menu
        statusItem = item
    }

    private func addMenuItem(
        _ title: String,
        action: Selector,
        key: String = "",
        to menu: NSMenu
    ) {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: key
        )

        item.target = self
        menu.addItem(item)
    }

    private func observe(
        _ center: NotificationCenter,
        name: Notification.Name,
        action: @escaping @MainActor (AppDelegate) -> Void
    ) {
        let token = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }

        observers.append((center: center, token: token))
    }

    @objc private func toggleIsland() {
        island?.toggle()
    }

    @objc private func repositionIsland() {
        island?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Configuration

/// These values can be connected to the settings screen later.
/// Dimensions are measured in macOS points.
struct IslandConfiguration {
    var hoverEnabled = true

    // Total width increase: 16 points on each side.
    var hoverWidthIncrease: CGFloat = 32

    // Additional height below the physical notch.
    var hoverHeightIncrease: CGFloat = 8

    var expandedWidth: CGFloat = 420
    var expandedContentHeight: CGFloat = 180

    var animationDuration: TimeInterval = 0.22
}

// MARK: - Presentation State

enum IslandPresentation: Equatable {
    case compact
    case hover
    case expanded
}

/// Hover is temporary. Clicking keeps the full panel open
/// even after the pointer leaves.
@MainActor
final class IslandState: ObservableObject {
    @Published private(set) var presentation: IslandPresentation = .compact

    private var isHovered = false
    private let hoverEnabled: Bool

    var isExpanded: Bool {
        presentation == .expanded
    }

    init(hoverEnabled: Bool = true) {
        self.hoverEnabled = hoverEnabled
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered

        // Moving the pointer away must not close a clicked-open panel.
        guard !isExpanded else { return }

        presentation = hovered && hoverEnabled ? .hover : .compact
    }

    func toggle() {
        if isExpanded {
            presentation = isHovered && hoverEnabled ? .hover : .compact
        } else {
            presentation = .expanded
        }
    }

    func collapse() {
        isHovered = false
        presentation = .compact
    }
}

// MARK: - Layout Calculations

/// Geometry only. Does not depend on native windows or music playback.
/// AppKit screen coordinates start at the bottom left.
struct IslandLayout {
    let screenFrame: CGRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var notchCenterX: CGFloat? = nil
    var configuration = IslandConfiguration()

    var headerHeight: CGFloat {
        notchHeight
    }

    func size(for presentation: IslandPresentation) -> CGSize {
        let width: CGFloat
        let height: CGFloat

        switch presentation {
        case .compact:
            width = notchWidth
            height = notchHeight

        case .hover:
            width = notchWidth + configuration.hoverWidthIncrease
            height = notchHeight + configuration.hoverHeightIncrease

        case .expanded:
            width = max(configuration.expandedWidth, notchWidth)
            height = notchHeight + configuration.expandedContentHeight
        }

        return CGSize(
            width: min(width, screenFrame.width),
            height: min(height, screenFrame.height)
        )
    }

    func frame(for presentation: IslandPresentation) -> CGRect {
        let size = size(for: presentation)
        let centerX = notchCenterX ?? screenFrame.midX
        let desiredX = centerX - size.width / 2

        // Keep the island within the display's horizontal bounds.
        let originX = min(
            max(desiredX, screenFrame.minX),
            screenFrame.maxX - size.width
        )

        return CGRect(
            x: originX,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Native Overlay Window

/// Accepts mouse interaction without taking keyboard focus.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        level = .statusBar

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }
}

// MARK: - Mouse Tracking

/// Tracks hovering even while another application has keyboard focus.
final class IslandHostingView: NSHostingView<IslandView> {
    var hoverChanged: ((Bool) -> Void)?

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverArea {
            removeTrackingArea(hoverArea)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )

        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged?(false)
    }
}

// MARK: - Window Controller

/// Owns display selection, positioning, animation, and outside clicks.
@MainActor
final class IslandWindowController {
    private let panel = IslandPanel()
    private let state: IslandState
    private let configuration: IslandConfiguration

    private let player = PreviewPlayer()

    private var layout: IslandLayout?
    private var expansionSubscription: AnyCancellable?

    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    init(configuration: IslandConfiguration = IslandConfiguration()) {
        self.configuration = configuration
        self.state = IslandState(
            hoverEnabled: configuration.hoverEnabled
        )

        expansionSubscription = state.$presentation
            .removeDuplicates()
            .sink { [weak self] presentation in
                self?.resize(presentation: presentation)
            }

        installClickMonitors()
    }

    func show() {
        guard let screen = preferredScreen else {
            panel.orderOut(nil)
            return
        }

        let hasNotch = screen.safeAreaInsets.top > 0
        let leftArea = screen.auxiliaryTopLeftArea
        let rightArea = screen.auxiliaryTopRightArea

        let notchWidth: CGFloat
        let notchCenterX: CGFloat

        if hasNotch, let leftArea, let rightArea {
            // The gap between the menu-bar areas is the notch.
            notchWidth = max(1, rightArea.minX - leftArea.maxX)
            notchCenterX = (leftArea.maxX + rightArea.minX) / 2
        } else {
            // Fallback for a display without a physical notch.
            notchWidth = 160
            notchCenterX = screen.frame.midX
        }

        let layout = IslandLayout(
            screenFrame: screen.frame,
            notchWidth: notchWidth,
            notchHeight: hasNotch ? screen.safeAreaInsets.top : 28,
            notchCenterX: notchCenterX,
            configuration: configuration
        )

        self.layout = layout

        let hostingView = IslandHostingView(
            rootView: IslandView(
                state: state,
                player: player,
                layout: layout
            )
        )

        // Window dimensions are controlled explicitly by this controller.
        hostingView.sizingOptions = []

        hostingView.hoverChanged = { [weak self] hovered in
            self?.state.setHovered(hovered)
        }

        panel.contentView = hostingView

        panel.setFrame(
            layout.frame(for: state.presentation),
            display: true
        )

        panel.orderFrontRegardless()
    }

    func toggle() {
        state.toggle()
        panel.orderFrontRegardless()
    }

    func hide() {
        state.collapse()
        panel.orderOut(nil)
    }

    func stop() {
        expansionSubscription?.cancel()

        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }

        localClickMonitor = nil
        globalClickMonitor = nil

        panel.close()
    }

    private var preferredScreen: NSScreen? {
        // NSScreen.main changes with keyboard focus.
        // Prefer the built-in display instead.
        NSScreen.screens.first { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")

            guard let number = screen.deviceDescription[key] as? NSNumber else {
                return false
            }

            let displayID = CGDirectDisplayID(number.uint32Value)

            return CGDisplayIsBuiltin(displayID) != 0
        } ?? NSScreen.screens.first
    }

    private func resize(presentation: IslandPresentation) {
        guard let layout else { return }

        let frame = layout.frame(for: presentation)
        let reduceMotion = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion
                ? 0
                : configuration.animationDuration

            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )

            panel.animator().setFrame(frame, display: true)
        }
    }

    private func installClickMonitors() {
        let clicks: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        // Clicks delivered to Minnow.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: clicks
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.collapseIfOutside()
            }

            // Preserve normal delivery of the click.
            return event
        }

        // Clicks delivered to other applications.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: clicks
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.collapseIfOutside()
            }
        }
    }

    private func collapseIfOutside() {
        guard state.isExpanded else { return }
        guard !panel.frame.contains(NSEvent.mouseLocation) else { return }

        state.collapse()
    }
}

// MARK: - Island Interface

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var player: PreviewPlayer

    let layout: IslandLayout

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.isExpanded {
                playerContent
                    .frame(
                        height: layout.configuration.expandedContentHeight
                    )
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(.black)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: state.isExpanded ? 26 : 14,
                bottomTrailingRadius: state.isExpanded ? 26 : 14,
                topTrailingRadius: 0
            )
        )
        .preferredColorScheme(.dark)
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(
                    duration: layout.configuration.animationDuration
                ),
            value: state.presentation
        )
    }

    private var header: some View {
        Button(action: state.toggle) {
            Color.clear
                .overlay(alignment: .trailing) {
                    if state.isExpanded {
                        Image(systemName: "chevron.up")
                            .font(
                                .system(size: 12, weight: .semibold)
                            )
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 20)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            state.isExpanded ? "Collapse Minnow" : "Expand Minnow"
        )
        .help(
            state.isExpanded ? "Collapse Minnow" : "Expand Minnow"
        )
    }

    private var headerHeight: CGFloat {
        if state.presentation == .hover {
            // Make the entire hover surface clickable,
            // including the extra strip below the notch.
            return layout.size(for: .hover).height
        }

        return layout.headerHeight
    }

    private var playerContent: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.mint.opacity(0.16))
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.title)
                            .foregroundStyle(.mint)
                    }
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(player.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(player.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 32) {
                playbackButton(
                    "backward.fill",
                    label: "Previous preview",
                    action: player.previous
                )

                playbackButton(
                    player.isPlaying ? "pause.fill" : "play.fill",
                    label: player.isPlaying
                        ? "Pause preview"
                        : "Play preview",
                    action: player.togglePlayback
                )

                playbackButton(
                    "forward.fill",
                    label: "Next preview",
                    action: player.next
                )
            }
            .font(.title3)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private func playbackButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Preview Playback

/// Sample state for checking the expanded layout.
/// Does not send commands to Apple Music or Spotify.
/// Dry Test Run
@MainActor
final class PreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var trackIndex = 0

    private let tracks = [
        "A little room to listen",
        "Somewhere by the water",
        "One more moment"
    ]

    var title: String {
        tracks[trackIndex]
    }

    var subtitle: String {
        "Minnow · Preview player"
    }

    func togglePlayback() {
        isPlaying.toggle()
    }

    func next() {
        trackIndex = (trackIndex + 1) % tracks.count
    }

    func previous() {
        trackIndex = (trackIndex + tracks.count - 1) % tracks.count
    }
}