import AppKit
import SwiftUI

// MARK: - Transient Sound Output Picker

@MainActor
struct OutputPickerButton: NSViewRepresentable {
  @ObservedObject var outputs: AudioOutputs
  @Binding var isPresented: Bool

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(frame: CGRect(x: 0, y: 0, width: 36, height: 40))
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.contentTintColor = .white
    button.target = context.coordinator
    button.action = #selector(Coordinator.toggle)
    button.setAccessibilityLabel("Choose sound output")
    context.coordinator.anchor = button
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    let device = outputs.current
    let image: NSImage?
    if let device, let native = device.nativeIcon, !device.symbol.hasPrefix("airpods") {
      image = native.copy() as? NSImage
    } else {
      image = NSImage(
        systemSymbolName: device?.symbol ?? "speaker.wave.2", accessibilityDescription: nil)
    }
    image?.isTemplate = true
    image?.size = NSSize(width: 20, height: 20)
    button.image = image
    button.toolTip = device?.name ?? "Choose sound output"
    context.coordinator.synchronize()
  }
  static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
    coordinator.popover.delegate = nil
    coordinator.popover.performClose(nil)
  }

  @MainActor
  final class Coordinator: NSObject, NSPopoverDelegate {
    var parent: OutputPickerButton
    weak var anchor: NSButton?
    let popover = NSPopover()
    init(_ parent: OutputPickerButton) {
      self.parent = parent
      super.init()
      popover.behavior = .transient
      popover.animates = true
      popover.delegate = self
    }
    @objc func toggle() {
      if popover.isShown {
        close()
      } else {
        parent.isPresented = true
        synchronize()
      }
    }
    func synchronize() {
      guard parent.isPresented else {
        if popover.isShown { popover.performClose(nil) }
        return
      }
      guard !popover.isShown, let anchor, anchor.window != nil else { return }
      let root = AudioOutputList(outputs: parent.outputs) { [weak self] in self?.close() }
        .preferredColorScheme(.dark)
      popover.contentViewController = NSHostingController(rootView: root)
      popover.contentSize = NSSize(width: 280, height: 280)
      popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }
    func close() {
      parent.isPresented = false
      if popover.isShown { popover.performClose(nil) }
    }
    func popoverDidClose(_ notification: Notification) {
      if parent.isPresented { parent.isPresented = false }
    }
  }
}
