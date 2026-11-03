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

// MARK: - Shared Playback Session

@MainActor
final class IslandMediaSession {
    let player = MediaPlayer()
    let audio = MusicAudioLevels()
    let outputs = AudioOutputs()
    let accessories: PlayerAccessories
    private var subscriptions = Set<AnyCancellable>()

    init() {
        accessories = PlayerAccessories(player: player)
        audio.setSuspended(true)
        player.$captureTarget.removeDuplicates().sink { [weak self] target in
            self?.audio.setPlayback(target)
        }.store(in: &subscriptions)
    }

    func start() { outputs.start(); player.start() }
    func apply(_ settings: MinnowSettings) {
        player.setSourcePreference(settings.source)
        if audio.isEnabled != settings.audioReactive { audio.setEnabled(settings.audioReactive) }
    }
    func stop() {
        accessories.stop(); outputs.stop(); player.stop(); audio.stop()
        subscriptions.removeAll()
    }
}

