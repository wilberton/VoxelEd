import Foundation
import simd

enum GridMesh {
    private static let gridColor = SIMD4<Float>(0.28, 0.31, 0.35, 1.0)
    private static let xAxisColor = SIMD4<Float>(0.92, 0.35, 0.31, 1.0)
    private static let yAxisColor = SIMD4<Float>(0.42, 0.84, 0.45, 1.0)
    private static let zAxisColor = SIMD4<Float>(0.34, 0.61, 0.96, 1.0)

    static func makeVertices(width: Int, height: Int, depth: Int, cameraPosition: SIMD3<Float>, focusPoint: SIMD3<Float>) -> [GridVertex] {
        var vertices: [GridVertex] = []
        vertices.reserveCapacity((((width + 1) + (depth + 1)) + ((width + 1) + (height + 1)) + ((depth + 1) + (height + 1))) * 2)

        let xOffset = Float(width) * 0.5
        let zOffset = Float(depth) * 0.5

        let minX = -xOffset
        let maxX = Float(width) - xOffset
        let minY: Float = 0
        let maxY = Float(height)
        let minZ = -zOffset
        let maxZ = Float(depth) - zOffset

        // Ground plane (XZ at y = 0).
        for x in 0...width {
            let px = Float(x) - xOffset
            appendLine(
                from: SIMD3<Float>(px, minY, minZ),
                to: SIMD3<Float>(px, minY, maxZ),
                color: gridColor,
                into: &vertices
            )
        }

        for z in 0...depth {
            let pz = Float(z) - zOffset
            appendLine(
                from: SIMD3<Float>(minX, minY, pz),
                to: SIMD3<Float>(maxX, minY, pz),
                color: gridColor,
                into: &vertices
            )
        }

        // Back XY plane at the far Z edge from the current camera side.
        let backZ = cameraPosition.z >= focusPoint.z ? minZ : maxZ
        for x in 0...width {
            let px = Float(x) - xOffset
            appendLine(
                from: SIMD3<Float>(px, minY, backZ),
                to: SIMD3<Float>(px, maxY, backZ),
                color: gridColor,
                into: &vertices
            )
        }

        for y in 0...height {
            let py = Float(y)
            appendLine(
                from: SIMD3<Float>(minX, py, backZ),
                to: SIMD3<Float>(maxX, py, backZ),
                color: gridColor,
                into: &vertices
            )
        }

        // Back ZY plane at the far X edge from the current camera side.
        let backX = cameraPosition.x >= focusPoint.x ? minX : maxX
        for z in 0...depth {
            let pz = Float(z) - zOffset
            appendLine(
                from: SIMD3<Float>(backX, minY, pz),
                to: SIMD3<Float>(backX, maxY, pz),
                color: gridColor,
                into: &vertices
            )
        }

        for y in 0...height {
            let py = Float(y)
            appendLine(
                from: SIMD3<Float>(backX, py, minZ),
                to: SIMD3<Float>(backX, py, maxZ),
                color: gridColor,
                into: &vertices
            )
        }

        return vertices
    }

    static func makeAxisVertices(width: Int, height: Int, depth: Int) -> [GridVertex] {
        let xOffset = Float(width) * 0.5
        let zOffset = Float(depth) * 0.5

        let minX = -xOffset
        let maxX = Float(width) - xOffset
        let maxY = Float(height)
        let minZ = -zOffset
        let maxZ = Float(depth) - zOffset

        let halfThickness: Float = 0.045

        var vertices: [GridVertex] = []
        vertices.reserveCapacity(36)

        appendAxis(
            from: SIMD3<Float>(minX, 0, minZ),
            to: SIMD3<Float>(maxX, 0, minZ),
            thicknessA: SIMD3<Float>(0, halfThickness, 0),
            thicknessB: SIMD3<Float>(0, 0, halfThickness),
            color: xAxisColor,
            into: &vertices
        )
        appendAxis(
            from: SIMD3<Float>(minX, 0, minZ),
            to: SIMD3<Float>(minX, 0, maxZ),
            thicknessA: SIMD3<Float>(halfThickness, 0, 0),
            thicknessB: SIMD3<Float>(0, halfThickness, 0),
            color: zAxisColor,
            into: &vertices
        )
        appendAxis(
            from: SIMD3<Float>(minX, 0, minZ),
            to: SIMD3<Float>(minX, maxY, minZ),
            thicknessA: SIMD3<Float>(halfThickness, 0, 0),
            thicknessB: SIMD3<Float>(0, 0, halfThickness),
            color: yAxisColor,
            into: &vertices
        )

        return vertices
    }

    private static func appendLine(from start: SIMD3<Float>, to end: SIMD3<Float>, color: SIMD4<Float>, into vertices: inout [GridVertex]) {
        vertices.append(GridVertex(position: start, color: color))
        vertices.append(GridVertex(position: end, color: color))
    }

    private static func appendAxis(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        thicknessA: SIMD3<Float>,
        thicknessB: SIMD3<Float>,
        color: SIMD4<Float>,
        into vertices: inout [GridVertex]
    ) {
        appendQuad(from: start, to: end, offset: thicknessA, color: color, into: &vertices)
        appendQuad(from: start, to: end, offset: thicknessB, color: color, into: &vertices)
    }

    private static func appendQuad(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        offset: SIMD3<Float>,
        color: SIMD4<Float>,
        into vertices: inout [GridVertex]
    ) {
        let a = start - offset
        let b = start + offset
        let c = end + offset
        let d = end - offset

        vertices.append(GridVertex(position: a, color: color))
        vertices.append(GridVertex(position: b, color: color))
        vertices.append(GridVertex(position: c, color: color))
        vertices.append(GridVertex(position: a, color: color))
        vertices.append(GridVertex(position: c, color: color))
        vertices.append(GridVertex(position: d, color: color))
    }
}
