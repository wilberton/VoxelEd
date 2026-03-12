import Foundation

struct VoxelDimensions: Equatable, Sendable {
    static let minSize = 4
    static let maxSize = 32

    var width: Int
    var height: Int
    var depth: Int

    init(width: Int, height: Int, depth: Int) {
        self.width = Self.clamp(width)
        self.height = Self.clamp(height)
        self.depth = Self.clamp(depth)
    }

    var voxelCount: Int {
        width * height * depth
    }

    var displayString: String {
        "\(width) x \(height) x \(depth)"
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, minSize), maxSize)
    }
}
