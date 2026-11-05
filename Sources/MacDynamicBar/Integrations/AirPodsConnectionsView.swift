import AppKit
import IOBluetooth
import SwiftUI

private struct BluetoothConnectionReference: @unchecked Sendable { let device: IOBluetoothDevice }

struct AirPodsConnectionsView: View {
  @ObservedObject var outputs: AudioOutputs
  @State private var devices: [IOBluetoothDevice] = []
  @State private var status = ""
  @State private var connecting = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Refresh Paired AirPods") { refresh() }
      ForEach(devices, id: \.addressString) { device in
        HStack {
          Label(
            displayName(device),
            systemImage: AirPodsIdentity.resolve(device: device)?.symbol ?? "airpods")
          Spacer()
          Button(device.isConnected() ? "Connected" : "Connect") {
            let reference = BluetoothConnectionReference(device: device)
            connecting = true
            Task { @MainActor in
              let result = await Task.detached { reference.device.openConnection() }.value
              refresh()
              status = result == 0 && reference.device.isConnected()
                ? "Connected to \(displayName(reference.device))"
                : "Connection failed or not confirmed (\(result))"
              connecting = false
            }
          }.disabled(connecting || device.isConnected())
        }
      }
      Text(status).font(.caption).foregroundStyle(.secondary)
      Text(
        "Lists paired devices. Nearby case discovery and per-bud battery readings are not available in this build."
      ).font(.caption).foregroundStyle(.secondary)
    }
    .task { refresh() }
  }
  private func displayName(_ device: IOBluetoothDevice) -> String {
    guard let rawAddress = device.addressString,
      let address = BluetoothOutputNaming.address(in: rawAddress),
      let output = outputs.devices.first(where: { $0.bluetoothAddress == address }) else {
      return device.name ?? "AirPods"
    }
    return output.name
  }
  private func refresh() {
    outputs.reload()
    devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
      AirPodsIdentity.resolve(device: $0) != nil
    }
    status = devices.isEmpty ? "No recognized paired AirPods found" : "\(devices.count) paired AirPods found"
  }
}
