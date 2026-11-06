import AppKit

struct ScriptResult: @unchecked Sendable {
  let value: NSAppleEventDescriptor
  let errorCode: Int?
}
final class PlaybackScriptWorker: @unchecked Sendable {
  static let shared = PlaybackScriptWorker()
  private var stopping = false  // Accessed only on queue.
  private let queue = DispatchQueue(label: "com.minnow.playback-scripts")
  func finishStopping() async {
    await withCheckedContinuation { continuation in
      queue.async {
        self.stopping = true
        continuation.resume()
      }
    }
  }
  func execute(_ source: String) async -> ScriptResult {
    await withCheckedContinuation { continuation in
      queue.async {
        guard !self.stopping, let script = NSAppleScript(source: source) else {
          continuation.resume(
            returning: ScriptResult(value: NSAppleEventDescriptor(), errorCode: -128))
          return
        }
        let timing = TransitionTiming("playback AppleScript")
        defer { timing.end() }
        var error: NSDictionary?
        let value =
          script.executeAndReturnError(&error)
        continuation.resume(
          returning: ScriptResult(
            value: value,
            errorCode: (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue))
      }
    }
  }
}
