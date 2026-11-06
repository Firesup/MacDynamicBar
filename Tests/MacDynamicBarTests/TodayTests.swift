import AppKit
import EventKit
import SwiftUI
import Testing

@testable import MacDynamicBar

private let source = TodaySource(
  id: "personal", title: "Personal", color: .fallback, writable: true)
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func event(
  _ id: String = "event", start: Date = now, end: Date = now.addingTimeInterval(3600)
) -> TodayEvent {
  TodayEvent(
    id: id, title: "Design review", start: start, end: end, allDay: false,
    source: source, location: "Studio", meetingURL: URL(string: "https://example.com/meeting"))
}
private enum SaveFailure: Error { case offline }

@MainActor private final class TodayFixture: CalendarProviding, ReminderProviding {
  var calendarAccess: TodayAccess = .granted
  var reminderAccess: TodayAccess = .granted
  var calendarConnections = 0
  var reminderConnections = 0
  var calendarFetches = 0
  var reminderFetches = 0
  var writes = 0
  var failSave = false
  var failFetch = false
  var eventValues = [event()]
  var reminderValues = [
    TodayReminder(id: "undated", title: "Buy supplies", due: nil, source: source)
  ]
  var delayCalendar = false
  var delayReminders = false
  var calendarContinuation: CheckedContinuation<[TodayEvent], any Error>?
  var reminderContinuation: CheckedContinuation<[TodayReminder], any Error>?
  func connectCalendar() async throws {
    calendarConnections += 1
    calendarAccess = .granted
  }
  func connectReminders() async throws {
    reminderConnections += 1
    reminderAccess = .granted
  }
  func calendars() -> [TodaySource] { [source] }
  func reminderLists() -> [TodaySource] { [source] }
  func events(in window: TodayWindow, selection: TodaySelection) async throws -> [TodayEvent] {
    calendarFetches += 1
    if delayCalendar {
      return try await withCheckedThrowingContinuation { calendarContinuation = $0 }
    }
    if failFetch { throw SaveFailure.offline }
    return eventValues
  }
  func reminders(selection: TodaySelection) async throws -> [TodayReminder] {
    reminderFetches += 1
    if delayReminders {
      return try await withCheckedThrowingContinuation { reminderContinuation = $0 }
    }
    if failFetch { throw SaveFailure.offline }
    return reminderValues
  }
  func complete(_ id: String, selection: TodaySelection) async throws {
    writes += 1
    if failSave { throw SaveFailure.offline }
    reminderValues.removeAll { $0.id == id }
  }
}
private func torontoCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Toronto")!
  return calendar
}

@Test @MainActor func todaySelectionsPersistNoneAndMissingListsWithoutChangingLockOptIns() throws {
  let suite = "MinnowToday.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  #expect(!settings.calendarEnabled && !settings.remindersEnabled)
  settings.calendarEnabled = true
  settings.selectedCalendars = .only([])
  settings.selectedReminderLists = .only(["missing", source.id])
  let restored = MinnowSettings(defaults: defaults)
  #expect(restored.calendarEnabled && !restored.remindersEnabled)
  #expect(restored.selectedCalendars == .only([]))
  #expect(!restored.selectedCalendars.contains(source.id))
  #expect(
    restored.selectedReminderLists.toggling(source.id, available: [source]) == .only(["missing"]))
  #expect(!restored.lockCalendar && !restored.lockReminders)
  restored.resetPreferences()
  #expect(!restored.todayEnabled)
  #expect(restored.selectedCalendars == .all && restored.selectedReminderLists == .all)
}

