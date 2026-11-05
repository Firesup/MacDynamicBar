import SwiftUI

struct LockScreenPlayerView: View {
  let session: IslandMediaSession
  @ObservedObject var settings: MinnowSettings
  @ObservedObject var lyrics: LyricsStore
  var expansionChanged: (Bool, Bool) -> Void
  @StateObject private var state = IslandState(hoverEnabled: false)
  @State private var expanded = false
  @State private var showLyrics = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      let card = LockScreenGeometry.cardFrame(size: geometry.size)
      let art = LockScreenGeometry.artworkFrame(size: geometry.size, lyrics: showLyrics).width
      VStack(spacing: 20) {
        Spacer(minLength: 0)
        if expanded {
          HStack(spacing: 30) {
            Button {
              expanded = false
            } label: {
              SceneArtwork(player: session.player).frame(width: art, height: art)
            }
            .buttonStyle(.plain).accessibilityLabel("Collapse album cover")
            if showLyrics {
              SceneLyricsView(player: session.player, lyrics: lyrics).frame(width: art, height: art)
            }
          }.frame(height: art)
        }
        VStack(spacing: 0) {
          HStack {
            Spacer()
            Button {
              showLyrics.toggle()
              if showLyrics { expanded = true }
            } label: {
              Image(systemName: "quote.bubble").foregroundStyle(
                showLyrics ? .white : .white.opacity(0.65))
            }
            .buttonStyle(.plain).accessibilityLabel("Toggle lyrics")
          }.padding(.horizontal, 20).padding(.top, 10)
          MusicView(
            state: state, player: session.player, audio: session.audio,
            accessories: session.accessories, outputs: session.outputs, settings: settings,
            onArtworkPress: { expanded.toggle() })
        }.frame(width: 408, height: 164)
          .background { SceneGlass() }.clipShape(RoundedRectangle(cornerRadius: 28))
          .overlay(
            RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.25), lineWidth: 0.7))
          .scaleEffect(card.width / 408, anchor: .bottom)
          .frame(width: card.width, height: card.height)
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onAppear { if !state.isExpanded { state.toggle() } }
        .onChange(of: expanded) { _, value in expansionChanged(value, showLyrics) }
        .onChange(of: showLyrics) { _, value in expansionChanged(expanded, value) }
        .animation(
          reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86), value: expanded)
    }
  }
}
