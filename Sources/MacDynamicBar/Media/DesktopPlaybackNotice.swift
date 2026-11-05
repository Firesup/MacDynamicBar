import Foundation

/// Value data already broadcast by Music/Spotify. Partial notices never invent track IDs or timing.
struct DesktopPlaybackNotice: Sendable {
  let playing: Bool
  let track: MusicTrack?
  let position: TimeInterval?
  let duration: TimeInterval?

  init?(userInfo: [AnyHashable: Any], source: MusicSource) {
    guard let state = (userInfo["Player State"] as? String)?.lowercased(),
      ["playing", "paused", "stopped"].contains(state) else { return nil }
    playing = state == "playing"
    func seconds(_ key: String, divisor: Double = 1) -> TimeInterval? {
      guard let value = userInfo[key] as? NSNumber, value.doubleValue.isFinite,
        value.doubleValue >= 0 else { return nil }
      return value.doubleValue / divisor
    }
    position = seconds("Playback Position")
    // Music specifies Total Time in milliseconds. Spotify's notification Duration has varied
    // across versions; preserve script-confirmed duration only for the same track instead.
    duration = source == .appleMusic ? seconds("Total Time", divisor: 1000) : nil
    if let title = userInfo["Name"] as? String, !title.isEmpty {
      let id: String?
      if source == .spotify {
        id = (userInfo["Track ID"] as? String).flatMap { $0.hasPrefix("spotify:track:") ? $0 : nil }
      } else if let persistentID = userInfo["PersistentID"] as? NSNumber {
        id = String(format: "%016llX", persistentID.uint64Value)
      } else {
        id = nil
      }
      track = MusicTrack(title: title, artist: userInfo["Artist"] as? String ?? "",
        album: userInfo["Album"] as? String ?? "", id: id)
    } else {
      track = nil
    }
  }
}
