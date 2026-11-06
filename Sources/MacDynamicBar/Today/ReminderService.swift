import Combine
import Foundation

@MainActor final class ReminderService: ObservableObject {
  @Published private(set) var snapshot = ReminderSnapshot()
  var onCompletionFinished: (() -> Void)?
  private let provider: any ReminderProviding
  private var generation = TodayGeneration()
  private var configurationGeneration = TodayGeneration()
  private(set) var enabled = false
  private(set) var selection: TodaySelection = .all
  init(provider: any ReminderProviding) { self.provider = provider }

  func configure(enabled: Bool, selection: TodaySelection) {
    guard self.enabled != enabled || self.selection != selection else { return }
    self.enabled = enabled
    self.selection = selection
    _ = configurationGeneration.advance()
    invalidate()
  }
  func invalidate() {
    _ = generation.advance()
    snapshot = ReminderSnapshot(
      state: enabled ? TodayLoadState(access: provider.reminderAccess) : .disabled,
      saving: snapshot.saving, saveError: snapshot.saveError)
  }
  func refresh(now: Date, calendar: Calendar) async {
    let request = generation.advance()
    guard enabled else {
      snapshot = ReminderSnapshot(saving: snapshot.saving)
      return
    }
    let saving = snapshot.saving
    let error = snapshot.saveError
    snapshot = ReminderSnapshot(
      state: TodayLoadState(access: provider.reminderAccess), saving: saving, saveError: error)
    guard provider.reminderAccess == .granted else { return }
    let sources = provider.reminderLists()
    snapshot.sources = sources
    do {
      let values = try await provider.reminders(selection: selection)
      guard generation.accepts(request), !Task.isCancelled else { return }
      guard provider.reminderAccess == .granted else {
        invalidate()
        return
      }
      let sorted = values.filter { selection.contains($0.source.id) }.sorted {
        let lhs = $0.dueDate(in: calendar) ?? .distantFuture
        let rhs = $1.dueDate(in: calendar) ?? .distantFuture
        return lhs == rhs ? $0.id < $1.id : lhs < rhs
      }
      snapshot = ReminderSnapshot(
        state: .ready, sources: sources, items: sorted,
        saving: snapshot.saving, saveError: snapshot.saveError)
    } catch {
      guard generation.accepts(request), !Task.isCancelled else { return }
      if provider.reminderAccess != .granted {
        invalidate()
        return
      }
      snapshot = ReminderSnapshot(
        state: .unavailable(error.localizedDescription), sources: sources,
        saving: snapshot.saving, saveError: snapshot.saveError)
    }
  }
  func connect() async {
    guard enabled else { return }
    let request = generation.advance()
    snapshot.state = .loading
    do { try await provider.connectReminders() } catch {
      guard generation.accepts(request) else { return }
      snapshot = ReminderSnapshot(state: .unavailable(error.localizedDescription))
    }
  }
  /// The view invokes this only from the completion button. Keep the row until
  /// save succeeds, so failure leaves the original incomplete reminder intact.
  func complete(_ id: String) async {
    guard enabled, provider.reminderAccess == .granted, snapshot.state == .ready,
      !snapshot.saving.contains(id),
      let item = snapshot.items.first(where: { $0.id == id }), item.source.writable,
      selection.contains(item.source.id)
    else { return }
    let configuration = configurationGeneration.value
    _ = generation.advance()  // Any fetch begun before this write is stale.
    snapshot.saving.insert(id)
    snapshot.saveError = nil
    defer {
      snapshot.saving.remove(id)
      onCompletionFinished?()
    }
    do {
      try await provider.complete(id, selection: selection)
      _ = generation.advance()  // Also reject a fetch that raced the write.
      guard configurationGeneration.accepts(configuration), enabled else { return }
      snapshot.items.removeAll { $0.id == id }
    } catch {
      _ = generation.advance()
      guard configurationGeneration.accepts(configuration), enabled else { return }
      if provider.reminderAccess != .granted {
        invalidate()
        return
      }
      if !snapshot.items.contains(where: { $0.id == id }) { snapshot.items.append(item) }
      snapshot.state = .ready
      snapshot.saveError = "Couldn’t complete reminder. " + error.localizedDescription
    }
  }
}
