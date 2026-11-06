import AppKit
import Combine
import ServiceManagement
import SwiftUI

// MARK: - Native Settings Window

enum SettingsPage: String, CaseIterable, Identifiable {
  case general, playback, today, shelf, appearance, events, musicScene
  var id: String { rawValue }
  var title: String {
    switch self {
    case .shelf: "Shelf"
    case .today: "Today"
    case .general: "General"
    case .playback: "Media"
    case .appearance: "Appearance"
    case .events: "Events"
    case .musicScene: "Lock Screen"
    }
  }
  var symbol: String {
    switch self {
    case .shelf: "tray"
    case .today: "calendar"
    case .general: "gearshape"
    case .playback: "play.fill"
    case .appearance: "paintpalette"
    case .events: "bell.badge"
    case .musicScene: "moon.stars"
    }
  }
  var keywords: String {
    switch self {
    case .shelf: "files drag drop thumbnails bookmark airdrop share tray"
    case .today: "calendar reminders lists connect permissions agenda overdue undated"
    case .musicScene: "lockscreen scene lyrics artwork clock widgets weather preview"
    case .events: "popups airpods headphones connection battery charging power preview alerts"
    case .general: "launch login startup display visibility fullscreen menu hover haptic reset"
    case .playback:
      "music spotify source heart shuffle repeat artwork explicit waveform pause hide scrub eq"
    case .appearance:
      "glass blur opacity sizing notch width height motion gradient pill shape layout tint text contrast"
    }
  }
}

@MainActor
final class SettingsNavigation: ObservableObject {
  @Published var selected: SettingsPage? = .general
}

@MainActor
final class MinnowSettingsWindow: NSWindowController {
  init(settings: MinnowSettings, coordinator: IslandCoordinator) {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 860, height: 730),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Minnow Settings"
    window.minSize = CGSize(width: 740, height: 520)
    window.isReleasedWhenClosed = false
    window.toolbarStyle = .unified
    window.titlebarAppearsTransparent = true
    window.backgroundColor = NSColor.windowBackgroundColor
    window.setFrameAutosaveName("MinnowSettingsWindow")
    window.contentView = NSHostingView(
      rootView: MinnowSettingsView(settings: settings, coordinator: coordinator))
    if !window.setFrameUsingName("MinnowSettingsWindow") { window.center() }
    super.init(window: window)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  func open() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

struct MinnowSettingsView: View {
  @ObservedObject var settings: MinnowSettings
  let coordinator: IslandCoordinator
  @StateObject private var navigation = SettingsNavigation()
  @StateObject private var login = LoginItemSettings()
  @StateObject private var displays = DisplaySettings()
  @ObservedObject private var spotify = SpotifyAccount.shared
  @State private var search = ""
  @State private var confirmReset = false

  private var pages: [SettingsPage] {
    SettingsPage.allCases.filter {
      search.isEmpty || ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(search)
    }
  }
  private var page: SettingsPage { navigation.selected ?? .general }

