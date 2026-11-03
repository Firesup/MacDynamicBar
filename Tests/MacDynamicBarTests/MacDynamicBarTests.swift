import Foundation
import Testing

@testable import MacDynamicBar

@Test func compactMatchesPhysicalNotchAndExpansionStaysAnchored() {
  let screen = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
  let layout = IslandLayout(screenFrame: screen, notchWidth: 180, notchHeight: 38)
  #expect(layout.size(for: .compact) == CGSize(width: 180, height: 38))
  #expect(layout.size(for: .hover) == CGSize(width: 212, height: 46))
  for mode in [IslandPresentation.compact, .hover, .expanded] {
    let frame = layout.frame(for: mode)
    #expect(frame.midX == screen.midX)
    #expect(frame.maxY == screen.maxY)
    #expect(screen.contains(frame))
  }
}

@Test func offCentreNotchAndSmallDisplay() {
  let layout = IslandLayout(
    screenFrame: CGRect(x: 0, y: 0, width: 320, height: 180),
    notchWidth: 160, notchHeight: 28, notchCenterX: 175)
  #expect(layout.frame(for: .compact).midX == 175)
  #expect(layout.screenFrame.contains(layout.frame(for: .expanded)))
}

@Test @MainActor func hoverPreviewsButClickPinsExpansion() async throws {
  let state = IslandState()
  state.setHovered(true)
  #expect(state.presentation == .hover)
  state.setHovered(false)
  try await waitForCondition { state.presentation == .compact }
  #expect(state.presentation == .compact)
  state.setHovered(true)
  state.toggle()
  state.setHovered(false)
  #expect(state.presentation == .expanded)
  state.collapse()
  #expect(state.presentation == .compact)
}

@Test @MainActor func clickCollapseReturnsToHoverAndHoverCanBeDisabled() {
  let state = IslandState()
  state.setHovered(true)
  state.toggle()
  state.toggle()
  #expect(state.presentation == .hover)
  let disabled = IslandState(hoverEnabled: false)
  disabled.setHovered(true)
  #expect(disabled.presentation == .compact)
  disabled.toggle()
  #expect(disabled.presentation == .expanded)
}
