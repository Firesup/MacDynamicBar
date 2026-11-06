import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
  @ObservedObject var shelf: ShelfStore
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Shelf", systemImage: "tray").font(.system(size: 12, weight: .semibold))
        Spacer()
        if shelf.importing { ProgressView().controlSize(.mini) }
        Button {
          shelf.chooseFiles()
        } label: {
          Label("Add files", systemImage: "plus")
        }.disabled(shelf.importing).buttonStyle(.plain)
          .font(.system(size: 11, weight: .semibold))
      }
      if let error = shelf.error {
        HStack(alignment: .top) {
          Text(error).font(.system(size: 11)).foregroundStyle(.orange)
          Spacer(minLength: 0)
          Button {
            shelf.error = nil
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain).accessibilityLabel("Dismiss Shelf error")
        }
      }
      if shelf.items.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "tray.and.arrow.down").font(.system(size: 25, weight: .medium))
          Text("Drop files here").font(.system(size: 13, weight: .semibold))
          Text("Keep files handy, then drag them out or AirDrop them.")
            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), alignment: .top)], spacing: 12) {
            ForEach(shelf.items) { item in
              card(item).onDrag { shelf.dragProvider(item.id) }
            }
          }.padding(.bottom, 12)
        }
      }
    }.foregroundStyle(.white).padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 14)
  }
  private func card(_ item: ShelfItem) -> some View {
    VStack(spacing: 4) {
      Button {
        shelf.open(item.id)
      } label: {
        Group {
          if let image = shelf.thumbnails[item.id] {
            Image(nsImage: image).resizable().scaledToFit()
          } else {
            Image(systemName: item.problem == nil ? "doc" : "exclamationmark.triangle")
              .font(.system(size: 29, weight: .light)).foregroundStyle(.secondary)
          }
        }.frame(width: 48, height: 48).contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(item.url == nil).accessibilityLabel("Open " + item.name)
      Text(item.name).font(.system(size: 10, weight: .medium)).lineLimit(2)
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
      HStack(spacing: 10) {
        Button {
          shelf.airDrop(item.id)
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
        .disabled(item.url == nil || shelf.sharing).accessibilityLabel("AirDrop " + item.name)
        Button {
          shelf.remove(item.id)
        } label: {
          Image(systemName: "xmark")
        }
        .accessibilityLabel("Remove " + item.name + " from Shelf")
      }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }.help(item.problem ?? item.name)
      .contextMenu {
        Button("Open") { shelf.open(item.id) }.disabled(item.url == nil)
        Button("Show in Finder") { shelf.reveal(item.id) }.disabled(item.url == nil)
        Button("AirDrop…") { shelf.airDrop(item.id) }.disabled(item.url == nil || shelf.sharing)
        Divider()
        Button("Remove from Shelf") { shelf.remove(item.id) }
      }
  }
}

struct ShelfSettingsView: View {
  @ObservedObject var settings: MinnowSettings
  @ObservedObject var shelf: ShelfStore
  @State private var targeted = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle("Enable Shelf", isOn: $settings.shelfEnabled)
      Text(
        "Add files here or drop them on the island. Shelf stores references to their original locations. Removing a Shelf item leaves its source file in place."
      )
      .foregroundStyle(.secondary)
      ShelfView(shelf: shelf).frame(height: 280)
        .background(.white.opacity(targeted ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 16))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
          guard settings.shelfEnabled else { return false }
          Task { await shelf.importFiles(providers) }
          return true
        }.disabled(!settings.shelfEnabled)
      Text(
        "Up to 30 files or folders. Move/delete/access changes may require re-adding a file. AirDrop uses macOS's native recipient picker and needs compatible hardware and connectivity. Shelf is never shown on the lock screen."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .onAppear { shelf.setEnabled(settings.shelfEnabled) }
    .onChange(of: settings.shelfEnabled) { _, enabled in shelf.setEnabled(enabled) }
  }
}
