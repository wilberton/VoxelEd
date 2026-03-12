import Foundation

enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case cube = "Cube"
    case add = "Add"
    case paint = "Paint"

    var id: String {
        rawValue
    }

    var symbolName: String {
        switch self {
        case .add:
            "plus.square"
        case .paint:
            "paintbrush.pointed"
        case .cube:
            "cube"
        }
    }

    var tooltip: String {
        switch self {
        case .add:
            "Add voxels on the ground or onto a hovered face. Hold Option to delete, Control to paint, Shift to pick a color."
        case .paint:
            "Recolor existing voxels by clicking or dragging across them. Hold Control to fill connected voxels, Shift to pick a color."
        case .cube:
            "Create a filled cuboid: click base corner, base opposite corner, then height. Hold Shift and click a voxel to pick its color. Escape cancels."
        }
    }
}
