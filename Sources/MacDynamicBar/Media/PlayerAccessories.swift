import AppKit
import Combine
import SwiftUI

// MARK: - Customizable Player Action

enum PlayerAction: String, CaseIterable, Identifiable {
  case like, shuffle, replay
  var id: String { rawValue }
  var title: String {
    switch self {
    case .like: "Like Song"
    case .shuffle: "Shuffle"
    case .replay: "Repeat Song"
    }
  }
}

@MainActor
final class PlayerAccessories: ObservableObject {
  @Published private(set) var liked: Bool?
  @Published private(set) var shuffled: Bool?
  @Published private(set) var repeatOne: Bool?
  @Published private(set) var spotifyArtists: [SpotifyArtistLink] = []
  @Published private(set) var isExplicit: Bool?
  @Published private(set) var busy = false
  @Published private(set) var error: String?
  private let player: MediaPlayer
  let account: SpotifyAccount
  private var source: MusicSource?
  private var trackID: String?
  private var revision = 0
  private var refreshTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?
  private var subscriptions = Set<AnyCancellable>()

  init(player: MediaPlayer, account: SpotifyAccount = .shared) {
    self.player = player
    self.account = account
    player.$captureTarget.sink { [weak self] target in
      guard let self else { return }
      let id = player.track?.id
      guard self.source != target.source || self.trackID != id else { return }
      self.source = target.source
      self.trackID = id
      self.refresh()
    }.store(in: &subscriptions)
    account.$isConnected.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
      self?.refresh()
    }.store(in: &subscriptions)
  }

  func stop() {
    revision += 1
    refreshTask?.cancel()
    actionTask?.cancel()
    subscriptions.removeAll()
  }

  func symbol(for action: PlayerAction) -> String {
    switch action {
    case .like: liked == true ? "heart.fill" : "heart"
    case .shuffle: "shuffle"
    case .replay: repeatOne == true ? "repeat.1" : "repeat"
    }
  }

  func active(_ action: PlayerAction) -> Bool {
    switch action {
    case .like: liked == true
    case .shuffle: shuffled == true
    case .replay: repeatOne == true
    }
  }

  func canUse(_ action: PlayerAction) -> Bool {
    guard player.canControlPlayback, !busy else { return false }
    if source == .spotify, action != .shuffle, !account.isConnected { return true }
    switch action {
    case .like: return liked != nil
    case .shuffle: return shuffled != nil
    case .replay: return repeatOne != nil
    }
  }

  func help(for action: PlayerAction) -> String {
    if source == .spotify, action != .shuffle, !account.isConnected {
      return "Connect Spotify to use \(action.title). Right-click to choose another action."
    }
    return action.title + ". Right-click to customize."
  }

  func refresh() {
    revision += 1
    let version = revision
    refreshTask?.cancel()
    liked = nil
    shuffled = nil
    repeatOne = nil
    isExplicit = nil
    spotifyArtists = []
    error = nil
    guard let source, player.track != nil else { return }
    refreshTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        if source == .appleMusic {
          guard let id = self.trackID, Self.validAppleID(id) else { return }
          let result = try await self.run(Self.appleStateScript(id: id))
          guard version == self.revision else { return }
          guard result.numberOfItems == 3 else {
            throw SpotifyAccountError.message(
              "The playing track changed. Open the player again to refresh.")
          }
          self.liked = result.atIndex(1)?.booleanValue
          self.shuffled = result.atIndex(2)?.booleanValue
          self.repeatOne = result.atIndex(3)?.booleanValue
        } else {
          let result = try await self.run(Self.spotifyShuffleScript)
          guard version == self.revision else { return }
          self.shuffled = result.booleanValue
          if self.account.isConnected {
            let details = try await self.account.playbackDetails()
            guard version == self.revision else { return }
            self.repeatOne = details.repeatMode.map { $0 == "track" }
            if details.uri == self.trackID {
              self.isExplicit = details.explicit
              self.spotifyArtists = details.artists(matching: self.trackID)
            }
            if let uri = self.trackID, Self.validSpotifyURI(uri) {
              let saved = try await self.account.contains(uri)
              guard version == self.revision else { return }
              self.liked = saved
            }
          }
        }
      } catch is CancellationError {
      } catch {
        guard version == self.revision else { return }
        self.error = error.localizedDescription
      }
    }
  }

  func perform(_ action: PlayerAction) {
    guard canUse(action), let source else { return }
    if source == .spotify, action != .shuffle, !account.isConnected {
      account.showConnectionPrompt()
      return
    }
    let id = trackID
    let version = revision
    let newLiked = !(liked ?? false)
    let newShuffle = !(shuffled ?? false)
    let newRepeat = !(repeatOne ?? false)
    busy = true
    error = nil
    actionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        self.busy = false
        self.actionTask = nil
      }
      guard version == self.revision else { return }
      do {
        if source == .appleMusic {
          guard let id, Self.validAppleID(id) else { return }
          let command: String
          switch action {
          case .like: command = "set favorited of current track to \(newLiked ? "true" : "false")"
          case .shuffle: command = "set shuffle enabled to \(newShuffle ? "true" : "false")"
          case .replay: command = "set song repeat to \(newRepeat ? "one" : "off")"
          }
          let script = """
            with timeout of 2 seconds
                tell application id "com.apple.Music"
                    if persistent ID of current track is not "\(id)" then return false
                    \(command)
                    return true
                end tell
            end timeout
            """
          guard try await self.run(script).booleanValue else {
            throw SpotifyAccountError.message(
              "The song changed before the action completed. Try again.")
          }
        } else {
          switch action {
          case .like:
            guard let id, Self.validSpotifyURI(id) else {
              throw SpotifyAccountError.message("This item cannot be saved to Spotify Liked Songs")
            }
            try await self.account.setSaved(newLiked, uri: id)
          case .shuffle:
            _ = try await self.run(
              """
              with timeout of 2 seconds
                  tell application id "com.spotify.client"
                      set shuffling to \(newShuffle ? "true" : "false")
                  end tell
              end timeout
              """)
          case .replay: try await self.account.setRepeatOne(newRepeat)
          }
        }
        guard version == self.revision else { return }
        // Read back the actual application/account state instead of
        // colouring the icon before a write has succeeded.
        self.refresh()
      } catch is CancellationError {
      } catch {
        guard version == self.revision else { return }
        self.error = error.localizedDescription
      }
    }
  }

  static func validSpotifyURI(_ value: String) -> Bool {
    let prefix = "spotify:track:"
    guard value.hasPrefix(prefix) else { return false }
    let id = value.dropFirst(prefix.count)
    return id.count == 22 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
  }

  private static func validAppleID(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { $0.isHexDigit }
  }

  private func run(_ source: String) async throws -> NSAppleEventDescriptor {
    let response = await PlaybackScriptWorker.shared.execute(source)
    try Task.checkCancellation()
    if let code = response.errorCode {
      if code == -1743 {
        throw SpotifyAccountError.message(
          "Allow Minnow access in System Settings → Privacy & Security → Automation")
      }
      throw SpotifyAccountError.message("The player could not complete the action (\(code))")
    }
    return response.value
  }

  static func appleStateScript(id: String) -> String {
    """
    with timeout of 2 seconds
        tell application id "com.apple.Music"
            if persistent ID of current track is not "\(id)" then return {}
            return {favorited of current track, shuffle enabled, song repeat is one}
        end tell
    end timeout
    """
  }

  static let spotifyShuffleScript = """
    with timeout of 2 seconds
        tell application id "com.spotify.client" to return shuffling
    end timeout
    """
}

struct PlayerActionButton: View {
  @ObservedObject var accessories: PlayerAccessories
  @ObservedObject var settings: MinnowSettings
  var songColor: Color = .pink
  private var action: PlayerAction { settings.leftAction }
  var body: some View {
    Button {
      accessories.perform(action)
    } label: {
      Image(systemName: accessories.symbol(for: action))
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(
          accessories.active(action)
            ? (settings.heartSongColor && action == .like ? songColor : Color.pink) : Color.white
        )
        .frame(width: 36, height: 40).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!accessories.canUse(action))
    .opacity(accessories.canUse(action) ? 1 : 0.35)
    .help(accessories.help(for: action))
    .accessibilityLabel(action.title)
    .accessibilityValue(accessories.active(action) ? "On" : "Off")
    .contextMenu {
      ForEach(PlayerAction.allCases) { option in
        Button {
          settings.leftAction = option
        } label: {
          if action == option {
            Label(option.title, systemImage: "checkmark")
          } else {
            Text(option.title)
          }
        }
      }
    }
  }
}

struct PlayerAccessoryDiagnostics: View {
  @ObservedObject var accessories: PlayerAccessories
  var body: some View {
    if let error = accessories.error {
      Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
  }
}
