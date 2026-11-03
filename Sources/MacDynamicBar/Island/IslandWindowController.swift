import AppKit
import Combine
import SwiftUI

/// Owns native window placement and event monitors. The SwiftUI view only owns presentation.
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
        self.state = IslandState(hoverEnabled: configuration.hoverEnabled)
        expansionSubscription = state.$presentation.removeDuplicates().sink { [weak self] presentation in
            self?.resize(presentation: presentation)
        }
        installClickMonitors()
    }

    func show() {
        guard let screen = preferredScreen else { panel.orderOut(nil); return }
        let hasNotch = screen.safeAreaInsets.top > 0
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchWidth: CGFloat
        let notchCenterX: CGFloat
        if hasNotch, let left, let right {
            notchWidth = max(1, right.minX - left.maxX)
            notchCenterX = (left.maxX + right.minX) / 2
        } else {
            notchWidth = 160
            notchCenterX = screen.frame.midX
        }
        let layout = IslandLayout(
            screenFrame: screen.frame, notchWidth: notchWidth,
            notchHeight: hasNotch ? screen.safeAreaInsets.top : 28,
            notchCenterX: notchCenterX, configuration: configuration
        )
        self.layout = layout
        let hostingView = IslandHostingView(rootView: IslandView(state: state, player: player, layout: layout))
        hostingView.sizingOptions = []
        hostingView.hoverChanged = { [weak self] hovered in self?.state.setHovered(hovered) }
        panel.contentView = hostingView
        panel.setFrame(layout.frame(for: state.presentation), display: true)
        panel.orderFrontRegardless()
    }

    func toggle() { state.toggle(); panel.orderFrontRegardless() }
    func collapse() { state.collapse() }
    func hide() { state.collapse(); panel.orderOut(nil) }

    func stop() {
        expansionSubscription?.cancel()
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
        panel.close()
    }

    private var preferredScreen: NSScreen? {
        // NSScreen.main follows keyboard focus; prefer the built-in panel even on an external monitor.
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        } ?? NSScreen.screens.first
    }

    private func resize(presentation: IslandPresentation) {
        guard let layout else { return }
        let frame = layout.frame(for: presentation)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : configuration.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func installClickMonitors() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            // A local event is already delivered on the app's main event loop.
            MainActor.assumeIsolated { self?.collapseIfOutside() }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            Task { @MainActor [weak self] in self?.collapseIfOutside() }
        }
    }

    private func collapseIfOutside() {
        guard state.isExpanded, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        state.collapse()
    }
}