@Test func todayBoundariesRespectDSTAndFilterOngoingVersusEndedAndTomorrow() {
  let calendar = torontoCalendar()
  let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
  let window = TodayWindow(now: spring, calendar: calendar)
  #expect(window.end.timeIntervalSince(window.start) == 23 * 3600)
  let fall = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
  let fallWindow = TodayWindow(now: fall, calendar: calendar)
  #expect(fallWindow.end.timeIntervalSince(fallWindow.start) == 25 * 3600)
  let allDay = TodayEvent(
    id: "all-day", title: "Holiday", start: window.start, end: window.end,
    allDay: true, source: source, location: nil, meetingURL: nil)
  let values = [
    event("ended", start: window.start, end: spring),
    event("ongoing", start: spring.addingTimeInterval(-600), end: spring.addingTimeInterval(600)),
    event("tomorrow", start: window.end, end: window.end.addingTimeInterval(600)), allDay,
  ]
  #expect(window.upcoming(values, at: spring).map(\.id) == ["all-day", "ongoing"])
  let nextDay = TodayWindow(now: window.end, calendar: calendar)
  #expect(nextDay.upcoming(values, at: window.end).map(\.id) == ["tomorrow"])
}

@Test func reminderDateOnlyTimedUndatedAndTimeZoneBoundaries() {
  let calendar = torontoCalendar()
  let dateOnly = TodayReminder(
    id: "day", title: "Today", due: DateComponents(year: 2026, month: 3, day: 8), source: source)
  let noon = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
  #expect(!dateOnly.isOverdue(at: noon, calendar: calendar))
  let midnight = TodayWindow(now: noon, calendar: calendar).end
  #expect(dateOnly.isOverdue(at: midnight, calendar: calendar))
  #expect(!dateOnly.isOverdue(at: midnight.addingTimeInterval(-1), calendar: calendar))
  let timed = TodayReminder(
    id: "timed", title: "Call",
    due: DateComponents(
      timeZone: TimeZone(secondsFromGMT: 0),
      year: 2026, month: 3, day: 8, hour: 12, minute: 0), source: source)
  #expect(timed.hasTime)
  #expect(
    timed.dueDate(in: calendar)?.timeIntervalSince1970
      == ISO8601DateFormatter().date(from: "2026-03-08T12:00:00Z")?.timeIntervalSince1970)
  #expect(timed.isOverdue(at: noon, calendar: calendar))
  let undated = TodayReminder(id: "none", title: "Someday", due: nil, source: source)
  #expect(undated.dueDate(in: calendar) == nil)
  #expect(!undated.isOverdue(at: .distantFuture, calendar: calendar))
}

@Test @MainActor func todayPermissionsNeverPromptDuringConfigureOrRefreshAndClearRevokedContent()
  async
{
  let fixture = TodayFixture()
  let calendar = CalendarService(provider: fixture)
  let reminders = ReminderService(provider: fixture)
  calendar.configure(enabled: true, selection: .all)
  reminders.configure(enabled: true, selection: .all)
  for access in [TodayAccess.granted, .notConnected, .denied, .restricted, .unavailable] {
    fixture.calendarAccess = access
    fixture.reminderAccess = access
    await calendar.refresh(now: now, calendar: .current)
    await reminders.refresh(now: now, calendar: .current)
    #expect(
      calendar.snapshot.state == (access == .granted ? .ready : TodayLoadState(access: access)))
    #expect(
      reminders.snapshot.state == (access == .granted ? .ready : TodayLoadState(access: access)))
    if access != .granted {
      #expect(calendar.snapshot.events.isEmpty && calendar.snapshot.sources.isEmpty)
      #expect(reminders.snapshot.items.isEmpty && reminders.snapshot.sources.isEmpty)
    }
  }
  #expect(fixture.calendarConnections == 0 && fixture.reminderConnections == 0)
  await calendar.connect()
  await reminders.connect()
  #expect(fixture.calendarConnections == 1 && fixture.reminderConnections == 1)
  #expect(TodayAccess.resolve(.writeOnly) == .unavailable)
  #expect(TodayAccess.resolve(.restricted) == .restricted)
}

