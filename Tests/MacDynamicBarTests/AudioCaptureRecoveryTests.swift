import Foundation
import ScreenCaptureKit
import Testing
@testable import MacDynamicBar

@Test func bluetoothOutputUsesTheMatchingPersonalizedName() {
  let names = ["b459763a87ad": "Abisan’s AirPods", "22b8a3d1a24b": "Abisan’s AirPods Pro"]
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "B4-59-76-3A-87-AD:output", pairedNames: names) == "Abisan’s AirPods")
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "b4:59:76:3a:87:ad", pairedNames: names) == "Abisan’s AirPods")
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "B459763A87AD:output", pairedNames: names) == "Abisan’s AirPods")
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "11-22-33-44-55-66:output", pairedNames: names) == "AirPods 4 ANC")
  #expect(BluetoothOutputNaming.name(audioName: "Speakers", uid: "BuiltInSpeakerDevice", pairedNames: names) == "Speakers")
  #expect(BluetoothOutputNaming.address(in: "06B35627-0000-0000-3021-0103803C2278") == nil)
}

@Test @MainActor func capturePermissionFailureIsActionableAndDomainSpecific() {
  #expect(MusicAudioLevels.failureStatus(domain: SCStreamErrorDomain, code: -3801).contains("permission"))
  #expect(!MusicAudioLevels.failureStatus(domain: NSOSStatusErrorDomain, code: -3801).contains("permission"))
}


@Test func personalizedAudioNameSurvivesBluetoothModelNameOnConnect() {
  #expect(BluetoothOutputNaming.name(audioName: "Abisan’s AirPods", uid: "B4-59-76-3A-87-AD:output",
    pairedNames: ["b459763a87ad": "AirPods 4 (ANC)"]) == "Abisan’s AirPods")
  #expect(BluetoothOutputNaming.preferredName(audioName: "Abisan’s AirPods", bluetoothName: "Old AirPods Name") == "Abisan’s AirPods")
  #expect(BluetoothOutputNaming.preferredName(audioName: "AirPods Pro", bluetoothName: "Abisan’s AirPods Pro") == "Abisan’s AirPods Pro")
  #expect(BluetoothOutputNaming.preferredName(audioName: "AirPods 4 (ANC)", bluetoothName: "AirPods") == "AirPods 4 (ANC)")
}
