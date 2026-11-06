import AppKit
import QuartzCore
import SwiftUI

// MARK: - Interruptible Surface Animation

/// An exact critically damped spring. Retargeting preserves current velocity.
struct SurfaceSpring {
  var value: Double
  var velocity = 0.0
  var target: Double

  mutating func advance(by dt: Double) {
    let omega = 24.0
    let displacement = value - target
    let coefficient = velocity + omega * displacement
    let decay = exp(-omega * dt)
    value = target + (displacement + coefficient * dt) * decay
    velocity = (velocity - omega * coefficient * dt) * decay
  }

  var settled: Bool { abs(value - target) < 0.05 && abs(velocity) < 0.5 }
  mutating func finish() {
    value = target
    velocity = 0
  }
}

private struct SurfaceRenderKey: Equatable {
  let bounds: CGRect
  let width: Double
  let height: Double
  let corner: Double
  let expansion: Double
  let shape: IslandShape
  let appearance: IslandAppearanceLayout
  let glass: Bool
  let blur: Bool
  let opacity: Double
  let gradient: Double
  let header: CGFloat
  let reduceTransparency: Bool
}

/// The window never resizes during interactions. One backing surface owns
/// the fill, clipping, content bounds and hit region on every animation tick.
@MainActor
final class IslandHostingView: NSView {
  let host: NSHostingView<IslandView>
  var regionChanged: (() -> Void)?

  private var widthSpring = SurfaceSpring(value: 1, target: 1)
  private var heightSpring = SurfaceSpring(value: 1, target: 1)
  private var cornerSpring = SurfaceSpring(value: 14, target: 14)
  private var expansionSpring = SurfaceSpring(value: 0, target: 0)
  private let gradientSurface = CAGradientLayer()
  private var surfaceShape: IslandShape = .applePill
  private var ticker: Timer?
  private var accessibilityObserver: NSObjectProtocol?
  private var lastTick = 0.0
  private var surfacePath = CGPath(rect: .zero, transform: nil)
  private var surfaceRect = CGRect.zero
  private let surfaceMask = CAShapeLayer()
  private let surface = NSView()
  private let backdrop: NSView
  private let blurBackdrop = NSVisualEffectView(frame: .zero)
  private let blackShell = CAShapeLayer()
  private let insetFinish = NSView()
  private var appearanceLayout: IslandAppearanceLayout = .standard
  private var usesGlass = false
  private var usesBlur = false
  private var backgroundOpacity = 1.0
  private var gradientVisibility = 0.45
  private var headerHeight: CGFloat = 28
  private var lastSurfaceKey: SurfaceRenderKey?

