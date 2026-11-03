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

// MARK: - Presentation State

enum IslandPresentation: Equatable {
    case compact, hover, expanded
}

@MainActor
final class IslandState: ObservableObject {
    @Published private(set) var presentation: IslandPresentation = .compact
    @Published var isOutputPickerOpen = false {
        didSet {
            if isOutputPickerOpen { hoverExitTask?.cancel() }
            else { scheduleHoverExit() }
        }
    }
    private var scrubbing = false
    var onToggle: (@MainActor () -> Void)?
    private var isHovered = false
    private var hoverEnabled: Bool
    private var hoverOpensPlayer = false
    private var pinned = false
    private var hoverSuppressed = false
    private var hoverExitTask: Task<Void, Never>?

    var isExpanded: Bool { presentation == .expanded }
    init(hoverEnabled: Bool = true) { self.hoverEnabled = hoverEnabled }

    func configureHover(enabled: Bool, opensPlayer: Bool) {
        hoverEnabled = enabled
        hoverOpensPlayer = opensPlayer
        guard !pinned else { return }
        if isHovered && enabled && !hoverSuppressed {
            presentation = opensPlayer ? .expanded : .hover
        } else if !enabled { presentation = .compact }
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        hoverExitTask?.cancel()
        hoverExitTask = nil
        if !hovered { hoverSuppressed = false }
        guard !pinned else { return }
        if hovered {
            if hoverEnabled && !hoverSuppressed {
                presentation = hoverOpensPlayer ? .expanded : .hover
            }
        } else { scheduleHoverExit() }
    }

    func setScrubbing(_ active: Bool) {
        scrubbing = active
        if active { hoverExitTask?.cancel() }
        else { scheduleHoverExit() }
    }

    private func scheduleHoverExit() {
        guard !isHovered, !pinned, !scrubbing, !isOutputPickerOpen else { return }
        hoverExitTask?.cancel()
        hoverExitTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, !self.isHovered, !self.pinned,
                  !self.scrubbing, !self.isOutputPickerOpen else { return }
            self.presentation = .compact
        }
    }

    func toggle() {
        onToggle?()
        hoverExitTask?.cancel()
        hoverExitTask = nil
        if hoverOpensPlayer && isExpanded && !pinned {
            pinned = true
        } else if isExpanded {
            pinned = false
            isOutputPickerOpen = false
            if hoverOpensPlayer {
                hoverSuppressed = isHovered
                presentation = .compact
            } else {
                presentation = isHovered && hoverEnabled ? .hover : .compact
            }
        } else {
            pinned = true
            presentation = .expanded
        }
    }

    func collapse() {
        isOutputPickerOpen = false
        hoverExitTask?.cancel()
        hoverExitTask = nil
        pinned = false
        scrubbing = false
        isHovered = false
        hoverSuppressed = false
        presentation = .compact
    }
}