@Test @MainActor func selectedNoneAndUnavailableListsReturnNoPersonalContent() async {
  let fixture = TodayFixture()
  let calendar = CalendarService(provider: fixture)
  let reminders = ReminderService(provider: fixture)
  for selection in [TodaySelection.only([]), .only(["removed-list"])] {
    calendar.configure(enabled: true, selection: selection)
    reminders.configure(enabled: true, selection: selection)
    await calendar.refresh(now: now, calendar: .current)
    await reminders.refresh(now: now, calendar: .current)
    #expect(calendar.snapshot.events.isEmpty && reminders.snapshot.items.isEmpty)
    #expect(calendar.snapshot.state == .ready && reminders.snapshot.state == .ready)
  }
  calendar.configure(enabled: false, selection: .all)
  reminders.configure(enabled: false, selection: .all)
  await calendar.connect()
  await reminders.connect()
  #expect(fixture.calendarConnections == 0 && fixture.reminderConnections == 0)
  #expect(calendar.snapshot.state == .disabled && reminders.snapshot.state == .disabled)
}

@Test @MainActor func undatedRemindersAreSeparateAndCompletionIsExplicitAndFailureRetainsRow() async
{
  let fixture = TodayFixture()
  fixture.reminderValues.append(
    TodayReminder(
      id: "due", title: "Book room",
      due: DateComponents(year: 2026, month: 1, day: 1), source: source))
  let service = ReminderService(provider: fixture)
  service.configure(enabled: true, selection: .all)
  await service.refresh(now: now, calendar: .current)
  #expect(service.snapshot.dated.map(\.id) == ["due"])
  #expect(service.snapshot.undated.map(\.id) == ["undated"])
  #expect(fixture.writes == 0)
  let original = service.snapshot.items
  fixture.failSave = true
  await service.complete("due")
  #expect(service.snapshot.items == original)
  #expect(service.snapshot.saveError != nil && service.snapshot.saving.isEmpty)
  fixture.failSave = false
  await service.complete("due")
  #expect(service.snapshot.items.map(\.id) == ["undated"])
  #expect(service.snapshot.saveError == nil)
  await service.complete("missing")
  #expect(fixture.writes == 2)
}

@Test @MainActor func readOnlyAndRevokedReminderControlsCannotWrite() async {
  let fixture = TodayFixture()
  let readOnly = TodaySource(
    id: source.id, title: source.title, color: source.color, writable: false)
  fixture.reminderValues = [
    TodayReminder(id: "read-only", title: "Shared", due: nil, source: readOnly)
  ]
  let service = ReminderService(provider: fixture)
  service.configure(enabled: true, selection: .all)
  await service.refresh(now: now, calendar: .current)
  await service.complete("read-only")
  fixture.reminderAccess = .denied
  await service.complete("read-only")
  #expect(fixture.writes == 0)
}

@Test @MainActor func staleCalendarResultsCannotRestoreDeselectedOrRevokedContent() async throws {
  let fixture = TodayFixture()
  fixture.delayCalendar = true
  let service = CalendarService(provider: fixture)
  service.configure(enabled: true, selection: .all)
  let old = Task { await service.refresh(now: now, calendar: .current) }
  try await waitForCondition { fixture.calendarContinuation != nil }
  #expect(service.snapshot.state == .loading)
  service.configure(enabled: true, selection: .only([]))
  fixture.delayCalendar = false
  await service.refresh(now: now, calendar: .current)
  fixture.calendarContinuation?.resume(returning: [event()])
  await old.value
  #expect(service.snapshot.state == .ready && service.snapshot.events.isEmpty)
  fixture.delayCalendar = true
  fixture.calendarContinuation = nil
  let revoked = Task { await service.refresh(now: now, calendar: .current) }
  try await waitForCondition { fixture.calendarContinuation != nil }
  fixture.calendarAccess = .denied
  fixture.calendarContinuation?.resume(returning: [event()])
  await revoked.value
  #expect(service.snapshot.state == .denied && service.snapshot.events.isEmpty)
}

