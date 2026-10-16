import AppKit
import GlanceCore
import SwiftUI

/// glance → Settings…: every folder browsed with its subfolders, and the subfolders each leaves out.
struct SettingsView: View {
    let store: SubfolderRoots
    @State private var roots: [SubfolderRoots.Root] = []

    var body: some View {
        Form {
            Section("Include Subfolders") {
                if roots.isEmpty {
                    Text("No folders yet. In a glance window, choose View → Include Subfolders.")
                        .foregroundStyle(.secondary)
                }
                ForEach(roots, id: \.path) { RootRow(root: $0, store: store) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 260)
        .onAppear { roots = store.roots }
        .onReceive(NotificationCenter.default.publisher(for: SubfolderRoots.didChange, object: store)) { _ in roots = store.roots }
    }
}

private struct RootRow: View {
    let root: SubfolderRoots.Root
    let store: SubfolderRoots

    private var exists: Bool { FileManager.default.fileExists(atPath: root.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((root.path as NSString).abbreviatingWithTildeInPath).font(.headline)
                if !exists { Text("Folder not found").foregroundStyle(.red) }
                Spacer()
                Button("Exclude Folder…", action: pickExclusion).disabled(!exists)
                Button("Remove") { store.disable(root.url) }
            }
            if root.excluded.isEmpty {
                Text("All subfolders included").foregroundStyle(.secondary)
            }
            ForEach(root.excluded, id: \.self) { relative in
                HStack {
                    Button { store.setExcluded(relative, false, in: root.url) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Include \(relative) again")
                    Text(relative)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pickExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = root.url
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let relative = SubfolderRoots.relativePath(of: url.resolvingSymlinksInPath(), in: root.url), !relative.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Choose a folder inside \(root.url.lastPathComponent)"
            alert.runModal()
            return
        }
        store.setExcluded(relative, true, in: root.url)
    }
}
