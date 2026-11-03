import AppKit
import IOBluetooth
import SwiftUI

private struct BluetoothConnectionReference: @unchecked Sendable { let device: IOBluetoothDevice }

struct AirPodsConnectionsView: View {
  @State private var devices: [IOBluetoothDevice] = []
  @State private var status = ""
  @State private var connecting = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Refresh Paired AirPods") { refresh() }
      ForEach(Array(devices.enumerated()), id: \.offset) { _, device in
        HStack {
          Label(
            device.name ?? "AirPods",
            systemImage: AirPodsIdentity.resolve(name: device.name ?? "")?.symbol ?? "airpods")
          Spacer()
          Button(device.isConnected() ? "Connected" : "Connect") {
            let reference = BluetoothConnectionReference(device: device)
            connecting = true
            Task { @MainActor in
              let result = await Task.detached { reference.device.openConnection() }.value
              status = result == 0 ? "Connected" : "Connection failed (\(result))"
              connecting = false
              refresh()
            }
          }.disabled(connecting || device.isConnected())
        }
      }
      Text(status).font(.caption).foregroundStyle(.secondary)
      Text(
        "Lists paired devices. Nearby case discovery and per-bud battery readings are not available in this build."
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  private func refresh() {
    devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
      AirPodsIdentity.resolve(name: $0.name ?? "") != nil
    }
    if devices.isEmpty { status = "No recognized paired AirPods found" }
  }
}
