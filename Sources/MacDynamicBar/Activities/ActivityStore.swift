import Combine
import Foundation

/// Minnow-owned activities only; never represents another app's ActivityKit data.
struct IslandActivity: Identifiable, Equatable {
  let id: String
  let title: String
  let detail: String
  let compact: String
  let symbol: String
  var isPreview = false
}

@MainActor final class ActivityStore: ObservableObject {
  @Published private(set) var entries: [IslandActivity] = []
  var primary: IslandActivity? { entries.first }
  private var previewTask: Task<Void, Never>?

  func updatePower(_ snapshot: MacBatterySnapshot) {
    entries.removeAll { $0.id == "mac.power" }
    if snapshot.onExternalPower {
      entries.append(
        IslandActivity(
          id: "mac.power", title: "Mac Battery",
          detail: snapshot.charging ? "Charging" : "Connected · Not charging",
          compact: "\(snapshot.percentage)%", symbol: "battery.100percent.bolt"))
    }
  }
  func preview() {
    previewTask?.cancel()
    entries.removeAll { $0.isPreview }
    entries.insert(
      IslandActivity(
        id: "preview.activity", title: "Activity Preview",
        detail: "Sample activity · not a live sports feed", compact: "Preview",
        symbol: "sportscourt", isPreview: true), at: 0)
    previewTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(30)) } catch { return }
      self?.entries.removeAll { $0.isPreview }
    }
  }
  func clear() {
    previewTask?.cancel()
    entries.removeAll()
  }
}
