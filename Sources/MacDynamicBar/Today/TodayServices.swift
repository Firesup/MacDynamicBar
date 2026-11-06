import AppKit
import Combine
import EventKit

/// Owns refresh lifecycle for the two services, without a polling loop.
@MainActor final class TodayServices: ObservableObject {
  let calendar: CalendarService
  let reminders: ReminderService
  @Published private(set) var now = Date.now
  private let settings: MinnowSettings
  private var subscriptions = Set<AnyCancellable>()
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var refreshTask: Task<Void, Never>?
  private var boundaryTask: Task<Void, Never>?
  private var calendarConnectTask: Task<Void, Never>?
  private var remindersConnectTask: Task<Void, Never>?
  private var started = false
  private var lastConfiguration: Configuration?
  private struct Configuration: Equatable {
    var calendar: Bool
    var reminders: Bool
    var calendars: TodaySelection
    var lists: TodaySelection
  }

  init(settings: MinnowSettings, provider: (any CalendarProviding & ReminderProviding)? = nil) {
    self.settings = settings
    let store = provider ?? EventKitTodayStore()
    calendar = CalendarService(provider: store)
    reminders = ReminderService(provider: store)
    reminders.onCompletionFinished = { [weak self] in self?.refresh() }
    calendar.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    reminders.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
      guard let self, self.started else { return }
      self.applySettings()
    }.store(in: &subscriptions)
  }
  func start() {
    guard !started else { return }
    started = true
    observe(.default, .EKEventStoreChanged)
    observe(.default, .NSCalendarDayChanged)
    observe(.default, .NSSystemTimeZoneDidChange)
    observe(.default, NSNotification.Name.NSSystemClockDidChange)
    observe(.default, NSApplication.didBecomeActiveNotification)
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidBecomeActiveNotification)
    applySettings()
  }
  private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    observers.append((center, token))
  }
  func applySettings() {
    let next = Configuration(
      calendar: settings.calendarEnabled, reminders: settings.remindersEnabled,
      calendars: settings.selectedCalendars, lists: settings.selectedReminderLists)
    guard next != lastConfiguration else { return }
    lastConfiguration = next
    calendar.configure(enabled: next.calendar, selection: next.calendars)
    reminders.configure(enabled: next.reminders, selection: next.lists)
    refresh()
  }
  func refresh() {
    guard started else { return }
    // EventKit often notifies during save. Refresh after the explicit write settles.
    guard reminders.snapshot.saving.isEmpty else { return }
    refreshTask?.cancel()
    boundaryTask?.cancel()
    // Invalidate before debouncing, including permission revocations and source changes.
    calendar.invalidate()
    reminders.invalidate()
    refreshTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      guard let self else { return }
      self.now = .now
      let clockCalendar = Calendar.autoupdatingCurrent
      await self.calendar.refresh(now: self.now, calendar: clockCalendar)
      guard !Task.isCancelled else { return }
      await self.reminders.refresh(now: self.now, calendar: clockCalendar)
      guard !Task.isCancelled else { return }
      self.scheduleBoundary(calendar: clockCalendar)
    }
  }
  private func scheduleBoundary(calendar: Calendar) {
    guard settings.todayEnabled else { return }
    let current = Date.now
    let midnight = TodayWindow(now: current, calendar: calendar).end
    let boundaries =
      self.calendar.snapshot.events.map(\.end)
      + reminders.snapshot.items.compactMap { $0.overdueBoundary(in: calendar) }
    let next = boundaries.filter { $0 > current }.reduce(midnight, min)
    boundaryTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(max(0.1, next.timeIntervalSinceNow))) } catch {
        return
      }
      self?.refresh()
    }
  }
  func connectCalendar() {
    calendarConnectTask?.cancel()
    calendarConnectTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.calendar.connect()
      // Preserve a request error; the Retry control can fetch again explicitly.
      if case .unavailable = self.calendar.snapshot.state { return }
      self.refresh()
    }
  }
  func connectReminders() {
    remindersConnectTask?.cancel()
    remindersConnectTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.reminders.connect()
      if case .unavailable = self.reminders.snapshot.state { return }
      self.refresh()
    }
  }
  func stop() {
    started = false
    lastConfiguration = nil
    refreshTask?.cancel()
    boundaryTask?.cancel()
    calendarConnectTask?.cancel()
    remindersConnectTask?.cancel()
    observers.forEach { $0.0.removeObserver($0.1) }
    observers.removeAll()
    calendar.invalidate()
    reminders.invalidate()
  }
}
