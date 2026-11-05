import Foundation

/// Value-only presentation data. Event monitors never own windows or playback.
struct IslandPopup: Identifiable, Equatable {
  enum Kind: String { case lowBattery, charging, airPods, notification, hud, phoneCall }
  let id: UUID
  let kind: Kind
  let key: String
  let title: String
  let subtitle: String
  let symbol: String
  let percentage: Int?
  let createdAt: Date
  let isPreview: Bool

  init(
    kind: Kind, key: String, title: String, subtitle: String, symbol: String,
    percentage: Int? = nil, createdAt: Date = .now, isPreview: Bool = false
  ) {
    self.id = UUID()
    self.kind = kind
    self.key = key
    self.title = title
    self.subtitle = subtitle
    self.symbol = symbol
    self.percentage = percentage.flatMap { (0...100).contains($0) ? $0 : nil }
    self.createdAt = createdAt
    self.isPreview = isPreview
  }

  var priority: Int {
    switch kind {
    case .phoneCall: 90
    case .lowBattery: 100
    case .charging: 40
    case .airPods: 20
    case .notification: 30
    case .hud: 25
    }
  }
  var duration: TimeInterval { 2 }
  var lifetime: TimeInterval { kind == .lowBattery ? 30 : 15 }
  func isFresh(at date: Date) -> Bool { date.timeIntervalSince(createdAt) < lifetime }

  static func preview(_ kind: Kind) -> IslandPopup {
    switch kind {
    case .phoneCall:
      IslandPopup(
        kind: kind, key: "preview.phoneCall", title: "Incoming Call",
        subtitle: "Sample caller · Phone", symbol: "phone.fill", isPreview: true)
    case .hud:
      IslandPopup(
        kind: kind, key: "preview.hud", title: "Volume", subtitle: "Sound output",
        symbol: "speaker.wave.2.fill", percentage: 50, isPreview: true)
    case .notification:
      IslandPopup(
        kind: kind, key: "preview.notification", title: "Minnow",
        subtitle: "Your activity is ready", symbol: "bell.fill", isPreview: true)
    case .airPods:
      IslandPopup(
        kind: kind, key: "preview.airpods", title: "AirPods Pro",
        subtitle: "Connected", symbol: "airpodspro", percentage: 82, isPreview: true)
    case .lowBattery:
      IslandPopup(
        kind: kind, key: "preview.battery", title: "Low Battery",
        subtitle: "Connect your Mac to power", symbol: "battery.25percent", percentage: 20,
        isPreview: true)
    case .charging:
      IslandPopup(
        kind: kind, key: "preview.charging", title: "Power Connected",
        subtitle: "Charging", symbol: "battery.100percent.bolt", percentage: 64, isPreview: true)
    }
  }
}
