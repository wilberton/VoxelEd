import SwiftUI

struct ToolPanelView: View {
    @Binding var selectedTool: EditorTool
    @Binding var isXSymmetryEnabled: Bool
    let onClear: () -> Void
    let onFlipX: () -> Void
    let onRotate90: () -> Void
    let onCull: () -> Void
    let onCrop: () -> Void
    let onResize: () -> Void
    @State private var hoveredTool: EditorTool?
    @State private var hoveredActionDescription: String?
    private let columns = Array(repeating: GridItem(.flexible(minimum: 44, maximum: 56), spacing: 10), count: 3)

    var body: some View {
        EditorSection(title: "Tools") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)

                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedTool == tool ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)

                            Image(systemName: tool.symbolName)
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .help(tool.tooltip)
                    .accessibilityLabel(tool.rawValue)
                    .onHover { isHovering in
                        hoveredTool = isHovering ? tool : (hoveredTool == tool ? nil : hoveredTool)
                    }
                }
            }

            HStack(spacing: 8) {
                actionButton("Clear", systemImage: "trash", help: "Clear the current frame.", action: onClear)
                actionButton("Flip X", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Mirror the current frame across the X axis.", action: onFlipX)
            }

            HStack(spacing: 8) {
                actionButton("Rotate90", systemImage: "rotate.right", help: "Rotate the current frame 90 degrees around the Y axis.", action: onRotate90)
                actionButton("Resize", systemImage: "arrow.up.left.and.arrow.down.right", help: "Resize all frames, cropping or extending them to a shared volume size.", action: onResize)
            }

            HStack(spacing: 8) {
                actionButton("Cull", systemImage: "eye.slash", help: "Remove voxels hidden on all visible faces across every frame.", action: onCull)
                actionButton("Crop", systemImage: "crop", help: "Crop all frames to the occupied bounds in X, Z, and +Y.", action: onCrop)
            }

            Toggle("X Symmetry", isOn: $isXSymmetryEnabled)
                .help("Mirror cube, add, remove, and paint edits across the X axis.")
                .onHover { isHovering in
                    let help = "Mirror cube, add, remove, and paint edits across the X axis."
                    hoveredActionDescription = isHovering ? help : hoveredActionDescription == help ? nil : hoveredActionDescription
                }

            PanelHelpText(text: activeDescription, reservedLineCount: 3)
        }
    }

    private var activeDescription: String {
        hoveredActionDescription ?? hoveredTool?.tooltip ?? selectedTool.tooltip
    }

    private func actionButton(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .help(help)
        .onHover { isHovering in
            hoveredActionDescription = isHovering ? help : hoveredActionDescription == help ? nil : hoveredActionDescription
        }
    }
}