  init(rootView: IslandView) {
    host = NSHostingView(rootView: rootView)
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView(frame: .zero)
      glass.cornerRadius = 0
      backdrop = glass
    } else {
      let blur = NSVisualEffectView(frame: .zero)
      blur.material = .hudWindow
      blur.blendingMode = .behindWindow
      blur.state = .active
      backdrop = blur
    }
    super.init(frame: .zero)
    updateSurfaceAppearance()
    accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateSurfaceAppearance()
        self?.applySurface()
      }
    }
    wantsLayer = true
    surface.wantsLayer = true
    surface.layer?.backgroundColor = NSColor.black.cgColor
    surface.layer?.mask = surfaceMask
    gradientSurface.isHidden = true
    gradientSurface.startPoint = CGPoint(x: 0.5, y: 1)
    gradientSurface.endPoint = CGPoint(x: 0.5, y: 0)
    gradientSurface.locations = [0, 0.3, 1]
    surface.layer?.addSublayer(gradientSurface)
    blackShell.fillColor = NSColor.black.cgColor
    blackShell.fillRule = .evenOdd
    blackShell.isHidden = true
    surface.layer?.addSublayer(blackShell)
    backdrop.isHidden = true
    host.sizingOptions = []
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor.clear.cgColor
    blurBackdrop.material = .hudWindow
    blurBackdrop.blendingMode = .behindWindow
    blurBackdrop.state = .active
    blurBackdrop.isHidden = true
    surface.addSubview(blurBackdrop)
    surface.addSubview(backdrop)
    insetFinish.wantsLayer = true
    insetFinish.isHidden = true
    insetFinish.layer?.borderWidth = 0.75
    insetFinish.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    insetFinish.layer?.masksToBounds = true
    surface.addSubview(insetFinish)
    surface.addSubview(host)
    addSubview(surface)
  }

  private func updateSurfaceAppearance() {
    appearance = NSAppearance(
      named: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        ? .accessibilityHighContrastDarkAqua : .darkAqua)
  }

  isolated deinit {
    if let accessibilityObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
    }
  }

  func applyAppearance(
    layout: IslandAppearanceLayout, glass: Bool, blur: Bool,
    opacity: Double, headerHeight: CGFloat, shape: IslandShape, gradientVisibility: Double
  ) {
    surfaceShape = shape
    appearanceLayout = layout
    usesGlass = glass
    usesBlur = blur
    backgroundOpacity = opacity
    self.gradientVisibility = gradientVisibility
    self.headerHeight = headerHeight
    applySurface()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override var isFlipped: Bool { true }

  func move(to size: CGSize, expanded: Bool, animated: Bool) {
    widthSpring.target = size.width
    heightSpring.target = size.height
    cornerSpring.target = expanded ? 32 : 14
    expansionSpring.target = expanded ? 1 : 0
    if !animated {
      stopAnimating()
      widthSpring.finish()
      heightSpring.finish()
      cornerSpring.finish()
      expansionSpring.finish()
      applySurface()
      return
    }
    guard ticker == nil else { return }
    lastTick = CACurrentMediaTime()
    let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    ticker = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stopAnimating() {
    ticker?.invalidate()
    ticker = nil
  }

  override func layout() {
    super.layout()
    applySurface()
  }

  func containsScreenPoint(_ point: NSPoint) -> Bool {
    guard let window else { return false }
    let local = convert(window.convertPoint(fromScreen: point), from: nil)
    let inSurface = CGPoint(
      x: local.x - surfaceRect.minX,
      y: local.y - surfaceRect.minY)
    return surfacePath.contains(inSurface)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    let inSurface = CGPoint(
      x: local.x - surfaceRect.minX,
      y: local.y - surfaceRect.minY)
    guard surfacePath.contains(inSurface) else { return nil }
    return super.hitTest(point)
  }

  private func tick() {
    let now = CACurrentMediaTime()
    let dt = max(0, now - lastTick)
    lastTick = now
    widthSpring.advance(by: dt)
    heightSpring.advance(by: dt)
    cornerSpring.advance(by: dt)
    expansionSpring.advance(by: dt)
    if widthSpring.settled && heightSpring.settled && cornerSpring.settled
      && expansionSpring.settled
    {
      widthSpring.finish()
      heightSpring.finish()
      cornerSpring.finish()
      expansionSpring.finish()
      stopAnimating()
    }
    applySurface()
  }

  private func applySurface() {
    let key = SurfaceRenderKey(bounds: bounds, width: widthSpring.value, height: heightSpring.value,
      corner: cornerSpring.value, expansion: expansionSpring.value, shape: surfaceShape,
      appearance: appearanceLayout, glass: usesGlass, blur: usesBlur, opacity: backgroundOpacity,
      gradient: gradientVisibility, header: headerHeight,
      reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    guard key != lastSurfaceKey else { return }
    lastSurfaceKey = key
    let size = CGSize(
      width: min(bounds.width, max(1, widthSpring.value)),
      height: min(bounds.height, max(1, heightSpring.value)))
    surfaceRect = CGRect(
      x: (bounds.width - size.width) / 2,
      y: 0, width: size.width, height: size.height)
    let radius = min(cornerSpring.value, size.height / 2, size.width / 2)
    surfacePath = IslandShapeGeometry.path(
      size: size, radius: radius,
      shape: surfaceShape, expansion: expansionSpring.value)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.frame = surfaceRect
    host.frame = CGRect(origin: .zero, size: size)
    let whole = CGRect(origin: .zero, size: size)
    blackShell.frame = whole
    gradientSurface.frame = whole
    gradientSurface.isHidden = appearanceLayout != .softGradient
    if appearanceLayout == .softGradient {
      blackShell.isHidden = true
      insetFinish.isHidden = true
      backdrop.isHidden = true
      blurBackdrop.isHidden = true
      surface.layer?.backgroundColor = NSColor.clear.cgColor
      // Fade black into the real desktop, rather than painting an opaque gray.
      let lowerAlpha = SoftGradientAppearance.bottomOpacity(
        visibility: gradientVisibility, expansion: expansionSpring.value,
        reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
      let headerStop = min(0.95, headerHeight / max(1, size.height))
      gradientSurface.locations = [0, NSNumber(value: Double(headerStop)), 1]
      gradientSurface.colors = [
        NSColor.black.cgColor,
        NSColor.black.cgColor, NSColor.black.withAlphaComponent(lowerAlpha).cgColor,
      ]
    } else if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
      blackShell.isHidden = true
      insetFinish.isHidden = true
      backdrop.isHidden = true
      blurBackdrop.isHidden = true
      surface.layer?.backgroundColor = NSColor.black.cgColor
    } else if appearanceLayout == .glassInset {
      // The shell has a real cutout. An opaque black backing behind the
      // glass would prevent the inset from sampling the wallpaper.
      let shoulder =
        surfaceShape == .notch
        ? IslandShapeGeometry.shoulder(size: size, expansion: max(0.55, expansionSpring.value)) : 0
      let inset = InsetGlassGeometry.frame(
        size: size, headerHeight: headerHeight, sideInset: 10 + shoulder)
      let innerRadius = InsetGlassGeometry.cornerRadius(for: inset)
      let shellPath = CGMutablePath()
      shellPath.addRect(whole)
      if !inset.isEmpty {
        shellPath.addRoundedRect(in: inset, cornerWidth: innerRadius, cornerHeight: innerRadius)
      }
      blackShell.path = shellPath
      blackShell.isHidden = false
      surface.layer?.backgroundColor = NSColor.clear.cgColor
      backdrop.frame = inset
      backdrop.isHidden = inset.isEmpty
      backdrop.alphaValue = 1
      blurBackdrop.isHidden = true
      insetFinish.frame = inset
      insetFinish.isHidden = inset.isEmpty
      insetFinish.layer?.cornerRadius = innerRadius
      insetFinish.layer?.backgroundColor =
        NSColor.black.withAlphaComponent(
          0.08 + backgroundOpacity * 0.20
        ).cgColor
      if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
        glass.cornerRadius = innerRadius
        glass.style = .regular
        glass.tintColor = NSColor.black.withAlphaComponent(0.12 + backgroundOpacity * 0.28)
      } else {
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = innerRadius
        backdrop.layer?.masksToBounds = true
      }
    } else {
      blackShell.isHidden = true
      insetFinish.isHidden = true
      backdrop.frame = whole
      backdrop.isHidden = !usesGlass
      backdrop.alphaValue = backgroundOpacity
      blurBackdrop.isHidden = usesGlass || !usesBlur
      blurBackdrop.alphaValue = backgroundOpacity
      surface.layer?.backgroundColor =
        NSColor.black.withAlphaComponent(
          (usesGlass || usesBlur) ? max(0.1, backgroundOpacity * 0.18) : backgroundOpacity
        ).cgColor
      if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
        glass.cornerRadius = 0
        glass.tintColor = nil
      } else {
        backdrop.layer?.cornerRadius = 0
      }
    }
    blurBackdrop.frame = CGRect(origin: .zero, size: size)
    surfaceMask.frame = CGRect(origin: .zero, size: size)
    surfaceMask.path = surfacePath
    CATransaction.commit()
    regionChanged?()
  }
}
