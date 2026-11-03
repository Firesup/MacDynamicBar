import SwiftUI

/// iOS-inspired system-symbol artwork, battery treatment, and restrained typography.
/// Uses SF Symbols rather than copying private Apple pairing assets.
struct IslandPopupView: View {
  let popup: IslandPopup
  let dismiss: () -> Void
  @Environment(\.islandTextContrast) private var contrast

  private var accent: Color { popup.kind == .lowBattery ? .orange : .green }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: popup.symbol)
        .symbolRenderingMode(.hierarchical)
        .font(.system(size: popup.kind == .airPods ? 44 : 34, weight: .regular))
        .foregroundStyle(popup.kind == .airPods ? .white : accent)
        .frame(width: 56, height: 60)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(popup.title).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(
          0.8)
        Text(popup.subtitle).font(.system(size: 12, weight: .semibold))
          .foregroundStyle(contrast.secondary).lineLimit(2).fixedSize(
            horizontal: false, vertical: true)
        if let percentage = popup.percentage {
          HStack(spacing: 6) {
            Image(
              systemName: popup.kind == .charging ? "battery.100percent.bolt" : "battery.100percent"
            )
            .foregroundStyle(accent)
            Text("\(percentage)%").monospacedDigit()
          }.font(.system(size: 12, weight: .semibold))
        }
        if popup.isPreview { Text("Preview").font(.caption2).foregroundStyle(contrast.secondary) }
      }.frame(maxWidth: .infinity, alignment: .leading)
      Button(action: dismiss) { Image(systemName: "xmark.circle.fill").font(.system(size: 18)) }
        .buttonStyle(.plain).foregroundStyle(contrast.secondary).frame(width: 24).fixedSize()
        .accessibilityLabel("Dismiss popup").help("Dismiss popup")
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 10)
    .foregroundStyle(.white)
    .accessibilityElement(children: .contain)
  }
}
