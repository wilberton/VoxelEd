import CoreGraphics
import simd

final class CameraController {
    private let worldUp = SIMD3<Float>(0, 1, 0)
    private(set) var yaw: Float = .pi / 4
    private(set) var pitch: Float = .pi / 5
    private(set) var distance: Float = 26
    private(set) var panOffset = SIMD3<Float>(repeating: 0)
    var target = SIMD3<Float>(0, 0, 0)

    func recenter(on dimensions: VoxelDimensions) {
        target = SIMD3<Float>(0, Float(dimensions.height) * 0.5, 0)
        panOffset = .zero
    }

    func orbit(delta: CGSize) {
        yaw -= Float(delta.width) * 0.01
        pitch += Float(delta.height) * 0.01
        pitch = max(-1.2, min(1.2, pitch))
    }

    func pan(delta: CGSize) {
        let right = screenRightAxis
        let up = screenUpAxis
        panOffset += (right * Float(delta.width) * -0.015) + (up * Float(delta.height) * 0.015)
    }

    func zoom(delta: CGFloat) {
        distance += Float(delta) * 0.02
        distance = max(4, min(80, distance))
    }

    var focusPoint: SIMD3<Float> {
        target + panOffset
    }

    var cameraPosition: SIMD3<Float> {
        focusPoint + orbitOffset
    }

    func viewMatrix() -> simd_float4x4 {
        simd_float4x4.lookAt(
            eye: cameraPosition,
            center: focusPoint,
            up: worldUp
        )
    }

    func projectionMatrix(viewportSize: CGSize) -> simd_float4x4 {
        let aspect = max(Float(viewportSize.width / max(viewportSize.height, 1)), 0.1)
        return simd_float4x4.perspective(
            fovY: 50 * (.pi / 180),
            aspect: aspect,
            near: 0.1,
            far: 200
        )
    }

    func screenRay(at point: CGPoint, viewportSize: CGSize) -> Ray? {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return nil
        }

        let x = (2 * Float(point.x) / Float(viewportSize.width)) - 1
        let y = (2 * Float(point.y) / Float(viewportSize.height)) - 1
        let nearPoint = SIMD4<Float>(x, y, -1, 1)
        let farPoint = SIMD4<Float>(x, y, 1, 1)

        let inverseMatrix = simd_inverse(projectionMatrix(viewportSize: viewportSize) * viewMatrix())
        let worldNear = inverseMatrix * nearPoint
        let worldFar = inverseMatrix * farPoint

        let near3 = SIMD3<Float>(worldNear.x, worldNear.y, worldNear.z) / worldNear.w
        let far3 = SIMD3<Float>(worldFar.x, worldFar.y, worldFar.z) / worldFar.w

        return Ray(origin: near3, direction: simd_normalize(far3 - near3))
    }

    func orientationAxes() -> OrientationAxes {
        let view = viewMatrix()

        func project(_ axis: SIMD3<Float>) -> SIMD2<Float> {
            let vector = view * SIMD4<Float>(axis.x, axis.y, axis.z, 0)
            let projected = SIMD2<Float>(vector.x, -vector.y)
            let length = simd_length(projected)
            guard length > 0.0001 else {
                return SIMD2<Float>(0, 0)
            }
            return projected / length
        }

        return OrientationAxes(
            x: project(SIMD3<Float>(1, 0, 0)),
            y: project(SIMD3<Float>(0, 1, 0)),
            z: project(SIMD3<Float>(0, 0, 1))
        )
    }

    private var yawRotation: simd_quatf {
        simd_quatf(angle: yaw, axis: worldUp)
    }

    private var screenRightAxis: SIMD3<Float> {
        simd_normalize(yawRotation.act(SIMD3<Float>(1, 0, 0)))
    }

    private var orbitOffset: SIMD3<Float> {
        let cosPitch = cos(pitch)
        let x = sin(yaw) * cosPitch * distance
        let y = sin(pitch) * distance
        let z = cos(yaw) * cosPitch * distance
        return SIMD3<Float>(x, y, z)
    }

    private var viewDirection: SIMD3<Float> {
        simd_normalize(focusPoint - cameraPosition)
    }

    private var screenUpAxis: SIMD3<Float> {
        simd_normalize(simd_cross(screenRightAxis, viewDirection))
    }
}
