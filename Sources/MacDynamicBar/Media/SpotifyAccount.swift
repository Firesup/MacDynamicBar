import AppKit
import Combine
import CryptoKit
import Network
import LocalAuthentication
import Security

// MARK: - Spotify Account Authorization (PKCE)

enum SpotifyAccountError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}

@MainActor
final class SpotifyCallbackServer {
  static let redirectURI = "http://127.0.0.1:8888/spotify/callback"
  enum CallbackResult: Equatable {
    case invalid, denied
    case code(String)
  }

  static func parseTarget(_ target: String, expectedState: String) -> CallbackResult {
    guard let url = URLComponents(string: "http://127.0.0.1" + target),
      url.path == "/spotify/callback"
    else { return .invalid }
    let items = url.queryItems ?? []
    guard items.filter({ $0.name == "state" }).count == 1,
      items.first(where: { $0.name == "state" })?.value == expectedState
    else { return .invalid }
    if items.contains(where: { $0.name == "error" }) { return .denied }
    guard items.filter({ $0.name == "code" }).count == 1,
      let code = items.first(where: { $0.name == "code" })?.value,
      !code.isEmpty
    else { return .invalid }
    return .code(code)
  }
  private var listener: NWListener?
  private var completion: CheckedContinuation<String, Error>?
  private var timeout: Task<Void, Never>?
  private var expectedState = ""

  func receiveCode(state: String, authorizationURL: URL) async throws -> String {
    expectedState = state
    return try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      do {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8888)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
          Task { @MainActor [weak self] in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] listenerState in
          Task { @MainActor [weak self] in
            guard let self, self.completion != nil else { return }
            switch listenerState {
            case .ready:
              if !NSWorkspace.shared.open(authorizationURL) {
                self.finish(
                  .failure(SpotifyAccountError.message("Could not open the Spotify login page")))
              }
            case .failed:
              self.finish(
                .failure(
                  SpotifyAccountError.message(
                    "Could not open the local Spotify callback. Check whether port 8888 is in use.")
                ))
            default: break
            }
          }
        }
        listener.start(queue: .main)
        timeout = Task { @MainActor [weak self] in
          do { try await Task.sleep(for: .seconds(180)) } catch { return }
          self?.finish(
            .failure(
              SpotifyAccountError.message("Spotify sign-in timed out. Try connecting again.")))
        }
      } catch { finish(.failure(error)) }
    }
  }

  func cancel() { finish(.failure(CancellationError())) }

  private func accept(_ connection: NWConnection) {
    connection.start(queue: .main)
    read(connection, accumulated: Data())
  }

  private func read(_ connection: NWConnection, accumulated: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
      [weak self] data, _, complete, error in
      Task { @MainActor [weak self] in
        guard let self, self.completion != nil else {
          connection.cancel()
          return
        }
        var bytes = accumulated
        if let data { bytes.append(data) }
        guard bytes.count <= 16384, error == nil else {
          connection.cancel()
          return
        }
        guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n")
        else {
          if complete { connection.cancel() } else { self.read(connection, accumulated: bytes) }
          return
        }
        let firstLine = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard firstLine.count >= 2, firstLine[0] == "GET" else {
          self.respond(connection, text: "Not found", status: "404 Not Found")
          return
        }
        let result = Self.parseTarget(String(firstLine[1]), expectedState: self.expectedState)
        guard result != .invalid else {
          self.respond(connection, text: "Invalid sign-in state", status: "400 Bad Request")
          return
        }
        self.respond(connection, text: "You can return to Minnow.", status: "200 OK")
        if case .code(let code) = result {
          self.finish(.success(code))
        } else {
          self.finish(
            .failure(SpotifyAccountError.message("Spotify sign-in was cancelled or denied")))
        }
      }
    }
  }

  private func respond(_ connection: NWConnection, text: String, status: String) {
    let body = Data(text.utf8)
    let header =
      "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    connection.send(
      content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
  }

  private func finish(_ result: Result<String, Error>) {
    guard let completion else { return }
    self.completion = nil
    timeout?.cancel()
    timeout = nil
    listener?.cancel()
    listener = nil
    completion.resume(with: result)
  }
}

@MainActor
final class SpotifyAccount: ObservableObject {
  static let shared = SpotifyAccount()
  @Published private(set) var isConnected = false
  @Published private(set) var isConnecting = false
  @Published private(set) var status = "Connect Spotify to use Liked Songs and repeat-one"
  private let callback = SpotifyCallbackServer()
  private var tokens: Tokens?
  private var connectTask: Task<Void, Never>?
  private var refreshTask: Task<Tokens, Error>?
  private var generation = 0
  private let service = "com.minnow.spotify.oauth"
  private let requiredScopes =
    "user-library-read user-library-modify user-read-playback-state user-modify-playback-state"
  private var clientID: String { UserDefaults.standard.string(forKey: "spotifyClientID") ?? "" }

