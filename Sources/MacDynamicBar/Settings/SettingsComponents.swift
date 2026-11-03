import SwiftUI

// MARK: - Settings Components

struct SettingsCard<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 13) { content }
      .padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.075)))
  }
}

struct SettingsGroup<Content: View>: View {
  let title: String
  let caption: String?
  let content: Content
  init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.caption = caption
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(
        .leading, 8)
      SettingsCard { content }
      if let caption {
        Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct SourceChoice: View {
  let source: SourcePreference
  let selected: Bool
  let action: () -> Void
  private var icon: NSImage? {
    guard let id = source.source?.bundleIdentifier,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
  var body: some View {
    Button(action: action) {
      VStack(spacing: 12) {
        Text(source.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        Group {
          if let icon {
            Image(nsImage: icon).resizable().scaledToFit()
          } else {
            Image(systemName: source == .auto ? "sparkles" : "music.note").resizable().scaledToFit()
              .padding(7)
          }
        }.frame(width: 40, height: 40)
        Circle().fill(selected ? Color.white : Color.clear).frame(width: 4, height: 4)
      }.frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(.white.opacity(selected ? 0.12 : 0.025), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(selected ? 0.28 : 0.05)))
    }.buttonStyle(.plain).accessibilityLabel(source.title).accessibilityValue(
      selected ? "Selected" : "Not Selected")
  }
}

// Cover motion uses the available static artwork; it does not pretend to fetch video covers.
