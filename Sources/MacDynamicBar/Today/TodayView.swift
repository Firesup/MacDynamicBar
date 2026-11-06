import SwiftUI

extension TodayColor {
  var color: Color { Color(red: red, green: green, blue: blue) }
}

/// Compact rows live inside Minnow's existing clipped/material island surface.
struct TodayView: View {
  @ObservedObject var calendar: CalendarService
  @ObservedObject var reminders: ReminderService
  @ObservedObject var state: IslandState
  let now: Date
  @Environment(\.islandTextContrast) private var contrast

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        section("Calendar", symbol: "calendar", status: calendar.snapshot.state)
        if calendar.snapshot.state == .ready {
          if calendar.snapshot.events.isEmpty { empty("No upcoming events today") }
          ForEach(calendar.snapshot.events) { event in eventRow(event) }
        }
        section("Reminders", symbol: "checklist", status: reminders.snapshot.state)
        if let error = reminders.snapshot.saveError {
          Text(error).foregroundStyle(.orange).font(.system(size: 11, weight: .medium))
            .accessibilityLabel(error)
        }
        if reminders.snapshot.state == .ready {
          if reminders.snapshot.items.isEmpty { empty("No incomplete reminders") }
          ForEach(reminders.snapshot.dated) { item in reminderRow(item) }
          if !reminders.snapshot.undated.isEmpty {
            Text("No due date").font(.system(size: 10, weight: .semibold))
              .foregroundStyle(contrast.secondary)
            ForEach(reminders.snapshot.undated) { item in reminderRow(item) }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 18)
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(.white)
    .onChange(of: reminders.snapshot.saving) { _, saving in
      state.setCompletingReminder(!saving.isEmpty)
    }
    .onDisappear { state.setCompletingReminder(false) }
  }
  private func section(_ title: String, symbol: String, status: TodayLoadState) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
      if let message = status.message {
        HStack(spacing: 6) {
          if status == .loading { ProgressView().controlSize(.mini) }
          Text(message).font(.system(size: 11)).foregroundStyle(contrast.secondary)
        }
      }
    }
  }
  private func empty(_ message: String) -> some View {
    Text(message).font(.system(size: 11)).foregroundStyle(contrast.secondary)
  }
  private func eventRow(_ event: TodayEvent) -> some View {
    HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 2).fill(event.source.color.color).frame(width: 3)
      VStack(alignment: .leading, spacing: 3) {
        Text(event.title).font(.system(size: 12, weight: .semibold)).fixedSize(
          horizontal: false, vertical: true)
        Text(
          event.allDay
            ? "All day"
            : event.start.formatted(date: .omitted, time: .shortened)
              + " – "
              + event.end.formatted(
                date: Calendar.autoupdatingCurrent.isDate(event.start, inSameDayAs: event.end)
                  ? .omitted : .abbreviated, time: .shortened)
        )
        .font(.system(size: 11)).foregroundStyle(contrast.secondary)
        if let location = event.location, !location.isEmpty {
          Text(location).font(.system(size: 11)).foregroundStyle(contrast.secondary).lineLimit(2)
        }
        if let url = event.meetingURL {
          Link(destination: url) { Label("Open meeting", systemImage: "video") }
            .font(.system(size: 11, weight: .semibold)).help(url.absoluteString)
        }
      }
      Spacer(minLength: 0)
    }.fixedSize(horizontal: false, vertical: true)
      .accessibilityElement(children: .contain)
  }
  private func reminderRow(_ item: TodayReminder) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Button {
        // Set busy synchronously, before EventKit or the popup queue can react.
        state.setCompletingReminder(true)
        Task { @MainActor in
          await reminders.complete(item.id)
          state.setCompletingReminder(!reminders.snapshot.saving.isEmpty)
        }
      } label: {
        Image(
          systemName: reminders.snapshot.saving.contains(item.id) ? "ellipsis.circle" : "circle"
        )
        .font(.system(size: 16, weight: .medium)).foregroundStyle(item.source.color.color)
        .frame(width: 24, height: 24).contentShape(Rectangle())
      }.buttonStyle(.plain)
        .disabled(!item.source.writable || reminders.snapshot.saving.contains(item.id))
        .accessibilityLabel("Complete " + item.title)
        .help(item.source.writable ? "Mark complete" : "Read-only reminder list")
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title).fixedSize(horizontal: false, vertical: true)
        if let due = item.dueDate(in: .autoupdatingCurrent) {
          let overdue = item.isOverdue(at: now, calendar: .autoupdatingCurrent)
          Text(
            (overdue ? "Overdue · " : "")
              + due.formatted(
                date: .abbreviated,
                time: item.hasTime ? .shortened : .omitted)
          )
          .font(.system(size: 11)).foregroundStyle(overdue ? .orange : contrast.secondary)
        }
      }
      Spacer(minLength: 0)
    }.accessibilityElement(children: .contain)
  }
}

struct TodayPageSwitch: View {
  @ObservedObject var state: IslandState
  @ObservedObject var settings: MinnowSettings
  var body: some View {
    HStack(spacing: 4) {
      page(.music, title: "Music", symbol: "music.note", enabled: settings.mediaEnabled)
      page(.today, title: "Today", symbol: "calendar", enabled: settings.todayEnabled)
      if settings.shelfEnabled { page(.shelf, title: "Shelf", symbol: "tray", enabled: true) }
      Spacer(minLength: 0)
    }.padding(.horizontal, 26).frame(height: 28)
  }
  private func page(_ page: IslandPage, title: String, symbol: String, enabled: Bool) -> some View {
    let selected =
      state.effectivePage(
        mediaEnabled: settings.mediaEnabled, todayEnabled: settings.todayEnabled,
        shelfEnabled: settings.shelfEnabled)
      == page
    return Button {
      state.isOutputPickerOpen = false
      state.page = page
    } label: {
      Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(.white.opacity(selected ? 0.13 : 0), in: Capsule())
    }.buttonStyle(.plain).disabled(!enabled)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
