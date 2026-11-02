import AppKit
import CoreMedia
import CoreAudio
import CryptoKit
import Network
import Security
import ScreenCaptureKit
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
        menu.autoenablesItems = false

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

        addMenuItem(
            "Refresh Music / Spotify",
            action: #selector(refreshMusic),
            to: menu
        )

        addMenuItem(
            "Audio-Reactive Waves",
            action: #selector(toggleAudioReactiveWaves),
            to: menu
        )
        menu.delegate = self
        let actionMenu = NSMenu(title: "Left Player Button")
        for action in PlayerAction.allCases {
            let choice = NSMenuItem(title: action.title, action: #selector(choosePlayerAction), keyEquivalent: "")
            choice.target = self
            choice.representedObject = action.rawValue
            actionMenu.addItem(choice)
        }
        let actionItem = NSMenuItem(title: "Left Player Button", action: nil, keyEquivalent: "")
        actionItem.submenu = actionMenu
        menu.addItem(actionItem)
        addMenuItem("Connect Spotify…", action: #selector(connectSpotify), to: menu)
        addMenuItem("Disconnect Spotify", action: #selector(disconnectSpotify), to: menu)

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

    @objc private func refreshMusic() {
        island?.refreshMusic()
    }

    @objc private func toggleAudioReactiveWaves() {
        island?.toggleAudioReactiveWaves()
    }

    @objc private func choosePlayerAction(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              PlayerAction(rawValue: value) != nil else { return }
        UserDefaults.standard.set(value, forKey: "islandPlayerAction")
    }

    @objc private func connectSpotify() { SpotifyAccount.shared.showConnectionPrompt() }
    @objc private func disconnectSpotify() { SpotifyAccount.shared.disconnect() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let selectedAction = UserDefaults.standard.string(forKey: "islandPlayerAction") ?? PlayerAction.like.rawValue
        for item in menu.items.flatMap({ $0.submenu?.items ?? [] }) {
            if let value = item.representedObject as? String {
                item.state = value == selectedAction ? .on : .off
            }
        }
        menu.items.first { $0.action == #selector(connectSpotify) }?.isEnabled =
            !SpotifyAccount.shared.isConnecting
        menu.items.first { $0.action == #selector(disconnectSpotify) }?.isEnabled =
            SpotifyAccount.shared.isConnected
        menu.items.first { $0.action == #selector(toggleAudioReactiveWaves) }?.state =
            island?.audioReactiveWavesEnabled == true ? .on : .off
    }
}

// MARK: - Configuration

/// These values can be connected to the settings screen later.
/// Dimensions are measured in macOS points.
struct IslandConfiguration {
    var hoverEnabled = true

    // Space on each side of the physical notch when displaying music.
    var miniPlayerWingWidth: CGFloat = 26

    var hoverWidthIncrease: CGFloat = 32
    var hoverHeightIncrease: CGFloat = 8

    var expandedWidth: CGFloat = 400
    var expandedContentHeight: CGFloat = 174

}

// MARK: - Presentation State

enum IslandPresentation: Equatable {
    case compact, hover, expanded
}

@MainActor
final class IslandState: ObservableObject {
    @Published private(set) var presentation: IslandPresentation = .compact
    @Published var isOutputPickerOpen = false
    private var isHovered = false
    private let hoverEnabled: Bool
    private var hoverExitTask: Task<Void, Never>?

    var isExpanded: Bool { presentation == .expanded }

    init(hoverEnabled: Bool = true) { self.hoverEnabled = hoverEnabled }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        hoverExitTask?.cancel()
        hoverExitTask = nil
        guard !isExpanded else { return }
        if hovered {
            presentation = hoverEnabled ? .hover : .compact
        } else {
            hoverExitTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(120)) }
                catch { return }
                guard let self, !self.isHovered, !self.isExpanded else { return }
                self.presentation = .compact
            }
        }
    }

    func toggle() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        presentation = isExpanded
            ? (isHovered && hoverEnabled ? .hover : .compact)
            : .expanded
    }

    func collapse() {
        isOutputPickerOpen = false
        hoverExitTask?.cancel()
        hoverExitTask = nil
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
    var showsMiniPlayer = false
    var notchCenterX: CGFloat? = nil
    var configuration = IslandConfiguration()

    var headerHeight: CGFloat {
        notchHeight
    }

    func size(for presentation: IslandPresentation) -> CGSize {
    let wingsWidth = showsMiniPlayer
        ? configuration.miniPlayerWingWidth * 2
        : 0

    let compactWidth = notchWidth + wingsWidth

    let width: CGFloat
    let height: CGFloat

    switch presentation {
    case .compact:
        width = compactWidth
        height = notchHeight

    case .hover:
        width = compactWidth + configuration.hoverWidthIncrease
        height = notchHeight + configuration.hoverHeightIncrease

    case .expanded:
        width = max(configuration.expandedWidth, compactWidth)
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

// MARK: - Interruptible Surface Animation


/// An exact critically damped spring. Retargeting preserves current velocity.
struct SurfaceSpring {
    var value: Double
    var velocity = 0.0
    var target: Double

    mutating func advance(by dt: Double) {
        let omega = 24.0
        let displacement = value - target
        let coefficient = velocity + omega * displacement
        let decay = exp(-omega * dt)
        value = target + (displacement + coefficient * dt) * decay
        velocity = (velocity - omega * coefficient * dt) * decay
    }

    var settled: Bool { abs(value - target) < 0.05 && abs(velocity) < 0.5 }
    mutating func finish() { value = target; velocity = 0 }
}

/// The window never resizes during interactions. One backing surface owns
/// the fill, clipping, content bounds and hit region on every animation tick.
@MainActor
final class IslandHostingView: NSView {
    let host: NSHostingView<IslandView>
    var regionChanged: (() -> Void)?

    private var widthSpring = SurfaceSpring(value: 1, target: 1)
    private var heightSpring = SurfaceSpring(value: 1, target: 1)
    private var cornerSpring = SurfaceSpring(value: 14, target: 14)
    private var ticker: Timer?
    private var lastTick = 0.0
    private var surfacePath = CGPath(rect: .zero, transform: nil)
    private var surfaceRect = CGRect.zero
    private let surfaceMask = CAShapeLayer()

    init(rootView: IslandView) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.layer?.mask = surfaceMask
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var isFlipped: Bool { true }

    func move(to size: CGSize, expanded: Bool, animated: Bool) {
        widthSpring.target = size.width
        heightSpring.target = size.height
        cornerSpring.target = expanded ? 32 : 14
        if !animated {
            stopAnimating()
            widthSpring.finish()
            heightSpring.finish()
            cornerSpring.finish()
            applySurface()
            return
        }
        guard ticker == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopAnimating() {
        ticker?.invalidate()
        ticker = nil
    }

    override func layout() {
        super.layout()
        applySurface()
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        guard let window else { return false }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        let inSurface = CGPoint(x: local.x - surfaceRect.minX,
                                y: local.y - surfaceRect.minY)
        return surfacePath.contains(inSurface)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let inSurface = CGPoint(x: local.x - surfaceRect.minX,
                                y: local.y - surfaceRect.minY)
        guard surfacePath.contains(inSurface) else { return nil }
        return super.hitTest(point)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = max(0, now - lastTick)
        lastTick = now
        widthSpring.advance(by: dt)
        heightSpring.advance(by: dt)
        cornerSpring.advance(by: dt)
        if widthSpring.settled && heightSpring.settled && cornerSpring.settled {
            widthSpring.finish()
            heightSpring.finish()
            cornerSpring.finish()
            stopAnimating()
        }
        applySurface()
    }

    private func applySurface() {
        let size = CGSize(width: min(bounds.width, max(1, widthSpring.value)),
                          height: min(bounds.height, max(1, heightSpring.value)))
        surfaceRect = CGRect(x: (bounds.width - size.width) / 2,
                             y: 0, width: size.width, height: size.height)
        let radius = min(cornerSpring.value, size.height / 2, size.width / 2)
        surfacePath = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                             cornerWidth: radius, cornerHeight: radius,
                             transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.frame = surfaceRect
        surfaceMask.frame = CGRect(origin: .zero, size: size)
        surfaceMask.path = surfacePath
        CATransaction.commit()
        regionChanged?()
    }
}


// MARK: - Window Controller

@MainActor
final class IslandWindowController {
    private let panel = IslandPanel()
    private let state: IslandState
    private let configuration: IslandConfiguration
    private let player = MediaPlayer()
    private let accessories: PlayerAccessories
    private let outputs = AudioOutputs()
    private let audio = MusicAudioLevels()
    private var layout: IslandLayout?
    private var hostingView: IslandHostingView?
    private var subscriptions = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isShown = false

    var audioReactiveWavesEnabled: Bool { audio.isEnabled }

    init(configuration: IslandConfiguration = IslandConfiguration()) {
        self.accessories = PlayerAccessories(player: player)
        self.configuration = configuration
        self.state = IslandState(hoverEnabled: configuration.hoverEnabled)
        state.$presentation.removeDuplicates().sink { [weak self] presentation in
            self?.resize(presentation: presentation)
        }.store(in: &subscriptions)
        player.$track.map { $0 != nil }.removeDuplicates().sink { [weak self] visible in
            guard let self, var layout = self.layout else { return }
            layout.showsMiniPlayer = visible
            self.layout = layout
            self.updateRootView()
            self.resize(presentation: self.state.presentation)
        }.store(in: &subscriptions)
        player.$captureTarget.removeDuplicates().sink { [weak self] target in
            self?.audio.setPlayback(target)
        }.store(in: &subscriptions)
        installMonitors()
        outputs.start()
        player.start()
    }

    func refreshMusic() { player.refresh() }

    func toggleAudioReactiveWaves() {
        // Toggling off/on also retries capture after changing system access.
        audio.setEnabled(!audio.isEnabled)
    }

    func show() {
        guard let screen = preferredScreen else { hide(); return }
        let hasNotch = screen.safeAreaInsets.top > 0
        let notchWidth: CGFloat
        let notchCenterX: CGFloat
        if hasNotch, let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = max(1, right.minX - left.maxX)
            notchCenterX = (left.maxX + right.minX) / 2
        } else {
            notchWidth = 160
            notchCenterX = screen.frame.midX
        }
        let layout = IslandLayout(
            screenFrame: screen.frame, notchWidth: notchWidth,
            notchHeight: hasNotch ? screen.safeAreaInsets.top : 28,
            showsMiniPlayer: player.track != nil, notchCenterX: notchCenterX,
            configuration: configuration)
        self.layout = layout
        hostingView?.stopAnimating()
        let host = IslandHostingView(rootView: IslandView(
            state: state, player: player, audio: audio,
            accessories: accessories, outputs: outputs, layout: layout))
        hostingView = host
        host.regionChanged = { [weak self] in self?.updatePointer() }
        panel.contentView = host
        // The transparent canvas stays fixed throughout all interactions.
        let expanded = layout.size(for: .expanded)
        let hover = layout.size(for: .hover)
        let canvasSize = CGSize(width: max(expanded.width, hover.width),
                                height: max(expanded.height, hover.height))
        let originX = min(max(notchCenterX - canvasSize.width / 2, screen.frame.minX),
                          screen.frame.maxX - canvasSize.width)
        panel.setFrame(CGRect(x: originX, y: screen.frame.maxY - canvasSize.height,
                              width: canvasSize.width, height: canvasSize.height),
                       display: true)
        host.frame = CGRect(origin: .zero, size: canvasSize)
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        isShown = true
        host.move(to: layout.size(for: state.presentation),
                  expanded: state.isExpanded, animated: false)
        panel.orderFrontRegardless()
        audio.setSuspended(false)
        updatePointer()
    }

    func toggle() {
        if !isShown { show() }
        state.toggle()
        panel.orderFrontRegardless()
    }

    func hide() {
        isShown = false
        state.collapse()
        hostingView?.stopAnimating()
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        audio.setSuspended(true)
    }

    func stop() {
        hide()
        accessories.stop()
        outputs.stop()
        player.stop()
        audio.stop()
        subscriptions.removeAll()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        panel.close()
    }

    private var preferredScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        } ?? NSScreen.screens.first
    }

    private func updateRootView() {
        guard let layout else { return }
        hostingView?.host.rootView = IslandView(
            state: state, player: player, audio: audio,
            accessories: accessories, outputs: outputs, layout: layout)
    }

    private func resize(presentation: IslandPresentation) {
        guard let layout else { return }
        hostingView?.move(to: layout.size(for: presentation),
                          expanded: presentation == .expanded,
                          animated: isShown && !NSWorkspace.shared
                            .accessibilityDisplayShouldReduceMotion)
    }

    private func updatePointer() {
        let inside = isShown && (hostingView?.containsScreenPoint(
            NSEvent.mouseLocation) ?? false)
        // Transparent canvas space must pass clicks to the application below.
        panel.ignoresMouseEvents = !inside
        state.setHovered(inside)
    }

    private func handleEvent(isClick: Bool) {
        updatePointer()
        guard !state.isOutputPickerOpen else { return }
        if isClick, state.isExpanded,
           hostingView?.containsScreenPoint(NSEvent.mouseLocation) != true {
            state.collapse()
        }
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let click = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
            MainActor.assumeIsolated { self?.handleEvent(isClick: click) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let click = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
            Task { @MainActor [weak self] in self?.handleEvent(isClick: click) }
        }
    }
}

// MARK: - Island Interface

// MARK: - Album Cover

struct AlbumCover: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(.white.opacity(0.1))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: size * 0.2)
        )
        .accessibilityLabel("Album artwork")
    }
}

