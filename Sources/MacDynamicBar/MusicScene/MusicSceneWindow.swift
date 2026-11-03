import AppKit
import Combine
import SwiftUI

@MainActor final class MusicSceneWidgets: ObservableObject {
  @Published var battery: MacBatterySnapshot?
}

/// An unlocked-session music scene, never a replacement for loginwindow or authentication.
@MainActor final class MusicSceneWindow: NSWindowController {
  init(session: IslandMediaSession, settings: MinnowSettings, widgets: MusicSceneWidgets) {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 1100, height: 760),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
    )
    window.title = "Minnow Music Scene — Unlocked Preview"
    window.minSize = CGSize(width: 780, height: 640)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: MusicSceneView(session: session, settings: settings, widgets: widgets))
    window.center()
    super.init(window: window)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  func open() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

struct MusicSceneView: View {
  let session: IslandMediaSession
  @ObservedObject var settings: MinnowSettings
  @ObservedObject var widgets: MusicSceneWidgets
  @StateObject private var state = IslandState(hoverEnabled: false)
  @StateObject private var lyrics = LyricsStore()
  @State private var largeArtwork = false
  @State private var showLyrics = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var wallpaper: NSImage? {
    guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen)
    else { return nil }
    return NSImage(contentsOf: url)
  }
  var body: some View {
    ZStack {
      GeometryReader { geometry in
        if let wallpaper {
          Image(nsImage: wallpaper).resizable().scaledToFill().frame(
            width: geometry.size.width, height: geometry.size.height
          ).clipped()
        } else {
          LinearGradient(
            colors: [.black, Color(red: 0.12, green: 0.19, blue: 0.22)], startPoint: .top,
            endPoint: .bottom)
        }
      }.allowsHitTesting(false)
      Color.black.opacity(0.18).allowsHitTesting(false)
      VStack(spacing: 18) {
        HStack {
          Label("Music Scene · Unlocked Preview", systemImage: "rectangle.on.rectangle").font(
            .caption)
          Spacer()
          Button("Import Lyrics…") { lyrics.importFile(for: session.player.track) }
          Toggle("Lyrics", isOn: $showLyrics).toggleStyle(.button)
        }.padding(18).background(.ultraThinMaterial)
        TimelineView(.everyMinute) { context in
          VStack(spacing: 0) {
            Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
              .font(.system(size: 22, weight: .medium))
            Text(context.date, style: .time).font(
              .system(size: 96, weight: .thin, design: .rounded)
            ).monospacedDigit()
            HStack(spacing: 24) {
              Label {
                Text(context.date, format: .dateTime.month(.abbreviated).day())
              } icon: {
                Image(systemName: "calendar")
              }
              if let battery = widgets.battery {
                Label(
                  "\(battery.percentage)%",
                  systemImage: battery.charging ? "battery.100percent.bolt" : "battery.100percent")
              }
              Label("Weather not connected", systemImage: "cloud")
            }.font(.system(size: 13, weight: .semibold))
          }
        }
        Spacer(minLength: 0)
        HStack(spacing: 36) {
          if largeArtwork {
            Button {
              largeArtwork = false
            } label: {
              SceneArtwork(player: session.player).frame(
                width: showLyrics ? 260 : 300, height: showLyrics ? 260 : 300)
            }
            .buttonStyle(.plain).accessibilityLabel("Collapse album cover")
          }
          if showLyrics {
            SceneLyricsView(player: session.player, lyrics: lyrics).frame(width: 320, height: 260)
          }
        }
        ScenePlayerCard(
          session: session, settings: settings, state: state, expandedCover: $largeArtwork
        )
        .frame(width: 408, height: 176)
        Spacer(minLength: 0)
        Text("This scene does not lock your Mac. Use macOS Lock Screen to secure your session.")
          .font(.caption).padding(.bottom, 18)
      }
    }.foregroundStyle(.white).preferredColorScheme(.dark)
      .onAppear { if !state.isExpanded { state.toggle() } }
      .onReceive(session.player.$track) {
        if settings.onlineLyrics {
          lyrics.fetch(for: $0, duration: session.player.duration)
        } else {
          lyrics.trackChanged($0)
        }
      }
      .onReceive(session.player.$duration) {
        if settings.onlineLyrics { lyrics.fetch(for: session.player.track, duration: $0) }
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: largeArtwork
      )
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showLyrics)
  }
}

private struct ScenePlayerCard: View {
  let session: IslandMediaSession
  @ObservedObject var settings: MinnowSettings
  @ObservedObject var state: IslandState
  @Binding var expandedCover: Bool
  var body: some View {
    VStack(spacing: 0) {
      Button {
        expandedCover.toggle()
      } label: {
        Label(
          expandedCover ? "Collapse Artwork" : "Expand Artwork",
          systemImage: "arrow.up.left.and.arrow.down.right"
        )
        .font(.caption).frame(maxWidth: .infinity).padding(.top, 10)
      }.buttonStyle(.plain)
      MusicView(
        state: state, player: session.player, audio: session.audio,
        accessories: session.accessories, outputs: session.outputs, settings: settings,
        onArtworkPress: { expandedCover.toggle() })
    }.background { SceneGlass() }
      .clipShape(RoundedRectangle(cornerRadius: 28))
      .overlay(
        RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.25), lineWidth: 0.7))
  }
}

struct SceneGlass: View {
  var body: some View {
    if #available(macOS 26, *) {
      Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
    } else {
      RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial)
    }
  }
}

struct SceneArtwork: View {
  @ObservedObject var player: MediaPlayer
  var body: some View {
    GeometryReader { geometry in
      Group {
        if let image = player.artwork {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          Image(systemName: "music.note").font(.system(size: 60)).frame(
            maxWidth: .infinity, maxHeight: .infinity
          ).background(.white.opacity(0.1))
        }
      }.frame(width: geometry.size.width, height: geometry.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14)).shadow(radius: 16)
    }
  }
}

struct SceneLyricsView: View {
  @ObservedObject var player: MediaPlayer
  @ObservedObject var lyrics: LyricsStore
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.5, paused: !player.isPlaying)) { context in
      let index = SyncedLyrics.currentIndex(
        in: lyrics.lines, at: player.playbackPosition(at: context.date))
      ScrollViewReader { proxy in
        ScrollView {
          if lyrics.lines.isEmpty { Text(lyrics.status).font(.headline).padding() }
          LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(lyrics.lines) { line in
              Text(line.text).font(.system(size: 23, weight: .bold))
                .foregroundStyle(
                  .white.opacity(
                    index.map { lyrics.lines[$0].time == line.time } == true ? 1 : 0.38)
                ).id(line.time)
            }
          }
        }.onChange(of: index) { _, value in
          if let value { proxy.scrollTo(lyrics.lines[value].time, anchor: .center) }
        }
      }
    }
  }
}
