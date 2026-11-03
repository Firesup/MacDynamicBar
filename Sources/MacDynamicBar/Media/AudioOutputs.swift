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

// MARK: - System Audio Outputs

struct AudioOutputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let symbol: String
    let nativeIcon: NSImage?
}

@MainActor
final class AudioOutputs: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var selectedID: AudioDeviceID = 0
    @Published private(set) var error: String?
    private var started = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress,
                             AudioObjectPropertyListenerBlock)] = []
    private let system = AudioObjectID(kAudioObjectSystemObject)
    var current: AudioOutputDevice? { devices.first { $0.id == selectedID } }

    func start() { guard !started else { return }; started = true; reload() }
    func stop() { started = false; removeListeners() }

    func reload() {
        removeListeners()
        selectedID = integer(system, kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            devices = []; error = "Could not read audio outputs"; return
        }
        guard size > 0 else {
            devices = []
            if started {
                observe(system, kAudioHardwarePropertyDevices)
                observe(system, kAudioHardwarePropertyDefaultOutputDevice)
            }
            return
        }
        var ids = [AudioDeviceID](repeating: 0,
                                 count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { error = "Could not read audio outputs (\(status))"; return }
        devices = ids.filter { id in
            outputChannels(id) > 0 && integer(id, kAudioDevicePropertyDeviceIsAlive) != 0
                && integer(id, kAudioDevicePropertyIsHidden) != 1
                && integer(id, kAudioDevicePropertyDeviceCanBeDefaultDevice,
                           scope: kAudioDevicePropertyScopeOutput) != 0
        }.map { id in
            let name = string(id, kAudioObjectPropertyName) ?? "Audio output"
            let model = string(id, kAudioDevicePropertyModelUID) ?? ""
            let transport = integer(id, kAudioDevicePropertyTransportType) ?? 0
            return AudioOutputDevice(id: id, name: name,
                symbol: Self.symbol(name: name, model: model, transport: transport),
                nativeIcon: icon(id))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if started {
            observe(system, kAudioHardwarePropertyDevices)
            observe(system, kAudioHardwarePropertyDefaultOutputDevice)
            for id in ids {
                observe(id, kAudioObjectPropertyName)
                observe(id, kAudioDevicePropertyDeviceIsAlive)
                observe(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
                observe(id, kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
            }
        }
    }

    func select(_ device: AudioOutputDevice) {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(system, &address, &settable) == noErr,
              settable.boolValue else { error = "The system output cannot be changed"; return }
        var id = device.id
        let status = AudioObjectSetPropertyData(system, &address, 0, nil,
                                               UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard status == noErr else { error = "Could not select \(device.name) (\(status))"; return }
        error = nil
        reload()
    }

    static func symbol(name: String, model: String, transport: UInt32) -> String {
        let identity = (model + " " + name).lowercased().replacingOccurrences(of: " ", with: "")
        if identity.contains("airpodsmax") { return "airpodsmax" }
        if identity.contains("airpodspro") { return "airpodspro" }
        if identity.contains("airpods") { return "airpods" }
        if identity.contains("headphone") || identity.contains("headset") { return "headphones" }
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return "wave.3.right" // Unknown Bluetooth model: use a neutral audio-route icon.
        }
        if transport == kAudioDeviceTransportTypeAirPlay { return "airplay.audio" }
        if transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort {
            return "display"
        }
        return "speaker.wave.2"
    }

    private func property(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func integer(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = property(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func icon(_ id: AudioObjectID) -> NSImage? {
        var address = property(kAudioDevicePropertyIcon)
        var value: Unmanaged<CFURL>?
        var size = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let url = value?.takeRetainedValue() else { return nil }
        return NSImage(contentsOf: url as URL)
    }

    private func outputChannels(_ id: AudioDeviceID) -> Int {
        var address = property(kAudioDevicePropertyStreamConfiguration,
                               scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                           alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory) == noErr else { return 0 }
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func observe(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = property(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.started else { return }
                self.reload()
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func removeListeners() {
        for (object, original, block) in listeners {
            var address = original
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
    }
}

struct AudioOutputIcon: View {
    let device: AudioOutputDevice?
    var body: some View {
        Group {
            if let device, let icon = device.nativeIcon,
               !device.symbol.hasPrefix("airpods") {
                Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: device?.symbol ?? "speaker.wave.2")
                    .resizable().scaledToFit()
            }
        }.foregroundStyle(.white).frame(width: 20, height: 20)
    }
}

struct AudioOutputList: View {
    @ObservedObject var outputs: AudioOutputs
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound Output").font(.headline)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(outputs.devices) { device in
                        Button {
                            outputs.select(device)
                            if outputs.error == nil { close() }
                        } label: {
                            HStack(spacing: 10) {
                                AudioOutputIcon(device: device)
                                Text(device.name).lineLimit(1)
                                Spacer()
                                if device.id == outputs.selectedID { Image(systemName: "checkmark") }
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 220)
            if outputs.devices.isEmpty { Text("No connected outputs found").foregroundStyle(.secondary) }
            if let error = outputs.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(14).frame(width: 280).onAppear { outputs.reload() }
    }
}

