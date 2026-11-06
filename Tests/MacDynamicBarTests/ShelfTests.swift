import AppKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import MacDynamicBar

private enum ShelfTestError: Error { case inaccessible, diskFull, corrupted }
@MainActor private final class MemoryShelfPersistence: ShelfPersistence {
  var records: [ShelfRecord] = []
  var failLoad = false
  var failSave = false
  var writes = 0
  func load() throws -> [ShelfRecord] {
    if failLoad { throw ShelfTestError.corrupted }
    return records
  }
  func save(_ records: [ShelfRecord]) throws {
    if failSave { throw ShelfTestError.diskFull }
    writes += 1
    self.records = records
  }
}
@MainActor private final class TestShelfAccess: ShelfFileAccess {
  var locations: [Data: URL] = [:]
  var unavailable: Set<URL> = []
  var stale: Set<Data> = []
  private var next = 0
  func bookmark(for url: URL) throws -> Data {
    guard !unavailable.contains(url) else { throw ShelfTestError.inaccessible }
    next += 1
    let data = Data("bookmark-\(next)".utf8)
    locations[data] = url
    return data
  }
  func resolve(_ bookmark: Data) throws -> ShelfFileLease {
    guard let url = locations[bookmark], !unavailable.contains(url) else {
      throw ShelfTestError.inaccessible
    }
    return ShelfFileLease(url: url, stale: stale.contains(bookmark))
  }
}
private func shelfURL(_ name: String) -> URL {
  URL(fileURLWithPath: "/private/tmp/minnow-shelf-fixtures/" + name)
}

@Test @MainActor func shelfPersistsBookmarksDeduplicatesAndRestoresWithoutEnablingItself() throws {
  let persistence = MemoryShelfPersistence()
  let access = TestShelfAccess()
  let shelf = ShelfStore(persistence: persistence, access: access, generatesThumbnails: false)
  shelf.add([shelfURL("ignored.txt")])
  #expect(persistence.writes == 0)
  shelf.setEnabled(true)
  shelf.add([shelfURL("photo.jpg"), shelfURL("photo.jpg"), shelfURL("notes.txt")])
  #expect(shelf.items.count == 2 && persistence.records.count == 2)
  let second = ShelfStore(persistence: persistence, access: access, generatesThumbnails: false)
  #expect(second.items.isEmpty)
  second.setEnabled(true)
  #expect(second.items.map(\.name) == ["photo.jpg", "notes.txt"])
  #expect(second.items.allSatisfy { $0.url != nil })
  second.setEnabled(false)
  #expect(second.items.isEmpty && persistence.records.count == 2)
  shelf.stop()
}

