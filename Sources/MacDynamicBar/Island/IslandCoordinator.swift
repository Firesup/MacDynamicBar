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

// MARK: - Display and Visibility Coordination

@MainActor
final class IslandCoordinator {
    let settings: MinnowSettings
    let session = IslandMediaSession()
    private var controllers: [CGDirectDisplayID: IslandWindowController] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var pauseTask: Task<Void, Never>?
    private var sessionActive = true
    private var hiddenAfterPause = false
    private var previouslyEnabled = true
    private var visibilityTask: Task<Void, Never>?

    init(settings: MinnowSettings) { self.settings = settings }

    func start() {
        session.apply(settings)
        settings.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &subscriptions)
        session.player.$captureTarget.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.playbackChanged() }
            .store(in: &subscriptions)
        session.start()
        reconcileDisplays()
    }

    func applySettings() {
        session.apply(settings)
        if settings.islandEnabled && !previouslyEnabled { hiddenAfterPause = false }
        previouslyEnabled = settings.islandEnabled
        if !settings.hideOnPause { hiddenAfterPause = false }
        reconcileDisplays()
        schedulePauseActions()
    }

    func reconcileDisplays(reposition: Bool = false) {
        let screens = chosenScreens()
        let ids = Set(screens.compactMap { MinnowDisplay.from($0)?.nativeID })
        for id in Array(controllers.keys) where !ids.contains(id) {
            controllers.removeValue(forKey: id)?.stop()
        }
        let visible = settings.islandEnabled && settings.mediaEnabled && sessionActive && !hiddenAfterPause
        var anyVisible = false
        for screen in screens {
            guard let id = MinnowDisplay.from(screen)?.nativeID else { continue }
            if controllers[id] == nil {
                controllers[id] = IslandWindowController(session: session, settings: settings, displayID: id)
            }
            guard let controller = controllers[id] else { continue }
            controller.applySettings(reposition: reposition)
            if visible && !(settings.hideFullscreen && FullscreenVisibility.covers(screen)) {
                anyVisible = true
                if !controller.isVisible { controller.show() }
            } else { controller.hide() }
        }
        session.audio.setSuspended(!anyVisible)
    }

    func refreshVisibility() {
        visibilityTask?.cancel()
        visibilityTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.reconcileDisplays()
        }
    }

    func setSessionActive(_ active: Bool) {
        sessionActive = active
        reconcileDisplays()
    }

    func reposition() { reconcileDisplays(reposition: true) }
    func refresh() { session.player.refresh(); session.accessories.refresh() }
    func retryCapture() {
        guard settings.audioReactive else { return }
        session.audio.setEnabled(false)
        session.audio.setEnabled(true)
        reconcileDisplays()
    }
    func stop() {
        pauseTask?.cancel()
        visibilityTask?.cancel()
        subscriptions.removeAll()
        controllers.values.forEach { $0.stop() }
        controllers.removeAll()
        session.stop()
    }

    private func chosenScreens() -> [NSScreen] {
        if settings.allDisplays { return NSScreen.screens }
        if settings.display == "main", let main = NSScreen.screens.first(where: {
            MinnowDisplay.from($0)?.nativeID == CGMainDisplayID()
        }) { return [main] }
        if settings.display != "automatic",
           let selected = NSScreen.screens.first(where: { MinnowDisplay.from($0)?.id == settings.display }) {
            return [selected]
        }
        let builtIn = NSScreen.screens.first { screen in
            guard let id = MinnowDisplay.from(screen)?.nativeID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
        return (builtIn ?? NSScreen.screens.first).map { [$0] } ?? []
    }

    private func playbackChanged() {
        // Visibility rules apply equally to playing and paused tracks.
        reconcileDisplays()
        if session.player.isPlaying {
            pauseTask?.cancel()
            hiddenAfterPause = false
            reconcileDisplays()
        } else { schedulePauseActions() }
    }

    private func schedulePauseActions() {
        pauseTask?.cancel()
        guard !session.player.isPlaying, session.player.track != nil,
              settings.islandEnabled, settings.collapseOnPause || settings.hideOnPause else { return }
        let collapse = settings.collapseOnPause ? settings.collapseDelay : Double.infinity
        let hide = settings.hideOnPause ? settings.hideDelay : Double.infinity
        pauseTask = Task { @MainActor [weak self] in
            let first = min(collapse, hide)
            do { try await Task.sleep(for: .seconds(first)) } catch { return }
            guard let self, !self.session.player.isPlaying else { return }
            if collapse <= hide { self.controllers.values.forEach { $0.collapse() } }
            if hide <= collapse {
                self.hiddenAfterPause = true
                self.reconcileDisplays()
                return
            }
            guard hide.isFinite else { return }
            do { try await Task.sleep(for: .seconds(max(0, hide - collapse))) } catch { return }
            guard !self.session.player.isPlaying else { return }
            self.hiddenAfterPause = true
            self.reconcileDisplays()
        }
    }
}

