import AppKit
import Combine
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Owns references, never copies, moves or deletes the user's source files.
@MainActor final class ShelfStore: ObservableObject {
  static let limit = 30
  @Published private(set) var items: [ShelfItem] = []
  @Published private(set) var thumbnails: [UUID: NSImage] = [:]
  @Published private(set) var importing = false
  @Published private(set) var sharing = false
  @Published var error: String?
  private let persistence: any ShelfPersistence
  private let access: any ShelfFileAccess
  private let generatesThumbnails: Bool
  private var records: [ShelfRecord] = []
  private var leases: [UUID: ShelfFileLease] = [:]
  private var requests: [UUID: QLThumbnailGenerator.Request] = [:]
  private var shares: [UUID: ShelfAirDropSession] = [:]
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var generation = 0
  private var importGeneration = 0
  private var active = false
  private var loaded = false
  private var loadFailed = false
  var isInteractionBusy: Bool { importing || sharing }

  init(
    persistence: any ShelfPersistence = ShelfJSONPersistence.standard,
    access: any ShelfFileAccess = NativeShelfFileAccess(), generatesThumbnails: Bool = true
  ) {
    self.persistence = persistence
    self.access = access
    self.generatesThumbnails = generatesThumbnails
  }
  func setEnabled(_ enabled: Bool) {
    guard active != enabled else { return }
    active = enabled
    importGeneration += 1
    if enabled {
      if !loaded {
        do {
          records = try persistence.load()
          loaded = true
          loadFailed = false
        } catch {
          self.error = "Couldn’t load Shelf. " + error.localizedDescription
          loadFailed = true
        }
      }
      observe(.default, NSApplication.didBecomeActiveNotification)
      observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
      refresh()
    } else {
      generation += 1
      importing = false
      cancelThumbnails()
      leases.removeAll()
      thumbnails.removeAll()
      items.removeAll()
      observers.forEach { $0.0.removeObserver($0.1) }
      observers.removeAll()
      // Native sharing retains an independent lease until its delegate finishes.
    }
  }
  private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
    let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    observers.append((center, observer))
  }
  func refresh() {
    guard active, !loadFailed else { return }
    generation += 1
    cancelThumbnails()
    leases.removeAll()
    thumbnails.removeAll()
    var renewed = records
    items = records.enumerated().map { index, record in
      do {
        let lease = try access.resolve(record.bookmark)
        leases[record.id] = lease
        renewed[index].name = lease.url.lastPathComponent
        if lease.stale {
          renewed[index].bookmark = try access.bookmark(for: lease.url)
          renewed[index].name = lease.url.lastPathComponent
        }
        return ShelfItem(record: renewed[index], url: lease.url, problem: nil)
      } catch {
        return ShelfItem(
          record: record, url: nil, problem: "File unavailable · re-add it to restore access")
      }
    }
    if renewed != records {
      do {
        try persistence.save(renewed)
        records = renewed
      } catch { self.error = "Couldn’t update saved file access. " + error.localizedDescription }
    }
    if generatesThumbnails {
      for item in items { requestThumbnail(item) }
    }
  }
  func add(_ urls: [URL]) {
    guard active else {
      error = ShelfError.inactive.localizedDescription
      return
    }
    guard !loadFailed else {
      error = ShelfError.invalidManifest.localizedDescription
      return
    }
    var proposed = records
    var known = Set(leases.values.map { $0.url.standardizedFileURL.resolvingSymlinksInPath() })
    var failures: [String] = []
    for url in urls {
      guard url.isFileURL else {
        failures.append(ShelfError.fileURLsOnly.localizedDescription)
        continue
      }
      let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
      guard !known.contains(normalized) else { continue }
      guard proposed.count < Self.limit else {
        failures.append(ShelfError.full.localizedDescription)
        break
      }
      do {
        let bookmark = try access.bookmark(for: url)
        proposed.append(ShelfRecord(id: UUID(), bookmark: bookmark, name: url.lastPathComponent))
        known.insert(normalized)
      } catch {
        failures.append("Couldn’t add “\(url.lastPathComponent)”. " + error.localizedDescription)
      }
    }
    guard proposed != records else {
      if let failure = failures.first { error = failure }
      return
    }
    do {
      try persistence.save(proposed)
      records = proposed
      error = failures.first
      refresh()
    } catch { self.error = "Couldn’t save Shelf. " + error.localizedDescription }
  }
  func remove(_ id: UUID) {
    guard active, !loadFailed else { return }
    let proposed = records.filter { $0.id != id }
    do {
      try persistence.save(proposed)
      records = proposed
      refresh()
    } catch { self.error = "Couldn’t remove item from Shelf. " + error.localizedDescription }
  }
  func chooseFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.prompt = "Add to Shelf"
    guard active, !importing else { return }
    importing = true
    let request = importGeneration
    panel.begin { [weak self] response in
      MainActor.assumeIsolated {
        guard let self, self.importGeneration == request else { return }
        defer { self.importing = false }
        if response == .OK { self.add(panel.urls) }
      }
    }
  }
  func importFiles(_ providers: [NSItemProvider]) async {
    guard active, !importing else { return }
    importing = true
    let request = importGeneration
    defer { if importGeneration == request { importing = false } }
    var urls: [URL] = []
    for provider in providers.prefix(Self.limit)
    where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      let url: URL? = await withCheckedContinuation { continuation in
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
          continuation.resume(
            returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
        }
      }
      if let url { urls.append(url) }
    }
    guard active, importGeneration == request, !Task.isCancelled else { return }
    if urls.isEmpty {
      error = "No accessible local files were found in this drop."
    } else {
      add(urls)
    }
  }
  func dragProvider(_ id: UUID) -> NSItemProvider {
    guard let record = records.first(where: { $0.id == id }),
      let lease = try? access.resolve(record.bookmark)
    else { return NSItemProvider() }
    let provider = NSItemProvider()
    // The provider owns this independent lease until the drag is released.
    provider.registerDataRepresentation(
      forTypeIdentifier: UTType.fileURL.identifier, visibility: .all
    ) { completion in
      completion(lease.url.dataRepresentation, nil)
      return nil
    }
    return provider
  }
  func open(_ id: UUID) {
    guard let url = leases[id]?.url else { return }
    if !NSWorkspace.shared.open(url) { error = "macOS couldn’t open this file." }
  }
  func reveal(_ id: UUID) {
    guard let url = leases[id]?.url else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
  func airDrop(_ id: UUID) {
    guard shares[id] == nil else { return }
    guard let record = records.first(where: { $0.id == id }) else { return }
    do {
      let lease = try access.resolve(record.bookmark)
      let session = try ShelfAirDropSession(lease: lease) { [weak self] error in
        guard let self else { return }
        self.shares.removeValue(forKey: id)
        self.sharing = !self.shares.isEmpty
        if let error { self.error = error }
      }
      shares[id] = session
      sharing = true
      session.start()
    } catch { self.error = error.localizedDescription }
  }
  private func requestThumbnail(_ item: ShelfItem) {
    guard let lease = leases[item.id] else { return }
    let requestGeneration = generation
    let request = QLThumbnailGenerator.Request(
      fileAt: lease.url, size: CGSize(width: 72, height: 72),
      scale: 2, representationTypes: [.thumbnail, .icon])
    requests[item.id] = request
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
      [weak self, lease] representation, _ in
      let image = representation?.nsImage
      Task { @MainActor [weak self, lease] in
        _ = lease  // Keep scoped access alive through generation and actor handoff.
        guard let self, self.active, self.generation == requestGeneration,
          self.records.contains(where: { $0.id == item.id })
        else { return }
        self.requests.removeValue(forKey: item.id)
        if let image { self.thumbnails[item.id] = image }
      }
    }
  }
  private func cancelThumbnails() {
    requests.values.forEach { QLThumbnailGenerator.shared.cancel($0) }
    requests.removeAll()
  }
  func stop() { setEnabled(false) }
}

@MainActor private final class ShelfAirDropSession: NSObject, NSSharingServiceDelegate {
  private let lease: ShelfFileLease
  private let service: NSSharingService
  private var completion: ((String?) -> Void)?
  init(lease: ShelfFileLease, completion: @escaping (String?) -> Void) throws {
    guard let service = NSSharingService(named: .sendViaAirDrop),
      service.canPerform(withItems: [lease.url])
    else { throw ShelfError.airDropUnavailable }
    self.lease = lease
    self.service = service
    self.completion = completion
    super.init()
    service.delegate = self
  }
  func start() { service.perform(withItems: [lease.url]) }
  func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
    finish(nil)
  }
  func sharingService(
    _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error
  ) {
    let nsError = error as NSError
    finish(
      nsError.code == NSUserCancelledError ? nil : "AirDrop failed. " + error.localizedDescription)
  }
  private func finish(_ error: String?) {
    service.delegate = nil
    let callback = completion
    completion = nil
    callback?(error)
  }
}
