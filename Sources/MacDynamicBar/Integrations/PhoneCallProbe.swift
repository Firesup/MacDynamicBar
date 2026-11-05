import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

/// Call state must come from explicit call controls, never music playback or a window title.
/// These English labels are a probe heuristic until actual app/version fixtures are verified.
enum PhoneCallEvidence: Equatable {
  case incoming, active, unavailable

  static func classify(buttonLabels: Set<String>) -> Self {
    let labels = Set(buttonLabels.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    })
    if !labels.isDisjoint(with: ["accept", "answer", "accept call", "answer call"]),
      !labels.isDisjoint(with: ["decline", "decline call", "reject call"]) {
      return .incoming
    }
    if !labels.isDisjoint(with: ["end call", "hang up"]) { return .active }
    return .unavailable
  }
}

@MainActor final class PhoneCallProbe: ObservableObject {
  @Published private(set) var status = "Not inspected"
  @Published private(set) var isInspecting = false

  func requestAccess() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    status = "Enable Minnow in macOS Accessibility settings, then inspect again."
  }

  func inspect() {
    guard !isInspecting else { return }
    guard AXIsProcessTrusted() else {
      status = "Accessibility access is required to inspect call controls."
      return
    }
    let apps = NSWorkspace.shared.runningApplications.filter {
      ["com.apple.FaceTime", "com.apple.mobilephone"].contains($0.bundleIdentifier ?? "")
    }
    guard !apps.isEmpty else {
      status = "FaceTime or Phone is not running."
      return
    }
    // Keep cross-process AX IPC and unresponsive apps off the main actor.
    let targets = apps.map { ($0.processIdentifier, $0.localizedName ?? "Call app") }
    isInspecting = true
    status = "Inspecting call controls…"
    Task {
      let reports = await Task.detached {
        targets.map { pid, name in
          let application = AXUIElementCreateApplication(pid)
          AXUIElementSetMessagingTimeout(application, 0.1)
          var windows: CFTypeRef?
          guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
            == .success, let roots = windows as? [AXUIElement] else {
            return "\(name): UI unavailable"
          }
          var labels = Set<String>()
          var remaining = 200
          let deadline = Date().addingTimeInterval(2)
          func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard remaining > 0, Date() < deadline else { return nil }
            remaining -= 1
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
            else { return nil }
            return result
          }
          func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 10, remaining > 0, Date() < deadline else { return }
            if value(element, kAXRoleAttribute) as? String == kAXButtonRole {
              for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = value(element, attribute) as? String { labels.insert(text) }
              }
            }
            for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
              visit(child, depth: depth + 1)
            }
          }
          for root in roots { visit(root, depth: 0) }
          switch PhoneCallEvidence.classify(buttonLabels: labels) {
          case .incoming: return "\(name): incoming-call controls found (unverified heuristic)"
          case .active: return "\(name): active-call controls found (unverified heuristic)"
          case .unavailable: return "\(name): no supported call controls found"
          }
        }
      }.value
      status = reports.joined(separator: "\n")
      isInspecting = false
    }
  }
}

struct PhoneCallProbeView: View {
  @StateObject private var probe = PhoneCallProbe()
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button("Allow Accessibility…") { probe.requestAccess() }
        Button("Inspect FaceTime / Phone") { probe.inspect() }.disabled(probe.isInspecting)
      }
      Text(probe.status).font(.caption).foregroundStyle(.secondary)
      Text("Explicit inspection only. Call detection is experimental; unsupported or localized controls may be missed. No caller details are stored and no calls are answered or declined.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}