@Test @MainActor func staleReminderResultsCannotRestoreDisabledContent() async throws {
  let fixture = TodayFixture()
  fixture.delayReminders = true
  let service = ReminderService(provider: fixture)
  service.configure(enabled: true, selection: .all)
  let old = Task { await service.refresh(now: now, calendar: .current) }
  try await waitForCondition { fixture.reminderContinuation != nil }
  service.configure(enabled: false, selection: .all)
  fixture.reminderContinuation?.resume(returning: fixture.reminderValues)
  await old.value
  #expect(service.snapshot.state == .disabled && service.snapshot.items.isEmpty)
}

@Test @MainActor func todayFetchFailuresAreUnavailableAndCanRecover() async {
  let fixture = TodayFixture()
  fixture.failFetch = true
  let service = CalendarService(provider: fixture)
  service.configure(enabled: true, selection: .all)
  await service.refresh(now: now, calendar: .current)
  if case .unavailable = service.snapshot.state {} else { Issue.record("Expected unavailable") }
  #expect(service.snapshot.events.isEmpty)
  fixture.failFetch = false
  await service.refresh(now: now, calendar: .current)
  #expect(service.snapshot.state == .ready)
}

@Test @MainActor func todaySurvivesMediaDisabledPauseAndPopupDeferralWithoutChangingPage() {
  let state = IslandState()
  state.page = .today
  state.toggle()
  #expect(state.effectivePage(mediaEnabled: false, todayEnabled: true) == .today)
  #expect(
    IslandContentPolicy.hasContent(
      mediaEnabled: false, hiddenAfterPause: true,
      todayEnabled: true, hasPopup: false, hasActivity: false))
  state.collapseForPausedMedia(mediaEnabled: false, todayEnabled: true)
  #expect(state.isExpanded)
  let popups = PopupCoordinator(automaticallyDismiss: false)
  state.setCompletingReminder(true)
  popups.setBusy(state.isInteractionBusy)
  popups.submit(.preview(.airPods))
  popups.submit(.preview(.lowBattery))
  #expect(popups.active == nil)
  state.setCompletingReminder(false)
  popups.setBusy(state.isInteractionBusy)
  #expect(popups.active?.kind == .lowBattery)
  popups.dismiss()
  popups.dismiss()
  #expect(state.page == .today && state.isExpanded)
  state.collapse()
  #expect(!state.isExpanded && state.page == .today)
}

@Test @MainActor func todayRefreshesOnEventStoreDayTimeZoneAndWakeWithoutPrompting() async throws {
  let suite = "MinnowTodayLifecycle.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  settings.calendarEnabled = true
  settings.remindersEnabled = true
  let fixture = TodayFixture()
  let today = TodayServices(settings: settings, provider: fixture)
  today.start()
  defer { today.stop() }
  try await waitForCondition { today.reminders.snapshot.state == .ready }
  for name in [
    Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange,
  ] {
    let count = fixture.calendarFetches
    NotificationCenter.default.post(name: name, object: nil)
    try await waitForCondition {
      fixture.calendarFetches > count && today.reminders.snapshot.state == .ready
    }
  }
  let count = fixture.calendarFetches
  NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
  try await waitForCondition { fixture.calendarFetches > count }
  #expect(fixture.calendarConnections == 0 && fixture.reminderConnections == 0)
  fixture.calendarAccess = .denied
  NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
  try await waitForCondition { today.calendar.snapshot.state == .denied }
  #expect(today.calendar.snapshot.events.isEmpty)
}

