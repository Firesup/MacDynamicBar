import AppKit
import os

/// Uses the existing serial Apple Events worker, without activating either music app.
/// Commands may return before playback changes: poll the actual state, never flip optimistically.
enum LockedPlaybackTransport {
  struct Observation: Equatable {
    let playing: Bool
    let position: TimeInterval?
    init?(state: String?, position: TimeInterval?) {
      guard state == "playing" || state == "paused" || state == "stopped" else { return nil }
      playing = state == "playing"
      self.position = position.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
  }

  @MainActor static func toggle(
    _ source: MusicSource, before: Bool,
    execute: (String) async -> ScriptResult = { await PlaybackScriptWorker.shared.execute($0) },
    pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }
  ) async -> Observation? {
    let logger = Logger(subsystem: "com.minnow.MacDynamicBar", category: "LockScreen")
    for attempt in 0..<10 {
      if attempt > 0 {
        do { try await pause() } catch { return nil }
      }
      // The command is sent exactly once. Subsequent requests only read state.
      let command = attempt == 0 ? "playpause" : ""
      let script = """
        with timeout of 2 seconds
          if application id "\(source.bundleIdentifier)" is running then
            tell application id "\(source.bundleIdentifier)"
              \(command)
              return {player state as text, player position}
            end tell
          end if
        end timeout
        """
      let result = await execute(script)
      guard result.errorCode == nil else {
        logger.error("locked transport source=\(source.rawValue, privacy: .public) AppleEvent error=\(result.errorCode ?? 0)")
        return nil
      }
      guard let observed = Observation(
        state: result.value.atIndex(1)?.stringValue,
        position: result.value.atIndex(2)?.doubleValue) else {
        logger.error("locked transport source=\(source.rawValue, privacy: .public) returned no usable player state")
        return nil
      }
      if observed.playing != before {
        logger.info("locked transport source=\(source.rawValue, privacy: .public) actualPlaying=\(observed.playing) canonicalLocked=\(LockSessionSnapshot.current().locked == true)")
        return observed
      }
    }
    logger.error("locked transport source=\(source.rawValue, privacy: .public) did not confirm the requested state")
    return nil
  }
}
