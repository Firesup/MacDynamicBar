import AppKit
import Combine
import CoreLocation
import WeatherKit

@MainActor final class WidgetServices: ObservableObject {
  @Published var weather = "Weather not configured"
  @Published var weatherSymbol = "cloud"
  let today: TodayServices
  private var todaySubscription: AnyCancellable?
  // Compatibility summaries are derived from the very same typed snapshots.
  var nextEvent: String {
    today.calendar.snapshot.state.message ?? today.calendar.snapshot.events.first?.title ?? "No upcoming events today"
  }
  var reminders: String {
    today.reminders.snapshot.state.message ?? "\(today.reminders.snapshot.items.count) incomplete reminders"
  }
  @Published var timerEnd: Date?
  @Published var latitude = ""
  @Published var longitude = ""
  private var weatherTask: Task<Void, Never>?
  private var weatherRequest: Task<Void, Never>?
  init(settings: MinnowSettings = .shared) {
    today = TodayServices(settings: settings)
    todaySubscription = today.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
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
  func connectCalendar() { today.connectCalendar() }
  func connectReminders() { today.connectReminders() }
  func refreshEvents() { today.refresh() }
  func stop() {
    weatherTask?.cancel()
    weatherRequest?.cancel()
    today.stop()
  }
}
