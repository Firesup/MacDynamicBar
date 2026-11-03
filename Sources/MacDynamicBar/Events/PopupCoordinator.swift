import Combine
import Foundation

/// Serializes temporary events without mutating the underlying music presentation.
@MainActor
final class PopupCoordinator: ObservableObject {
  @Published private(set) var active: IslandPopup?
  private(set) var pending: [IslandPopup] = []
  private var recent: [String: Date] = [:]
  private var dismissal: Task<Void, Never>?
  private var allowed = true
  private var busy = false
  private let clock: () -> Date
  private let automaticallyDismiss: Bool
  var displayDuration: TimeInterval = 2

  init(clock: @escaping () -> Date = { .now }, automaticallyDismiss: Bool = true) {
    self.clock = clock
    self.automaticallyDismiss = automaticallyDismiss
  }

  func submit(_ popup: IslandPopup) {
    let now = clock()
    guard allowed, popup.isFresh(at: now) else { return }
    recent = recent.filter { now.timeIntervalSince($0.value) < 10 }
    if !popup.isPreview, recent[popup.key] != nil { return }
    recent[popup.key] = now
    pending.removeAll { $0.key == popup.key || !$0.isFresh(at: now) }
    if let active, popup.priority > active.priority, !busy {
      // Superseded information is dropped, rather than replayed after a critical alert.
      dismissal?.cancel()
      self.active = nil
    }
    pending.append(popup)
    pending.sort {
      $0.priority == $1.priority ? $0.createdAt < $1.createdAt : $0.priority > $1.priority
    }
    pending = Array(pending.prefix(8))
    presentNext()
  }

  func setBusy(_ busy: Bool) {
    self.busy = busy
    if !busy { presentNext() }
  }

  func setAllowed(_ allowed: Bool) {
    guard self.allowed != allowed else { return }
    self.allowed = allowed
    if !allowed { clear() } else { presentNext() }
  }

  func discard(kind: IslandPopup.Kind) {
    pending.removeAll { $0.kind == kind }
    if active?.kind == kind { dismiss() }
  }

  func dismiss() {
    dismissal?.cancel()
    dismissal = nil
    active = nil
    presentNext()
  }

  func clear() {
    dismissal?.cancel()
    dismissal = nil
    pending.removeAll()
    active = nil
  }

  private func presentNext() {
    guard allowed, !busy, active == nil else { return }
    pending.removeAll { !$0.isFresh(at: clock()) }
    guard !pending.isEmpty else { return }
    let popup = pending.removeFirst()
    active = popup
    guard automaticallyDismiss else { return }
    dismissal = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(min(10, max(1, self?.displayDuration ?? 2)))) } catch
      { return }
      guard let self, self.active?.id == popup.id else { return }
      self.dismiss()
    }
  }
}
