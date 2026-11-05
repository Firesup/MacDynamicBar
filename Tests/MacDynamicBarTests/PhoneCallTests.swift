import Testing
@testable import MacDynamicBar

@Test func callEvidenceRequiresExplicitCallControls() {
  #expect(PhoneCallEvidence.classify(buttonLabels: ["Play", "Pause", "Phone", "Incoming Call"]) == .unavailable)
  #expect(PhoneCallEvidence.classify(buttonLabels: ["Accept"]) == .unavailable)
  #expect(PhoneCallEvidence.classify(buttonLabels: ["Decline"]) == .unavailable)
  #expect(PhoneCallEvidence.classify(buttonLabels: [" Answer Call ", "Decline Call"]) == .incoming)
  #expect(PhoneCallEvidence.classify(buttonLabels: ["End Call", "Mute"]) == .active)
  #expect(PhoneCallEvidence.classify(buttonLabels: ["Call History", "Call Back"]) == .unavailable)
  #expect(PhoneCallEvidence.classify(buttonLabels: ["Accepter", "Refuser"]) == .unavailable)
}

@Test func phoneCallPreviewIsExplicitSampleDataWithCallPriority() {
  let call = IslandPopup.preview(.phoneCall)
  #expect(call.isPreview)
  #expect(call.percentage == nil)
  #expect(call.priority > IslandPopup.preview(.airPods).priority)
  #expect(call.priority < IslandPopup.preview(.lowBattery).priority)
}
