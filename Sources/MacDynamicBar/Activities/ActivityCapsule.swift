import AppKit
import SwiftUI

struct ActivityDetailView: View {
  let activity: IslandActivity
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: activity.symbol).font(.title2).foregroundStyle(.green)
      Text(activity.title).font(.headline)
      Text(activity.compact).font(.title3.monospacedDigit())
      Text(activity.detail).font(.caption).foregroundStyle(.secondary)
    }.padding(20).frame(minWidth: 200)
  }
}

/// Separate hit-tested panel: the gap between the island and capsule passes clicks through.
@MainActor final class ActivityCapsule {
  private let panel = IslandPanel()
  private var activity: IslandActivity?
  func show(_ activity: IslandActivity, beside frame: CGRect, screen: CGRect) {
    guard frame.maxX + 8 + 116 <= screen.maxX else {
      hide()
      return
    }
    if self.activity != activity {
      self.activity = activity
      panel.contentView = NSHostingView(rootView: CapsuleContent(activity: activity))
    }
    panel.setFrame(
      CGRect(x: frame.maxX + 8, y: frame.maxY - 30, width: 116, height: 30), display: true)
    panel.ignoresMouseEvents = false
    panel.orderFrontRegardless()
  }
  var containsMouse: Bool { panel.isVisible && panel.frame.contains(NSEvent.mouseLocation) }
  func hide() { panel.orderOut(nil) }
  func stop() { panel.close() }
}

private struct CapsuleContent: View {
  let activity: IslandActivity
  @State private var expanded = false
  var body: some View {
    Button {
      expanded.toggle()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: activity.symbol).foregroundStyle(.green)
        Text(activity.compact).font(.system(size: 11, weight: .semibold)).monospacedDigit()
      }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black, in: Capsule()).contentShape(Capsule())
    }.buttonStyle(.plain).help(activity.title + " · " + activity.detail)
      .accessibilityLabel(activity.title + ", " + activity.compact)
      .popover(isPresented: $expanded) { ActivityDetailView(activity: activity) }
      .preferredColorScheme(.dark)
  }
}