  private struct Tokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let clientID: String
  }

  private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double
  }

  private init() {
    // Even a noninteractive legacy Keychain read can wait on securityd. Never run it on the UI thread.
    let service = service
    let version = generation
    Task { @MainActor [weak self] in
      let result = await Task.detached {
        Self.readStoredTokens(service: service, allowInteraction: false)
      }.value
      guard let self, self.generation == version, !self.isConnecting, self.tokens == nil else { return }
      _ = self.applyStoredTokens(result)
    }
  }

  nonisolated private static func readStoredTokens(service: String, allowInteraction: Bool)
    -> (OSStatus, Data?)
  {
    var item: CFTypeRef?
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "tokens",
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if !allowInteraction {
      let context = LAContext()
      context.interactionNotAllowed = true
      query[kSecUseAuthenticationContext as String] = context
    }
    let result = SecItemCopyMatching(query as CFDictionary, &item)
    return (result, item as? Data)
  }

  @discardableResult private func applyStoredTokens(_ result: (OSStatus, Data?)) -> Bool {
    if result.0 == errSecSuccess,
      let data = result.1, let stored = try? JSONDecoder().decode(Tokens.self, from: data),
      stored.clientID == clientID
    {
      tokens = stored
      isConnected = true
      status = "Spotify connected"
      return true
    }
    if result.0 == errSecInteractionNotAllowed {
      status = "Spotify login needs Keychain access — click Connect Spotify"
    }
    return false
  }

  func showConnectionPrompt() {
    guard !isConnecting else { return }
    if !isConnected,
      applyStoredTokens(Self.readStoredTokens(service: service, allowInteraction: true)) { return }
    let alert = NSAlert()
    alert.messageText = "Connect Spotify"
    alert.informativeText =
      "Create a Web API app in Spotify's Developer Dashboard and register this exact Redirect URI:\n\n\(SpotifyCallbackServer.redirectURI)\n\nPaste its public Client ID below. A client secret is not needed. Spotify Development Mode currently requires the app owner to have Premium."
    let field = NSTextField(string: clientID)
    field.placeholderString = "Spotify Client ID"
    field.frame = CGRect(x: 0, y: 0, width: 340, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "Connect")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let id = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard id.count == 32, id.allSatisfy({ $0.isHexDigit }) else {
      status = "Enter the 32-character public Client ID from Spotify's Developer Dashboard"
      showError(status)
      return
    }
    disconnect()
    UserDefaults.standard.set(id, forKey: "spotifyClientID")
    isConnecting = true
    status = "Waiting for Spotify sign-in"
    let version = generation
    connectTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        if version == self.generation {
          self.isConnecting = false
          self.connectTask = nil
        }
      }
      do {
        let verifier = try Self.randomURLString()
        let state = try Self.randomURLString()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = [
          URLQueryItem(name: "client_id", value: id),
          URLQueryItem(name: "response_type", value: "code"),
          URLQueryItem(name: "redirect_uri", value: SpotifyCallbackServer.redirectURI),
          URLQueryItem(name: "scope", value: self.requiredScopes),
          URLQueryItem(name: "state", value: state),
          URLQueryItem(name: "code_challenge_method", value: "S256"),
          URLQueryItem(name: "code_challenge", value: challenge),
        ]
        let code = try await self.callback.receiveCode(state: state, authorizationURL: url.url!)
        try Task.checkCancellation()
        let response = try await self.exchange([
          "grant_type": "authorization_code", "client_id": id,
          "code": code, "code_verifier": verifier,
          "redirect_uri": SpotifyCallbackServer.redirectURI,
        ])
        guard version == self.generation, let refresh = response.refresh_token else { return }
        let tokens = Tokens(
          accessToken: response.access_token, refreshToken: refresh,
          expiresAt: Date().addingTimeInterval(response.expires_in), clientID: id)
        try self.persist(tokens)
        self.tokens = tokens
        self.isConnected = true
        self.status = "Spotify connected"
      } catch {
        guard version == self.generation else { return }
        self.status = error.localizedDescription
        self.showError(self.status)
      }
    }
  }

  func disconnect() {
    generation += 1
    callback.cancel()
    connectTask?.cancel()
    connectTask = nil
    refreshTask?.cancel()
    refreshTask = nil
    tokens = nil
    isConnected = false
    isConnecting = false
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "tokens",
    ]
    SecItemDelete(query as CFDictionary)
    status = "Spotify disconnected"
  }

  func contains(_ uri: String) async throws -> Bool {
    let data = try await request(
      path: "me/library/contains", method: "GET",
      items: [URLQueryItem(name: "uris", value: uri)])
    let values = try JSONDecoder().decode([Bool].self, from: data)
    guard let saved = values.first else {
      throw SpotifyAccountError.message("Spotify did not return a saved-song state")
    }
    return saved
  }

  func setSaved(_ saved: Bool, uri: String) async throws {
    _ = try await request(
      path: "me/library", method: saved ? "PUT" : "DELETE",
      items: [URLQueryItem(name: "uris", value: uri)])
  }

  func playbackDetails() async throws -> SpotifyPlaybackDetails {
    let data = try await request(path: "me/player", method: "GET")
    if data.isEmpty { return SpotifyPlaybackDetails(repeatMode: nil, item: nil) }
    return try JSONDecoder().decode(SpotifyPlaybackDetails.self, from: data)
  }

  func setRepeatOne(_ enabled: Bool) async throws {
    _ = try await request(
      path: "me/player/repeat", method: "PUT",
      items: [URLQueryItem(name: "state", value: enabled ? "track" : "off")])
  }

  private func request(path: String, method: String, items: [URLQueryItem] = []) async throws
    -> Data
  {
    let version = generation
    for attempt in 0..<2 {
      let token = try await accessToken(forceRefresh: attempt > 0)
      guard version == generation else { throw CancellationError() }
      var url = URLComponents(string: "https://api.spotify.com/v1/" + path)!
      if !items.isEmpty { url.queryItems = items }
      var request = URLRequest(url: url.url!)
      request.httpMethod = method
      request.timeoutInterval = 15
      request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
      let (data, response) = try await URLSession.shared.data(for: request)
      try Task.checkCancellation()
      guard version == generation else { throw CancellationError() }
      let http = response as? HTTPURLResponse
      let code = http?.statusCode ?? 0
      if code == 401 && attempt == 0 { continue }
      if code == 429 {
        throw SpotifyAccountError.message("Spotify is limiting requests. Try again shortly.")
      }
      guard (200..<300).contains(code) else {
        throw SpotifyAccountError.message(
          "Spotify request failed (\(code)). Check account permissions and Premium access.")
      }
      return data
    }
    throw SpotifyAccountError.message("Reconnect Spotify to continue")
  }

  private func accessToken(forceRefresh: Bool) async throws -> String {
    guard let stored = tokens else { throw SpotifyAccountError.message("Connect Spotify first") }
    if !forceRefresh, stored.expiresAt.timeIntervalSinceNow > 60 { return stored.accessToken }
    if let refreshTask { return try await refreshTask.value.accessToken }
    let version = generation
    let task = Task { @MainActor in
      let response = try await self.exchange([
        "grant_type": "refresh_token",
        "refresh_token": stored.refreshToken, "client_id": stored.clientID,
      ])
      try Task.checkCancellation()
      return Tokens(
        accessToken: response.access_token,
        refreshToken: response.refresh_token ?? stored.refreshToken,
        expiresAt: Date().addingTimeInterval(response.expires_in), clientID: stored.clientID)
    }
    refreshTask = task
    defer { if version == generation { refreshTask = nil } }
    let updated = try await task.value
    guard version == generation else { throw CancellationError() }
    try persist(updated)
    tokens = updated
    return updated.accessToken
  }

  private func exchange(_ fields: [String: String]) async throws -> TokenResponse {
    var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    request.httpBody = Data(
      fields.map { key, value in
        key.addingPercentEncoding(withAllowedCharacters: allowed)! + "="
          + value.addingPercentEncoding(withAllowedCharacters: allowed)!
      }.joined(separator: "&").utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw SpotifyAccountError.message(
        "Spotify authorization failed. Check the Client ID and registered Redirect URI, then connect again."
      )
    }
    return try JSONDecoder().decode(TokenResponse.self, from: data)
  }

  private func persist(_ value: Tokens) throws {
    let data = try JSONEncoder().encode(value)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "tokens",
    ]
    let changes = [kSecValueData as String: data]
    var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
    if status == errSecItemNotFound {
      var create = query
      create[kSecValueData as String] = data
      create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(create as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw SpotifyAccountError.message(
        "Could not save Spotify sign-in securely in Keychain (\(status))")
    }
  }

  private static func randomURLString() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw SpotifyAccountError.message("Could not prepare secure Spotify sign-in")
    }
    return base64URL(Data(bytes))
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Spotify Connection"
    alert.informativeText = message
    alert.runModal()
  }
}
