import CoreGraphics
import simd

struct Ray {
    var origin: SIMD3<Float>
    var direction: SIMD3<Float>
}

enum FaceDirection: CaseIterable, Equatable, Sendable {
    case left
    case right
    case down
    case up
    case back
    case front

    var vector: SIMD3<Int> {
        switch self {
        case .left: SIMD3(-1, 0, 0)
        case .right: SIMD3(1, 0, 0)
        case .down: SIMD3(0, -1, 0)
        case .up: SIMD3(0, 1, 0)
        case .back: SIMD3(0, 0, -1)
        case .front: SIMD3(0, 0, 1)
        }
    }

    var normal: SIMD3<Float> {
        SIMD3(Float(vector.x), Float(vector.y), Float(vector.z))
    }
}

enum HoverTarget: Equatable, Sendable {
    case ground(x: Int, z: Int)
    case voxelFace(x: Int, y: Int, z: Int, face: FaceDirection)

    var groundCell: SIMD2<Int>? {
        switch self {
        case let .ground(x, z):
            return SIMD2(x, z)
        case .voxelFace:
            return nil
        }
    }

    var deleteCell: SIMD3<Int>? {
        switch self {
        case let .voxelFace(x, y, z, _):
            SIMD3(x, y, z)
        case .ground:
            nil
        }
    }

    var addCell: SIMD3<Int> {
        switch self {
        case let .ground(x, z):
            return SIMD3(x, 0, z)
        case let .voxelFace(x, y, z, face):
            let delta = face.vector
            return SIMD3(x + delta.x, y + delta.y, z + delta.z)
        }
    }
}

struct RaycastHit {
    var target: HoverTarget
    var distance: Float
}

struct CubePreviewBox: Equatable, Sendable {
    var minCell: SIMD3<Int>
    var maxCell: SIMD3<Int>
}

extension VoxelGrid {
    func raycast(_ ray: Ray, includeGround: Bool) -> RaycastHit? {
        var closestHit: RaycastHit?

        for voxel in filledVoxels {
            let minBounds = worldMin(x: voxel.x, y: voxel.y, z: voxel.z)
            let maxBounds = minBounds + SIMD3<Float>(repeating: 1)

            guard let (distance, face) = intersectAABB(ray: ray, minBounds: minBounds, maxBounds: maxBounds) else {
                continue
            }

            let hit = RaycastHit(
                target: .voxelFace(x: voxel.x, y: voxel.y, z: voxel.z, face: face),
                distance: distance
            )

            if closestHit == nil || hit.distance < closestHit!.distance {
                closestHit = hit
            }
        }

        if includeGround, let groundHit = intersectGround(ray: ray) {
            if closestHit == nil || groundHit.distance < closestHit!.distance {
                closestHit = groundHit
            }
        }

        return closestHit
    }

    func worldMin(x: Int, y: Int, z: Int) -> SIMD3<Float> {
        SIMD3(
            Float(x) + sceneOffset.x,
            Float(y),
            Float(z) + sceneOffset.z
        )
    }

    private func intersectGround(ray: Ray) -> RaycastHit? {
        let epsilon: Float = 0.0001
        guard abs(ray.direction.y) > epsilon else {
            return nil
        }

        let distance = -ray.origin.y / ray.direction.y
        guard distance > epsilon else {
            return nil
        }

        let point = ray.origin + (ray.direction * distance)
        let localX = point.x - sceneOffset.x
        let localZ = point.z - sceneOffset.z
        let cellX = Int(floor(localX))
        let cellZ = Int(floor(localZ))

        guard (0..<dimensions.width).contains(cellX), (0..<dimensions.depth).contains(cellZ) else {
            return nil
        }

        return RaycastHit(target: .ground(x: cellX, z: cellZ), distance: distance)
    }

    private func intersectAABB(ray: Ray, minBounds: SIMD3<Float>, maxBounds: SIMD3<Float>) -> (Float, FaceDirection)? {
        let epsilon: Float = 0.0001
        var tMin: Float = -Float.greatestFiniteMagnitude
        var tMax: Float = Float.greatestFiniteMagnitude
        var hitFace: FaceDirection?

        func updateAxis(origin: Float, direction: Float, minValue: Float, maxValue: Float, negativeFace: FaceDirection, positiveFace: FaceDirection) -> Bool {
            if abs(direction) < epsilon {
                return origin >= minValue && origin <= maxValue
            }

            var t1 = (minValue - origin) / direction
            var t2 = (maxValue - origin) / direction
            var face1 = negativeFace
            var face2 = positiveFace

            if t1 > t2 {
                swap(&t1, &t2)
                swap(&face1, &face2)
            }

            if t1 > tMin {
                tMin = t1
                hitFace = face1
            }

            tMax = min(tMax, t2)
            return tMin <= tMax
        }

        guard
            updateAxis(origin: ray.origin.x, direction: ray.direction.x, minValue: minBounds.x, maxValue: maxBounds.x, negativeFace: .left, positiveFace: .right),
            updateAxis(origin: ray.origin.y, direction: ray.direction.y, minValue: minBounds.y, maxValue: maxBounds.y, negativeFace: .down, positiveFace: .up),
            updateAxis(origin: ray.origin.z, direction: ray.direction.z, minValue: minBounds.z, maxValue: maxBounds.z, negativeFace: .back, positiveFace: .front),
            let hitFace
        else {
            return nil
        }

        let distance = tMin > epsilon ? tMin : tMax
        guard distance > epsilon else {
            return nil
        }

        return (distance, hitFace)
    }
}
