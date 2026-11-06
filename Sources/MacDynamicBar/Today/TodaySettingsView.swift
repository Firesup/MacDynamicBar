import SwiftUI

struct TodaySettingsView: View {
  @ObservedObject var settings: MinnowSettings
  @ObservedObject var today: TodayServices
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Your day in the island").font(.headline)
      Text(
        "Enable each service independently. Enabling it does not request access; use Connect to authorize Minnow. Today remains available when music is paused or Media is disabled."
      )
      .foregroundStyle(.secondary)
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle("Calendar", isOn: $settings.calendarEnabled)
          Text(
            today.calendar.snapshot.state.message
              ?? "Connected · Upcoming events through the end of today"
          )
          .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button("Connect Calendar…") { today.connectCalendar() }
              .disabled(!settings.calendarEnabled || today.calendar.snapshot.state == .loading)
            Button("Refresh") { today.refresh() }.disabled(!settings.calendarEnabled)
          }
          sources(today.calendar.snapshot.sources, selection: $settings.selectedCalendars)
            .disabled(!settings.calendarEnabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle("Reminders", isOn: $settings.remindersEnabled)
          Text(
            today.reminders.snapshot.state.message
              ?? "Connected · Incomplete reminders, including those without a due date"
          )
          .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button("Connect Reminders…") { today.connectReminders() }
              .disabled(!settings.remindersEnabled || today.reminders.snapshot.state == .loading)
            Button("Refresh") { today.refresh() }.disabled(!settings.remindersEnabled)
          }
          sources(today.reminders.snapshot.sources, selection: $settings.selectedReminderLists)
            .disabled(!settings.remindersEnabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      Text(
        "Selecting None shows no content. Saved selections are retained when a service is disabled or a list is temporarily unavailable."
      )
      .font(.caption).foregroundStyle(.secondary)
      Toggle("Show Calendar on Lock Screen", isOn: $settings.lockCalendar)
      Toggle("Show Reminders on Lock Screen", isOn: $settings.lockReminders)
      Text(
        "Personal calendar titles and reminder counts stay hidden while locked unless the corresponding switch is enabled."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
  private func sources(_ sources: [TodaySource], selection: Binding<TodaySelection>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button("All") { selection.wrappedValue = .all }
        Button("None") { selection.wrappedValue = .only([]) }
        Text(selection.wrappedValue == .all ? "All lists" : selectedCount(selection.wrappedValue))
          .font(.caption).foregroundStyle(.secondary)
      }
      ForEach(sources) { source in
        Toggle(
          isOn: Binding(
            get: { selection.wrappedValue.contains(source.id) },
            set: { selected in
              if selection.wrappedValue.contains(source.id) != selected {
                selection.wrappedValue = selection.wrappedValue.toggling(
                  source.id, available: sources)
              }
            })
        ) {
          HStack(spacing: 7) {
            Circle().fill(source.color.color).frame(width: 7, height: 7)
            Text(source.title)
            if !source.writable { Text("Read only").font(.caption).foregroundStyle(.secondary) }
          }
        }.toggleStyle(.checkbox)
      }
    }
  }
  private func selectedCount(_ selection: TodaySelection) -> String {
    if case .only(let ids) = selection {
      return ids.isEmpty ? "None selected" : "\(ids.count) selected"
    }
    return "All lists"
  }
}
