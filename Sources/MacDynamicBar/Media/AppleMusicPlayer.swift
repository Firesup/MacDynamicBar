import AppKit
import Combine

// MARK: - Apple Music Track

struct MusicTrack: Equatable, Sendable {
  let title: String
  let artist: String
  let album: String
  var id: String? = nil
}

// MARK: - Apple Music Player

@MainActor
final class AppleMusicPlayer: ObservableObject {
  var onChange: (@MainActor () -> Void)?
  @Published private(set) var track: MusicTrack?
  @Published private(set) var isPlaying = false
  @Published private(set) var isMusicRunning = false
  @Published private(set) var lastError: String?
  @Published private(set) var artwork: NSImage?
  @Published private(set) var duration: TimeInterval = 0

  private var positionAtUpdate: TimeInterval = 0
  private var positionUpdatedAt = Date.now

  private var artworkTrackID: String?
  private var isRefreshing = false
  private var refreshPending = false
  private var lifecycle = 0

  private let musicBundleID = "com.apple.Music"

  private var playbackObserver: NSObjectProtocol?

  private var workspaceObservers: [NSObjectProtocol] = []

  var title: String {
    track?.title ?? "No audio found"
  }

  var subtitle: String {
    if let lastError {
      return lastError
    }

    guard let track else {
      return isMusicRunning
        ? "Play a song in Apple Music"
        : "Open Apple Music to begin"
    }

    let artist =
      track.artist.isEmpty
      ? "Unknown artist"
      : track.artist

    return isMusicRunning
      ? artist
      : "\(artist) · Music closed"
  }

  func playbackPosition(at date: Date) -> TimeInterval {
    // Advance locally between playback notifications.
    // This does not repeatedly query the Music application.
    let elapsed =
      isPlaying
      ? max(0, date.timeIntervalSince(positionUpdatedAt))
      : 0

    return min(
      duration,
      max(0, positionAtUpdate + elapsed)
    )
  }

  private func loadArtwork(for trackID: String) async {
    let version = lifecycle
    // Never display the previous song's cover for a new song.
    artwork = nil

    // Music persistent IDs are hexadecimal.
    // Validate before inserting the ID into AppleScript.
    guard
      !trackID.isEmpty,
      trackID.allSatisfy({ $0.isHexDigit })
    else {
      return
    }

    let source = """
      with timeout of 2 seconds
          if application id "com.apple.Music" is not running then
              return missing value
          end if

          tell application id "com.apple.Music"
              set selectedTrack to current track

              if persistent ID of selectedTrack is not "\(trackID)" then
                  return missing value
              end if

              try
                  return raw data of artwork 1 of selectedTrack
              on error
                  return missing value
              end try
          end tell
      end timeout
      """

    let response = await PlaybackScriptWorker.shared.execute(source)
    guard version == lifecycle, !sessionLocked, response.errorCode == nil else { return }
    artwork = NSImage(data: response.value.data)
  }

  var canControlPlayback: Bool {
    isMusicRunning && track != nil && lastError == nil
  }

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
    isMusicRunning = true
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
    // Prevent duplicate observers if start is called again.
    guard playbackObserver == nil else { return }

    playbackObserver = DistributedNotificationCenter.default()
      .addObserver(
        forName: Notification.Name(
          "com.apple.Music.playerInfo"
        ),
        object: nil,
        queue: .main
      ) { [weak self] notification in
        let notice = DesktopPlaybackNotice(
          userInfo: notification.userInfo ?? [:], source: .appleMusic)
        MainActor.assumeIsolated {
          self?.receivePlaybackNotice(notice)
        }
      }

    observeWorkspace(
      NSWorkspace.didLaunchApplicationNotification
    )

    observeWorkspace(
      NSWorkspace.didTerminateApplicationNotification
    )

