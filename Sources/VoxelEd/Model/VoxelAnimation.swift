import Foundation

struct VoxelAnimation: Equatable, Sendable, Identifiable {
    static let maxFrameIndices = 32
    static let defaultFPS = 8

    var id = UUID()
    var name: String
    var fps: Int
    var frameIndices: [Int]

    init(name: String, fps: Int = VoxelAnimation.defaultFPS, frameIndices: [Int] = []) {
        self.name = name
        self.fps = max(1, fps)
        self.frameIndices = Array(frameIndices.prefix(Self.maxFrameIndices))
    }

    var playbackFrameIndices: [Int] {
        frameIndices
    }
}
