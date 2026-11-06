import Combine
import Foundation

// MARK: - Presentation State

enum IslandContentPolicy {
  static func hasContent(
    mediaEnabled: Bool, hiddenAfterPause: Bool, todayEnabled: Bool,
    hasPopup: Bool, hasActivity: Bool, shelfEnabled: Bool = false
  ) -> Bool {
    hasPopup || hasActivity || todayEnabled || shelfEnabled || (mediaEnabled && !hiddenAfterPause)
  }
}

enum IslandPage: String, Equatable { case music, today, shelf }

enum IslandPresentation: Equatable {
  case compact, hover, expanded
}

@MainActor
final class IslandState: ObservableObject {
  @Published private(set) var presentation: IslandPresentation = .compact
  @Published var page: IslandPage = .music
  @Published private(set) var completingReminder = false
  @Published private(set) var draggingShelf = false
  private var beforeShelfDrop: (page: IslandPage, presentation: IslandPresentation, pinned: Bool)?
  func effectivePage(mediaEnabled: Bool, todayEnabled: Bool, shelfEnabled: Bool = false)
    -> IslandPage
  {
    switch page {
    case .music where mediaEnabled: return .music
    case .today where todayEnabled: return .today
    case .shelf where shelfEnabled: return .shelf
    default:
      if todayEnabled { return .today }
      if shelfEnabled { return .shelf }
      return .music
    }
  }
  func beginShelfDrop() {
    guard beforeShelfDrop == nil else { return }
    beforeShelfDrop = (page, presentation, pinned)
    draggingShelf = true
    hoverExitTask?.cancel()
    page = .shelf
    pinned = true
    presentation = .expanded
  }
  func finishShelfDrop(accepted: Bool) {
    if let previous = beforeShelfDrop, !accepted {
      page = previous.page
      pinned = previous.pinned
      presentation = previous.presentation
    }
    beforeShelfDrop = nil
    draggingShelf = false
  }
  func setCompletingReminder(_ active: Bool) {
    completingReminder = active
    if active { hoverExitTask?.cancel() } else { scheduleHoverExit() }
  }
  @Published var isOutputPickerOpen = false {
    didSet {
      if isOutputPickerOpen { hoverExitTask?.cancel() } else { scheduleHoverExit() }
    }
  }
  @Published private(set) var scrubbing = false
  var isInteractionBusy: Bool {
    scrubbing || isOutputPickerOpen || completingReminder || draggingShelf
  }
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
    } else if !enabled {
      presentation = .compact
    }
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
    } else {
      scheduleHoverExit()
    }
  }

  func setScrubbing(_ active: Bool) {
    scrubbing = active
    if active { hoverExitTask?.cancel() } else { scheduleHoverExit() }
  }

  private func scheduleHoverExit() {
    guard !isHovered, !pinned, !scrubbing, !isOutputPickerOpen, !completingReminder, !draggingShelf
    else { return }
    hoverExitTask?.cancel()
    hoverExitTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
      guard let self, !self.isHovered, !self.pinned,
        !self.scrubbing, !self.isOutputPickerOpen, !self.completingReminder, !self.draggingShelf
      else { return }
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

  func collapseForPausedMedia(mediaEnabled: Bool, todayEnabled: Bool, shelfEnabled: Bool = false) {
    if effectivePage(
      mediaEnabled: mediaEnabled, todayEnabled: todayEnabled, shelfEnabled: shelfEnabled) == .music
    {
      collapse()
    }
  }

  func collapse() {
    beforeShelfDrop = nil
    draggingShelf = false
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
