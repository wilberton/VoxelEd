import SwiftUI

struct SettingsPanelView: View {
    @Binding var isGridVisible: Bool
    @Binding var isAxesVisible: Bool
    @Binding var edgeOpacity: Float
    @State private var hoveredHelpText: String?

    private let showGridHelp = "Show or hide the scene grid planes and in-view boundary axes."
    private let showAxesHelp = "Show or hide the small world-orientation axes overlay in the viewport corner."
    private let edgeOpacityHelp = "Blend strength of the voxel edge texture. 0 leaves flat cell color, 1 applies the full edge texture."

    var body: some View {
        EditorSection(title: "Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Grid", isOn: $isGridVisible)
                    .help(showGridHelp)
                    .onHover { isHovering in
                        hoveredHelpText = isHovering ? showGridHelp : hoveredHelpText == showGridHelp ? nil : hoveredHelpText
                    }

                Toggle("Show Axes", isOn: $isAxesVisible)
                    .help(showAxesHelp)
                    .onHover { isHovering in
                        hoveredHelpText = isHovering ? showAxesHelp : hoveredHelpText == showAxesHelp ? nil : hoveredHelpText
                    }

                HStack {
                    Text("Edge Opacity")
                    Spacer()
                    Text(edgeOpacity.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                Slider(value: $edgeOpacity, in: 0...1, step: 0.01)
                    .help(edgeOpacityHelp)
                    .onHover { isHovering in
                        hoveredHelpText = isHovering ? edgeOpacityHelp : hoveredHelpText == edgeOpacityHelp ? nil : hoveredHelpText
                    }
            }

            PanelHelpText(text: hoveredHelpText ?? edgeOpacityHelp)
        }
    }
}

#Preview {
    SettingsPanelView(
        isGridVisible: .constant(true),
        isAxesVisible: .constant(true),
        edgeOpacity: .constant(0.5)
    )
}
