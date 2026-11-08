import Foundation
import ScreenCaptureKit
import Testing
@testable import MacDynamicBar

@Test func bluetoothOutputUsesTheMatchingPersonalizedName() {
  let names = ["aabbcc112233": "Alex’s AirPods", "ddeeff445566": "Alex’s AirPods Pro"]
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "AA-BB-CC-11-22-33:output", pairedNames: names) == "Alex’s AirPods")
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "aa:bb:cc:11:22:33", pairedNames: names) == "Alex’s AirPods")
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "AABBCC112233:output", pairedNames: names) == "Alex’s AirPods")
  #expect(BluetoothOutputNaming.name(audioName: "AirPods 4 ANC", uid: "11-22-33-44-55-66:output", pairedNames: names) == "AirPods 4 ANC")
  #expect(BluetoothOutputNaming.name(audioName: "Speakers", uid: "BuiltInSpeakerDevice", pairedNames: names) == "Speakers")
  #expect(BluetoothOutputNaming.address(in: "06B35627-0000-0000-3021-0103803C2278") == nil)
}

@Test @MainActor func capturePermissionFailureIsActionableAndDomainSpecific() {
  #expect(MusicAudioLevels.failureStatus(domain: SCStreamErrorDomain, code: -3801).contains("permission"))
  #expect(!MusicAudioLevels.failureStatus(domain: NSOSStatusErrorDomain, code: -3801).contains("permission"))
}


@Test func personalizedAudioNameSurvivesBluetoothModelNameOnConnect() {
  #expect(BluetoothOutputNaming.name(audioName: "Alex’s AirPods", uid: "AA-BB-CC-11-22-33:output",
    pairedNames: ["aabbcc112233": "AirPods 4 (ANC)"]) == "Alex’s AirPods")
  #expect(BluetoothOutputNaming.preferredName(audioName: "Alex’s AirPods", bluetoothName: "Old AirPods Name") == "Alex’s AirPods")
  #expect(BluetoothOutputNaming.preferredName(audioName: "AirPods Pro", bluetoothName: "Alex’s AirPods Pro") == "Alex’s AirPods Pro")
  #expect(BluetoothOutputNaming.preferredName(audioName: "AirPods 4 (ANC)", bluetoothName: "AirPods") == "AirPods 4 (ANC)")
}
