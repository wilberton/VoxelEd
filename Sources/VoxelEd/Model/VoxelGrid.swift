import Foundation
import simd

struct FilledVoxel: Equatable, Sendable {
    var x: Int
    var y: Int
    var z: Int
    var paletteIndex: UInt8
}

struct VoxelBounds: Equatable, Sendable {
    var min: SIMD3<Int>
    var max: SIMD3<Int>
}

struct VoxelGrid: Equatable, Sendable {
    var dimensions: VoxelDimensions
    private var cells: [UInt8]

    static let emptyPaletteIndex: UInt8 = 0

    init(dimensions: VoxelDimensions) {
        self.dimensions = dimensions
        self.cells = Array(repeating: Self.emptyPaletteIndex, count: dimensions.voxelCount)
    }

    func contains(x: Int, y: Int, z: Int) -> Bool {
        (0..<dimensions.width).contains(x) &&
        (0..<dimensions.height).contains(y) &&
        (0..<dimensions.depth).contains(z)
    }

    func index(x: Int, y: Int, z: Int) -> Int {
        ((y * dimensions.depth) + z) * dimensions.width + x
    }

    subscript(x: Int, y: Int, z: Int) -> UInt8 {
        get {
            guard contains(x: x, y: y, z: z) else {
                return Self.emptyPaletteIndex
            }
            return cells[index(x: x, y: y, z: z)]
        }
        set {
            guard contains(x: x, y: y, z: z) else {
                return
            }
            cells[index(x: x, y: y, z: z)] = newValue
        }
    }

    var filledVoxels: [FilledVoxel] {
        var result: [FilledVoxel] = []
        result.reserveCapacity(cells.count / 4)

        for y in 0..<dimensions.height {
            for z in 0..<dimensions.depth {
                for x in 0..<dimensions.width {
                    let paletteIndex = self[x, y, z]
                    guard paletteIndex != Self.emptyPaletteIndex else {
                        continue
                    }
                    result.append(FilledVoxel(x: x, y: y, z: z, paletteIndex: paletteIndex))
                }
            }
        }

        return result
    }

    var filledVoxelCount: Int {
        cells.lazy.filter { $0 != Self.emptyPaletteIndex }.count
    }

    var occupiedBounds: VoxelBounds? {
        var minCell = SIMD3(Int.max, Int.max, Int.max)
        var maxCell = SIMD3(Int.min, Int.min, Int.min)
        var foundVoxel = false

        for y in 0..<dimensions.height {
            for z in 0..<dimensions.depth {
                for x in 0..<dimensions.width {
                    guard self[x, y, z] != Self.emptyPaletteIndex else {
                        continue
                    }
                    foundVoxel = true
                    minCell = SIMD3(min(minCell.x, x), min(minCell.y, y), min(minCell.z, z))
                    maxCell = SIMD3(max(maxCell.x, x), max(maxCell.y, y), max(maxCell.z, z))
                }
            }
        }

        guard foundVoxel else {
            return nil
        }
        return VoxelBounds(min: minCell, max: maxCell)
    }

    var sceneOffset: SIMD3<Float> {
        SIMD3(
            -Float(dimensions.width) * 0.5,
            0,
            -Float(dimensions.depth) * 0.5
        )
    }

    static func makeTestModel() -> VoxelGrid {
        VoxelGrid(dimensions: VoxelDimensions(width: 16, height: 16, depth: 16))
    }

    func cleared() -> VoxelGrid {
        VoxelGrid(dimensions: dimensions)
    }

    func flippedX() -> VoxelGrid {
        var result = VoxelGrid(dimensions: dimensions)
        for y in 0..<dimensions.height {
            for z in 0..<dimensions.depth {
                for x in 0..<dimensions.width {
                    let mirroredX = dimensions.width - 1 - x
                    result[mirroredX, y, z] = self[x, y, z]
                }
            }
        }
        return result
    }

    func rotated90Y() -> VoxelGrid {
        var result = VoxelGrid(dimensions: dimensions)
        let halfWidth = Float(dimensions.width) * 0.5
        let halfDepth = Float(dimensions.depth) * 0.5

        for y in 0..<dimensions.height {
            for z in 0..<dimensions.depth {
                for x in 0..<dimensions.width {
                    let paletteIndex = self[x, y, z]
                    guard paletteIndex != Self.emptyPaletteIndex else {
                        continue
                    }

                    let localX = (Float(x) + 0.5) - halfWidth
                    let localZ = (Float(z) + 0.5) - halfDepth
                    let rotatedLocalX = -localZ
                    let rotatedLocalZ = localX
                    let rotatedX = Int(floor(rotatedLocalX + halfWidth))
                    let rotatedZ = Int(floor(rotatedLocalZ + halfDepth))

                    guard result.contains(x: rotatedX, y: y, z: rotatedZ) else {
                        continue
                    }
                    result[rotatedX, y, rotatedZ] = paletteIndex
                }
            }
        }

        return result
    }

    mutating func fillBox(from minCell: SIMD3<Int>, to maxCell: SIMD3<Int>, paletteIndex: UInt8) {
        guard paletteIndex != Self.emptyPaletteIndex else {
            return
        }

        let clampedMin = SIMD3(
            max(0, min(minCell.x, maxCell.x)),
            max(0, min(minCell.y, maxCell.y)),
            max(0, min(minCell.z, maxCell.z))
        )

        let clampedMax = SIMD3(
            min(dimensions.width - 1, max(minCell.x, maxCell.x)),
            min(dimensions.height - 1, max(minCell.y, maxCell.y)),
            min(dimensions.depth - 1, max(minCell.z, maxCell.z))
        )

        guard clampedMin.x <= clampedMax.x, clampedMin.y <= clampedMax.y, clampedMin.z <= clampedMax.z else {
            return
        }

        for x in clampedMin.x...clampedMax.x {
            for y in clampedMin.y...clampedMax.y {
                for z in clampedMin.z...clampedMax.z {
                    self[x, y, z] = paletteIndex
                }
            }
        }
    }

