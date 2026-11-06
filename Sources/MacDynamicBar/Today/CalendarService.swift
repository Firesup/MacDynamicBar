import Combine
import Foundation

@MainActor final class CalendarService: ObservableObject {
  @Published private(set) var snapshot = CalendarSnapshot()
  private let provider: any CalendarProviding
  private var generation = TodayGeneration()
  private(set) var enabled = false
  private(set) var selection: TodaySelection = .all
  init(provider: any CalendarProviding) { self.provider = provider }

  func configure(enabled: Bool, selection: TodaySelection) {
    guard self.enabled != enabled || self.selection != selection else { return }
    self.enabled = enabled
    self.selection = selection
    invalidate()
  }
  func invalidate() {
    _ = generation.advance()
    snapshot = CalendarSnapshot(
      state: enabled ? TodayLoadState(access: provider.calendarAccess) : .disabled)
  }
  func refresh(now: Date, calendar: Calendar) async {
    let request = generation.advance()
    guard enabled else {
      snapshot = CalendarSnapshot()
      return
    }
    snapshot = CalendarSnapshot(state: TodayLoadState(access: provider.calendarAccess))
    guard provider.calendarAccess == .granted else { return }
    let sources = provider.calendars()
    snapshot.sources = sources
    do {
      let window = TodayWindow(now: now, calendar: calendar)
      let values = try await provider.events(in: window, selection: selection)
      guard generation.accepts(request), !Task.isCancelled else { return }
      guard provider.calendarAccess == .granted else {
        invalidate()
        return
      }
      snapshot = CalendarSnapshot(
        state: .ready, sources: sources,
        events: window.upcoming(values.filter { selection.contains($0.source.id) }, at: now))
    } catch {
      guard generation.accepts(request), !Task.isCancelled else { return }
      if provider.calendarAccess != .granted {
        invalidate()
        return
      }
      snapshot = CalendarSnapshot(state: .unavailable(error.localizedDescription), sources: sources)
    }
  }
  /// Called exclusively from a Connect control, never from refresh or enable.
  func connect() async {
    guard enabled else { return }
    let request = generation.advance()
    snapshot.state = .loading
    do { try await provider.connectCalendar() } catch {
      guard generation.accepts(request) else { return }
      snapshot = CalendarSnapshot(state: .unavailable(error.localizedDescription))
    }
  }
}
