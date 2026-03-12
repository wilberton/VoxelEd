import AppKit
import SwiftUI

private struct PaletteEditSession: Identifiable {
    let index: Int
    let originalPalette: Palette
    var draftColor: PaletteColor

    var id: Int { index }
}

struct PaletteGridView: View {
    let palette: Palette
    let onSelectPreset: (String) -> Void
    let onLoadPalette: () -> Void
    let onPreviewPaletteColor: (Int, PaletteColor) -> Void
    let onRestorePalette: (Palette) -> Void
    let onCommitPaletteChange: (Palette) -> Void
    @Binding var selectedPaletteIndex: UInt8
    @State private var hoveredDescription: String?
    @State private var editSession: PaletteEditSession?

    private let columns = Array(repeating: GridItem(.flexible(minimum: 20, maximum: 28), spacing: 6), count: 8)
    private let customPresetLabel = "Custom"

    var body: some View {
        EditorSection(title: "Palette") {
            Picker(
                "Preset",
                selection: Binding(
                    get: { selectedPresetID },
                    set: { newValue in
                        guard newValue != PalettePreset.customID else {
                            return
                        }
                        onSelectPreset(newValue)
                    }
                )
            ) {
                Text(customPresetLabel).tag(PalettePreset.customID)
                ForEach(PalettePreset.builtIn) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .help("Choose a built-in palette preset.")
            .onHover { isHovering in
                let help = "Choose a built-in palette preset."
                hoveredDescription = isHovering ? help : hoveredDescription == help ? nil : hoveredDescription
            }

            Button {
                onLoadPalette()
            } label: {
                Label("Load Palette", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .help(loadPaletteHelpText)
            .onHover { isHovering in
                hoveredDescription = isHovering ? loadPaletteHelpText : hoveredDescription == loadPaletteHelpText ? nil : hoveredDescription
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(palette.colors.enumerated()), id: \.offset) { index, color in
                    Button {
                        if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
                            editSession = PaletteEditSession(index: index, originalPalette: palette, draftColor: color)
                        } else {
                            selectedPaletteIndex = UInt8(index)
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(index == 0 ? Color(nsColor: .tertiaryLabelColor).opacity(0.18) : color.swatchColor)

                            if index == 0 {
                                Image(systemName: "slash.circle")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(borderColor(for: index), lineWidth: index == Int(selectedPaletteIndex) ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(helpText(for: index))
                    .onHover { isHovering in
                        let help = helpText(for: index)
                        hoveredDescription = isHovering ? help : hoveredDescription == help ? nil : hoveredDescription
                    }
                    .popover(
                        isPresented: Binding(
                            get: { editSession?.index == index },
                            set: { isPresented in
                                if !isPresented, editSession?.index == index {
                                    if let activeSession = editSession {
                                        onRestorePalette(activeSession.originalPalette)
                                    }
                                    editSession = nil
                                }
                            }
                        ),
                        arrowEdge: .trailing
                    ) {
                        paletteEditor(for: index)
                    }
                }
            }

            Text(selectedPaletteIndex == 0 ? "Selected: Empty" : "Selected: \(selectedPaletteIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)

            PanelHelpText(text: hoveredDescription ?? selectedHelpText)
        }
    }

    private func borderColor(for index: Int) -> Color {
        index == Int(selectedPaletteIndex) ? .white : .black.opacity(0.25)
    }

    private var selectedHelpText: String {
        helpText(for: Int(selectedPaletteIndex))
    }

    private var loadPaletteHelpText: String {
        "Load palette colors from a 64x1 PNG image."
    }

    private var selectedPresetID: String {
        PalettePreset.builtIn.first(where: { $0.palette == palette })?.id ?? PalettePreset.customID
    }

    private func helpText(for index: Int) -> String {
        index == 0 ? "Palette slot 0: empty voxel / erase color. Control-click to open the color editor." : "Select palette color \(index). Control-click to open the color editor."
    }

    private func updatePaletteColor(at index: Int, from color: PaletteColor) {
        let alpha: Float = index == 0 ? 0.0 : 1.0
        onPreviewPaletteColor(
            index,
            PaletteColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
        )
    }

    @ViewBuilder
    private func paletteEditor(for index: Int) -> some View {
        if let session = editSession, session.index == index {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Palette \(session.index)")
                    .font(.headline)

                InlineColorWheelPicker(
                    color: Binding(
                        get: { editSession?.draftColor ?? session.draftColor },
                        set: { newValue in
                            editSession?.draftColor = newValue
                            updatePaletteColor(at: session.index, from: newValue)
                        }
                    )
                )

                Text(session.index == 0 ? "Slot 0 remains the empty voxel entry." : "Choose a new color for palette slot \(session.index).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()

                    Button("Cancel", role: .cancel) {
                        onRestorePalette(session.originalPalette)
                        editSession = nil
                    }

                    Button("OK") {
                        onCommitPaletteChange(session.originalPalette)
                        editSession = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 320)
        } else {
            EmptyView()
        }
    }
}