@Test @MainActor func todayRowsAndPageSwitchRenderAtMinimumWidthWithoutLivePermissions()
  async throws
{
  let fixture = TodayFixture()
  let calendar = CalendarService(provider: fixture)
  let reminders = ReminderService(provider: fixture)
  calendar.configure(enabled: true, selection: .all)
  reminders.configure(enabled: true, selection: .all)
  await calendar.refresh(now: now, calendar: .current)
  await reminders.refresh(now: now, calendar: .current)
  let state = IslandState()
  state.page = .today
  let host = NSHostingView(
    rootView:
      TodayView(calendar: calendar, reminders: reminders, state: state, now: now)
      .frame(width: 320, height: 204).background(.black).preferredColorScheme(.dark))
  host.frame = NSRect(x: 0, y: 0, width: 320, height: 204)
  let window = NSWindow(
    contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  defer { window.close() }
  host.layoutSubtreeIfNeeded()
  host.displayIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  #expect(bitmap.pixelsWide >= 320)
  let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent(".build/ui-checks")
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  let png = try #require(bitmap.representation(using: .png, properties: [:]))
  try png.write(to: output.appendingPathComponent("today.png"))
  #expect(fixture.writes == 0 && fixture.calendarConnections == 0)
}

@Test @MainActor func existingLockWidgetOptInsMigrateWithoutWideningSelections() throws {
  let suite = "MinnowTodayMigration.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(true, forKey: "lockCalendar")
  let settings = MinnowSettings(defaults: defaults)
  #expect(settings.calendarEnabled && settings.lockCalendar)
  #expect(!settings.remindersEnabled && !settings.lockReminders)
  settings.calendarEnabled = false
  #expect(!MinnowSettings(defaults: defaults).calendarEnabled)
}

@Test @MainActor func todayLifecycleCanStopRestartAndIgnoreStoppedNotifications() async throws {
  let suite = "MinnowTodayRestart.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  settings.calendarEnabled = true
  let fixture = TodayFixture()
  let today = TodayServices(settings: settings, provider: fixture)
  today.start()
  try await waitForCondition { today.calendar.snapshot.state == .ready }
  today.stop()
  let count = fixture.calendarFetches
  NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
  #expect(fixture.calendarFetches == count)
  today.start()
  defer { today.stop() }
  try await waitForCondition {
    fixture.calendarFetches > count && today.calendar.snapshot.state == .ready
  }
}

@Test @MainActor func todayIslandWithMediaDisabledRendersActualSurfaceAndCameraHeader() async throws
{
  let suite = "MinnowTodayIslandRender.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  settings.mediaEnabled = false
  settings.calendarEnabled = true
  settings.remindersEnabled = true
  let fixture = TodayFixture()
  let today = TodayServices(settings: settings, provider: fixture)
  today.applySettings()
  await today.calendar.refresh(now: now, calendar: .current)
  await today.reminders.refresh(now: now, calendar: .current)
  let state = IslandState()
  state.toggle()
  let session = IslandMediaSession()  // Never started; no permission or device monitoring.
  let layout = IslandLayout(
    screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    notchWidth: 160, notchHeight: 28, showsMiniPlayer: true, configuration: settings.configuration)
  let size = layout.size(for: .expanded)
  let root = IslandView(
    state: state, player: session.player, audio: session.audio,
    accessories: session.accessories, outputs: session.outputs,
    popups: PopupCoordinator(automaticallyDismiss: false), activities: ActivityStore(),
    settings: settings, today: today, shelf: ShelfStore(generatesThumbnails: false), layout: layout)
  let host = IslandHostingView(rootView: root)
  host.frame = CGRect(origin: .zero, size: size)
  host.applyAppearance(
    layout: .standard, glass: false, blur: false, opacity: 1,
    headerHeight: layout.headerHeight, shape: .notch, gradientVisibility: 0.45)
  host.move(to: size, expanded: true, animated: false)
  let window = NSWindow(
    contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  defer {
    window.close()
    host.stopAnimating()
  }
  host.layoutSubtreeIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent(".build/ui-checks/today-island.png")
  try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
  try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
  #expect(
    state.effectivePage(mediaEnabled: settings.mediaEnabled, todayEnabled: settings.todayEnabled)
      == .today)
  #expect(size.height >= layout.headerHeight + 232)
  #expect(
    fixture.writes == 0 && fixture.calendarConnections == 0 && fixture.reminderConnections == 0)
}
