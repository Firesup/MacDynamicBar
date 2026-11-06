import Combine

// MARK: - Shared Playback Session

@MainActor
final class IslandMediaSession {
  let player = MediaPlayer()
  let audio = MusicAudioLevels()
  let outputs = AudioOutputs()
  let accessories: PlayerAccessories
  private var routeVersion = 0
  private var systemAwake = true
  private var routeTask: Task<Void, Never>?
  private var subscriptions = Set<AnyCancellable>()

  init() {
    accessories = PlayerAccessories(player: player)
    audio.setSuspended(true)
    outputs.$selectedID.removeDuplicates().dropFirst().sink { [weak self] id in
      self?.audio.outputChanged(id)
    }.store(in: &subscriptions)
    player.$captureTarget.removeDuplicates().sink { [weak self] target in
      self?.routeVersion += 1
      self?.audio.setPlayback(target)
    }.store(in: &subscriptions)
  }

  func start() {
    outputs.start()
    player.start()
    guard routeTask == nil else { return }
    routeTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if self.systemAwake, self.player.captureTarget.source == .spotify,
          self.accessories.account.isConnected
        {
          let version = self.routeVersion
          do {
            let details = try await self.accessories.account.playbackDetails()
            try Task.checkCancellation()
            if self.systemAwake, self.routeVersion == version,
              self.player.captureTarget.source == .spotify
            {
              self.audio.setSpotifyLocation(.resolve(details))
            }
          } catch {
            if !Task.isCancelled, self.routeVersion == version {
              self.audio.setSpotifyLocation(.unknown)
            }
          }
        } else {
          self.audio.setSpotifyLocation(.unknown)
        }
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
      }
    }
  }
  func setSystemAwake(_ awake: Bool) {
    systemAwake = awake
    routeVersion += 1
  }
  func apply(_ settings: MinnowSettings) {
    player.setSourcePreference(settings.source)
    if audio.isEnabled != settings.audioReactive { audio.setEnabled(settings.audioReactive) }
  }
  func stop() {
    routeVersion += 1
    routeTask?.cancel()
    routeTask = nil
    accessories.stop()
    outputs.stop()
    player.stop()
    audio.stop()
    subscriptions.removeAll()
  }
}
