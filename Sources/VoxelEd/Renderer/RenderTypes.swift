import simd

struct SceneUniforms {
    var viewProjectionMatrix: simd_float4x4
    var keyLightAndAmbient: SIMD4<Float>
    var fillLightAndIntensity: SIMD4<Float>
    var materialSettings: SIMD4<Float>
}

struct GridVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}

typealias HoverVertex = GridVertex

struct CubeVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
}

struct VoxelInstanceGPU {
    var position: SIMD3<Float>
    var paletteIndex: UInt32
}

extension simd_float4x4 {
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near

        return simd_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, -(far + near) / zRange, -1),
            SIMD4<Float>(0, 0, -(2 * far * near) / zRange, 0)
        )
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)

        return simd_float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        )
    }
}