// MARK: - Island Interface

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var player: MediaPlayer
    @ObservedObject var audio: MusicAudioLevels
    @ObservedObject var accessories: PlayerAccessories
    @ObservedObject var outputs: AudioOutputs

    let layout: IslandLayout

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            // Overlay keeps the expanded content's fixed width from forcing
            // the compact header wider than the actual visible surface.
            expandedPlayer
                .frame(width: layout.size(for: .expanded).width,
                       height: layout.configuration.expandedContentHeight)
                .padding(.top, layout.headerHeight)
                .opacity(state.isExpanded ? 1 : 0)
                .allowsHitTesting(state.isExpanded)
                .accessibilityHidden(!state.isExpanded)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                           value: state.isExpanded)
        }
        .preferredColorScheme(.dark)
        .onChange(of: state.isExpanded) { _, expanded in
            if expanded { accessories.refresh() }
        }
    }

    // MARK: Compact Player / Header

    private var header: some View {
        Button(action: state.toggle) {
            HStack(spacing: 0) {
                // Left section.
                if !state.isExpanded, player.track != nil {
                    AlbumCover(
                        image: player.artwork,
                        size: min(20, layout.notchHeight - 6)
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                }

                // Reserve the camera housing area.
                Color.clear
                    .frame(width: layout.notchWidth)

                // Right section.
                Group {
                    if !state.isExpanded, player.track != nil {
                        PlaybackIndicator(
                            isPlaying: player.isPlaying, audio: audio
                        )
                    } else if state.isExpanded {
                        Image(systemName: "chevron.up")
                            .font(
                                .system(size: 11, weight: .semibold)
                            )
                            .foregroundStyle(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            state.isExpanded ? "Collapse Minnow" : "Expand Minnow"
        )
        .help(
            player.track == nil
                ? "Expand Minnow"
                : "\(player.title) — \(player.subtitle)"
        )
    }

    private var headerHeight: CGFloat {
        state.presentation == .hover
            ? layout.size(for: .hover).height
            : layout.headerHeight
    }

    // MARK: Expanded Player

    private var expandedPlayer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                AlbumCover(
                    image: player.artwork,
                    size: 54
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title)
                        .font(
                            .system(size: 17, weight: .semibold)
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(player.subtitle)
                        .font(
                            .system(size: 14, weight: .medium)
                        )
                        .foregroundStyle(.gray)
                        .lineLimit(1)

                    if let error = accessories.error {
                        Text(error).font(.system(size: 10))
                            .foregroundStyle(.orange).lineLimit(1).help(error)
                    } else if player.isPlaying && !audio.hasAudioSignal {
                        Text(audio.status)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(audio.status)
                    }
                }

                Spacer(minLength: 8)

                PlaybackIndicator(
                    isPlaying: player.isPlaying, audio: audio
                )
            }

            playbackProgress

            HStack(spacing: 8) {
                PlayerActionButton(accessories: accessories)
                Spacer(minLength: 0)
                HStack(spacing: 20) {
                    playbackButton("backward.fill", label: "Previous track", size: 24,
                                   action: player.previous)
                    playbackButton(player.isPlaying ? "pause.fill" : "play.fill",
                                   label: player.isPlaying ? "Pause" : "Play", size: 30,
                                   action: player.togglePlayback)
                    playbackButton("forward.fill", label: "Next track", size: 24,
                                   action: player.next)
                }
                .disabled(!player.canControlPlayback)
                .opacity(player.canControlPlayback ? 1 : 0.35)
                Spacer(minLength: 0)
                Button { state.isOutputPickerOpen.toggle() } label: {
                    AudioOutputIcon(device: outputs.current)
                        .frame(width: 36, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose sound output")
                .help(outputs.current?.name ?? "Choose sound output")
                .popover(isPresented: $state.isOutputPickerOpen, arrowEdge: .bottom) {
                    AudioOutputList(outputs: outputs) { state.isOutputPickerOpen = false }
                        .preferredColorScheme(.dark)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: Progress Display

    private var playbackProgress: some View {
    PlaybackScrubber(
        player: player,
        isExpanded: state.isExpanded
    )
}


    // MARK: Helpers

    private func playbackButton(
    _ symbol: String,
    label: String,
    size: CGFloat,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .font(.system(size: size, weight: .semibold))
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .help(label)
}

    private func progress(at position: TimeInterval) -> CGFloat {
        guard player.duration > 0 else { return 0 }

        return CGFloat(
            min(1, max(0, position / player.duration))
        )
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let value = Int(
            max(0, seconds.isFinite ? seconds : 0)
        )

        return "\(value / 60):"
            + String(format: "%02d", value % 60)
    }
}

// MARK: - Apple Music Track

struct MusicTrack: Equatable {
    let title: String
    let artist: String
    let album: String
    var id: String? = nil
}

// MARK: - Apple Music Player

@MainActor
final class AppleMusicPlayer: ObservableObject {
    var onChange: (@MainActor () -> Void)?
    @Published private(set) var track: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var isMusicRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var artwork: NSImage?
@Published private(set) var duration: TimeInterval = 0

private var positionAtUpdate: TimeInterval = 0
private var positionUpdatedAt = Date.now

private var artworkTrackID: String?
private var isRefreshing = false

    private let musicBundleID = "com.apple.Music"

    private var playbackObserver: NSObjectProtocol?

    private var workspaceObservers: [
        NSObjectProtocol
    ] = []

    var title: String {
        track?.title ?? "No audio found"
    }

    var subtitle: String {
        if let lastError {
            return lastError
        }

        guard let track else {
            return isMusicRunning
                ? "Play a song in Apple Music"
                : "Open Apple Music to begin"
        }

        let artist = track.artist.isEmpty
            ? "Unknown artist"
            : track.artist

        return isMusicRunning
            ? artist
            : "\(artist) · Music closed"
    }

    func playbackPosition(at date: Date) -> TimeInterval {
    // Advance locally between playback notifications.
    // This does not repeatedly query the Music application.
    let elapsed = isPlaying
        ? max(0, date.timeIntervalSince(positionUpdatedAt))
        : 0

    return min(
        duration,
        max(0, positionAtUpdate + elapsed)
    )
}

private func loadArtwork(for trackID: String) {
    // Never display the previous song's cover for a new song.
    artwork = nil

    // Music persistent IDs are hexadecimal.
    // Validate before inserting the ID into AppleScript.
    guard
        !trackID.isEmpty,
        trackID.allSatisfy({ $0.isHexDigit })
    else {
        return
    }

    let source = """
    with timeout of 2 seconds
        if application id "com.apple.Music" is not running then
            return missing value
        end if

        tell application id "com.apple.Music"
            set selectedTrack to current track

            if persistent ID of selectedTrack is not "\(trackID)" then
                return missing value
            end if

            try
                return raw data of artwork 1 of selectedTrack
            on error
                return missing value
            end try
        end tell
    end timeout
    """

    guard let script = NSAppleScript(source: source) else {
        return
    }

    var error: NSDictionary?
    let descriptor = script.executeAndReturnError(&error)

    guard error == nil else { return }

    // Missing artwork should not disable working playback controls.
    artwork = NSImage(data: descriptor.data)
}

    var canControlPlayback: Bool {
        isMusicRunning && track != nil && lastError == nil
    }

    func start() {
        // Prevent duplicate observers if start is called again.
        guard playbackObserver == nil else { return }

        playbackObserver = DistributedNotificationCenter.default()
            .addObserver(
                forName: Notification.Name(
                    "com.apple.Music.playerInfo"
                ),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }

        observeWorkspace(
            NSWorkspace.didLaunchApplicationNotification
        )

        observeWorkspace(
            NSWorkspace.didTerminateApplicationNotification
        )

        refresh()
    }

    func stop() {
        if let playbackObserver {
            DistributedNotificationCenter.default()
                .removeObserver(playbackObserver)
        }

        playbackObserver = nil

        let center = NSWorkspace.shared.notificationCenter

        for observer in workspaceObservers {
            center.removeObserver(observer)
        }

        workspaceObservers.removeAll()
    }

    func refresh() {
    // Prevent overlapping refreshes while AppleScript processes events.
    guard !isRefreshing else { return }

    isRefreshing = true
    defer { isRefreshing = false; onChange?() }

    isMusicRunning = !NSRunningApplication
        .runningApplications(
            withBundleIdentifier: musicBundleID
        )
        .isEmpty

    guard isMusicRunning else {
        isPlaying = false
        lastError = nil

        // Preserve the last track and artwork when Music closes.
        return
    }

    guard let result = execute(Self.snapshotScript) else {
        isPlaying = false
        return
    }

    guard
        let playbackState = result.atIndex(1)?.stringValue,
        let title = result.atIndex(2)?.stringValue,
        let artist = result.atIndex(3)?.stringValue,
        let album = result.atIndex(4)?.stringValue,
        let trackID = result.atIndex(5)?.stringValue
    else {
        isPlaying = false
        lastError = "Could not read Apple Music"
        return
    }

    isPlaying = playbackState == "playing"

    guard playbackState != "stopped", !title.isEmpty else {
        return
    }

    duration = max(
        0,
        result.atIndex(6)?.doubleValue ?? 0
    )

    positionAtUpdate = max(
        0,
        result.atIndex(7)?.doubleValue ?? 0
    )

    positionUpdatedAt = .now

    // Avoid fetching the same artwork on every play/pause event.
    // Retry on a later event if Music did not provide an image.
    if artworkTrackID != trackID || artwork == nil {
        loadArtwork(for: trackID)
        artworkTrackID = trackID
    }

    let updatedTrack = MusicTrack(
        title: title,
        artist: artist,
        album: album,
        id: trackID
    )

    if track != updatedTrack {
        track = updatedTrack
    }
}

    func togglePlayback() {
        send(.togglePlayback)
    }

    func next() {
        send(.next)
    }

    func previous() {
        send(.previous)
    }

    private enum Command: String {
        case togglePlayback = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    private func send(_ command: Command) {
        guard canControlPlayback, !isRefreshing else { return }

        // Command text comes only from the enum above.
        let source = """
        with timeout of 2 seconds
            if application id "com.apple.Music" is running then
                tell application id "com.apple.Music"
                    \(command.rawValue)
                end tell
            end if
        end timeout
        """

        isRefreshing = true
        let result = execute(source)
        isRefreshing = false
        guard result != nil else { onChange?(); return }
        refresh()
    }

    

    private func observeWorkspace(
    _ name: Notification.Name
) {
    let center = NSWorkspace.shared.notificationCenter

    let observer = center.addObserver(
        forName: name,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        // Extract the String before crossing into the main actor.
        let bundleIdentifier: String? = (
            notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication
        )?.bundleIdentifier

        // Capture the String rather than the notification.
        Task { @MainActor [weak self, bundleIdentifier] in
            guard let self else { return }

            guard bundleIdentifier == self.musicBundleID else {
                return
            }

            self.refresh()
        }
    }

    workspaceObservers.append(observer)
}

    private func execute(
        _ source: String
    ) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            lastError = "Could not prepare Music command"
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = (
                error[NSAppleScript.errorNumber] as? NSNumber
            )?.intValue

            if code == -1743 {
                lastError = "Allow Music access in System Settings"
            } else {
                lastError = "Apple Music is unavailable"
            }

            return nil
        }

        lastError = nil
        return result
    }

    func seek(to position: TimeInterval, expectedTrackID: String) {
    guard
        canControlPlayback,
        !isRefreshing,
        track?.id == expectedTrackID,
        let command = DesktopSeek.make(
            source: .appleMusic,
            trackID: expectedTrackID,
            position: position,
            duration: duration
        )
    else {
        return
    }

    isRefreshing = true
    let result = execute(command.script)
    isRefreshing = false

    guard let result else {
        onChange?()
        return
    }

    guard result.booleanValue else {
        refresh()
        return
    }

    positionAtUpdate = command.position
    positionUpdatedAt = .now
    onChange?()
}

    private static let snapshotScript = """
with timeout of 2 seconds
    if application id "com.apple.Music" is not running then
        return {"stopped", "", "", "", "", 0, 0}
    end if

    tell application id "com.apple.Music"
        set playbackState to player state

        if playbackState is stopped then
            return {"stopped", "", "", "", "", 0, 0}
        end if

        if playbackState is playing then
            set stateText to "playing"
        else
            set stateText to "paused"
        end if

        set selectedTrack to current track

        return {stateText, name of selectedTrack, artist of selectedTrack, ¬
            album of selectedTrack, persistent ID of selectedTrack, ¬
            duration of selectedTrack, player position}
    end tell
end timeout
"""
}

// MARK: - Audio-Reactive Playback Levels

/// A short audio envelope history, measured from PCM samples rather than
/// a decorative repeating animation. Kept independent for deterministic tests.
struct AudioEnvelope {
    private(set) var levels = [Float](repeating: 0, count: 5)
    private var averageEnergy: Float = 0
    private var previousEnergy: Float = 0

    mutating func consume(rms: Float) -> [Float] {
        let safe = rms.isFinite ? max(0, rms) : 0
        let energy = min(1, max(0, safe - 0.001))
        averageEnergy += (energy - averageEnergy) * 0.06
        // Emphasize changes relative to the current song's level instead of
        // pinning loud recordings near full height. Peaks receive an extra
        // transient boost; quieter moments fall much closer to the baseline.
        let relative = min(1, energy / max(0.04, averageEnergy * 2.2))
        let transient = max(0, energy - previousEnergy) / max(0.04, averageEnergy)
        let measured = min(1, pow(relative, 1.7) + transient * 0.45)
        previousEnergy = energy
        let previous = levels.last ?? 0
        let smoothing: Float = measured > previous ? 0.92 : 0.60
        let next = previous + (measured - previous) * smoothing
        levels.removeFirst()
        levels.append(next < 0.005 ? 0 : next)
        return levels
    }
}

/// Only this serial capture queue accesses the mutable envelope and timestamp.
/// Callback payloads contain Sendable numbers, never CMSampleBuffer objects.
final class MusicAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate,
                              @unchecked Sendable {
    let onLevels: @Sendable ([Float]) -> Void
    let onStop: @Sendable (String) -> Void
    private var envelope = AudioEnvelope()
    private var lastDelivery = 0.0

    init(onLevels: @escaping @Sendable ([Float]) -> Void,
         onStop: @escaping @Sendable (String) -> Void) {
        self.onLevels = onLevels
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop(error.localizedDescription)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM,
              asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.pointee.mBitsPerChannel == 32 else { return }

        // ScreenCaptureKit supplies native-endian float PCM. The returned
        // block buffer keeps the audio storage alive until analysis finishes.
        var required = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &required,
            bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: nil)
        guard required > 0 else { return }
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: required, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil,
            bufferListOut: list, bufferListSize: required,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block)
        guard result == noErr else { return }

        let now = CACurrentMediaTime()
        guard now - lastDelivery >= 1.0 / 30.0 else { return }
        lastDelivery = now
        var sum = 0.0
        var count = 0
        withExtendedLifetime(block) {
            for buffer in UnsafeMutableAudioBufferListPointer(list) {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                // Square channels separately so opposite-phase stereo does
                // not cancel out and incorrectly appear silent.
                for index in 0..<sampleCount {
                    let sample = samples[index]
                    guard sample.isFinite else { continue }
                    sum += Double(sample) * Double(sample)
                    count += 1
                }
            }
        }
        guard count > 0 else { return }
        onLevels(envelope.consume(rms: Float(sqrt(sum / Double(count)))))
    }
}

@MainActor
final class MusicAudioLevels: ObservableObject {
    @Published private(set) var levels = [Float](repeating: 0, count: 5)
    @Published private(set) var isEnabled: Bool
    @Published private(set) var hasAudioSignal = false
    @Published private(set) var status: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // First launch should request capture when Music plays. Respect an
        // explicit saved choice to turn the feature off.
        let enabled = defaults.object(forKey: "audioReactiveWavesEnabled") as? Bool ?? true
        isEnabled = enabled
        status = enabled ? "Waiting for audio" : "Audio-reactive waves off"
    }

    private var stream: SCStream?
    private var output: MusicAudioOutput?
    private let audioQueue = DispatchQueue(label: "com.minnow.audio-levels",
                                           qos: .userInteractive)
    private var wantsPlayback = false
    private var captureSource: MusicSource?
    private var sourceName: String { captureSource?.displayName ?? "player" }
    private var suspended = false
    private var generation = 0
    private var reconcileTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var firstSampleTask: Task<Void, Never>?

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "audioReactiveWavesEnabled")
        status = enabled ? "Waiting for playback" : "Audio-reactive waves off"
        requestUpdate()
    }

    func setPlayback(_ target: AudioCaptureTarget) {
        guard wantsPlayback != target.isPlaying || captureSource != target.source else { return }
        wantsPlayback = target.isPlaying
        captureSource = target.source
        requestUpdate()
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        requestUpdate()
    }

    func stop() {
        isEnabled = false // Does not change the saved user preference.
        wantsPlayback = false
        requestUpdate()
    }

    private var shouldCapture: Bool {
        isEnabled && wantsPlayback && captureSource != nil && !suspended
    }

    private func requestUpdate() {
        generation += 1
        silenceTask?.cancel()
        firstSampleTask?.cancel()
        hasAudioSignal = false
        levels = Array(repeating: 0, count: 5)
        // Serialize asynchronous start/stop operations. A changed generation
        // causes the in-flight setup to be discarded before it can publish.
        guard reconcileTask == nil else { return }
        reconcileTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while true {
                let version = self.generation
                await self.reconcile(version: version)
                if version == self.generation { break }
            }
            self.reconcileTask = nil
        }
    }

    private func reconcile(version: Int) async {
        if let oldStream = stream {
            stream = nil
            try? await oldStream.stopCapture()
            output = nil
        }
        guard version == generation else { return }
        guard shouldCapture else {
            status = isEnabled ? "Waiting for playback" : "Audio-reactive waves off"
            return
        }
        status = "Starting audio capture…"
        do {
            // macOS handles capture consent here. Audio follows the active app;
            // no microphone, screen output handler or file writer is added.
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard version == generation, shouldCapture else { return }
            guard let source = captureSource,
                  let display = content.displays.first,
                  let application = content.applications.first(where: {
                      $0.bundleIdentifier == source.bundleIdentifier
                  }) else {
                status = "Active player's audio is not available"
                return
            }
            let filter = SCContentFilter(display: display, including: [application],
                                         exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48000
            configuration.channelCount = 2
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.showsCursor = false

            let sink = MusicAudioOutput(onLevels: { [weak self] values in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == version,
                          self.shouldCapture else { return }
                    self.receive(values)
                }
            }, onStop: { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == version else { return }
                    self.levels = Array(repeating: 0, count: 5)
                    self.hasAudioSignal = false
                    self.firstSampleTask?.cancel()
                    self.silenceTask?.cancel()
                    self.status = "Audio capture stopped: \(message)"
                }
            })
            let candidate = SCStream(filter: filter, configuration: configuration,
                                     delegate: sink)
            try candidate.addStreamOutput(sink, type: .audio,
                                           sampleHandlerQueue: audioQueue)
            try await candidate.startCapture()
            guard version == generation, shouldCapture else {
                try? await candidate.stopCapture()
                return
            }
            output = sink
            stream = candidate
            status = "Waiting for audio"
            firstSampleTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard let self, self.generation == version else { return }
                self.status = "No audio received — check capture access"
            }
        } catch {
            guard version == generation else { return }
            let detail = error as NSError
            status = "Capture unavailable (\(detail.code)): \(detail.localizedDescription)"
            levels = Array(repeating: 0, count: 5)
        }
    }

    private func receive(_ values: [Float]) {
        firstSampleTask?.cancel()
        firstSampleTask = nil
        levels = values
        hasAudioSignal = values.contains { $0 > 0.01 }
        status = hasAudioSignal ? "Listening to \(sourceName)" : "\(sourceName) is sending silent audio"
        silenceTask?.cancel()
        // Some sources stop sending samples during silence. A one-shot reset
        // prevents frozen bars; it does not poll Music or the capture stream.
        silenceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            self?.levels = Array(repeating: 0, count: 5)
            self?.hasAudioSignal = false
            self?.status = "Waiting for audio"
        }
    }
}

