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

// MARK: - Login Item

@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var error: String?
    var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func refresh() {
        guard isBundled else { enabled = false; requiresApproval = false; return }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ desired: Bool) {
        guard isBundled else { error = "Launch at login requires the bundled Minnow.app"; return }
        do {
            if desired { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = error.localizedDescription }
        refresh()
    }
}

