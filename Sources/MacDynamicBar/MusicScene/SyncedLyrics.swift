import AppKit
import Combine
import UniformTypeIdentifiers

struct LyricLine: Equatable, Identifiable {
  let time: TimeInterval
  let text: String
  var id: TimeInterval { time }
}

enum SyncedLyrics {
  /// LRC supports repeated timestamps, fractional seconds, and a global millisecond offset.
  static func parse(_ text: String) -> [LyricLine] {
    let pattern = try! NSRegularExpression(pattern: #"\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]"#)
    let offsetPattern = try! NSRegularExpression(
      pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
    let ns = text as NSString
    var offset = 0.0
    if let m = offsetPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
      offset = (Double(ns.substring(with: m.range(at: 1))) ?? 0) / 1000
    }
    var lines: [LyricLine] = []
    for raw in text.components(separatedBy: .newlines) {
      let line = raw as NSString
      let matches = pattern.matches(in: raw, range: NSRange(location: 0, length: line.length))
      guard let last = matches.last else { continue }
      let lyric = line.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
      for match in matches {
        let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
        let fraction =
          match.range(at: 3).location == NSNotFound ? "" : line.substring(with: match.range(at: 3))
        lines.append(
          LyricLine(
            time: max(0, minutes * 60 + seconds + (Double("0." + fraction) ?? 0) + offset),
            text: lyric))
      }
    }
    // One stable row per timestamp, even with malformed or duplicated source lines.
    return Dictionary(lines.map { ($0.time, $0) }, uniquingKeysWith: { _, last in last }).values
      .sorted { $0.time < $1.time }
  }
  static func currentIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
    guard position.isFinite else { return nil }
    return lines.lastIndex { $0.time <= position }
  }
}

@MainActor final class LyricsStore: ObservableObject {
  @Published private(set) var lines: [LyricLine] = []
  @Published private(set) var status = "Import an LRC file for the current track."
  private var track: MusicTrack?
  private var request: LyricsRequest?
  private var download: Task<Void, Never>?
  func fetch(for track: MusicTrack?, duration: TimeInterval) {
    guard let track, duration.isFinite, duration >= 1, duration <= 3600 else {
      trackChanged(track)
      return
    }
    let query = LyricsRequest(
      title: track.title, artist: track.artist, album: track.album,
      duration: Int(duration.rounded()))
    guard request != query else { return }
    clear()
    self.track = track
    request = query
    status = "Finding lyrics…"
    download = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(350))
        let result = try await LRCLIBClient.shared.fetch(query)
        guard let self, !Task.isCancelled, self.request == query else { return }
        if let result {
          self.lines = SyncedLyrics.parse(result.syncedLyrics ?? "")
          self.status =
            result.instrumental
            ? "Instrumental"
            : (self.lines.isEmpty ? "Synced lyrics unavailable" : "Lyrics · LRCLIB")
        } else {
          self.status = "No matching lyrics found"
        }
      } catch {
        guard let self, !Task.isCancelled, self.request == query else { return }
        self.status = "Lyrics unavailable · check connection"
      }
    }
  }
  func cancelOnline() { if request != nil { clear() } }
  func clear() {
    download?.cancel()
    download = nil
    request = nil
    lines = []
    track = nil
    status = "Import an LRC file for the current track."
  }
  func importFile(for track: MusicTrack?) {
    guard let track else {
      status = "Play a track before importing lyrics."
      return
    }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 1_048_576 else {
        status = "The lyrics file is too large."
        return
      }
      let parsed = SyncedLyrics.parse(try String(contentsOf: url, encoding: .utf8))
      guard !parsed.isEmpty else {
        status = "No timestamped LRC lines were found."
        return
      }
      clear()
      self.track = track
      lines = parsed
      status = "Local synced lyrics"
    } catch { status = "Could not read the selected lyrics file." }
  }
  func trackChanged(_ track: MusicTrack?) { if self.track != track { clear() } }
}