struct PlaybackIndicator: View {
    let isPlaying: Bool
    @ObservedObject var audio: MusicAudioLevels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(isPlaying ? Color.pink : Color.gray)
                    .frame(width: 2.5, height: barHeight(index))
            }
        }
        .frame(width: 18.5, height: 22)
        .animation(reduceMotion ? nil : .linear(duration: 0.045), value: audio.levels)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
        .help(audio.status)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard isPlaying, !reduceMotion else { return 4 }
        // Uneven visual weighting creates stronger high/low contrast between
        // neighbours while every bar remains driven by captured audio.
        let emphasis: [CGFloat] = [0.65, 1, 0.80, 1, 0.60]
        return 2 + CGFloat(audio.levels[index]) * 20 * emphasis[index]
    }
}

// MARK: - Shared Media Sources

enum MusicSource: String, CaseIterable, Sendable {
    case appleMusic, spotify

    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
    var bundleIdentifier: String {
        self == .spotify ? "com.spotify.client" : "com.apple.Music"
    }
}

struct AudioCaptureTarget: Equatable, Sendable {
    var source: MusicSource?
    var isPlaying = false
}

/// Pure selection logic: a new playback start wins. Pausing falls back to
/// another playing source; an inactive player retains the last selection.
struct MediaSourceSelection {
    private(set) var active: MusicSource?
    private var playing: Set<MusicSource> = []
    private var knownTracks: Set<MusicSource> = []
    private var starts: [MusicSource: Int] = [:]
    private var sequence = 0

