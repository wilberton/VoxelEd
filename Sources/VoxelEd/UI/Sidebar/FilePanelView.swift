import SwiftUI

struct FilePanelView: View {
    let hasUnsavedChanges: Bool
    let currentFileName: String
    let onLoad: () -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onNew: () -> Void
    @State private var hoveredDescription: String?

    var body: some View {
        EditorSection(title: "File") {
            HStack(spacing: 8) {
                fileButton("Load", systemImage: "folder", help: "Open a .vxm file from disk.", action: onLoad)
                fileButton("Save", systemImage: "square.and.arrow.down", help: "Save the current document.", action: onSave)
            }

            HStack(spacing: 8) {
                fileButton("Save As", systemImage: "square.and.arrow.down.on.square", help: "Save a copy to a new file path.", action: onSaveAs)
                fileButton("New", systemImage: "doc.badge.plus", help: "Create a new voxel document.", action: onNew)
            }

            Text(currentFileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(hasUnsavedChanges ? "Unsaved changes" : "No unsaved changes")
                .font(.caption)
                .foregroundStyle(hasUnsavedChanges ? .orange : .secondary)

            PanelHelpText(text: hoveredDescription ?? "File operations for opening, saving, and creating documents.")
        }
    }

    private func fileButton(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .help(help)
        .onHover { isHovering in
            hoveredDescription = isHovering ? help : hoveredDescription == help ? nil : hoveredDescription
        }
    }
}
