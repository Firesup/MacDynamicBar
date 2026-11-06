import AppKit
import Combine

// MARK: - Spotify Desktop Playback

@MainActor
final class SpotifyPlayer: ObservableObject, DesktopPlayback {
  @Published private(set) var track: MusicTrack?
  @Published private(set) var isPlaying = false
  @Published private(set) var artwork: NSImage?
  @Published private(set) var duration: TimeInterval = 0
  private(set) var isRunning = false
  private(set) var lastError: String?
  var onChange: (@MainActor () -> Void)?

  private var positionAtUpdate: TimeInterval = 0
  private var positionUpdatedAt = Date.now
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var isRefreshing = false
  private var refreshPending = false
  private var lifecycle = 0
  private var artworkTrackID: String?
  private var artworkTask: Task<Void, Never>?
  private var artworkGeneration = 0

  var title: String { track?.title ?? "No audio found" }
  var subtitle: String {
    if let lastError { return lastError }
    guard let track else { return isRunning ? "Play a song in Spotify" : "Open Spotify to begin" }
    let artist = track.artist.isEmpty ? "Unknown artist" : track.artist
    return isRunning ? artist : "\(artist) · Spotify closed"
  }
  var canControlPlayback: Bool { isRunning && track != nil && lastError == nil }

  private var sessionLocked = false
  func setSessionLocked(_ locked: Bool) {
    if locked != sessionLocked { lifecycle += 1 }
    sessionLocked = locked
  }

  private func receivePlaybackNotice(_ notice: DesktopPlaybackNotice?) {
    guard sessionLocked else {
      refresh()
      return
    }
    guard let notice else { return }
    isRunning = true
    let position = playbackPosition(at: .now)
    if let incoming = notice.track {
      let sameTrack =
        (incoming.id != nil && incoming.id == track?.id)
        || (incoming.title == track?.title && incoming.artist == track?.artist
          && incoming.album == track?.album)
      if !sameTrack {
        artwork = nil
        duration = notice.duration ?? 0
      }
      // A partial event for the current track must not erase its confirmed seek identifier.
      if !sameTrack || incoming.id != nil { track = incoming }
      positionAtUpdate = notice.position ?? (sameTrack ? position : 0)
    } else {
      positionAtUpdate = notice.position ?? position
    }
    if let duration = notice.duration { self.duration = duration }
    positionUpdatedAt = .now
    isPlaying = notice.playing
    onChange?()
  }