    mutating func update(_ source: MusicSource, playing nowPlaying: Bool,
                         hasTrack: Bool) {
        if hasTrack { knownTracks.insert(source) }
        else { knownTracks.remove(source) }
        if nowPlaying && hasTrack {
            if playing.insert(source).inserted {
                sequence += 1
                starts[source] = sequence
            }
        } else {
            playing.remove(source)
        }
        if let latest = playing.max(by: { starts[$0, default: 0] < starts[$1, default: 0] }) {
            active = latest
        } else if active == nil || !knownTracks.contains(active!) {
            active = MusicSource.allCases.first { knownTracks.contains($0) }
        }
    }
}

@MainActor
protocol DesktopPlayback: AnyObject {
    var track: MusicTrack? { get }
    var isPlaying: Bool { get }
    var artwork: NSImage? { get }
    var duration: TimeInterval { get }
    var title: String { get }
    var subtitle: String { get }
    var canControlPlayback: Bool { get }
    var lastError: String? { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    func togglePlayback()
    func next()
    func previous()
    func playbackPosition(at date: Date) -> TimeInterval
    func seek(to position: TimeInterval, expectedTrackID: String)
}

extension AppleMusicPlayer: DesktopPlayback {}

@MainActor
final class MediaPlayer: ObservableObject {
    @Published private(set) var track: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var title = "No audio found"
    @Published private(set) var subtitle = "Play a song in Music or Spotify"
    @Published private(set) var canControlPlayback = false
    @Published private(set) var captureTarget = AudioCaptureTarget()

