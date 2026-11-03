import Foundation

// MARK: - Background-Revealing Gradient

struct SoftGradientAppearance {
  static func bottomOpacity(visibility: Double, expansion: Double, reduceTransparency: Bool)
    -> Double
  {
    guard !reduceTransparency else { return 1 }
    let visible = visibility.isFinite ? min(0.85, max(0, visibility)) : 0.45
    let amount = expansion.isFinite ? min(1, max(0, expansion)) : 0
    return 1 - visible * amount
  }
}
