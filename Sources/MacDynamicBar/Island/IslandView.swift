import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var player: PreviewPlayer
    let layout: IslandLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.isExpanded {
                playerContent
                    .frame(height: layout.configuration.expandedContentHeight)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: state.isExpanded ? 26 : 14,
            bottomTrailingRadius: state.isExpanded ? 26 : 14, topTrailingRadius: 0
        ))
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: layout.configuration.animationDuration), value: state.presentation)
    }

    private var header: some View {
        Button(action: state.toggle) {
            Color.clear
                .overlay(alignment: .trailing) {
                    if state.isExpanded {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 20)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: state.presentation == .hover
                       ? layout.size(for: .hover).height : layout.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isExpanded ? "Collapse Minnow" : "Expand Minnow")
        .help(state.isExpanded ? "Collapse Minnow" : "Expand Minnow")
    }

    private var playerContent: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.mint.opacity(0.16))
                    .overlay { Image(systemName: "waveform").font(.title).foregroundStyle(.mint) }
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(player.title).font(.headline).lineLimit(1)
                    Text(player.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 32) {
                playbackButton("backward.fill", label: "Previous preview", action: player.previous)
                playbackButton(player.isPlaying ? "pause.fill" : "play.fill",
                               label: player.isPlaying ? "Pause preview" : "Play preview",
                               action: player.togglePlayback)
                playbackButton("forward.fill", label: "Next preview", action: player.next)
            }
            .font(.title3)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private func playbackButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 36, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
