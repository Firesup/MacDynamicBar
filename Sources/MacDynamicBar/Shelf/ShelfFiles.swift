import AppKit
import Foundation

struct ShelfRecord: Codable, Equatable, Identifiable {
  let id: UUID
  var bookmark: Data
  var name: String
}
struct ShelfItem: Identifiable {
  let record: ShelfRecord
  let url: URL?
  let problem: String?
  var id: UUID { record.id }
  var name: String { record.name }
}

/// Balanced access for the lifetime of a thumbnail, drag or native share.
final class ShelfFileLease: Sendable {
  let url: URL
  let stale: Bool
  private let acquired: Bool
  init(url: URL, stale: Bool = false) {
    self.url = url
    self.stale = stale
    acquired = url.startAccessingSecurityScopedResource()
  }
  deinit { if acquired { url.stopAccessingSecurityScopedResource() } }
}

@MainActor protocol ShelfFileAccess {
  func bookmark(for url: URL) throws -> Data
  func resolve(_ bookmark: Data) throws -> ShelfFileLease
}
@MainActor struct NativeShelfFileAccess: ShelfFileAccess {
  func bookmark(for url: URL) throws -> Data {
    guard url.isFileURL else { throw ShelfError.fileURLsOnly }
    let lease = ShelfFileLease(url: url)
    return try withExtendedLifetime(lease) {
      _ = try url.resourceValues(forKeys: [.nameKey])
      return try url.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: [.nameKey], relativeTo: nil)
    }
  }
  func resolve(_ bookmark: Data) throws -> ShelfFileLease {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard url.isFileURL else { throw ShelfError.fileURLsOnly }
    let lease = ShelfFileLease(url: url, stale: stale)
    _ = try url.resourceValues(forKeys: [.nameKey])
    return lease
  }
}

@MainActor protocol ShelfPersistence {
  func load() throws -> [ShelfRecord]
  func save(_ records: [ShelfRecord]) throws
}
@MainActor struct ShelfJSONPersistence: ShelfPersistence {
  let file: URL
  private struct Manifest: Codable {
    let version: Int
    let records: [ShelfRecord]
  }
  func load() throws -> [ShelfRecord] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
    guard manifest.version == 1, manifest.records.count <= ShelfStore.limit,
      Set(manifest.records.map(\.id)).count == manifest.records.count
    else { throw ShelfError.invalidManifest }
    return manifest.records
  }
  func save(_ records: [ShelfRecord]) throws {
    let data = try JSONEncoder().encode(Manifest(version: 1, records: records))
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file, options: [.atomic])
  }
  static var standard: Self {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    return Self(file: support.appendingPathComponent("Minnow/Shelf.json"))
  }
}

enum ShelfError: LocalizedError {
  case fileURLsOnly, full, invalidManifest, inactive, airDropUnavailable
  var errorDescription: String? {
    switch self {
    case .fileURLsOnly: "Shelf accepts local files and folders."
    case .full: "Shelf holds up to 30 items. Remove an item before adding another."
    case .invalidManifest: "Saved Shelf data could not be read. It has been left unchanged."
    case .inactive: "Enable Shelf before adding files."
    case .airDropUnavailable: "AirDrop is unavailable for this file or on this Mac."
    }
  }
}
