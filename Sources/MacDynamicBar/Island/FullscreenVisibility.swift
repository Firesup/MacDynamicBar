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

@MainActor
enum FullscreenVisibility {
    static func matches(window: CGRect, display: CGRect, systemFullscreen: Bool = false) -> Bool {
        if systemFullscreen, display.width > 0, display.height > 0 {
            // Notched Macs may reserve the camera strip above a native fullscreen window.
            let overlap = display.intersection(window)
            return !overlap.isNull && overlap.width / display.width > 0.9
                && overlap.height / display.height > 0.9
        }
        return abs(window.minX - display.minX) < 3 && abs(window.minY - display.minY) < 3
            && abs(window.width - display.width) < 3 && abs(window.height - display.height) < 3
    }
    static func covers(_ screen: NSScreen) -> Bool {
        guard let id = MinnowDisplay.from(screen)?.nativeID,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let bounds = CGDisplayBounds(id)
        return windows.contains { value in
            guard (value[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (value[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let raw = value[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw) else { return false }
            return matches(window: frame, display: bounds,
                           systemFullscreen: NSApp.currentSystemPresentationOptions.contains(.fullScreen))
        }
    }
}


