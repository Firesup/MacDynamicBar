import EventKit
import Foundation

/// An explicit empty selection is different from the initial “all” preference.
enum TodaySelection: Codable, Equatable, Sendable {
  case all
  case only(Set<String>)

  func contains(_ id: String) -> Bool {
    switch self {
    case .all: true
    case .only(let ids): ids.contains(id)
    }
  }
  func toggling(_ id: String, available: [TodaySource]) -> Self {
    var ids: Set<String>
    switch self {
    case .all: ids = Set(available.map(\.id))
    case .only(let selected): ids = selected
    }
    if !ids.insert(id).inserted { ids.remove(id) }
    return .only(ids)
  }
}

struct TodayColor: Equatable, Sendable {
  let red: Double
  let green: Double
  let blue: Double
  static let fallback = Self(red: 0.35, green: 0.65, blue: 1)
}
struct TodaySource: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let color: TodayColor
  let writable: Bool
}

enum TodayAccess: Equatable, Sendable {
  case notConnected, granted, denied, restricted, unavailable
  static func resolve(_ status: EKAuthorizationStatus) -> Self {
    switch status {
    case .notDetermined: .notConnected
    case .fullAccess: .granted
    case .denied: .denied
    case .restricted: .restricted
    case .writeOnly: .unavailable
    @unknown default: .unavailable
    }
  }
}
enum TodayLoadState: Equatable, Sendable {
  case disabled, notConnected, loading, ready, denied, restricted
  case unavailable(String)
  init(access: TodayAccess) {
    switch access {
    case .granted: self = .loading
    case .notConnected: self = .notConnected
    case .denied: self = .denied
    case .restricted: self = .restricted
    case .unavailable: self = .unavailable("Full access is required to read this content.")
    }
  }
  var message: String? {
    switch self {
    case .disabled: "Disabled in Settings → Today"
    case .notConnected: "Connect in Settings → Today"
    case .loading: "Loading…"
    case .ready: nil
    case .denied: "Access denied. Review macOS Privacy & Security."
    case .restricted: "Access restricted by macOS."
    case .unavailable(let reason): "Unavailable · " + reason
    }
  }
}
struct TodayEvent: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let start: Date
  let end: Date
  let allDay: Bool
  let source: TodaySource
  let location: String?
  let meetingURL: URL?
}
struct TodayReminder: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let due: DateComponents?
  let source: TodaySource

  var hasTime: Bool { due?.hour != nil }
  func dueDate(in calendar: Calendar) -> Date? {
    guard let due else { return nil }
    var resolved = due.calendar ?? calendar
    resolved.timeZone = due.timeZone ?? calendar.timeZone
    return resolved.date(from: due)
  }
  /// Date-only reminders become overdue at the following local midnight.
  func overdueBoundary(in calendar: Calendar) -> Date? {
    guard let date = dueDate(in: calendar) else { return nil }
    if hasTime { return date }
    var resolved = due?.calendar ?? calendar
    resolved.timeZone = due?.timeZone ?? calendar.timeZone
    return resolved.date(byAdding: .day, value: 1, to: resolved.startOfDay(for: date))
  }
  func isOverdue(at now: Date, calendar: Calendar) -> Bool {
    overdueBoundary(in: calendar).map { $0 <= now } ?? false
  }
}
struct TodayWindow: Equatable, Sendable {
  let start: Date
  let end: Date
  init(now: Date, calendar: Calendar) {
    start = calendar.startOfDay(for: now)
    end = calendar.date(byAdding: .day, value: 1, to: start)!
  }
  func upcoming(_ events: [TodayEvent], at now: Date) -> [TodayEvent] {
    events.filter { $0.start < end && $0.end > now }.sorted {
      if $0.allDay != $1.allDay { return $0.allDay }
      return $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
    }
  }
}
struct CalendarSnapshot: Equatable, Sendable {
  var state: TodayLoadState = .disabled
  var sources: [TodaySource] = []
  var events: [TodayEvent] = []
}
struct ReminderSnapshot: Equatable, Sendable {
  var state: TodayLoadState = .disabled
  var sources: [TodaySource] = []
  var items: [TodayReminder] = []
  var saving: Set<String> = []
  var saveError: String?
  var dated: [TodayReminder] { items.filter { $0.due != nil } }
  var undated: [TodayReminder] { items.filter { $0.due == nil } }
}

/// Generation checks also cover APIs that cannot reliably cancel their callbacks.
struct TodayGeneration {
  private(set) var value = 0
  mutating func advance() -> Int {
    value += 1
    return value
  }
  func accepts(_ candidate: Int) -> Bool { candidate == value }
}
