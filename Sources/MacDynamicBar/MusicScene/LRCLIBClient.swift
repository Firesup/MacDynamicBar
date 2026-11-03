import Foundation

struct LyricsRequest: Hashable, Sendable {
  let title: String
  let artist: String
  let album: String
  let duration: Int
  var url: URL? {
    var components = URLComponents(string: "https://lrclib.net/api/get")!
    components.queryItems = [
      URLQueryItem(name: "track_name", value: title),
      URLQueryItem(name: "artist_name", value: artist),
      URLQueryItem(name: "album_name", value: album),
      URLQueryItem(name: "duration", value: String(duration)),
    ]
    return components.url
  }
}

struct LRCLIBRecord: Decodable, Sendable {
  let trackName: String
  let artistName: String
  let duration: Double
  let instrumental: Bool
  let syncedLyrics: String?
  let plainLyrics: String?
  func matches(_ request: LyricsRequest) -> Bool {
    trackName.compare(request.title, options: [.caseInsensitive, .diacriticInsensitive])
      == .orderedSame
      && artistName.compare(request.artist, options: [.caseInsensitive, .diacriticInsensitive])
        == .orderedSame
      && abs(duration - Double(request.duration)) <= 2
  }
}

actor LRCLIBClient {
  static let shared = LRCLIBClient()
  private var cache: [LyricsRequest: LRCLIBRecord] = [:]
  func fetch(_ request: LyricsRequest) async throws -> LRCLIBRecord? {
    if let cached = cache[request] { return cached }
    guard let url = request.url else { return nil }
    var query = URLRequest(url: url)
    query.timeoutInterval = 15
    query.setValue("Minnow/1.0 (macOS music companion)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: query)
    guard let response = response as? HTTPURLResponse else { return nil }
    if response.statusCode == 404 { return nil }
    guard response.statusCode == 200, data.count <= 1_048_576 else {
      throw URLError(.badServerResponse)
    }
    let record = try JSONDecoder().decode(LRCLIBRecord.self, from: data)
    guard record.matches(request) else { return nil }
    if cache.count >= 30 { cache.removeAll() }
    cache[request] = record
    return record
  }
}
