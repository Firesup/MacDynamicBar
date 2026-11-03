import Combine

/// Temporary UI fixture. Replace with a real playback adapter at the next milestone.
/// Nothing in this type sends commands to Apple Music or Spotify.
@MainActor
final class PreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var trackIndex = 0

    private let tracks = ["A little room to listen", "Somewhere by the water", "One more moment"]
    var title: String { tracks[trackIndex] }
    var subtitle: String { "Minnow · Preview player" }

    func togglePlayback() { isPlaying.toggle() }
    func next() { trackIndex = (trackIndex + 1) % tracks.count }
    func previous() { trackIndex = (trackIndex + tracks.count - 1) % tracks.count }
}
