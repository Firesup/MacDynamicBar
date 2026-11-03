import AppKit
import CoreMedia
import CoreAudio
import CryptoKit
import Network
import Security
import ServiceManagement
import ScreenCaptureKit
import Combine
import QuartzCore
import SwiftUI

// MARK: - Displays

struct MinnowDisplay: Identifiable {
    let id: String
    let name: String
    let nativeID: CGDirectDisplayID

    @MainActor static func from(_ screen: NSScreen) -> MinnowDisplay? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()
        return MinnowDisplay(id: CFUUIDCreateString(nil, uuid) as String,
                             name: screen.localizedName, nativeID: id)
    }
}

@MainActor
final class DisplaySettings: ObservableObject {
    @Published private(set) var displays: [MinnowDisplay] = []
    func refresh() { displays = NSScreen.screens.compactMap(MinnowDisplay.from) }
}