    refresh()
  }

  func stop() {
    lifecycle += 1
    refreshPending = false
    if let playbackObserver {
      DistributedNotificationCenter.default()
        .removeObserver(playbackObserver)
    }

    playbackObserver = nil

    let center = NSWorkspace.shared.notificationCenter

    for observer in workspaceObservers {
      center.removeObserver(observer)
    }

    workspaceObservers.removeAll()
  }

  func refresh() {
    guard !sessionLocked else { return }
    // Prevent overlapping refreshes while AppleScript processes events.
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

      isMusicRunning =
        !NSRunningApplication
        .runningApplications(
          withBundleIdentifier: musicBundleID
        )
        .isEmpty

      guard isMusicRunning else {
        isPlaying = false
        lastError = nil

        // Preserve the last track and artwork when Music closes.
        return
      }

      let snapshot = await execute(Self.snapshotScript)
      guard version == lifecycle, !sessionLocked else { return }
      guard !refreshPending else { return }
      guard let result = snapshot else {
        isPlaying = false
        return
      }

      guard
        let playbackState = result.atIndex(1)?.stringValue,
        let title = result.atIndex(2)?.stringValue,
        let artist = result.atIndex(3)?.stringValue,
        let album = result.atIndex(4)?.stringValue,
        let trackID = result.atIndex(5)?.stringValue
      else {
        isPlaying = false
        lastError = "Could not read Apple Music"
        return
      }

      isPlaying = playbackState == "playing"

      guard playbackState != "stopped", !title.isEmpty else {
        return
      }

      duration = max(
        0,
        result.atIndex(6)?.doubleValue ?? 0
      )

      positionAtUpdate = max(
        0,
        result.atIndex(7)?.doubleValue ?? 0
      )

      positionUpdatedAt = .now

      // Avoid fetching the same artwork on every play/pause event.
      // Retry on a later event if Music did not provide an image.
      if artworkTrackID != trackID || artwork == nil {
        await loadArtwork(for: trackID)
        guard version == lifecycle, !sessionLocked else { return }
        artworkTrackID = trackID
      }

      let updatedTrack = MusicTrack(
        title: title,
        artist: artist,
        album: album,
        id: trackID
      )

      if track != updatedTrack {
        track = updatedTrack
      }
    }

  }

  func seek(to position: TimeInterval, expectedTrackID: String) {
    guard canControlPlayback, track?.id == expectedTrackID,
      let command = DesktopSeek.make(
        source: .appleMusic, trackID: expectedTrackID,
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

  func togglePlayback() {
    send(.togglePlayback)
  }

  func next() {
    send(.next)
  }

  func previous() {
    send(.previous)
  }

  private enum Command: String {
    case togglePlayback = "playpause"
    case next = "next track"
    case previous = "previous track"
  }

  private func send(_ command: Command) {
    guard canControlPlayback else { return }

    // Command text comes only from the enum above.
    let source = """
      with timeout of 2 seconds
          if application id "com.apple.Music" is running then
              tell application id "com.apple.Music"
                  \(command.rawValue)
              end tell
          end if
      end timeout
      """

    let version = lifecycle
    Task { @MainActor in
      let result = await execute(source)
      guard version == lifecycle, !sessionLocked else { return }
      guard result != nil else {
        onChange?()
        return
      }
      refresh()
    }

  }

  private func observeWorkspace(
    _ name: Notification.Name
  ) {
    let center = NSWorkspace.shared.notificationCenter

    let observer = center.addObserver(
      forName: name,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      // Extract the String before crossing into the main actor.
      let bundleIdentifier: String? =
        (notification.userInfo?[
          NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication)?.bundleIdentifier

      // Capture the String rather than the notification.
      Task { @MainActor [weak self, bundleIdentifier] in
        guard let self else { return }

        guard bundleIdentifier == self.musicBundleID else {
          return
        }

        self.refresh()
      }
    }

    workspaceObservers.append(observer)
  }

  private func execute(
    _ source: String
  ) async -> NSAppleEventDescriptor? {
    let version = lifecycle
    let response = await PlaybackScriptWorker.shared.execute(source)
    guard version == lifecycle, !sessionLocked else { return nil }
    if let code = response.errorCode {
      if code == -1743 {
        lastError = "Allow Music access in System Settings"
      } else {
        lastError = "Apple Music is unavailable"
      }

      return nil
    }

    lastError = nil
    return response.value
  }

  private static let snapshotScript = """
    with timeout of 2 seconds
        if application id "com.apple.Music" is not running then
            return {"stopped", "", "", "", "", 0, 0}
        end if

        tell application id "com.apple.Music"
            set playbackState to player state

            if playbackState is stopped then
                return {"stopped", "", "", "", "", 0, 0}
            end if

            if playbackState is playing then
                set stateText to "playing"
            else
                set stateText to "paused"
            end if

            set selectedTrack to current track

            return {stateText, name of selectedTrack, artist of selectedTrack, ¬
                album of selectedTrack, persistent ID of selectedTrack, ¬
                duration of selectedTrack, player position}
        end tell
    end timeout
    """
}