    func resized(to newDimensions: VoxelDimensions) -> VoxelGrid {
        var resizedGrid = VoxelGrid(dimensions: newDimensions)
        let copyWidth = min(dimensions.width, newDimensions.width)
        let copyHeight = min(dimensions.height, newDimensions.height)
        let copyDepth = min(dimensions.depth, newDimensions.depth)

        for x in 0..<copyWidth {
            for y in 0..<copyHeight {
                for z in 0..<copyDepth {
                    resizedGrid[x, y, z] = self[x, y, z]
                }
            }
        }

        return resizedGrid
    }

    func shifted(x dx: Int, y dy: Int, z dz: Int) -> VoxelGrid {
        var result = VoxelGrid(dimensions: dimensions)

        for y in 0..<dimensions.height {
            for z in 0..<dimensions.depth {
                for x in 0..<dimensions.width {
                    let paletteIndex = self[x, y, z]
                    guard paletteIndex != Self.emptyPaletteIndex else {
                        continue
                    }

                    let shiftedX = x + dx
                    let shiftedY = y + dy
                    let shiftedZ = z + dz
                    guard result.contains(x: shiftedX, y: shiftedY, z: shiftedZ) else {
                        continue
                    }
                    result[shiftedX, shiftedY, shiftedZ] = paletteIndex
                }
            }
        }

        return result
    }

    func cropped(using bounds: VoxelBounds?) -> VoxelGrid {
        guard let bounds else {
            return VoxelGrid(dimensions: VoxelDimensions(width: VoxelDimensions.minSize, height: VoxelDimensions.minSize, depth: VoxelDimensions.minSize))
        }

        let occupiedWidth = bounds.max.x - bounds.min.x + 1
        let occupiedDepth = bounds.max.z - bounds.min.z + 1
        let occupiedHeight = bounds.max.y + 1

        let newDimensions = VoxelDimensions(
            width: max(VoxelDimensions.minSize, occupiedWidth),
            height: max(VoxelDimensions.minSize, occupiedHeight),
            depth: max(VoxelDimensions.minSize, occupiedDepth)
        )

        var result = VoxelGrid(dimensions: newDimensions)
        for y in 0..<min(dimensions.height, newDimensions.height) {
            for z in bounds.min.z...bounds.max.z {
                for x in bounds.min.x...bounds.max.x {
                    let paletteIndex = self[x, y, z]
                    guard paletteIndex != Self.emptyPaletteIndex else {
                        continue
                    }
                    result[x - bounds.min.x, y, z - bounds.min.z] = paletteIndex
                }
            }
        }
        return result
    }

    func bucketFilled(from start: SIMD3<Int>, replacementPaletteIndex: UInt8) -> VoxelGrid {
        guard contains(x: start.x, y: start.y, z: start.z) else {
            return self
        }

        let targetPaletteIndex = self[start.x, start.y, start.z]
        guard targetPaletteIndex != Self.emptyPaletteIndex else {
            return self
        }
        guard targetPaletteIndex != replacementPaletteIndex else {
            return self
        }
        guard replacementPaletteIndex != Self.emptyPaletteIndex else {
            return self
        }

        var result = self
        var queue: [SIMD3<Int>] = [start]
        var queueIndex = 0

        while queueIndex < queue.count {
            let cell = queue[queueIndex]
            queueIndex += 1

            guard result[cell.x, cell.y, cell.z] == targetPaletteIndex else {
                continue
            }

            result[cell.x, cell.y, cell.z] = replacementPaletteIndex

            let neighbors = [
                SIMD3(cell.x - 1, cell.y, cell.z),
                SIMD3(cell.x + 1, cell.y, cell.z),
                SIMD3(cell.x, cell.y - 1, cell.z),
                SIMD3(cell.x, cell.y + 1, cell.z),
                SIMD3(cell.x, cell.y, cell.z - 1),
                SIMD3(cell.x, cell.y, cell.z + 1)
            ]

            for neighbor in neighbors where result.contains(x: neighbor.x, y: neighbor.y, z: neighbor.z) {
                if result[neighbor.x, neighbor.y, neighbor.z] == targetPaletteIndex {
                    queue.append(neighbor)
                }
            }
        }

        return result
    }

    func culledHiddenVoxels() -> (grid: VoxelGrid, culledCount: Int) {
        var result = self
        var culledCount = 0

        for y in 0..<dimensions.height {
            for z in 0..<dimensions.depth {
                for x in 0..<dimensions.width {
                    guard self[x, y, z] != Self.emptyPaletteIndex else {
                        continue
                    }

                    let isHidden =
                        self[x - 1, y, z] != Self.emptyPaletteIndex &&
                        self[x + 1, y, z] != Self.emptyPaletteIndex &&
                        self[x, y, z - 1] != Self.emptyPaletteIndex &&
                        self[x, y, z + 1] != Self.emptyPaletteIndex &&
                        self[x, y + 1, z] != Self.emptyPaletteIndex

                    guard isHidden else {
                        continue
                    }

                    result[x, y, z] = Self.emptyPaletteIndex
                    culledCount += 1
                }
            }
        }

        return (result, culledCount)
    }
}
