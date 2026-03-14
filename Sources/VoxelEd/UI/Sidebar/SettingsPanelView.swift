import SwiftUI

struct SettingsPanelView: View {
    @Binding var edgeOpacity: Float
    @State private var isHoveringEdgeOpacity = false

    private let edgeOpacityHelp = "Blend strength of the voxel edge texture. 0 leaves flat cell color, 1 applies the full edge texture."

    var body: some View {
        EditorSection(title: "Settings") {
            VStack(alignment: .leading, spacing: 8) {
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
                        isHoveringEdgeOpacity = isHovering
                    }
            }

            PanelHelpText(text: isHoveringEdgeOpacity ? edgeOpacityHelp : edgeOpacityHelp)
        }
    }
}

#Preview {
    SettingsPanelView(edgeOpacity: .constant(0.5))
}
