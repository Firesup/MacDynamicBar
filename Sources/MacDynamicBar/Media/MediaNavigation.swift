import AppKit

// MARK: - Artist Metadata and Navigation

struct SpotifyArtistLink: Decodable, Equatable, Sendable {
  let name: String
  let uri: String?
}

struct SpotifyPlaybackDetails: Decodable, Sendable {
  struct Item: Decodable, Sendable {
    let uri: String?
    let explicit: Bool?
    let artists: [SpotifyArtistLink]?
  }
  struct Device: Decodable, Sendable {
    let id: String?
    let name: String?
    let type: String?
  }
  let device: Device?
  let isPlaying: Bool?
  init(repeatMode: String?, item: Item?, device: Device? = nil, isPlaying: Bool? = nil) {
    self.repeatMode = repeatMode
    self.item = item
    self.device = device
    self.isPlaying = isPlaying
  }
  let repeatMode: String?
  let item: Item?
  enum CodingKeys: String, CodingKey {
    case repeatMode = "repeat_state"
    case item, device
    case isPlaying = "is_playing"
  }
  var uri: String? { item?.uri }
  var explicit: Bool? { item?.explicit }
  func artists(matching trackID: String?) -> [SpotifyArtistLink] {
    guard let trackID, !trackID.isEmpty, item?.uri == trackID else { return [] }
    return (item?.artists ?? []).filter {
      !$0.name.isEmpty && MediaNavigation.artistID(from: $0.uri) != nil
    }
  }
}

enum MediaNavigation {
  static func artistID(from uri: String?) -> String? {
    guard let uri, uri.hasPrefix("spotify:artist:") else { return nil }
    let value = String(uri.dropFirst("spotify:artist:".count))
    guard value.count == 22, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
      return nil
    }
    return value
  }
  static func artistURL(name: String, uri: String?, web: Bool = false) -> URL? {
    if let id = artistID(from: uri) {
      return URL(string: web ? "https://open.spotify.com/artist/" + id : "spotify:artist:" + id)
    }
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    guard let encoded = name.addingPercentEncoding(withAllowedCharacters: safe) else { return nil }
    return URL(
      string: web ? "https://open.spotify.com/search/" + encoded : "spotify:search:" + encoded)
  }
  @MainActor static func openSource(_ source: MusicSource) {
    guard
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)
    else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(
      at: url, configuration: configuration, completionHandler: nil)
  }
  @MainActor static func openArtist(name: String, uri: String?) {
    guard let url = artistURL(name: name, uri: uri) else { return }
    if !NSWorkspace.shared.open(url), let fallback = artistURL(name: name, uri: uri, web: true) {
      NSWorkspace.shared.open(fallback)
    }
  }
}

/// Only a trusted Connect ID can establish local identity. A desktop name is not an ID.
enum SpotifyPlaybackLocation: Equatable {
  case unknown, local
  case remote(String)
  static func resolve(_ details: SpotifyPlaybackDetails, localDeviceID: String? = nil) -> Self {
    guard details.isPlaying == true, let device = details.device,
      let id = device.id, !id.isEmpty
    else { return .unknown }
    if let localDeviceID, id == localDeviceID { return .local }
    // These device classes cannot be this Mac. All computer/unknown classes stay unknown.
    let remoteTypes = [
      "smartphone", "tablet", "speaker", "tv", "avr", "stb", "audiodongle", "gameconsole",
      "castaudio", "castvideo",
    ]
    guard localDeviceID != nil || remoteTypes.contains(device.type?.lowercased() ?? ""),
      let name = device.name, !name.isEmpty
    else { return .unknown }
    return .remote(name)
  }
}
