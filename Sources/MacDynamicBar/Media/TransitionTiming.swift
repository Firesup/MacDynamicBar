import Foundation
import os

/// Debug-only intervals visible in Instruments and the development log. No player metadata.
struct TransitionTiming {
  private static let log = OSLog(subsystem: "com.minnow", category: "DeviceTransitions")
  private let id = OSSignpostID(log: log)
  private let operation: String
  private let start = ProcessInfo.processInfo.systemUptime
  init(_ operation: String) {
    self.operation = operation
    #if DEBUG
      os_signpost(
        .begin, log: Self.log, name: "Transition", signpostID: id, "%{public}@", operation)
    #endif
  }
  func end() {
    #if DEBUG
      let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
      os_signpost(
        .end, log: Self.log, name: "Transition", signpostID: id, "%{public}@ %.1f ms", operation,
        elapsed)
    #endif
  }
}

enum WaveformDefaults {
  static var enabled: Bool {
    #if DEBUG
      true
    #else
      false
    #endif
  }
}
