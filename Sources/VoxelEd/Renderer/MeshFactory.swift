import Foundation
import simd

enum MeshFactory {
    static func makeCubeVertices() -> [CubeVertex] {
        let p000 = SIMD3<Float>(0, 0, 0)
        let p100 = SIMD3<Float>(1, 0, 0)
        let p010 = SIMD3<Float>(0, 1, 0)
        let p110 = SIMD3<Float>(1, 1, 0)
        let p001 = SIMD3<Float>(0, 0, 1)
        let p101 = SIMD3<Float>(1, 0, 1)
        let p011 = SIMD3<Float>(0, 1, 1)
        let p111 = SIMD3<Float>(1, 1, 1)

        let uv00 = SIMD2<Float>(0, 0)
        let uv10 = SIMD2<Float>(1, 0)
        let uv11 = SIMD2<Float>(1, 1)
        let uv01 = SIMD2<Float>(0, 1)

        func face(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal: SIMD3<Float>) -> [CubeVertex] {
            [
                CubeVertex(position: a, normal: normal, uv: uv00),
                CubeVertex(position: b, normal: normal, uv: uv10),
                CubeVertex(position: c, normal: normal, uv: uv11),
                CubeVertex(position: a, normal: normal, uv: uv00),
                CubeVertex(position: c, normal: normal, uv: uv11),
                CubeVertex(position: d, normal: normal, uv: uv01)
            ]
        }

        return
            face(p001, p101, p111, p011, normal: SIMD3<Float>(0, 0, 1)) +
            face(p100, p000, p010, p110, normal: SIMD3<Float>(0, 0, -1)) +
            face(p000, p001, p011, p010, normal: SIMD3<Float>(-1, 0, 0)) +
            face(p101, p100, p110, p111, normal: SIMD3<Float>(1, 0, 0)) +
            face(p010, p011, p111, p110, normal: SIMD3<Float>(0, 1, 0)) +
            face(p000, p100, p101, p001, normal: SIMD3<Float>(0, -1, 0))
    }
}