  var body: some View {
    NavigationSplitView {
      VStack(spacing: 18) {
        HStack(spacing: 10) {
          Image(systemName: "fish.fill").font(.title2).foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
          VStack(alignment: .leading, spacing: 2) {
            Text("Minnow").font(.headline)
            Text("Make it yours").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
        }.padding(.top, 20)
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Search settings", text: $search).textFieldStyle(.plain)
            .accessibilityLabel("Search settings")
          if !search.isEmpty {
            Button {
              search = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
            }.buttonStyle(.plain)
          }
        }.padding(10).background(.white.opacity(0.06), in: Capsule())
        List(selection: $navigation.selected) {
          ForEach(pages) { item in
            HStack(spacing: 12) {
              Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.10)))
              Text(item.title).font(.system(size: 14, weight: .semibold))
            }.padding(.vertical, 5).tag(item)
          }
        }.listStyle(.sidebar).scrollContentBackground(.hidden)
        Spacer(minLength: 0)
        Text("Minnow V1").font(.caption).foregroundStyle(.tertiary).padding(.bottom, 16)
      }.padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 250)
    } detail: {
      VStack(alignment: .leading, spacing: 0) {
        Label(page.title, systemImage: page.symbol)
          .font(.system(size: 27, weight: .bold)).padding(.horizontal, 30).padding(.vertical, 24)
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            if pages.isEmpty {
              ContentUnavailableView.search(text: search)
            } else {
              switch page {
              case .general: general
              case .playback: playback
              case .appearance: appearance
              case .shelf: ShelfSettingsView(settings: settings, shelf: coordinator.shelf)
              case .today: TodaySettingsView(settings: settings, today: coordinator.widgets.today)
              case .events: events
              case .musicScene: musicSceneSettings
              }
            }
          }.padding(.horizontal, 28).padding(.bottom, 28)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
      }.frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
    }
    .preferredColorScheme(.dark)
    .tint(.blue)
    .toggleStyle(.switch)
    .controlSize(.small)
    .onAppear {
      login.refresh()
      displays.refresh()
    }
    .onChange(of: search) { _, _ in
      if !pages.contains(page) { navigation.selected = pages.first }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in login.refresh() }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
    ) { _ in displays.refresh() }
    .confirmationDialog("Reset Minnow preferences?", isPresented: $confirmReset) {
      Button("Reset Settings", role: .destructive) { settings.resetPreferences() }
    } message: {
      Text(
        "Restores appearance and player preferences. Your Spotify connection and macOS login-item registration are kept."
      )
    }
  }

  private var general: some View {
    Group {
      VStack(spacing: 10) {
        Image(systemName: "fish.fill").font(.system(size: 36, weight: .medium))
          .frame(width: 78, height: 78).background(.white.opacity(0.07), in: Circle())
        Text("A little space for your music.").font(.title3.bold())
        Text("Personalize the island, your displays, and everyday interactions.")
          .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      }.frame(maxWidth: .infinity).padding(.vertical, 10)
      SettingsCard {
        Toggle("Launch at Login", isOn: Binding(get: { login.enabled }, set: login.setEnabled))
          .disabled(!login.isBundled)
        Divider()
        Toggle("Open Settings on Launch", isOn: $settings.openSettingsOnLaunch)
        if login.requiresApproval {
          Button("Allow in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
        }
        if let error = login.error { note(error, color: .orange) }
        if !login.isBundled { note("Launch the bundled Minnow.app to enable launch at login.") }
      }
      SettingsGroup("Display", caption: "Choose which screens show the island.") {
        Picker(selection: displaySelection) {
          Text("Automatic · Built-in Preferred").tag("automatic")
          Text("All Displays").tag("all")
          Text("Main Display").tag("main")
          ForEach(displays.displays) { display in Text(display.name).tag(display.id) }
          if settings.display != "automatic", settings.display != "main",
            !displays.displays.contains(where: { $0.id == settings.display })
          {
            Text("Disconnected · Automatic Fallback").tag(settings.display)
          }
        } label: {
          Label("Display", systemImage: "display")
        }
        Divider()
        Button("Reposition Island") { coordinator.reposition() }
      }
      SettingsGroup(
        "Visibility",
        caption: "Reopen Minnow from Finder to reach Settings if you hide its menu bar icon."
      ) {
        Toggle("Enable Island", isOn: $settings.islandEnabled)
        Divider()
        Toggle("Hide in Fullscreen", isOn: $settings.hideFullscreen)
        Divider()
        Toggle("Menu Bar Icon", isOn: $settings.showMenuBar)
        Divider()
        Toggle("Hide from Screen Capture", isOn: .constant(false)).disabled(true)
        note(
          "Unavailable: macOS no longer provides reliable window exclusion for modern screen recorders."
        )
      }
      SettingsGroup("Behaviour") {
        Toggle("Haptic Touch", isOn: $settings.haptics)
        Divider()
        Toggle("Slight Hover Expansion", isOn: $settings.slightHover).disabled(
          settings.expandOnHover)
        Divider()
        Toggle("Expand on Hover", isOn: $settings.expandOnHover)
        note(
          "Slight expansion is on by default. Expand on Hover opens the full player instead and takes priority."
        )
        note("Click to pin the player open. Haptics require supported hardware.")
      }
      SettingsCard {
        Button("Reset All Settings", role: .destructive) { confirmReset = true }
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var musicSceneSettings: some View {
    SettingsGroup(
      "Lock Screen Player",
      caption:
        "Experimental player over the real macOS lockscreen. Native date/time and authentication remain handled by macOS. Enable, then lock your Mac to test."
    ) {
      Toggle("Lock Screen Player (Experimental)", isOn: $settings.lockScreenPlayer)
      LockScreenStatusView(controller: coordinator.lockScreen)
      Toggle("Online Lyrics · LRCLIB", isOn: $settings.onlineLyrics)
      note(
        "Online lyrics sends the current track title, artist, album and duration to lrclib.net. The lockscreen panel does not replace authentication. Turn it off here to disable it."
      )
      LockWidgetSettings(widgets: coordinator.widgets, settings: settings)
      Button("Open Music Scene Preview…") { coordinator.openMusicScene() }
      note(
        "Glass player, expandable album cover, shared playback controls, local synced LRC lyrics, clock and battery widgets."
      )
      Divider()
      note(
        "Weather requires a configured provider. Focus and AirPods battery widgets require verified data sources. No sample readings are presented as live data."
      )
      note(
        "Spotify provides no public lyrics endpoint. Import an LRC file for the current track from the scene toolbar. Lyrics clear when the track changes."
      )
      note(
        "This window never requests a password or imitates Touch ID. Use the standard macOS Lock Screen to secure your Mac."
      )
    }
  }

  private var events: some View {
    VStack(spacing: 20) {
      SettingsGroup(
        "AirPods",
        caption:
          "Apple-style connection popups for recognized AirPods, AirPods Pro, and AirPods Max. Bluetooth access may be requested by macOS."
      ) {
        Toggle("AirPods Connections", isOn: $settings.airPodsPopups)
        AirPodsMonitorStatus(monitor: coordinator.airPods)
        AirPodsConnectionsView(outputs: coordinator.session.outputs)
        note(
          "Shows connections to this Mac. Connecting does not necessarily select the device as audio output."
        )
        note(
          "Live earbud and case battery reporting needs hardware validation. Connection popups do not invent battery values."
        )
        Divider()
        Button("Preview AirPods Connection") { coordinator.preview(.airPods) }
      }
      SettingsGroup("System Feedback") {
        note(
          "Charging and low-battery alerts stay with macOS. Battery percentage is not a persistent island activity."
        )
        note(
          "Volume changes appear in the island on outputs that expose Core Audio volume. Native macOS HUDs are not suppressed. Brightness key feedback is available experimentally on supported built-in displays. Native HUD suppression is not enabled."
        )
        Toggle("Brightness Key HUD (Experimental)", isOn: $settings.brightnessHUD)
        Button("Preview Volume HUD") { coordinator.preview(.hud) }
      }
      SettingsGroup("Phone Calls (Experimental)") {
        PhoneCallProbeView()
        Button("Preview Incoming Call") { coordinator.preview(.phoneCall) }
      }
      SettingsGroup("Live Activities") {
        Toggle("Show Activities", isOn: $settings.showActivities)
        note(
          "Music takes the main island while playing. Battery and charging are not persistent activities. External apps’ mirrored activities are not imported."
        )
        Button("Preview Activity (30 seconds)") { coordinator.previewActivity() }
      }
      SettingsGroup("Presentation") {
        SettingsSlider(
          title: "Collapse After", value: $settings.popupDuration, range: 1...10, suffix: "s")
        Button("Preview Notification") { coordinator.preview(.notification) }

        note(
          "Popups dismiss automatically and restore the previous player. Critical battery alerts take priority. Scrubbing and the audio-output picker defer incoming events."
        )
        note(
          "Previews contain sample data. All popups and previews respect Enable Island, Hide in Fullscreen, display selection, and system Reduce Motion. Hidden events are discarded."
        )
        Button("Dismiss Current Popup") { coordinator.popups.dismiss() }
      }
    }
  }

  private var playback: some View {
    Group {
      SettingsCard { Toggle("Media Player", isOn: $settings.mediaEnabled) }
      SettingsGroup(
        "Source",
        caption:
          "Auto follows the player that most recently starts playing. Choose Music or Spotify to keep that source selected."
      ) {
        HStack(spacing: 10) {
          ForEach(SourcePreference.allCases) { source in
            SourceChoice(source: source, selected: settings.source == source) {
              settings.source = source
            }
          }
        }
      }
      SettingsGroup(
        "Left Button", caption: "The right button always opens the audio output selector."
      ) {
        HStack(spacing: 8) {
          actionChoice("heart.fill", "Like Song", action: .like)
          actionChoice("shuffle", "Shuffle", action: .shuffle)
          actionChoice("repeat", "Repeat Song", action: .replay)
          choice("nosign", title: "None", selected: !settings.showLeftButton) {
            settings.showLeftButton = false
          }
        }
      }
      SettingsGroup("Appearance") {
        Toggle("Show Album Artwork", isOn: $settings.artwork)
        Divider()
        Toggle("Animate Artwork", isOn: $settings.animateArtwork).disabled(!settings.artwork)
        note(
          "Adds gentle motion to the cover image while playing. Video album artwork is not supplied by the desktop players."
        )
        Divider()
        Toggle("Explicit Tag", isOn: $settings.explicitTag)
        Divider()
        Toggle("Explicit Color Match", isOn: $settings.explicitColor).disabled(
          !settings.explicitTag)
        note(
          "Explicit status is available for the connected Spotify account when it matches the desktop track. Music does not expose this status here."
        )
        Divider()
        Toggle("Heart Matches Song Color", isOn: $settings.heartSongColor)
      }
      SettingsGroup(
        "Waveform",
        caption:
          "Live waveform measures the selected player's audio and displays the macOS capture indicator while active."
      ) {
        Toggle("Live Waveform", isOn: $settings.audioReactive)
        Button("Retry Audio Capture") { coordinator.retryCapture() }
        AudioCaptureStatusView(audio: coordinator.session.audio)
        PlayerAccessoryDiagnostics(accessories: coordinator.session.accessories)
      }
      SettingsGroup("Behaviour") {
        Toggle("Collapse on Pause", isOn: $settings.collapseOnPause)
        if settings.collapseOnPause {
          SettingsSlider(
            title: "Collapse After", value: $settings.collapseDelay, range: 0...30, suffix: "s")
        }
        Divider()
        Picker("Hide After Pausing", selection: pauseHideSelection) {
          Text("Never").tag(-1.0)
          Text("Instant").tag(0.0)
          ForEach([3.0, 5, 10, 15, 30, 60, 120], id: \.self) { value in
            Text("\(Int(value)) seconds").tag(value)
          }
          if settings.hideOnPause, ![0.0, 3, 5, 10, 15, 30, 60, 120].contains(settings.hideDelay) {
            Text("\(Int(settings.hideDelay)) seconds").tag(settings.hideDelay)
          }
        }
        Divider()
        Toggle("Collapse After Seeking", isOn: $settings.collapseAfterScrub)
        note(
          "Playback resuming reveals an automatically hidden island. The Hide menu action keeps it hidden until you choose Show."
        )
      }
      SettingsGroup("Equalizer") {
        Toggle("EQ", isOn: .constant(false)).disabled(true)
        note(
          "Deferred: system audio processing needs a separate audio engine. Use the equalizer in your music app for now."
        )
      }
      SettingsGroup("Spotify Account") {
        LabeledContent("Connection", value: spotify.isConnected ? "Connected" : "Not Connected")
        note(spotify.status)
        HStack {
          Button(spotify.isConnecting ? "Connecting…" : "Connect Spotify…") {
            spotify.showConnectionPrompt()
          }
          .disabled(spotify.isConnecting)
          if spotify.isConnected { Button("Disconnect") { spotify.disconnect() } }
        }
        note(
          "Connect for Liked Songs, repeat-one, and explicit labels. Desktop playback and seeking work without sign-in."
        )
      }
    }
  }

  private var appearancePreviewFill: AnyShapeStyle {
    if settings.appearanceLayout == .softGradient {
      return AnyShapeStyle(
        LinearGradient(
          stops: [
            .init(color: .black, location: 0), .init(color: .black, location: 0.3),
            .init(
              color: .black.opacity(
                SoftGradientAppearance.bottomOpacity(
                  visibility: settings.gradientVisibility, expansion: 1, reduceTransparency: false)),
              location: 1),
          ], startPoint: .top, endPoint: .bottom))
    }
    return AnyShapeStyle(
      settings.appearanceLayout == .glassInset
        ? Color.black
        : (settings.glass || settings.backgroundBlur
          ? Color.white.opacity(0.09) : Color.black.opacity(settings.opacity)))
  }

  private var appearance: some View {
    Group {
      VStack(spacing: 14) {
        IslandPreviewOutline(shape: settings.islandShape)
          .fill(appearancePreviewFill)
          .overlay {
            if settings.appearanceLayout == .glassInset {
              RoundedRectangle(cornerRadius: 17)
                .fill(.ultraThinMaterial)
                .overlay(
                  RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.18), lineWidth: 0.75)
                )
                .padding(8)
            }
          }
          .overlay {
            HStack(spacing: 16) {
              Image(systemName: "music.note").font(.title2).foregroundStyle(.pink)
              VStack(alignment: .leading, spacing: 4) {
                Text("Your music, at a glance").font(.headline)
                Text("Minnow").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "waveform").foregroundStyle(.pink)
            }.padding(22)
          }
          .frame(height: 96)
          .overlay(IslandPreviewOutline(shape: settings.islandShape).stroke(.white.opacity(0.08)))
        Text("Appearance changes apply immediately.").font(.caption).foregroundStyle(.secondary)
      }.padding(.vertical, 5)
      SettingsGroup(
        "Layout",
        caption:
          "Standard keeps your current appearance. Glass Inset places the glass player inside a solid black island."
      ) {
        Picker("Island Layout", selection: $settings.appearanceLayout) {
          ForEach(IslandAppearanceLayout.allCases) { layout in
            Text(layout.title).tag(layout)
          }
        }.pickerStyle(.segmented)
        Divider()
        Picker("Island Shape", selection: $settings.islandShape) {
          ForEach(IslandShape.allCases) { shape in Text(shape.title).tag(shape) }
        }.pickerStyle(.segmented)
        note(
          "Apple Pill keeps rounded upper corners. Notch flares into the screen's top edge, matching the reference. Shape and material are independent."
        )
        if settings.appearanceLayout == .glassInset {
          note(
            "The compact island and camera header stay black. The expanded player gets an inset glass panel with a black border."
          )
        }
      }
      SettingsGroup(settings.appearanceLayout == .softGradient ? "Gradient" : "Glass") {
        if settings.appearanceLayout == .standard {
          Toggle("Liquid Glass View", isOn: $settings.glass)
          Divider()
        }
        if settings.appearanceLayout == .softGradient {
          SettingsSlider(
            title: "Background Visibility", value: $settings.gradientVisibility,
            range: 0...0.85, suffix: "%", multiplier: 100)
          HStack {
            Text("Solid")
            Spacer()
            Text("More Background")
          }.font(.caption).foregroundStyle(.secondary)
          note(
            "Black at the camera header, fading into the wallpaper or windows behind the player. Higher visibility reveals more of the background. System Reduce Transparency keeps the surface opaque."
          )
        } else {
          SettingsSlider(
            title: settings.appearanceLayout == .glassInset || settings.glass
              ? "Glass Tint" : "Background Opacity",
            value: $settings.opacity, range: 0.35...1, suffix: "%", multiplier: 100)
          HStack {
            Text("Clear")
            Spacer()
            Text("Dark")
          }.font(.caption).foregroundStyle(.secondary)
          note(
            "Native Liquid Glass on macOS 26 and later; blurred material on earlier versions. Controls remain opaque."
          )
        }
        if settings.appearanceLayout == .standard {
          Divider()
          Toggle("Background Blur", isOn: $settings.backgroundBlur).disabled(settings.glass)
          note("Glass includes its own blur. Background Blur applies when Liquid Glass is off.")
        } else if settings.appearanceLayout == .glassInset {
          note(
            "Glass Inset includes blur. Your Standard glass and blur preferences are kept when you switch layouts."
          )
        }
      }
      SettingsGroup("Sizing") {
        Toggle("Automatic Sizing", isOn: $settings.automaticSizing)
        if !settings.automaticSizing {
          Divider()
          SettingsSlider(
            title: "Compact Side Width", value: $settings.compactWing, range: 20...60, suffix: "pt")
          SettingsSlider(
            title: "Expanded Width", value: $settings.expandedWidth, range: 320...600, suffix: "pt")
          SettingsSlider(
            title: "Expanded Height", value: $settings.expandedHeight, range: 154...280,
            suffix: "pt")
        }
      }
      SettingsGroup(
        "Notch Tuning",
        caption: "Offsets from the size reported by the display. Dimensions use macOS points."
      ) {
        SettingsSlider(
          title: "Notch Width", value: $settings.notchWidthOffset, range: -40...120, suffix: "pt")
        Divider()
        SettingsSlider(
          title: "Notch Height", value: $settings.notchHeightOffset, range: -8...30, suffix: "pt")
        Button("Reset Tuning") {
          settings.notchWidthOffset = 0
          settings.notchHeightOffset = 0
        }
      }
      SettingsGroup("Motion") {
        note(
          "Minnow follows the system Reduce Motion setting for transitions, artwork motion, and waveform animation."
        )
      }
    }
  }

  private var displaySelection: Binding<String> {
    Binding(
      get: { settings.allDisplays ? "all" : settings.display },
      set: { value in
        settings.allDisplays = value == "all"
        if value != "all" { settings.display = value }
      })
  }
  private var pauseHideSelection: Binding<Double> {
    Binding(
      get: { settings.hideOnPause ? settings.hideDelay : -1 },
      set: { value in
        settings.hideOnPause = value >= 0
        if value >= 0 { settings.hideDelay = value }
      })
  }
  private func note(_ text: String, color: Color = .secondary) -> some View {
    Text(text).font(.system(size: 11)).foregroundStyle(color).fixedSize(
      horizontal: false, vertical: true)
  }
  private func actionChoice(_ symbol: String, _ title: String, action: PlayerAction) -> some View {
    choice(symbol, title: title, selected: settings.showLeftButton && settings.leftAction == action)
    {
      settings.leftAction = action
      settings.showLeftButton = true
    }
  }
  private func choice(_ symbol: String, title: String, selected: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
        .frame(maxWidth: .infinity).frame(height: 46)
        .background(.white.opacity(selected ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: 13))
        .overlay(
          RoundedRectangle(cornerRadius: 13).stroke(
            .white.opacity(selected ? 0.4 : 0.09), lineWidth: selected ? 2 : 1))
    }.buttonStyle(.plain).help(title).accessibilityLabel(title)
      .accessibilityValue(selected ? "Selected" : "Not Selected")
  }
}

