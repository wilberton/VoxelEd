import SwiftUI

struct VolumeSizeSheet: View {
    let title: String
    let initialDimensions: VoxelDimensions
    let actionLabel: String
    let onConfirm: (VoxelDimensions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var widthValue: Int
    @State private var heightValue: Int
    @State private var depthValue: Int

    init(title: String, initialDimensions: VoxelDimensions, actionLabel: String, onConfirm: @escaping (VoxelDimensions) -> Void) {
        self.title = title
        self.initialDimensions = initialDimensions
        self.actionLabel = actionLabel
        self.onConfirm = onConfirm
        _widthValue = State(initialValue: initialDimensions.width)
        _heightValue = State(initialValue: initialDimensions.height)
        _depthValue = State(initialValue: initialDimensions.depth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            Stepper("Width: \(widthValue)", value: $widthValue, in: VoxelDimensions.minSize...VoxelDimensions.maxSize)
            Stepper("Height: \(heightValue)", value: $heightValue, in: VoxelDimensions.minSize...VoxelDimensions.maxSize)
            Stepper("Depth: \(depthValue)", value: $depthValue, in: VoxelDimensions.minSize...VoxelDimensions.maxSize)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button(actionLabel) {
                    onConfirm(
                        VoxelDimensions(width: widthValue, height: heightValue, depth: depthValue)
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
