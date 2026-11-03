import AppKit
import Combine
import CoreLocation
import EventKit
import WeatherKit

@MainActor final class WidgetServices: ObservableObject {
  @Published var weather = "Weather not configured"
  @Published var weatherSymbol = "cloud"
  @Published var nextEvent = "Calendar not connected"
  @Published var reminders = "Reminders not connected"
  @Published var timerEnd: Date?
  @Published var latitude = ""
  @Published var longitude = ""
  private let store = EKEventStore()
  private var observer: NSObjectProtocol?
  private var weatherTask: Task<Void, Never>?
  private var weatherRequest: Task<Void, Never>?
  init() {
    observer = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshEvents() } }
  }
  func refreshWeather() {
    guard let lat = Double(latitude), let lon = Double(longitude), (-90...90).contains(lat),
      (-180...180).contains(lon)
    else {
      weather = "Enter valid latitude and longitude"
      return
    }
    weatherRequest?.cancel()
    weatherRequest = Task { @MainActor [weak self] in
      do {
        let result = try await WeatherService.shared.weather(
          for: CLLocation(latitude: lat, longitude: lon))
        guard let self, !Task.isCancelled else { return }
        self.weather = result.currentWeather.temperature.formatted(
          .measurement(width: .abbreviated, usage: .weather))
        self.weatherSymbol = result.currentWeather.symbolName
      } catch { self?.weather = "Weather unavailable · verify WeatherKit signing" }
    }
    if weatherTask == nil {
      weatherTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(1800)) } catch { return }
          self?.refreshWeather()
        }
      }
    }
  }
  func connectCalendar() {
    Task { @MainActor in
      do {
        if try await store.requestFullAccessToEvents() {
          refreshEvents()
        } else {
          nextEvent = "Calendar access denied"
        }
      } catch { nextEvent = "Calendar unavailable" }
    }
  }
  func connectReminders() {
    Task { @MainActor in
      do {
        if try await store.requestFullAccessToReminders() {
          refreshEvents()
        } else {
          reminders = "Reminders access denied"
        }
      } catch { reminders = "Reminders unavailable" }
    }
  }
  func refreshEvents() {
    if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
      let now = Date.now
      let predicate = store.predicateForEvents(
        withStart: now, end: now.addingTimeInterval(86400), calendars: nil)
      nextEvent =
        store.events(matching: predicate).filter { $0.endDate > now }.sorted {
          $0.startDate < $1.startDate
        }.first?.title ?? "No upcoming events"
    }
    if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
      store.fetchReminders(
        matching: store.predicateForIncompleteReminders(
          withDueDateStarting: nil, ending: nil, calendars: nil)
      ) { [weak self] entries in
        let count = entries?.count ?? 0
        Task { @MainActor [weak self] in self?.reminders = "\(count) reminders" }
      }
    }
  }
  func stop() {
    weatherTask?.cancel()
    weatherRequest?.cancel()
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
  }
}