    private let appleMusic: any DesktopPlayback
    private let spotify: any DesktopPlayback
    private var selection = MediaSourceSelection()
    private var started = false

    init(appleMusic: any DesktopPlayback = AppleMusicPlayer(),
         spotify: any DesktopPlayback = SpotifyPlayer()) {
        self.appleMusic = appleMusic
        self.spotify = spotify
        appleMusic.onChange = { [weak self] in self?.synchronize(.appleMusic) }
        spotify.onChange = { [weak self] in self?.synchronize(.spotify) }
    }

    func start() {
        guard !started else { return }
        started = true
        appleMusic.start()
        spotify.start()
    }

    func stop() {
        started = false
        appleMusic.stop()
        spotify.stop()
        captureTarget = AudioCaptureTarget()
    }

    func refresh() { appleMusic.refresh(); spotify.refresh() }
    func togglePlayback() { current?.togglePlayback() }
    func next() { current?.next() }
    func previous() { current?.previous() }
    func playbackPosition(at date: Date) -> TimeInterval {
        current?.playbackPosition(at: date) ?? 0
    }

    private var current: (any DesktopPlayback)? {
        guard let source = selection.active else { return nil }
        return source == .appleMusic ? appleMusic : spotify
    }

    private func synchronize(_ changedSource: MusicSource) {
        guard started else { return }
        let changed = changedSource == .appleMusic ? appleMusic : spotify
        selection.update(changedSource, playing: changed.isPlaying,
                         hasTrack: changed.track != nil)
        guard let selected = current, let source = selection.active else {
            subtitle = spotify.lastError ?? appleMusic.lastError ?? "Play a song in Music or Spotify"
            return
        }
        track = selected.track
        artwork = selected.artwork
        duration = selected.duration
        title = selected.title
        subtitle = selected.subtitle + " · " + source.displayName
        isPlaying = selected.isPlaying
        canControlPlayback = selected.canControlPlayback
        // One publication carries source and state together. Switching between
        // two playing apps must restart audio capture even if isPlaying stays true.
        captureTarget = AudioCaptureTarget(source: source,
                                           isPlaying: selected.isPlaying && selected.canControlPlayback)
    }

    var seekTarget: SeekTarget? {
    guard
        canControlPlayback,
        duration.isFinite,
        duration > 0,
        let source = captureTarget.source,
        let id = track?.id,
        !id.isEmpty
    else {
        return nil
    }

    return SeekTarget(source: source, trackID: id)
}

func seek(to position: TimeInterval, expected target: SeekTarget) {
    guard seekTarget == target else { return }

    current?.seek(
        to: position,
        expectedTrackID: target.trackID
    )
}
}

// MARK: - Spotify Desktop Playback

@MainActor
final class SpotifyPlayer: ObservableObject, DesktopPlayback {
    @Published private(set) var track: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var duration: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var lastError: String?
    var onChange: (@MainActor () -> Void)?

    private var positionAtUpdate: TimeInterval = 0
    private var positionUpdatedAt = Date.now
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var isRefreshing = false
    private var artworkTrackID: String?
    private var artworkTask: Task<Void, Never>?
    private var artworkGeneration = 0

    var title: String { track?.title ?? "No audio found" }
    var subtitle: String {
        if let lastError { return lastError }
        guard let track else { return isRunning ? "Play a song in Spotify" : "Open Spotify to begin" }
        let artist = track.artist.isEmpty ? "Unknown artist" : track.artist
        return isRunning ? artist : "\(artist) · Spotify closed"
    }
    var canControlPlayback: Bool { isRunning && track != nil && lastError == nil }

    func start() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let playback = distributed.addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        observers.append((distributed, playback))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                                as? NSRunningApplication)?.bundleIdentifier
                Task { @MainActor [weak self, bundleID] in
                    guard bundleID == MusicSource.spotify.bundleIdentifier else { return }
                    self?.refresh()
                }
            }
            observers.append((workspace, token))
        }
        refresh()
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        artworkGeneration += 1
        artworkTask?.cancel()
        artworkTask = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; onChange?() }
        isRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicSource.spotify.bundleIdentifier).isEmpty
        guard isRunning else {
            positionAtUpdate = playbackPosition(at: .now)
            positionUpdatedAt = .now
            isPlaying = false
            lastError = nil
            return
        }
        guard let result = execute(Self.snapshotScript) else {
            isPlaying = false
            return
        }
        guard let state = result.atIndex(1)?.stringValue,
              let name = result.atIndex(2)?.stringValue,
              let artist = result.atIndex(3)?.stringValue,
              let album = result.atIndex(4)?.stringValue,
              let trackID = result.atIndex(5)?.stringValue else {
            isPlaying = false
            lastError = "Could not read Spotify"
            return
        }
        isPlaying = state == "playing"
        guard state != "stopped", !name.isEmpty else { return }
        duration = Self.durationInSeconds(result.atIndex(6)?.doubleValue ?? 0)
        positionAtUpdate = Self.finiteNonnegative(result.atIndex(7)?.doubleValue ?? 0)
        positionUpdatedAt = .now
        track = MusicTrack(title: name, artist: artist, album: album, id: trackID)
        if artworkTrackID != trackID || (artwork == nil && artworkTask == nil) {
            loadArtwork(for: trackID, urlString: result.atIndex(8)?.stringValue ?? "")
        }
    }

    static func durationInSeconds(_ milliseconds: Double) -> TimeInterval {
        // Spotify returns milliseconds despite the scripting dictionary's label.
        finiteNonnegative(milliseconds) / 1000
    }

    private static func finiteNonnegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    func playbackPosition(at date: Date) -> TimeInterval {
        let elapsed = isPlaying ? max(0, date.timeIntervalSince(positionUpdatedAt)) : 0
        return min(duration, max(0, positionAtUpdate + elapsed))
    }

    func togglePlayback() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard canControlPlayback, !isRefreshing else { return }
        // This private method receives only the three constant commands above.
        let script = """
        with timeout of 2 seconds
            if application id "com.spotify.client" is running then
                tell application id "com.spotify.client" to \(command)
            end if
        end timeout
        """
        isRefreshing = true
        let result = execute(script)
        isRefreshing = false
        guard result != nil else { onChange?(); return }
        refresh()
    }

    private func execute(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            lastError = "Could not prepare Spotify command"
            return nil
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard let error else { lastError = nil; return result }
        let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        switch code {
        case -1743: lastError = "Allow Spotify access in System Settings → Automation"
        case -1712: lastError = "Spotify took too long to respond"
        default: lastError = "Could not communicate with Spotify"
        }
        return nil
    }

    private func loadArtwork(for trackID: String, urlString: String) {
        artworkGeneration += 1
        let version = artworkGeneration
        artworkTask?.cancel()
        artworkTask = nil
        artworkTrackID = trackID
        artwork = nil
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else { return }
        artworkTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.artworkGeneration == version { self.artworkTask = nil }
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard let self, self.artworkGeneration == version,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      response.mimeType?.hasPrefix("image/") == true,
                      data.count <= 10 * 1024 * 1024 else { return }
                self.artwork = NSImage(data: data)
                self.onChange?()
            } catch {
                // Missing artwork must not disable playback controls.
            }
        }
    }

    func seek(to position: TimeInterval, expectedTrackID: String) {
    guard
        canControlPlayback,
        !isRefreshing,
        track?.id == expectedTrackID,
        let command = DesktopSeek.make(
            source: .spotify,
            trackID: expectedTrackID,
            position: position,
            duration: duration
        )
    else {
        return
    }

    isRefreshing = true
    let result = execute(command.script)
    isRefreshing = false

    guard let result else {
        onChange?()
        return
    }

    guard result.booleanValue else {
        refresh()
        return
    }

    positionAtUpdate = command.position
    positionUpdatedAt = .now
    onChange?()
}

    static let snapshotScript = """
    with timeout of 2 seconds
        if application id "com.spotify.client" is not running then
            return {"stopped", "", "", "", "", 0, 0, ""}
        end if
        tell application id "com.spotify.client"
            set playbackState to player state
            if playbackState is stopped then
                return {"stopped", "", "", "", "", 0, 0, ""}
            end if
            set stateText to "paused"
            if playbackState is playing then set stateText to "playing"
            set selectedTrack to current track
            if selectedTrack is missing value then
                return {stateText, "", "", "", "", 0, 0, ""}
            end if
            set coverURL to ""
            try
                set coverURL to artwork url of selectedTrack
                if coverURL is missing value then set coverURL to ""
            end try
            return {stateText, name of selectedTrack, artist of selectedTrack, ¬
                album of selectedTrack, id of selectedTrack, duration of selectedTrack, ¬
                player position, coverURL}
        end tell
    end timeout
    """
}

