import AppKit
import CoreAudio
import SwiftUI
import Testing

@testable import MacDynamicBar

@Test @MainActor func audioOutputGlyphMappingUsesTransportAndAirPodsIdentity() throws {
  #expect(AudioOutputs.symbol(name: "MacBook Air Speakers", model: "", transport: kAudioDeviceTransportTypeBuiltIn) == "laptopcomputer")
  #expect(AudioOutputs.symbol(name: "Abisan’s AirPods", model: "", transport: kAudioDeviceTransportTypeBluetooth) == "airpods")
  #expect(AudioOutputs.symbol(name: "Listening", model: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth) == "airpodspro")
  let identity = try #require(AirPodsIdentity.resolve(name: "Listening", vendor: 0x004C, product: 0x2013))
  #expect(AudioOutputs.symbol(name: "Listening", model: "", transport: kAudioDeviceTransportTypeBluetooth, pairedIdentity: identity) == "airpods.gen3")
  for transport in [kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort,
    kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeAirPlay,
    kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, 0] {
    #expect(AudioOutputs.symbol(name: "Headphones", model: "Unknown", transport: transport) == "speaker.wave.2")
  }
}

@Test func audioOutputGlyphFallsBackToAvailableSymbols() {
  #expect(AudioOutputGlyph.symbolName(for: "airpods.gen3", available: { $0 == "airpods" }) == "airpods")
  #expect(AudioOutputGlyph.symbolName(for: "airpodspro", available: { $0 == "speaker.wave.2" }) == "speaker.wave.2")
  #expect(AudioOutputGlyph.symbolName(for: "laptopcomputer", available: { $0 == "speaker.wave.2" }) == "speaker.wave.2")
  #expect(AudioOutputGlyph.symbolName(for: nil, available: { _ in true }) == "speaker.wave.2")
}

@Test @MainActor func selectedRouteAndPickerGlyphsRemainIndependent() throws {
  let speakers = AudioOutputDevice(id: 1, name: "MacBook Air Speakers", symbol: "laptopcomputer")
  let airPods = AudioOutputDevice(id: 2, name: "Abisan’s AirPods", symbol: "airpods")
  let hdmi = AudioOutputDevice(id: 3, name: "HDMI Display", symbol: "speaker.wave.2")
  let devices = [speakers, airPods, hdmi]
  let button = NSButton(frame: CGRect(x: 0, y: 0, width: 36, height: 40))
  // AirPods remain in every picker, including both speaker-selected states.
  for selected in [speakers, airPods, speakers, hdmi] {
    let outputs = AudioOutputs(devices: devices, selectedID: selected.id)
    #expect(outputs.current?.symbol == selected.symbol)
    OutputPickerButton.update(button, device: outputs.current)
    #expect(button.image?.tiffRepresentation == AudioOutputGlyph.image(for: selected).tiffRepresentation)
    #expect(button.toolTip == selected.name)
    #expect(button.accessibilityValue() as? String == selected.name)
    #expect(button.frame.size == NSSize(width: 36, height: 40))
    for device in outputs.devices {
      let renderer = ImageRenderer(content: AudioOutputIcon(device: device))
      #expect(renderer.cgImage != nil)
    }
  }
  let laptop = AudioOutputGlyph.image(for: speakers)
  #expect(laptop.size.width > laptop.size.height)
  OutputPickerButton.update(button, device: nil)
  #expect(button.image != nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MINNOW_RENDER_OUTPUTS"] == "1")) @MainActor
func audioOutputViewsRenderForReview() async throws {
  let devices = [
    AudioOutputDevice(id: 1, name: "MacBook Air Speakers", symbol: "laptopcomputer"),
    AudioOutputDevice(id: 2, name: "Abisan’s AirPods", symbol: "airpods"),
    AudioOutputDevice(id: 3, name: "HDMI Display", symbol: "speaker.wave.2"),
  ]
  let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/ui-checks")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let snapshots = devices.map { AudioOutputs(devices: devices, selectedID: $0.id) }
  let view = HStack(spacing: 0) {
    ForEach(Array(snapshots.enumerated()), id: \.offset) { _, outputs in
      VStack {
        OutputPickerButton(outputs: outputs, isPresented: .constant(false))
          .frame(width: 36, height: 40)
        AudioOutputList(outputs: outputs, close: {})
      }.padding().frame(width: 312, height: 330)
    }
  }.background(Color.black).environment(\.colorScheme, .dark)
  let host = NSHostingView(rootView: view)
  let window = NSWindow(
    contentRect: CGRect(x: 0, y: 0, width: 936, height: 330),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  window.contentView = host
  try await Task.sleep(for: .milliseconds(100))
  host.layoutSubtreeIfNeeded()
  host.displayIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  try #require(bitmap.representation(using: .png, properties: [:]))
    .write(to: directory.appendingPathComponent("output-icons.png"))
}