@Test @MainActor func shelfSaveFailuresLeavePreviousReferencesIntact() throws {
  let persistence = MemoryShelfPersistence()
  let access = TestShelfAccess()
  let shelf = ShelfStore(persistence: persistence, access: access, generatesThumbnails: false)
  shelf.setEnabled(true)
  shelf.add([shelfURL("first.txt")])
  let original = persistence.records
  persistence.failSave = true
  shelf.add([shelfURL("second.txt")])
  #expect(persistence.records == original && shelf.items.count == 1)
  #expect(shelf.error != nil)
  shelf.remove(try #require(shelf.items.first?.id))
  #expect(persistence.records == original && shelf.items.count == 1)
  shelf.stop()
}

@Test @MainActor func shelfCorruptManifestIsNeverOverwrittenByAddingFiles() {
  let persistence = MemoryShelfPersistence()
  persistence.failLoad = true
  let shelf = ShelfStore(
    persistence: persistence, access: TestShelfAccess(), generatesThumbnails: false)
  shelf.setEnabled(true)
  shelf.add([shelfURL("new.txt")])
  #expect(persistence.writes == 0 && shelf.items.isEmpty && shelf.error != nil)
  shelf.stop()
}

@Test @MainActor func shelfMissingFilesStayRemovableAndStaleBookmarksRenew() throws {
  let persistence = MemoryShelfPersistence()
  let access = TestShelfAccess()
  let shelf = ShelfStore(persistence: persistence, access: access, generatesThumbnails: false)
  shelf.setEnabled(true)
  shelf.add([shelfURL("first.txt")])
  let old = try #require(persistence.records.first)
  access.stale.insert(old.bookmark)
  shelf.refresh()
  #expect(persistence.records.first?.bookmark != old.bookmark)
  access.unavailable.insert(shelfURL("first.txt"))
  shelf.refresh()
  #expect(shelf.items.first?.problem != nil && shelf.items.first?.url == nil)
  shelf.remove(old.id)
  #expect(shelf.items.isEmpty && persistence.records.isEmpty)
  shelf.stop()
}

@Test @MainActor func shelfLimitsItemsAndRejectsRemoteURLsAndUnreadableFiles() {
  let persistence = MemoryShelfPersistence()
  let access = TestShelfAccess()
  let shelf = ShelfStore(persistence: persistence, access: access, generatesThumbnails: false)
  shelf.setEnabled(true)
  access.unavailable.insert(shelfURL("private.txt"))
  shelf.add([URL(string: "https://example.com/file.txt")!, shelfURL("private.txt")])
  #expect(shelf.items.isEmpty && persistence.records.isEmpty)
  shelf.add((0..<40).map { shelfURL("\($0).txt") })
  #expect(shelf.items.count == ShelfStore.limit && persistence.records.count == ShelfStore.limit)
  #expect(shelf.error != nil)
  shelf.stop()
}

@Test @MainActor func shelfNativeBookmarkRoundTripAndRemovalDoNotDeleteOriginalFile() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "MinnowShelf-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let original = directory.appendingPathComponent("Sample.txt")
  try Data("Disposable Shelf test file".utf8).write(to: original)
  let persistence = ShelfJSONPersistence(file: directory.appendingPathComponent("Shelf.json"))
  let shelf = ShelfStore(persistence: persistence, generatesThumbnails: false)
  shelf.setEnabled(true)
  shelf.add([original])
  #expect(shelf.error == nil)
  let id = try #require(shelf.items.first?.id)
  shelf.stop()
  let restored = ShelfStore(persistence: persistence, generatesThumbnails: false)
  restored.setEnabled(true)
  #expect(restored.items.first?.url?.standardizedFileURL == original.standardizedFileURL)
  restored.remove(id)
  #expect(restored.items.isEmpty)
  #expect(FileManager.default.fileExists(atPath: original.path))
  restored.stop()
}

@Test @MainActor func shelfImportsAndExportsOnlyFileURLProviders() async throws {
  let persistence = MemoryShelfPersistence()
  let access = TestShelfAccess()
  let shelf = ShelfStore(persistence: persistence, access: access, generatesThumbnails: false)
  shelf.setEnabled(true)
  let input = shelfURL("Dropped.txt")
  let provider = NSItemProvider(object: input as NSURL)
  await shelf.importFiles([provider])
  #expect(shelf.items.first?.name == "Dropped.txt")
  let outgoing = shelf.dragProvider(try #require(shelf.items.first?.id))
  let data: Data? = await withCheckedContinuation { continuation in
    outgoing.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
      continuation.resume(returning: data)
    }
  }
  #expect(data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) } == input)
  #expect(!shelf.importing)
  shelf.stop()
}