// MARK: - Spotify Account Authorization (PKCE)

enum SpotifyAccountError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
final class SpotifyCallbackServer {
    static let redirectURI = "http://127.0.0.1:8888/spotify/callback"
    enum CallbackResult: Equatable { case invalid, denied, code(String) }

    static func parseTarget(_ target: String, expectedState: String) -> CallbackResult {
        guard let url = URLComponents(string: "http://127.0.0.1" + target),
              url.path == "/spotify/callback" else { return .invalid }
        let items = url.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == expectedState else { return .invalid }
        if items.contains(where: { $0.name == "error" }) { return .denied }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return .invalid }
        return .code(code)
    }
    private var listener: NWListener?
    private var completion: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var expectedState = ""

    func receiveCode(state: String, authorizationURL: URL) async throws -> String {
        expectedState = state
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8888)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor [weak self] in self?.accept(connection) }
                }
                listener.stateUpdateHandler = { [weak self] listenerState in
                    Task { @MainActor [weak self] in
                        guard let self, self.completion != nil else { return }
                        switch listenerState {
                        case .ready:
                            if !NSWorkspace.shared.open(authorizationURL) {
                                self.finish(.failure(SpotifyAccountError.message("Could not open the Spotify login page")))
                            }
                        case .failed:
                            self.finish(.failure(SpotifyAccountError.message("Could not open the local Spotify callback. Check whether port 8888 is in use.")))
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(180)) } catch { return }
                    self?.finish(.failure(SpotifyAccountError.message("Spotify sign-in timed out. Try connecting again.")))
                }
            } catch { finish(.failure(error)) }
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, accumulated: Data())
    }

    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
            [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, self.completion != nil else { connection.cancel(); return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                guard bytes.count <= 16384, error == nil else { connection.cancel(); return }
                guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.read(connection, accumulated: bytes) }
                    return
                }
                let firstLine = request.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard firstLine.count >= 2, firstLine[0] == "GET" else {
                    self.respond(connection, text: "Not found", status: "404 Not Found"); return
                }
                let result = Self.parseTarget(String(firstLine[1]), expectedState: self.expectedState)
                guard result != .invalid else {
                    self.respond(connection, text: "Invalid sign-in state", status: "400 Bad Request"); return
                }
                self.respond(connection, text: "You can return to Minnow.", status: "200 OK")
                if case .code(let code) = result {
                    self.finish(.success(code))
                } else {
                    self.finish(.failure(SpotifyAccountError.message("Spotify sign-in was cancelled or denied")))
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, text: String, status: String) {
        let body = Data(text.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<String, Error>) {
        guard let completion else { return }
        self.completion = nil
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        completion.resume(with: result)
    }
}

@MainActor
final class SpotifyAccount: ObservableObject {
    static let shared = SpotifyAccount()
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var status = "Connect Spotify to use Liked Songs and repeat-one"
    private let callback = SpotifyCallbackServer()
    private var tokens: Tokens?
    private var connectTask: Task<Void, Never>?
    private var refreshTask: Task<Tokens, Error>?
    private var generation = 0
    private let service = "com.minnow.spotify.oauth"
    private let requiredScopes = "user-library-read user-library-modify user-read-playback-state user-modify-playback-state"
    private var clientID: String { UserDefaults.standard.string(forKey: "spotifyClientID") ?? "" }

    private struct Tokens: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let clientID: String
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }

    private init() {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "tokens",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let stored = try? JSONDecoder().decode(Tokens.self, from: data),
           stored.clientID == clientID {
            tokens = stored
            isConnected = true
            status = "Spotify connected"
        }
    }

    func showConnectionPrompt() {
        guard !isConnecting else { return }
        let alert = NSAlert()
        alert.messageText = "Connect Spotify"
        alert.informativeText = "Create a Web API app in Spotify's Developer Dashboard and register this exact Redirect URI:\n\n\(SpotifyCallbackServer.redirectURI)\n\nPaste its public Client ID below. A client secret is not needed. Spotify Development Mode currently requires the app owner to have Premium."
        let field = NSTextField(string: clientID)
        field.placeholderString = "Spotify Client ID"
        field.frame = CGRect(x: 0, y: 0, width: 340, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let id = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count == 32, id.allSatisfy({ $0.isHexDigit }) else {
            status = "Enter the 32-character public Client ID from Spotify's Developer Dashboard"
            showError(status); return
        }
        disconnect()
        UserDefaults.standard.set(id, forKey: "spotifyClientID")
        isConnecting = true
        status = "Waiting for Spotify sign-in"
        let version = generation
        connectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if version == self.generation {
                    self.isConnecting = false
                    self.connectTask = nil
                }
            }
            do {
                let verifier = try Self.randomURLString()
                let state = try Self.randomURLString()
                let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
                var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
                url.queryItems = [URLQueryItem(name: "client_id", value: id),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "redirect_uri", value: SpotifyCallbackServer.redirectURI),
                    URLQueryItem(name: "scope", value: self.requiredScopes),
                    URLQueryItem(name: "state", value: state),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                    URLQueryItem(name: "code_challenge", value: challenge)]
                let code = try await self.callback.receiveCode(state: state, authorizationURL: url.url!)
                try Task.checkCancellation()
                let response = try await self.exchange([
                    "grant_type": "authorization_code", "client_id": id,
                    "code": code, "code_verifier": verifier,
                    "redirect_uri": SpotifyCallbackServer.redirectURI])
                guard version == self.generation, let refresh = response.refresh_token else { return }
                let tokens = Tokens(accessToken: response.access_token, refreshToken: refresh,
                                    expiresAt: Date().addingTimeInterval(response.expires_in), clientID: id)
                try self.persist(tokens)
                self.tokens = tokens
                self.isConnected = true
                self.status = "Spotify connected"
            } catch {
                guard version == self.generation else { return }
                self.status = error.localizedDescription
                self.showError(self.status)
            }
        }
    }

    func disconnect() {
        generation += 1
        callback.cancel()
        connectTask?.cancel(); connectTask = nil
        refreshTask?.cancel(); refreshTask = nil
        tokens = nil
        isConnected = false
        isConnecting = false
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "tokens"]
        SecItemDelete(query as CFDictionary)
        status = "Spotify disconnected"
    }

    func contains(_ uri: String) async throws -> Bool {
        let data = try await request(path: "me/library/contains", method: "GET",
                                     items: [URLQueryItem(name: "uris", value: uri)])
        let values = try JSONDecoder().decode([Bool].self, from: data)
        guard let saved = values.first else { throw SpotifyAccountError.message("Spotify did not return a saved-song state") }
        return saved
    }

    func setSaved(_ saved: Bool, uri: String) async throws {
        _ = try await request(path: "me/library", method: saved ? "PUT" : "DELETE",
                              items: [URLQueryItem(name: "uris", value: uri)])
    }

    func repeatMode() async throws -> String? {
        let data = try await request(path: "me/player", method: "GET")
        if data.isEmpty { return nil }
        struct Playback: Decodable { let repeat_state: String }
        return try JSONDecoder().decode(Playback.self, from: data).repeat_state
    }

    func setRepeatOne(_ enabled: Bool) async throws {
        _ = try await request(path: "me/player/repeat", method: "PUT",
                              items: [URLQueryItem(name: "state", value: enabled ? "track" : "off")])
    }

    private func request(path: String, method: String, items: [URLQueryItem] = []) async throws -> Data {
        let version = generation
        for attempt in 0..<2 {
            let token = try await accessToken(forceRefresh: attempt > 0)
            guard version == generation else { throw CancellationError() }
            var url = URLComponents(string: "https://api.spotify.com/v1/" + path)!
            if !items.isEmpty { url.queryItems = items }
            var request = URLRequest(url: url.url!)
            request.httpMethod = method
            request.timeoutInterval = 15
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard version == generation else { throw CancellationError() }
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if code == 401 && attempt == 0 { continue }
            if code == 429 { throw SpotifyAccountError.message("Spotify is limiting requests. Try again shortly.") }
            guard (200..<300).contains(code) else {
                throw SpotifyAccountError.message("Spotify request failed (\(code)). Check account permissions and Premium access.")
            }
            return data
        }
        throw SpotifyAccountError.message("Reconnect Spotify to continue")
    }

    private func accessToken(forceRefresh: Bool) async throws -> String {
        guard let stored = tokens else { throw SpotifyAccountError.message("Connect Spotify first") }
        if !forceRefresh, stored.expiresAt.timeIntervalSinceNow > 60 { return stored.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let version = generation
        let task = Task { @MainActor in
            let response = try await self.exchange(["grant_type": "refresh_token",
                "refresh_token": stored.refreshToken, "client_id": stored.clientID])
            try Task.checkCancellation()
            return Tokens(accessToken: response.access_token,
                refreshToken: response.refresh_token ?? stored.refreshToken,
                expiresAt: Date().addingTimeInterval(response.expires_in), clientID: stored.clientID)
        }
        refreshTask = task
        defer { if version == generation { refreshTask = nil } }
        let updated = try await task.value
        guard version == generation else { throw CancellationError() }
        try persist(updated)
        tokens = updated
        return updated.accessToken
    }

    private func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(fields.map { key, value in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "="
                + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SpotifyAccountError.message("Spotify authorization failed. Check the Client ID and registered Redirect URI, then connect again.")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func persist(_ value: Tokens) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "tokens"]
        let changes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(create as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SpotifyAccountError.message("Could not save Spotify sign-in securely in Keychain (\(status))") }
    }

    private static func randomURLString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SpotifyAccountError.message("Could not prepare secure Spotify sign-in")
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Spotify Connection"
        alert.informativeText = message
        alert.runModal()
    }
}

