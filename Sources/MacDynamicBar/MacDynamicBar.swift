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

        addMenuItem(
            "Refresh Apple Music",
            action: #selector(refreshMusic),
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

    @objc private func refreshMusic() {
        island?.refreshMusic()
    }
}

// MARK: - Configuration

/// These values can be connected to the settings screen later.
/// Dimensions are measured in macOS points.
struct IslandConfiguration {
    var hoverEnabled = true

    // Space on each side of the physical notch when displaying music.
    var miniPlayerWingWidth: CGFloat = 46

    var hoverWidthIncrease: CGFloat = 32
    var hoverHeightIncrease: CGFloat = 8

    var expandedWidth: CGFloat = 460
    var expandedContentHeight: CGFloat = 190

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

    private let player = AppleMusicPlayer()

    private var layout: IslandLayout?
    private var expansionSubscription: AnyCancellable?
    private var trackSubscription: AnyCancellable?

    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func refreshMusic() {
    player.refresh()
}
    private func setMiniPlayerVisible(_ visible: Bool) {
    guard var layout else { return }

    layout.showsMiniPlayer = visible
    self.layout = layout

    resize(presentation: state.presentation)
}

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

        trackSubscription = player.$track
    .map { $0 != nil }
    .removeDuplicates()
    .sink { [weak self] visible in
        self?.setMiniPlayerVisible(visible)
    }

        installClickMonitors()
        player.start()
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
    showsMiniPlayer: player.track != nil,
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
        player.stop() // Refreshes the initial state without keeping observers.
        expansionSubscription?.cancel()
        trackSubscription?.cancel()

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

// MARK: - Playback Indicator

/// Indicates playback activity, not measured audio amplitude.
struct PlaybackIndicator: View {
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(
                isPlaying ? Color.pink : Color.gray
            )
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: isPlaying && !reduceMotion
            )
            .accessibilityLabel(
                isPlaying ? "Playing" : "Paused"
            )
    }
}

// MARK: - Island Interface

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var player: AppleMusicPlayer

    let layout: IslandLayout

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.isExpanded {
                expandedPlayer
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
                topLeadingRadius: state.isExpanded ? 32 : 0,
                bottomLeadingRadius: state.isExpanded ? 42 : 14,
                bottomTrailingRadius: state.isExpanded ? 42 : 14,
                topTrailingRadius: state.isExpanded ? 32 : 0
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

    // MARK: Compact Player / Header

    private var header: some View {
        Button(action: state.toggle) {
            HStack(spacing: 0) {
                // Left section.
                if !state.isExpanded, player.track != nil {
                    AlbumCover(
                        image: player.artwork,
                        size: min(24, layout.notchHeight - 4)
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
                            isPlaying: player.isPlaying
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
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                AlbumCover(
                    image: player.artwork,
                    size: 64
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
                }

                Spacer(minLength: 8)

                PlaybackIndicator(
                    isPlaying: player.isPlaying
                )
            }

            playbackProgress

            HStack(spacing: 42) {
                playbackButton(
                    "backward.fill",
                    label: "Previous track",
                    size: 24,
                    action: player.previous
                )

                playbackButton(
                    player.isPlaying ? "pause.fill" : "play.fill",
                    label: player.isPlaying ? "Pause" : "Play",
                    size: 30,
                    action: player.togglePlayback
                )

                playbackButton(
                    "forward.fill",
                    label: "Next track",
                    size: 24,
                    action: player.next
                )
            }
            .disabled(!player.canControlPlayback)
            .opacity(player.canControlPlayback ? 1 : 0.35)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: Progress Display

    private var playbackProgress: some View {
        // Redraw the visible progress display while playing.
        // This schedule does not fetch data from Music.
        TimelineView(
            .animation(
                minimumInterval: 1,
                paused: !player.isPlaying
            )
        ) { context in
            let position = player.playbackPosition(
                at: context.date
            )

            HStack(spacing: 10) {
                Text(timeLabel(position))
                    .frame(width: 34, alignment: .leading)

                GeometryReader { geometry in
                    Capsule()
                        .fill(.white.opacity(0.09))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.38))
                                .frame(
                                    width: geometry.size.width
                                        * progress(at: position)
                                )
                        }
                }
                .frame(height: 4)
                .accessibilityLabel("Playback progress")
                .accessibilityValue(
                    "\(timeLabel(position)) of \(timeLabel(player.duration))"
                )

                Text(
                    "-" + timeLabel(
                        max(0, player.duration - position)
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
                .font(
                    .system(size: size, weight: .semibold)
                )
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

// MARK: - Preview Playback

// MARK: - Apple Music Track

struct MusicTrack: Equatable {
    let title: String
    let artist: String
    let album: String
}

// MARK: - Apple Music Player

@MainActor
final class AppleMusicPlayer: ObservableObject {
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
    defer { isRefreshing = false }

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
        album: album
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
        guard canControlPlayback else { return }

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

        guard execute(source) != nil else { return }

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