import SwiftUI

/// iOS-inspired system-symbol artwork, battery treatment, and restrained typography.
/// Uses SF Symbols rather than copying private Apple pairing assets.
struct IslandPopupView: View {
  let popup: IslandPopup
  let dismiss: () -> Void
  @Environment(\.islandTextContrast) private var contrast

  private var accent: Color {
    popup.kind == .lowBattery ? .orange : (popup.kind == .notification ? .blue : .green)
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: popup.symbol)
        .symbolRenderingMode(.hierarchical)
        .font(.system(size: popup.kind == .airPods ? 32 : 28, weight: .regular))
        .foregroundStyle(popup.kind == .airPods ? .white : accent)
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(popup.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
          .minimumScaleFactor(
            0.8)
        Text(popup.subtitle).font(.system(size: 12, weight: .semibold))
          .foregroundStyle(contrast.secondary).lineLimit(2).fixedSize(
            horizontal: false, vertical: true)
        if popup.kind == .hud, let percentage = popup.percentage {
          ProgressView(value: Double(percentage), total: 100).tint(.white)
            .accessibilityLabel(popup.title).accessibilityValue("\(percentage)%")
        } else if let percentage = popup.percentage {
          HStack(spacing: 3) {
            Image(
              systemName: popup.kind == .charging
                ? "battery.100percent.bolt"
                : (popup.kind == .lowBattery ? popup.symbol : "battery.100percent")
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
