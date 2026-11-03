import AppKit
import Darwin

/// Isolated compatibility bridge. Reads brightness after illumination key events;
/// never changes brightness or suppresses the native HUD.
@MainActor final class BrightnessHUDMonitor {
  private typealias ReadBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
  private var library: UnsafeMutableRawPointer?
  private var readBrightness: ReadBrightness?
  private var monitors: [Any] = []
  private var settle: Task<Void, Never>?
  private var last: Int?
  var onEvent: ((IslandPopup) -> Void)?
  func start() {
    guard monitors.isEmpty else { return }
    if library == nil {
      library = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY | RTLD_LOCAL)
    }
    guard let library, let symbol = dlsym(library, "DisplayServicesGetBrightness") else { return }
    readBrightness = unsafeBitCast(symbol, to: ReadBrightness.self)
    let handler: (NSEvent) -> Void = { [weak self] event in
      guard event.subtype.rawValue == 8 else { return }
      let key = (event.data1 >> 16) & 0xffff
      guard key == 2 || key == 3 else { return }
      MainActor.assumeIsolated { self?.changed() }
    }
    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: handler) {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: .systemDefined,
      handler: { event in
        handler(event)
        return event
      })
    {
      monitors.append(monitor)
    }
  }
  private func changed() {
    settle?.cancel()
    settle = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
      guard let self, let read = self.readBrightness else { return }
      var value: Float = 0
      guard read(CGMainDisplayID(), &value) == 0, value.isFinite else { return }
      let percentage = Int((min(1, max(0, value)) * 100).rounded())
      guard self.last != percentage else { return }
      self.last = percentage
      self.onEvent?(
        IslandPopup(
          kind: .hud, key: "hud.brightness", title: "Brightness", subtitle: "Built-in display",
          symbol: "sun.max.fill", percentage: percentage))
    }
  }
  func stop() {
    settle?.cancel()
    monitors.forEach { NSEvent.removeMonitor($0) }
    monitors.removeAll()
    last = nil
  }
}
