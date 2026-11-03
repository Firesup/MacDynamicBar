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

// MARK: - Track Scrubbing

struct SeekTarget: Equatable {
    let source: MusicSource
    let trackID: String
}

struct DesktopSeek {
    let position: TimeInterval
    let script: String

    static func make(source: MusicSource, trackID: String,
                     position: TimeInterval, duration: TimeInterval) -> DesktopSeek? {
        guard position.isFinite, duration.isFinite, duration > 0,
              !trackID.isEmpty, trackID.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        // Avoid accidentally advancing to the next song at the right edge.
        let bounded = min(max(0, position), max(0, duration - 0.05))
        let number = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), bounded)
        let escapedID = trackID.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let identity = source == .appleMusic ? "persistent ID" : "id"
        let script = """
        with timeout of 2 seconds
            if application id "\(source.bundleIdentifier)" is not running then return false
            tell application id "\(source.bundleIdentifier)"
                if player state is stopped then return false
                if \(identity) of current track is not "\(escapedID)" then return false
                set player position to \(number)
                return true
            end tell
        end timeout
        """
        return DesktopSeek(position: bounded, script: script)
    }
}

@MainActor
final class ScrubSession: ObservableObject {
    @Published var draft: Double?
    var target: SeekTarget?
    @Published var editing = false
    var cancelled = false
}

struct PlaybackScrubber: View {
    @Environment(\.islandTextContrast) private var textContrast
    @ObservedObject var player: MediaPlayer
    let isExpanded: Bool
    var onEditingChange: (Bool) -> Void = { _ in }
    @StateObject private var session = ScrubSession()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1,
            paused: !player.isPlaying || session.editing || !isExpanded)) { context in
            let maximum = player.duration.isFinite ? max(1, player.duration) : 1
            let live = min(maximum, max(0, player.playbackPosition(at: context.date)))
            let displayed = session.draft ?? live
            HStack(spacing: 10) {
                Text(timeLabel(displayed)).frame(width: 34, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white)
                            .frame(width: geometry.size.width * CGFloat(
                                min(1, max(0, displayed / maximum))))
                    }
                    .frame(height: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.seekTarget != nil else { return }
                            begin(at: live)
                            updateDraft(location: value.location.x,
                                        width: geometry.size.width, duration: maximum)
                        }
                        .onEnded { value in
                            guard session.editing, !session.cancelled else {
                                reset(); return
                            }
                            updateDraft(location: value.location.x,
                                        width: geometry.size.width, duration: maximum)
                            finish()
                        })
                }
                    .frame(height: 16)
                    .allowsHitTesting(player.seekTarget != nil)
                    .opacity(player.seekTarget == nil ? 0.35 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(timeLabel(displayed)) of \(timeLabel(player.duration))")
                    .accessibilityAdjustableAction { direction in
                        guard let target = player.seekTarget else { return }
                        let delta: Double = direction == .increment ? 5 : -5
                        player.seek(to: player.playbackPosition(at: .now) + delta,
                                    expected: target)
                    }
                Text("-" + timeLabel(max(0, player.duration - displayed)))
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit().foregroundStyle(textContrast.secondary).frame(height: 16)
            .shadow(color: .black.opacity(textContrast.shadowOpacity), radius: 1, y: 1)
        }
        .onChange(of: player.seekTarget) { _, _ in
            if session.editing { session.cancelled = true; session.draft = nil; session.target = nil }
        }
        .onChange(of: isExpanded) { _, expanded in if !expanded { reset() } }
        .onDisappear { reset() }
    }

    private func begin(at position: Double) {
        guard !session.editing else { return }
        session.editing = true
        onEditingChange(true)
        session.cancelled = false
        session.target = player.seekTarget
        session.draft = position
    }

    private func updateDraft(location: CGFloat, width: CGFloat, duration: Double) {
        guard !session.cancelled else { return }
        session.draft = Double(min(1, max(0, location / max(1, width)))) * duration
    }

    private func finish() {
        defer { reset() }
        guard !session.cancelled, let target = session.target, let draft = session.draft else { return }
        player.seek(to: draft, expected: target)
    }

    private func reset() {
        let wasEditing = session.editing
        session.editing = false; session.cancelled = false
        session.draft = nil; session.target = nil
        if wasEditing { onEditingChange(false) }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return "\(value / 60):" + String(format: "%02d", value % 60)
    }
}

