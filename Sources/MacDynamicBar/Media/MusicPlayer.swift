import AppKit
import CoreMedia
import CoreAudio
import CryptoKit
import Network
import Security
import ServiceManagement
import ScreenCaptureKit
import Combine
import QuartzCore
import SwiftUI

// MARK: - Shared Media Sources

enum MusicSource: String, CaseIterable, Sendable {
    case appleMusic, spotify

    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
    var bundleIdentifier: String {
        self == .spotify ? "com.spotify.client" : "com.apple.Music"
    }
}

struct AudioCaptureTarget: Equatable, Sendable {
    var source: MusicSource?
    var isPlaying = false
}

/// Pure selection logic: a new playback start wins. Pausing falls back to
/// another playing source; an inactive player retains the last selection.
struct MediaSourceSelection {
    private(set) var active: MusicSource?
    private var playing: Set<MusicSource> = []
    private var knownTracks: Set<MusicSource> = []
    private var starts: [MusicSource: Int] = [:]
    private var sequence = 0

    mutating func update(_ source: MusicSource, playing nowPlaying: Bool,
                         hasTrack: Bool) {
        if hasTrack { knownTracks.insert(source) }
        else { knownTracks.remove(source) }
        if nowPlaying && hasTrack {
            if playing.insert(source).inserted {
                sequence += 1
                starts[source] = sequence
            }
        } else {
            playing.remove(source)
        }
        if let latest = playing.max(by: { starts[$0, default: 0] < starts[$1, default: 0] }) {
            active = latest
        } else if active == nil || !knownTracks.contains(active!) {
            active = MusicSource.allCases.first { knownTracks.contains($0) }
        }
    }
}

@MainActor
protocol DesktopPlayback: AnyObject {
    var track: MusicTrack? { get }
    var isPlaying: Bool { get }
    var artwork: NSImage? { get }
    var duration: TimeInterval { get }
    var title: String { get }
    var subtitle: String { get }
    var canControlPlayback: Bool { get }
    var lastError: String? { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    func togglePlayback()
    func next()
    func previous()
    func playbackPosition(at date: Date) -> TimeInterval
    func seek(to position: TimeInterval, expectedTrackID: String)
}

extension AppleMusicPlayer: DesktopPlayback {}

@MainActor
final class MediaPlayer: ObservableObject {
    @Published private(set) var track: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var title = "No audio found"
    @Published private(set) var subtitle = "Play a song in Music or Spotify"
    @Published private(set) var canControlPlayback = false
    @Published private(set) var captureTarget = AudioCaptureTarget()
    @Published private(set) var artworkAccent: Color = .pink

    private let appleMusic: any DesktopPlayback
    private let spotify: any DesktopPlayback
    private var selection = MediaSourceSelection()
    private var sourcePreference: SourcePreference = .auto
    private var started = false

    init(appleMusic: any DesktopPlayback = AppleMusicPlayer(),
         spotify: any DesktopPlayback = SpotifyPlayer()) {
        self.appleMusic = appleMusic
        self.spotify = spotify
        appleMusic.onChange = { [weak self] in self?.synchronize(.appleMusic) }
        spotify.onChange = { [weak self] in self?.synchronize(.spotify) }
    }

    func start() {
        guard !started else { return }
        started = true
        appleMusic.start()
        spotify.start()
    }

    func stop() {
        started = false
        appleMusic.stop()
        spotify.stop()
        captureTarget = AudioCaptureTarget()
    }

    func refresh() { appleMusic.refresh(); spotify.refresh() }
    func togglePlayback() { current?.togglePlayback() }
    func next() { current?.next() }
    func previous() { current?.previous() }
    func playbackPosition(at date: Date) -> TimeInterval {
        current?.playbackPosition(at: date) ?? 0
    }

    var seekTarget: SeekTarget? {
        guard canControlPlayback, duration.isFinite, duration > 0,
              let source = captureTarget.source, let id = track?.id, !id.isEmpty else { return nil }
        return SeekTarget(source: source, trackID: id)
    }

    func seek(to position: TimeInterval, expected target: SeekTarget) {
        guard seekTarget == target else { return }
        current?.seek(to: position, expectedTrackID: target.trackID)
    }

    func setSourcePreference(_ preference: SourcePreference) {
        guard sourcePreference != preference else { return }
        sourcePreference = preference
        if started { synchronize(.appleMusic) }
    }

    private var selectedSource: MusicSource? { sourcePreference.source ?? selection.active }
    private var current: (any DesktopPlayback)? {
        guard let source = selectedSource else { return nil }
        return source == .appleMusic ? appleMusic : spotify
    }

    private func synchronize(_ changedSource: MusicSource) {
        guard started else { return }
        let changed = changedSource == .appleMusic ? appleMusic : spotify
        selection.update(changedSource, playing: changed.isPlaying,
                         hasTrack: changed.track != nil)
        guard let selected = current, let source = selectedSource else {
            subtitle = spotify.lastError ?? appleMusic.lastError ?? "Play a song in Music or Spotify"
            return
        }
        track = selected.track
        if artwork !== selected.artwork {
            artworkAccent = ArtworkPalette.color(from: selected.artwork)
        }
        artwork = selected.artwork
        duration = selected.duration
        title = selected.title
        subtitle = selected.subtitle + " · " + source.displayName
        isPlaying = selected.isPlaying
        canControlPlayback = selected.canControlPlayback
        // One publication carries source and state together. Switching between
        // two playing apps must restart audio capture even if isPlaying stays true.
        captureTarget = AudioCaptureTarget(source: source,
                                           isPlaying: selected.isPlaying && selected.canControlPlayback)
    }
}