// MARK: - Customizable Player Action

enum PlayerAction: String, CaseIterable, Identifiable {
    case like, shuffle, replay
    var id: String { rawValue }
    var title: String {
        switch self { case .like: "Like Song"; case .shuffle: "Shuffle"; case .replay: "Repeat Song" }
    }
}

@MainActor
final class PlayerAccessories: ObservableObject {
    @Published private(set) var liked: Bool?
    @Published private(set) var shuffled: Bool?
    @Published private(set) var repeatOne: Bool?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private let player: MediaPlayer
    let account: SpotifyAccount
    private var source: MusicSource?
    private var trackID: String?
    private var revision = 0
    private var refreshTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(player: MediaPlayer, account: SpotifyAccount = .shared) {
        self.player = player
        self.account = account
        player.$captureTarget.sink { [weak self] target in
            guard let self else { return }
            let id = player.track?.id
            guard self.source != target.source || self.trackID != id else { return }
            self.source = target.source
            self.trackID = id
            self.refresh()
        }.store(in: &subscriptions)
        account.$isConnected.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refresh()
        }.store(in: &subscriptions)
    }

    func stop() {
        revision += 1
        refreshTask?.cancel(); actionTask?.cancel()
        subscriptions.removeAll()
    }

    func symbol(for action: PlayerAction) -> String {
        switch action {
        case .like: liked == true ? "heart.fill" : "heart"
        case .shuffle: "shuffle"
        case .replay: repeatOne == true ? "repeat.1" : "repeat"
        }
    }

    func active(_ action: PlayerAction) -> Bool {
        switch action { case .like: liked == true; case .shuffle: shuffled == true; case .replay: repeatOne == true }
    }

    func canUse(_ action: PlayerAction) -> Bool {
        guard player.canControlPlayback, !busy else { return false }
        if source == .spotify, action != .shuffle, !account.isConnected { return true }
        switch action { case .like: return liked != nil; case .shuffle: return shuffled != nil; case .replay: return repeatOne != nil }
    }

    func help(for action: PlayerAction) -> String {
        if source == .spotify, action != .shuffle, !account.isConnected {
            return "Connect Spotify to use \(action.title). Right-click to choose another action."
        }
        return action.title + ". Right-click to customize."
    }

    func refresh() {
        revision += 1
        let version = revision
        refreshTask?.cancel()
        liked = nil; shuffled = nil; repeatOne = nil; error = nil
        guard let source, player.track != nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if source == .appleMusic {
                    guard let id = self.trackID, Self.validAppleID(id) else { return }
                    let result = try self.run(Self.appleStateScript(id: id))
                    guard version == self.revision else { return }
                    guard result.numberOfItems == 3 else { throw SpotifyAccountError.message("The playing track changed. Open the player again to refresh.") }
                    self.liked = result.atIndex(1)?.booleanValue
                    self.shuffled = result.atIndex(2)?.booleanValue
                    self.repeatOne = result.atIndex(3)?.booleanValue
                } else {
                    let result = try self.run(Self.spotifyShuffleScript)
                    guard version == self.revision else { return }
                    self.shuffled = result.booleanValue
                    if self.account.isConnected {
                        if let uri = self.trackID, Self.validSpotifyURI(uri) {
                            let saved = try await self.account.contains(uri)
                            guard version == self.revision else { return }
                            self.liked = saved
                        }
                        let mode = try await self.account.repeatMode()
                        guard version == self.revision else { return }
                        self.repeatOne = mode.map { $0 == "track" }
                    }
                }
            } catch is CancellationError {
            } catch {
                guard version == self.revision else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func perform(_ action: PlayerAction) {
        guard canUse(action), let source else { return }
        if source == .spotify, action != .shuffle, !account.isConnected {
            account.showConnectionPrompt()
            return
        }
        let id = trackID
        let version = revision
        let newLiked = !(liked ?? false)
        let newShuffle = !(shuffled ?? false)
        let newRepeat = !(repeatOne ?? false)
        busy = true; error = nil
        actionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.actionTask = nil }
            guard version == self.revision else { return }
            do {
                if source == .appleMusic {
                    guard let id, Self.validAppleID(id) else { return }
                    let command: String
                    switch action {
                    case .like: command = "set favorited of current track to \(newLiked ? "true" : "false")"
                    case .shuffle: command = "set shuffle enabled to \(newShuffle ? "true" : "false")"
                    case .replay: command = "set song repeat to \(newRepeat ? "one" : "off")"
                    }
                    let script = """
                    with timeout of 2 seconds
                        tell application id "com.apple.Music"
                            if persistent ID of current track is not "\(id)" then return false
                            \(command)
                            return true
                        end tell
                    end timeout
                    """
                    guard try self.run(script).booleanValue else {
                        throw SpotifyAccountError.message("The song changed before the action completed. Try again.")
                    }
                } else {
                    switch action {
                    case .like:
                        guard let id, Self.validSpotifyURI(id) else {
                            throw SpotifyAccountError.message("This item cannot be saved to Spotify Liked Songs")
                        }
                        try await self.account.setSaved(newLiked, uri: id)
                    case .shuffle:
                        _ = try self.run("""
                        with timeout of 2 seconds
                            tell application id "com.spotify.client"
                                set shuffling to \(newShuffle ? "true" : "false")
                            end tell
                        end timeout
                        """)
                    case .replay: try await self.account.setRepeatOne(newRepeat)
                    }
                }
                guard version == self.revision else { return }
                // Read back the actual application/account state instead of
                // colouring the icon before a write has succeeded.
                self.refresh()
            } catch is CancellationError {
            } catch {
                guard version == self.revision else { return }
                self.error = error.localizedDescription
            }
        }
    }

    static func validSpotifyURI(_ value: String) -> Bool {
        let prefix = "spotify:track:"
        guard value.hasPrefix(prefix) else { return false }
        let id = value.dropFirst(prefix.count)
        return id.count == 22 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func validAppleID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isHexDigit }
    }

    private func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw SpotifyAccountError.message("Could not prepare the player action")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if code == -1743 { throw SpotifyAccountError.message("Allow Minnow access in System Settings → Privacy & Security → Automation") }
            throw SpotifyAccountError.message("The player could not complete the action (\(code))")
        }
        return result
    }

    static func appleStateScript(id: String) -> String {
        """
        with timeout of 2 seconds
            tell application id "com.apple.Music"
                if persistent ID of current track is not "\(id)" then return {}
                return {favorited of current track, shuffle enabled, song repeat is one}
            end tell
        end timeout
        """
    }

    static let spotifyShuffleScript = """
    with timeout of 2 seconds
        tell application id "com.spotify.client" to return shuffling
    end timeout
    """
}

struct PlayerActionButton: View {
    @ObservedObject var accessories: PlayerAccessories
    @AppStorage("islandPlayerAction") private var storedAction = PlayerAction.like.rawValue
    private var action: PlayerAction { PlayerAction(rawValue: storedAction) ?? .like }
    var body: some View {
        Button { accessories.perform(action) } label: {
            Image(systemName: accessories.symbol(for: action))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accessories.active(action) ? Color.pink : Color.white)
                .frame(width: 36, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!accessories.canUse(action))
        .opacity(accessories.canUse(action) ? 1 : 0.35)
        .help(accessories.help(for: action))
        .accessibilityLabel(action.title)
        .accessibilityValue(accessories.active(action) ? "On" : "Off")
        .contextMenu {
            ForEach(PlayerAction.allCases) { option in
                Button { storedAction = option.rawValue } label: {
                    if action == option { Label(option.title, systemImage: "checkmark") }
                    else { Text(option.title) }
                }
            }
        }
    }
}

// MARK: - System Audio Outputs

struct AudioOutputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let symbol: String
    let nativeIcon: NSImage?
}