  func start() {
    guard observers.isEmpty else { return }
    let distributed = DistributedNotificationCenter.default()
    let playback = distributed.addObserver(
      forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
      object: nil, queue: .main
    ) { [weak self] notification in
      let notice = DesktopPlaybackNotice(userInfo: notification.userInfo ?? [:], source: .spotify)
      MainActor.assumeIsolated { self?.receivePlaybackNotice(notice) }
    }
    observers.append((distributed, playback))
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ] {
      let token = workspace.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] notification in
        let bundleID =
          (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication)?.bundleIdentifier
        Task { @MainActor [weak self, bundleID] in
          guard bundleID == MusicSource.spotify.bundleIdentifier else { return }
          self?.refresh()
        }
      }
      observers.append((workspace, token))
    }
    refresh()
  }

  func stop() {
    lifecycle += 1
    refreshPending = false
    for (center, token) in observers { center.removeObserver(token) }
    observers.removeAll()
    artworkGeneration += 1
    artworkTask?.cancel()
    artworkTask = nil
  }

  func refresh() {
    guard !sessionLocked else { return }
    guard !isRefreshing else {
      refreshPending = true
      return
    }
    isRefreshing = true
    let version = lifecycle
    Task { @MainActor in
      defer {
        isRefreshing = false
        onChange?()
        if refreshPending {
          refreshPending = false
          refresh()
        }
      }
      isRunning = !NSRunningApplication.runningApplications(
        withBundleIdentifier: MusicSource.spotify.bundleIdentifier
      ).isEmpty
      guard isRunning else {
        positionAtUpdate = playbackPosition(at: .now)
        positionUpdatedAt = .now
        isPlaying = false
        lastError = nil
        return
      }
      let snapshot = await execute(Self.snapshotScript)
      guard version == lifecycle, !sessionLocked else { return }
      guard !refreshPending else { return }
      guard let result = snapshot else {
        isPlaying = false
        return
      }
      guard version == lifecycle, !sessionLocked else { return }
      guard let state = result.atIndex(1)?.stringValue,
        let name = result.atIndex(2)?.stringValue,
        let artist = result.atIndex(3)?.stringValue,
        let album = result.atIndex(4)?.stringValue,
        let trackID = result.atIndex(5)?.stringValue
      else {
        isPlaying = false
        lastError = "Could not read Spotify"
        return
      }
      isPlaying = state == "playing"
      guard state != "stopped", !name.isEmpty else { return }
      duration = Self.durationInSeconds(result.atIndex(6)?.doubleValue ?? 0)
      positionAtUpdate = Self.finiteNonnegative(result.atIndex(7)?.doubleValue ?? 0)
      positionUpdatedAt = .now
      track = MusicTrack(title: name, artist: artist, album: album, id: trackID)
      if artworkTrackID != trackID || (artwork == nil && artworkTask == nil) {
        loadArtwork(for: trackID, urlString: result.atIndex(8)?.stringValue ?? "")
      }
    }

  }

  static func durationInSeconds(_ milliseconds: Double) -> TimeInterval {
    // Spotify returns milliseconds despite the scripting dictionary's label.
    finiteNonnegative(milliseconds) / 1000
  }

  private static func finiteNonnegative(_ value: Double) -> Double {
    value.isFinite ? max(0, value) : 0
  }

  func playbackPosition(at date: Date) -> TimeInterval {
    let elapsed = isPlaying ? max(0, date.timeIntervalSince(positionUpdatedAt)) : 0
    return min(duration, max(0, positionAtUpdate + elapsed))
  }

  func seek(to position: TimeInterval, expectedTrackID: String) {
    guard canControlPlayback, track?.id == expectedTrackID,
      let command = DesktopSeek.make(
        source: .spotify, trackID: expectedTrackID,
        position: position, duration: duration)
    else { return }
    let version = lifecycle
    Task { @MainActor in
      let result = await execute(command.script)
      guard version == lifecycle, !sessionLocked, track?.id == expectedTrackID else { return }
      guard let result else {
        onChange?()
        return
      }
      guard result.booleanValue else {
        refresh()
        return
      }
      positionAtUpdate = command.position
      positionUpdatedAt = .now
      onChange?()
    }

  }

  func togglePlayback() { send("playpause") }
  func next() { send("next track") }
  func previous() { send("previous track") }

  private func send(_ command: String) {
    guard canControlPlayback else { return }
    // This private method receives only the three constant commands above.
    let script = """
      with timeout of 2 seconds
          if application id "com.spotify.client" is running then
              tell application id "com.spotify.client" to \(command)
          end if
      end timeout
      """
    let version = lifecycle
    Task { @MainActor in
      let result = await execute(script)
      guard version == lifecycle, !sessionLocked else { return }
      guard result != nil else {
        onChange?()
        return
      }
      refresh()
    }

  }

  private func execute(_ source: String) async -> NSAppleEventDescriptor? {
    let version = lifecycle
    let result = await PlaybackScriptWorker.shared.execute(source)
    guard version == lifecycle, !sessionLocked else { return nil }
    guard let code = result.errorCode else {
      lastError = nil
      return result.value
    }
    switch code {
    case -1743: lastError = "Allow Spotify access in System Settings → Automation"
    case -1712: lastError = "Spotify took too long to respond"
    default: lastError = "Could not communicate with Spotify"
    }
    return nil
  }

  private func loadArtwork(for trackID: String, urlString: String) {
    artworkGeneration += 1
    let version = artworkGeneration
    artworkTask?.cancel()
    artworkTask = nil
    artworkTrackID = trackID
    artwork = nil
    guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else { return }
    artworkTask = Task { @MainActor [weak self] in
      defer {
        if let self, self.artworkGeneration == version { self.artworkTask = nil }
      }
      do {
        let (data, response) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()
        guard let self, self.artworkGeneration == version,
          (response as? HTTPURLResponse)?.statusCode == 200,
          response.mimeType?.hasPrefix("image/") == true,
          data.count <= 10 * 1024 * 1024
        else { return }
        self.artwork = NSImage(data: data)
        self.onChange?()
      } catch {
        // Missing artwork must not disable playback controls.
      }
    }
  }

  static let snapshotScript = """
    with timeout of 2 seconds
        if application id "com.spotify.client" is not running then
            return {"stopped", "", "", "", "", 0, 0, ""}
        end if
        tell application id "com.spotify.client"
            set playbackState to player state
            if playbackState is stopped then
                return {"stopped", "", "", "", "", 0, 0, ""}
            end if
            set stateText to "paused"
            if playbackState is playing then set stateText to "playing"
            set selectedTrack to current track
            if selectedTrack is missing value then
                return {stateText, "", "", "", "", 0, 0, ""}
            end if
            set coverURL to ""
            try
                set coverURL to artwork url of selectedTrack
                if coverURL is missing value then set coverURL to ""
            end try
            return {stateText, name of selectedTrack, artist of selectedTrack, ¬
                album of selectedTrack, id of selectedTrack, duration of selectedTrack, ¬
                player position, coverURL}
        end tell
    end timeout
    """
}