struct SettingsSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let suffix: String
  var multiplier = 1.0
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(title)
        Spacer()
        Text("\(Int((value * multiplier).rounded())) \(suffix)")
          .monospacedDigit().foregroundStyle(.secondary)
      }
      Slider(value: $value, in: range)
        .accessibilityLabel(title)
    }.padding(.vertical, 3)
  }
}

private struct AirPodsMonitorStatus: View {
  @ObservedObject var monitor: AirPodsMonitor
  var body: some View {
    Text(monitor.status).font(.caption).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct LockWidgetSettings: View {
  @ObservedObject var widgets: WidgetServices
  @ObservedObject var settings: MinnowSettings
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle("Mac Battery", isOn: $settings.lockBattery)
      Toggle("Weather", isOn: $settings.lockWeather)
      HStack {
        TextField("Latitude", text: $widgets.latitude)
        TextField("Longitude", text: $widgets.longitude)
      }
      Button("Refresh Apple Weather") { widgets.refreshWeather() }
      Text("Requires WeatherKit-enabled signing. " + widgets.weather).font(.caption)
      Toggle("Calendar on Lock Screen", isOn: $settings.lockCalendar)

      Toggle("Reminders on Lock Screen", isOn: $settings.lockReminders)
      Text("Connect and select calendars and reminder lists in Today settings. Lock screen visibility remains opt-in.").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Start 5-minute Timer") { widgets.timerEnd = .now.addingTimeInterval(300) }
        Button("Stop Timer") { widgets.timerEnd = nil }
      }
    }
  }
}