@MainActor
final class AudioOutputs: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var selectedID: AudioDeviceID = 0
    @Published private(set) var error: String?
    private var started = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress,
                             AudioObjectPropertyListenerBlock)] = []
    private let system = AudioObjectID(kAudioObjectSystemObject)
    var current: AudioOutputDevice? { devices.first { $0.id == selectedID } }

    func start() { guard !started else { return }; started = true; reload() }
    func stop() { started = false; removeListeners() }

    func reload() {
        removeListeners()
        selectedID = integer(system, kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            devices = []; error = "Could not read audio outputs"; return
        }
        guard size > 0 else {
            devices = []
            if started {
                observe(system, kAudioHardwarePropertyDevices)
                observe(system, kAudioHardwarePropertyDefaultOutputDevice)
            }
            return
        }
        var ids = [AudioDeviceID](repeating: 0,
                                 count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { error = "Could not read audio outputs (\(status))"; return }
        devices = ids.filter { id in
            outputChannels(id) > 0 && integer(id, kAudioDevicePropertyDeviceIsAlive) != 0
                && integer(id, kAudioDevicePropertyIsHidden) != 1
                && integer(id, kAudioDevicePropertyDeviceCanBeDefaultDevice,
                           scope: kAudioDevicePropertyScopeOutput) != 0
        }.map { id in
            let name = string(id, kAudioObjectPropertyName) ?? "Audio output"
            let model = string(id, kAudioDevicePropertyModelUID) ?? ""
            let transport = integer(id, kAudioDevicePropertyTransportType) ?? 0
            return AudioOutputDevice(id: id, name: name,
                symbol: Self.symbol(name: name, model: model, transport: transport),
                nativeIcon: icon(id))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if started {
            observe(system, kAudioHardwarePropertyDevices)
            observe(system, kAudioHardwarePropertyDefaultOutputDevice)
            for id in ids {
                observe(id, kAudioObjectPropertyName)
                observe(id, kAudioDevicePropertyDeviceIsAlive)
                observe(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
                observe(id, kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
            }
        }
    }

    func select(_ device: AudioOutputDevice) {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(system, &address, &settable) == noErr,
              settable.boolValue else { error = "The system output cannot be changed"; return }
        var id = device.id
        let status = AudioObjectSetPropertyData(system, &address, 0, nil,
                                               UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard status == noErr else { error = "Could not select \(device.name) (\(status))"; return }
        error = nil
        reload()
    }

    static func symbol(name: String, model: String, transport: UInt32) -> String {
        let identity = (model + " " + name).lowercased().replacingOccurrences(of: " ", with: "")
        if identity.contains("airpodsmax") { return "airpodsmax" }
        if identity.contains("airpodspro") { return "airpodspro" }
        if identity.contains("airpods") { return "airpods" }
        if identity.contains("headphone") || identity.contains("headset") { return "headphones" }
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return "wave.3.right" // Unknown Bluetooth model: use a neutral audio-route icon.
        }
        if transport == kAudioDeviceTransportTypeAirPlay { return "airplay.audio" }
        if transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort {
            return "display"
        }
        return "speaker.wave.2"
    }

    private func property(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func integer(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = property(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func icon(_ id: AudioObjectID) -> NSImage? {
        var address = property(kAudioDevicePropertyIcon)
        var value: Unmanaged<CFURL>?
        var size = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let url = value?.takeRetainedValue() else { return nil }
        return NSImage(contentsOf: url as URL)
    }

    private func outputChannels(_ id: AudioDeviceID) -> Int {
        var address = property(kAudioDevicePropertyStreamConfiguration,
                               scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                           alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory) == noErr else { return 0 }
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func observe(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = property(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.started else { return }
                self.reload()
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func removeListeners() {
        for (object, original, block) in listeners {
            var address = original
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
    }
}

struct AudioOutputIcon: View {
    let device: AudioOutputDevice?

    var body: some View {
        Group {
            if let device,
               let icon = device.nativeIcon,
               !device.symbol.hasPrefix("airpods") {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(
                    systemName: device?.symbol ?? "speaker.wave.2"
                )
                .resizable()
                .scaledToFit()
            }
        }
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
    }
}

struct AudioOutputList: View {
    @ObservedObject var outputs: AudioOutputs
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound Output").font(.headline)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(outputs.devices) { device in
                        Button {
                            outputs.select(device)
                            if outputs.error == nil { close() }
                        } label: {
                            HStack(spacing: 10) {
                                AudioOutputIcon(device: device)
                                Text(device.name).lineLimit(1)
                                Spacer()
                                if device.id == outputs.selectedID { Image(systemName: "checkmark") }
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 220)
            if outputs.devices.isEmpty { Text("No connected outputs found").foregroundStyle(.secondary) }
            if let error = outputs.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(14).frame(width: 280).onAppear { outputs.reload() }
    }
}

// MARK: - Track Scrubbing

struct SeekTarget: Equatable {
    let source: MusicSource
    let trackID: String
}

struct DesktopSeek {
    let position: TimeInterval
    let script: String

    static func make(
        source: MusicSource,
        trackID: String,
        position: TimeInterval,
        duration: TimeInterval
    ) -> DesktopSeek? {
        guard
            position.isFinite,
            duration.isFinite,
            duration > 0,
            !trackID.isEmpty,
            trackID.rangeOfCharacter(
                from: .controlCharacters
            ) == nil
        else {
            return nil
        }

        // Keep the slider's right edge from skipping to the next song.
        let bounded = min(
            max(0, position),
            max(0, duration - 0.05)
        )

        let number = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            bounded
        )

        let escapedID = trackID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let identity = source == .appleMusic
            ? "persistent ID"
            : "id"

        let script = """
        with timeout of 2 seconds
            if application id "\(source.bundleIdentifier)" is not running then return false
            tell application id "\(source.bundleIdentifier)"
                if player state is stopped then return false
                if \(identity) of current track is not "\(escapedID)" then return false
                set player position to \(number)
                return true
            end tell
        end timeout
        """

        return DesktopSeek(
            position: bounded,
            script: script
        )
    }
}

@MainActor
final class ScrubSession: ObservableObject {
    @Published var draft: Double?
    var target: SeekTarget?
    @Published var editing = false
    var cancelled = false
}

struct PlaybackScrubber: View {
    @ObservedObject var player: MediaPlayer

    let isExpanded: Bool
    var onEditingChange: (Bool) -> Void = { _ in }

    @StateObject private var session = ScrubSession()

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1,
                paused: !player.isPlaying
                    || session.editing
                    || !isExpanded
            )
        ) { context in
            let maximum = player.duration.isFinite
                ? max(1, player.duration)
                : 1

            let live = min(
                maximum,
                max(
                    0,
                    player.playbackPosition(at: context.date)
                )
            )

            let displayed = session.draft ?? live

            HStack(spacing: 10) {
                // Elapsed time.
                Text(timeLabel(displayed))
                    .frame(width: 34, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Full song length.
                        Capsule()
                            .fill(.white.opacity(0.18))

                        // Elapsed portion.
                        Capsule()
                            .fill(.white)
                            .frame(
                                width: geometry.size.width * CGFloat(
                                    min(
                                        1,
                                        max(0, displayed / maximum)
                                    )
                                )
                            )
                    }
                    .frame(height: 4)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard player.seekTarget != nil else {
                                    return
                                }

                                begin(at: live)

                                updateDraft(
                                    location: value.location.x,
                                    width: geometry.size.width,
                                    duration: maximum
                                )
                            }
                            .onEnded { value in
                                guard
                                    session.editing,
                                    !session.cancelled
                                else {
                                    reset()
                                    return
                                }

                                updateDraft(
                                    location: value.location.x,
                                    width: geometry.size.width,
                                    duration: maximum
                                )

                                finish()
                            }
                    )
                }
                .frame(height: 16)
                .allowsHitTesting(player.seekTarget != nil)
                .opacity(player.seekTarget == nil ? 0.35 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playback position")
                .accessibilityValue(
                    "\(timeLabel(displayed)) of "
                        + timeLabel(player.duration)
                )
                .accessibilityAdjustableAction { direction in
                    guard let target = player.seekTarget else {
                        return
                    }

                    let delta: Double

                    switch direction {
                    case .increment:
                        delta = 5
                    case .decrement:
                        delta = -5
                    @unknown default:
                        return
                    }

                    player.seek(
                        to: player.playbackPosition(at: .now) + delta,
                        expected: target
                    )
                }

                // Remaining time.
                Text(
                    "-" + timeLabel(
                        max(0, player.duration - displayed)
                    )
                )
                .frame(width: 40, alignment: .trailing)
            }
            .font(
                .system(
                    size: 11,
                    weight: .medium,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .foregroundStyle(.gray)
            .frame(height: 16)
        }
        .onChange(of: player.seekTarget) { _, _ in
            // Never apply a drag to a different song or source.
            if session.editing {
                session.cancelled = true
                session.draft = nil
                session.target = nil
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                reset()
            }
        }
        .onDisappear {
            reset()
        }
    }

    private func begin(at position: Double) {
        guard !session.editing else { return }

        session.editing = true
        session.cancelled = false
        session.target = player.seekTarget
        session.draft = position

        onEditingChange(true)
    }

    private func updateDraft(
        location: CGFloat,
        width: CGFloat,
        duration: Double
    ) {
        guard !session.cancelled else { return }

        let fraction = min(
            1,
            max(0, location / max(1, width))
        )

        session.draft = Double(fraction) * duration
    }

    private func finish() {
        defer { reset() }

        guard
            !session.cancelled,
            let target = session.target,
            let draft = session.draft
        else {
            return
        }

        // Commit once when the mouse is released.
        player.seek(to: draft, expected: target)
    }

    private func reset() {
        let wasEditing = session.editing

        session.editing = false
        session.cancelled = false
        session.draft = nil
        session.target = nil

        if wasEditing {
            onEditingChange(false)
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(
            max(0, seconds.isFinite ? seconds : 0)
        )

        return "\(value / 60):"
            + String(format: "%02d", value % 60)
    }
}