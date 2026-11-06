import AppKit
import EventKit

@MainActor protocol CalendarProviding: AnyObject {
  var calendarAccess: TodayAccess { get }
  func connectCalendar() async throws
  func calendars() -> [TodaySource]
  func events(in window: TodayWindow, selection: TodaySelection) async throws -> [TodayEvent]
}
@MainActor protocol ReminderProviding: AnyObject {
  var reminderAccess: TodayAccess { get }
  func connectReminders() async throws
  func reminderLists() -> [TodaySource]
  func reminders(selection: TodaySelection) async throws -> [TodayReminder]
  func complete(_ id: String, selection: TodaySelection) async throws
}

/// One EventKit store for both focused services. EventKit objects never enter view state.
@MainActor final class EventKitTodayStore: CalendarProviding, ReminderProviding {
  private let store = EKEventStore()
  var calendarAccess: TodayAccess { .resolve(EKEventStore.authorizationStatus(for: .event)) }
  var reminderAccess: TodayAccess { .resolve(EKEventStore.authorizationStatus(for: .reminder)) }
  func connectCalendar() async throws { _ = try await store.requestFullAccessToEvents() }
  func connectReminders() async throws { _ = try await store.requestFullAccessToReminders() }
  func calendars() -> [TodaySource] { store.calendars(for: .event).map(Self.source) }
  func reminderLists() -> [TodaySource] { store.calendars(for: .reminder).map(Self.source) }

  func events(in window: TodayWindow, selection: TodaySelection) async throws -> [TodayEvent] {
    let selected = store.calendars(for: .event).filter { selection.contains($0.calendarIdentifier) }
    // EventKit interprets nil/empty calendars as all. Never pass an empty selection through.
    guard !selected.isEmpty else { return [] }
    let predicate = store.predicateForEvents(
      withStart: window.start, end: window.end, calendars: selected)
    return store.events(matching: predicate).map { event in
      let url =
        Self.webURL(event.url) ?? Self.firstWebURL(in: event.location)
        ?? Self.firstWebURL(in: event.notes)
      return TodayEvent(
        id: (event.eventIdentifier ?? event.calendarItemIdentifier)
          + ".\(event.startDate.timeIntervalSince1970)",
        title: event.title ?? "Untitled event", start: event.startDate, end: event.endDate,
        allDay: event.isAllDay, source: Self.source(event.calendar),
        location: event.location, meetingURL: url)
    }
  }
  func reminders(selection: TodaySelection) async throws -> [TodayReminder] {
    let selected = store.calendars(for: .reminder).filter {
      selection.contains($0.calendarIdentifier)
    }
    guard !selected.isEmpty else { return [] }
    // No due-date bounds: nil-due reminders must be included, then grouped in the view.
    let predicate = store.predicateForIncompleteReminders(
      withDueDateStarting: nil, ending: nil, calendars: selected)
    return try await withCheckedThrowingContinuation { continuation in
      store.fetchReminders(matching: predicate) { entries in
        guard let entries else {
          continuation.resume(throwing: TodayStoreError.fetchFailed)
          return
        }
        let values = entries.filter { !$0.isCompleted }.map { reminder in
          TodayReminder(
            id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder",
            due: reminder.dueDateComponents, source: Self.source(reminder.calendar))
        }
        continuation.resume(returning: values)
      }
    }
  }
  func complete(_ id: String, selection: TodaySelection) async throws {
    guard reminderAccess == .granted,
      let reminder = store.calendarItem(withIdentifier: id) as? EKReminder,
      selection.contains(reminder.calendar.calendarIdentifier),
      reminder.calendar.allowsContentModifications
    else { throw TodayStoreError.noLongerWritable }
    guard !reminder.isCompleted else { return }
    let oldCompleted = reminder.isCompleted
    let oldDate = reminder.completionDate
    reminder.isCompleted = true
    do { try store.save(reminder, commit: true) } catch {
      reminder.isCompleted = oldCompleted
      reminder.completionDate = oldDate
      throw error
    }
  }
  nonisolated private static func source(_ calendar: EKCalendar) -> TodaySource {
    let color = calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB) }
    return TodaySource(
      id: calendar.calendarIdentifier, title: calendar.title,
      color: color.map {
        TodayColor(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent)
      } ?? .fallback,
      writable: calendar.allowsContentModifications)
  }
  nonisolated private static func webURL(_ url: URL?) -> URL? {
    guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
    return url
  }
  nonisolated private static func firstWebURL(in text: String?) -> URL? {
    guard let text,
      let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
      .compactMap { webURL($0.url) }.first
  }
}
private enum TodayStoreError: LocalizedError {
  case fetchFailed, noLongerWritable
  var errorDescription: String? {
    switch self {
    case .fetchFailed: "EventKit did not return reminders. Try refreshing."
    case .noLongerWritable: "This reminder is no longer available or its list is read-only."
    }
  }
}