@Test @MainActor func shelfDropPreviewRestoresPreviousTodayStateAndDefersPopups() {
  let state = IslandState()
  state.page = .today
  state.toggle()
  state.beginShelfDrop()
  #expect(state.page == .shelf && state.isExpanded && state.isInteractionBusy)
  let popups = PopupCoordinator(automaticallyDismiss: false)
  popups.setBusy(state.isInteractionBusy)
  popups.submit(.preview(.lowBattery))
  #expect(popups.active == nil)
  state.finishShelfDrop(accepted: false)
  #expect(state.page == .today && state.isExpanded)
  popups.setBusy(state.isInteractionBusy)
  #expect(popups.active?.kind == .lowBattery)
  popups.clear()
  state.collapse()
  state.beginShelfDrop()
  state.finishShelfDrop(accepted: true)
  #expect(state.page == .shelf && state.isExpanded && !state.isInteractionBusy)
  state.collapseForPausedMedia(mediaEnabled: false, todayEnabled: false, shelfEnabled: true)
  #expect(state.isExpanded)
  #expect(
    IslandContentPolicy.hasContent(
      mediaEnabled: false, hiddenAfterPause: true,
      todayEnabled: false, hasPopup: false, hasActivity: false, shelfEnabled: true))
}

@Test @MainActor func shelfPreferencePersistsAndDefaultsOff() throws {
  let suite = "MinnowShelfSettings.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = MinnowSettings(defaults: defaults)
  #expect(!settings.shelfEnabled)
  settings.shelfEnabled = true
  #expect(MinnowSettings(defaults: defaults).shelfEnabled)
  settings.resetPreferences()
  #expect(!settings.shelfEnabled)
}

@Test @MainActor func shelfRowsRenderAtMinimumWidthWithoutOpeningOrSharingFiles() throws {
  let persistence = MemoryShelfPersistence()
  let shelf = ShelfStore(
    persistence: persistence, access: TestShelfAccess(), generatesThumbnails: false)
  shelf.setEnabled(true)
  shelf.add([shelfURL("Project.pdf"), shelfURL("Photo.jpg"), shelfURL("Notes.txt")])
  let host = NSHostingView(
    rootView: ShelfView(shelf: shelf).frame(width: 320, height: 204)
      .background(.black).preferredColorScheme(.dark))
  host.frame = CGRect(x: 0, y: 0, width: 320, height: 204)
  let window = NSWindow(
    contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  defer {
    window.close()
    shelf.stop()
  }
  host.layoutSubtreeIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent(".build/ui-checks/shelf.png")
  try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
  try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
  #expect(!shelf.sharing && !shelf.importing)
}

/// NSItemProvider invokes representation handlers off the main actor. Only this
/// lock-protected completion crosses queues; Shelf state remains main-actor owned.
private final class ShelfDropGate: @unchecked Sendable {
  private let lock = NSLock()
  private var callback: ((Data?, (any Error)?) -> Void)?
  var pending: Bool { lock.withLock { callback != nil } }
  func hold(_ completion: @escaping (Data?, (any Error)?) -> Void) {
    lock.withLock { callback = completion }
  }
  func resolve(_ data: Data) {
    let completion = lock.withLock {
      let saved = callback
      callback = nil
      return saved
    }
    completion?(data, nil)
  }
}

@Test @MainActor func shelfRejectsADropThatFinishesAfterDisableAndReenable() async throws {
  let persistence = MemoryShelfPersistence()
  let shelf = ShelfStore(
    persistence: persistence, access: TestShelfAccess(), generatesThumbnails: false)
  shelf.setEnabled(true)
  let gate = ShelfDropGate()
  let provider = NSItemProvider()
  provider.registerDataRepresentation(
    forTypeIdentifier: UTType.fileURL.identifier, visibility: .all
  ) { completion in
    gate.hold(completion)
    return nil
  }
  let task = Task { await shelf.importFiles([provider]) }
  try await waitForCondition { gate.pending }
  #expect(shelf.importing)
  shelf.setEnabled(false)
  shelf.setEnabled(true)
  gate.resolve(shelfURL("stale.txt").dataRepresentation)
  await task.value
  #expect(shelf.items.isEmpty && persistence.records.isEmpty && !shelf.importing)
  shelf.stop()
}

@Test @MainActor func shelfShareAndUnavailableIconsExistOnTheHost() {
  for symbol in ["square.and.arrow.up", "exclamationmark.triangle", "tray.and.arrow.down", "doc"] {
    #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
  }
}
