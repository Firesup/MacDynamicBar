import SwiftUI

struct LockWidgetStrip: View {
  @ObservedObject var widgets: WidgetServices
  @ObservedObject var readings: MusicSceneWidgets
  @ObservedObject var settings: MinnowSettings
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      HStack(spacing: 22) {
        if settings.lockBattery, let battery = readings.battery {
          Label(
            "\(battery.percentage)%",
            systemImage: battery.charging ? "battery.100percent.bolt" : "battery.100percent")
        }
        if settings.lockWeather { Label(widgets.weather, systemImage: widgets.weatherSymbol) }
        if settings.lockCalendar { Label(widgets.nextEvent, systemImage: "calendar").lineLimit(1) }
        if settings.lockReminders { Label(widgets.reminders, systemImage: "checklist") }
        if let end = widgets.timerEnd {
          let seconds = max(0, Int(end.timeIntervalSince(context.date)))
          Label(String(format: "%d:%02d", seconds / 60, seconds % 60), systemImage: "timer")
            .monospacedDigit()
        }
      }.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).shadow(
        color: .black.opacity(0.4), radius: 2, y: 1)
    }
  }
}
