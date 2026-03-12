import SwiftUI

struct ModelInfoView: View {
    let dimensions: VoxelDimensions
    let filledVoxelCount: Int
    let frameCount: Int
    let animationCount: Int
    let estimatedFileSizeBytes: Int

    var body: some View {
        EditorSection(title: "Model") {
            VStack(alignment: .leading, spacing: 8) {
                Label(dimensions.displayString, systemImage: "cube.transparent")
                Label("\(filledVoxelCount) filled voxels", systemImage: "square.grid.3x3.fill")
                Label("\(frameCount) frame\(frameCount == 1 ? "" : "s")", systemImage: "rectangle.stack")
                Label("\(animationCount) anim\(animationCount == 1 ? "" : "s")", systemImage: "film.stack")
                Label(formattedFileSize, systemImage: "internaldrive")
            }
            .font(.subheadline)
        }
    }

    private var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(estimatedFileSizeBytes))
    }
}
