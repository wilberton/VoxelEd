import MetalKit
import simd

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?
    private(set) var cameraController = CameraController()

    private let deviceInstance: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let library: MTLLibrary?
    private let depthState: MTLDepthStencilState?

    private let cubeVertexBuffer: MTLBuffer?
    private var gridVertexBuffer: MTLBuffer?
    private var axisVertexBuffer: MTLBuffer?
    private var voxelInstanceBuffer: MTLBuffer?
    private var previewVoxelInstanceBuffer: MTLBuffer?
    private var hoverVertexBuffer: MTLBuffer?
    private var previewVertexBuffer: MTLBuffer?
    private var paletteTexture: MTLTexture?
    private var faceTexture: MTLTexture?

    private let voxelPipelineState: MTLRenderPipelineState?
    private let gridPipelineState: MTLRenderPipelineState?
    private let hoverPipelineState: MTLRenderPipelineState?
    private let previewPipelineState: MTLRenderPipelineState?

    private var sceneUniforms = SceneUniforms(
        viewProjectionMatrix: matrix_identity_float4x4,
        keyLightAndAmbient: SIMD4<Float>(simd_normalize(SIMD3<Float>(0.45, 0.85, 0.3)), 0.28),
        fillLightAndIntensity: SIMD4<Float>(simd_normalize(SIMD3<Float>(-0.55, 0.35, -0.65)), 0.26),
        materialSettings: SIMD4<Float>(0.5, 0, 0, 0)
    )
    private var currentGridDimensions = VoxelDimensions(width: 16, height: 16, depth: 16)
    private var isGridVisible = true
    private var viewportSize: CGSize = .zero
    private var gridVertexCount = 0
    private var axisVertexCount = 0
    private var voxelInstanceCount = 0
    private var previewVoxelInstanceCount = 0
    private var hoverVertexCount = 0
    private var previewVertexCount = 0
    private(set) var currentHover: HoverTarget?

    private var clearColor = MTLClearColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)

    override init() {
        self.deviceInstance = MTLCreateSystemDefaultDevice()
        self.commandQueue = deviceInstance?.makeCommandQueue()
        self.library = MetalRenderer.makeLibrary(device: deviceInstance)
        self.depthState = MetalRenderer.makeDepthState(device: deviceInstance)
        self.cubeVertexBuffer = MetalRenderer.makeCubeVertexBuffer(device: deviceInstance)
        self.gridPipelineState = MetalRenderer.makeGridPipelineState(device: deviceInstance, library: library)
        self.voxelPipelineState = MetalRenderer.makeVoxelPipelineState(device: deviceInstance, library: library)
        self.hoverPipelineState = MetalRenderer.makeHoverPipelineState(device: deviceInstance, library: library)
        self.previewPipelineState = MetalRenderer.makePreviewPipelineState(device: deviceInstance, library: library)
        super.init()

        if let deviceInstance {
            faceTexture =
                ImageTexture.makeTexture(device: deviceInstance, resource: "Textures/VoxelFace", extension: "png")
                ?? ImageTexture.makeSolidColorTexture(device: deviceInstance, color: SIMD4<UInt8>(255, 255, 255, 255))
        }

        if deviceInstance == nil {
            print("MetalRenderer: no Metal device available")
        }
        if library == nil {
            print("MetalRenderer: failed to create Metal shader library")
        }
        if gridPipelineState == nil {
            print("MetalRenderer: failed to create grid pipeline state")
        }
        if voxelPipelineState == nil {
            print("MetalRenderer: failed to create voxel pipeline state")
        }
        if hoverPipelineState == nil {
            print("MetalRenderer: failed to create hover pipeline state")
        }
        if previewPipelineState == nil {
            print("MetalRenderer: failed to create preview pipeline state")
        }
    }

    func attach(to view: MTKView) {
        self.view = view
        view.device = deviceInstance
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.clearColor = clearColor
    }

    func update(appState: AppState) {
        currentGridDimensions = appState.voxelGrid.dimensions
        isGridVisible = appState.isGridVisible
        sceneUniforms.materialSettings.x = appState.edgeOpacity
        if isGridVisible {
            updateGridBuffer(for: appState.voxelGrid.dimensions, includeGrid: true, includeAxes: true)
        } else {
            gridVertexCount = 0
            gridVertexBuffer = nil
            axisVertexCount = 0
            axisVertexBuffer = nil
        }
        updateVoxelInstanceBuffer(for: appState.voxelGrid)
        paletteTexture = deviceInstance.flatMap { PaletteTexture.makeTexture(device: $0, palette: appState.palette) }
        updateHover(currentHover, in: appState.voxelGrid)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        viewportSize = view.drawableSize
        sceneUniforms.viewProjectionMatrix = cameraController.projectionMatrix(viewportSize: viewportSize) * cameraController.viewMatrix()
        if isGridVisible {
            updateGridBuffer(for: currentGridDimensions, includeGrid: true, includeAxes: true)
        }
        descriptor.colorAttachments[0].clearColor = clearColor

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.label = "Viewport Encoder"
        encoder.setDepthStencilState(depthState)

        if
            isGridVisible,
            let gridPipelineState,
            let gridVertexBuffer,
            gridVertexCount > 0
        {
            var uniforms = sceneUniforms
            encoder.setRenderPipelineState(gridPipelineState)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 1)
            encoder.setVertexBuffer(gridVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridVertexCount)
        }

        if
            let gridPipelineState,
            let axisVertexBuffer,
            axisVertexCount > 0
        {
            var uniforms = sceneUniforms
            encoder.setRenderPipelineState(gridPipelineState)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 1)
            encoder.setVertexBuffer(axisVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: axisVertexCount)
        }

        if
            let voxelPipelineState,
            let cubeVertexBuffer,
            let activeVoxelInstanceBuffer = previewVoxelInstanceBuffer ?? voxelInstanceBuffer,
            let paletteTexture,
            (previewVoxelInstanceBuffer != nil ? previewVoxelInstanceCount : voxelInstanceCount) > 0
        {
            var uniforms = sceneUniforms
            encoder.setRenderPipelineState(voxelPipelineState)
            encoder.setVertexBuffer(cubeVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(activeVoxelInstanceBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 0)
            encoder.setFragmentTexture(paletteTexture, index: 0)
            encoder.setFragmentTexture(faceTexture, index: 1)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 36,
                instanceCount: previewVoxelInstanceBuffer != nil ? previewVoxelInstanceCount : voxelInstanceCount
            )
        }

        if
            let hoverPipelineState,
            let hoverVertexBuffer,
            hoverVertexCount > 0
        {
            var uniforms = sceneUniforms
            encoder.setRenderPipelineState(hoverPipelineState)
            encoder.setVertexBuffer(hoverVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: hoverVertexCount)
        }

        if
            let previewPipelineState,
            let previewVertexBuffer,
            previewVertexCount > 0
        {
            var uniforms = sceneUniforms
            encoder.setRenderPipelineState(previewPipelineState)
            encoder.setVertexBuffer(previewVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: previewVertexCount)
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateGridBuffer(for dimensions: VoxelDimensions, includeGrid: Bool, includeAxes: Bool) {
        if includeGrid {
            let vertices = GridMesh.makeVertices(
                width: dimensions.width,
                height: dimensions.height,
                depth: dimensions.depth,
                cameraPosition: cameraController.cameraPosition,
                focusPoint: cameraController.focusPoint
            )
            gridVertexCount = vertices.count
            gridVertexBuffer = deviceInstance?.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<GridVertex>.stride * vertices.count
            )
        } else {
            gridVertexCount = 0
            gridVertexBuffer = nil
        }

        if includeAxes {
            let axisVertices = GridMesh.makeAxisVertices(
                width: dimensions.width,
                height: dimensions.height,
                depth: dimensions.depth
            )
            axisVertexCount = axisVertices.count
            axisVertexBuffer = deviceInstance?.makeBuffer(
                bytes: axisVertices,
                length: MemoryLayout<GridVertex>.stride * axisVertices.count
            )
        } else {
            axisVertexCount = 0
            axisVertexBuffer = nil
        }
    }

    private func updateVoxelInstanceBuffer(for grid: VoxelGrid) {
        let instances = grid.filledVoxels.map { voxel in
            VoxelInstanceGPU(
                position: SIMD3<Float>(
                    Float(voxel.x) + grid.sceneOffset.x,
                    Float(voxel.y),
                    Float(voxel.z) + grid.sceneOffset.z
                ),
                paletteIndex: UInt32(voxel.paletteIndex)
            )
        }

        voxelInstanceCount = instances.count
        voxelInstanceBuffer = deviceInstance?.makeBuffer(
            bytes: instances,
            length: MemoryLayout<VoxelInstanceGPU>.stride * instances.count
        )
    }

    func updateHover(_ hover: HoverTarget?, in grid: VoxelGrid) {
        currentHover = hover

        guard let hover else {
            hoverVertexCount = 0
            hoverVertexBuffer = nil
            return
        }

        let vertices = hoverVertices(for: hover, in: grid)
        hoverVertexCount = vertices.count
        hoverVertexBuffer = deviceInstance?.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<HoverVertex>.stride * vertices.count
        )
    }

    func updateHoverFace(cell: SIMD3<Int>?, normal: SIMD3<Int>?, in grid: VoxelGrid) {
        currentHover = nil

        guard let cell, let normal else {
            hoverVertexCount = 0
            hoverVertexBuffer = nil
            return
        }

        let vertices = faceVertices(for: cell, normal: normal, in: grid)
        hoverVertexCount = vertices.count
        hoverVertexBuffer = deviceInstance?.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<HoverVertex>.stride * vertices.count
        )
    }

    func updateCubePreview(_ previewBox: CubePreviewBox?, in grid: VoxelGrid) {
        guard let previewBox else {
            previewVertexCount = 0
            previewVertexBuffer = nil
            return
        }

        let minWorld = grid.worldMin(x: previewBox.minCell.x, y: previewBox.minCell.y, z: previewBox.minCell.z)
        let maxWorld = grid.worldMin(x: previewBox.maxCell.x, y: previewBox.maxCell.y, z: previewBox.maxCell.z) + SIMD3<Float>(repeating: 1)
        let epsilon: Float = 0.01

        let p000 = SIMD3(minWorld.x, minWorld.y + epsilon, minWorld.z)
        let p100 = SIMD3(maxWorld.x, minWorld.y + epsilon, minWorld.z)
        let p010 = SIMD3(minWorld.x, maxWorld.y + epsilon, minWorld.z)
        let p110 = SIMD3(maxWorld.x, maxWorld.y + epsilon, minWorld.z)
        let p001 = SIMD3(minWorld.x, minWorld.y + epsilon, maxWorld.z)
        let p101 = SIMD3(maxWorld.x, minWorld.y + epsilon, maxWorld.z)
        let p011 = SIMD3(minWorld.x, maxWorld.y + epsilon, maxWorld.z)
        let p111 = SIMD3(maxWorld.x, maxWorld.y + epsilon, maxWorld.z)

        let positions: [SIMD3<Float>] = [
            p000, p100, p100, p101, p101, p001, p001, p000,
            p010, p110, p110, p111, p111, p011, p011, p010,
            p000, p010, p100, p110, p101, p111, p001, p011
        ]

        let vertices = positions.map { HoverVertex(position: $0, color: SIMD4<Float>(1, 1, 1, 1)) }
        previewVertexCount = vertices.count
        previewVertexBuffer = deviceInstance?.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<HoverVertex>.stride * vertices.count
        )
    }

    func updatePreviewGrid(_ grid: VoxelGrid?) {
        guard let grid else {
            previewVoxelInstanceCount = 0
            previewVoxelInstanceBuffer = nil
            return
        }

        let instances = grid.filledVoxels.map { voxel in
            VoxelInstanceGPU(
                position: SIMD3<Float>(
                    Float(voxel.x) + grid.sceneOffset.x,
                    Float(voxel.y),
                    Float(voxel.z) + grid.sceneOffset.z
                ),
                paletteIndex: UInt32(voxel.paletteIndex)
            )
        }

        previewVoxelInstanceCount = instances.count
        previewVoxelInstanceBuffer = deviceInstance?.makeBuffer(
            bytes: instances,
            length: MemoryLayout<VoxelInstanceGPU>.stride * instances.count
        )
    }

    private func hoverVertices(for hover: HoverTarget, in grid: VoxelGrid) -> [HoverVertex] {
        let epsilon: Float = 0.01
        let quad: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1),
            SIMD2(0, 0), SIMD2(1, 1), SIMD2(0, 1)
        ]

        func makeFace(origin: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, normal: SIMD3<Float>) -> [HoverVertex] {
            let faceOrigin = origin + (normal * epsilon)
            return quad.map { coord in
                HoverVertex(
                    position: faceOrigin + (u * coord.x) + (v * coord.y),
                    color: SIMD4<Float>(1, 1, 1, 1)
                )
            }
        }

        switch hover {
        case let .ground(x, z):
            let origin = grid.worldMin(x: x, y: 0, z: z)
            return makeFace(
                origin: SIMD3(origin.x, 0, origin.z),
                u: SIMD3(1, 0, 0),
                v: SIMD3(0, 0, 1),
                normal: SIMD3(0, 1, 0)
            )

        case let .voxelFace(x, y, z, face):
            let minBounds = grid.worldMin(x: x, y: y, z: z)
            switch face {
            case .up:
                return makeFace(origin: minBounds + SIMD3(0, 1, 0), u: SIMD3(1, 0, 0), v: SIMD3(0, 0, 1), normal: face.normal)
            case .down:
                return makeFace(origin: minBounds, u: SIMD3(1, 0, 0), v: SIMD3(0, 0, 1), normal: face.normal)
            case .left:
                return makeFace(origin: minBounds, u: SIMD3(0, 1, 0), v: SIMD3(0, 0, 1), normal: face.normal)
            case .right:
                return makeFace(origin: minBounds + SIMD3(1, 0, 0), u: SIMD3(0, 0, 1), v: SIMD3(0, 1, 0), normal: face.normal)
            case .front:
                return makeFace(origin: minBounds + SIMD3(0, 0, 1), u: SIMD3(1, 0, 0), v: SIMD3(0, 1, 0), normal: face.normal)
            case .back:
                return makeFace(origin: minBounds, u: SIMD3(0, 1, 0), v: SIMD3(1, 0, 0), normal: face.normal)
            }
        }
    }

    private func faceVertices(for cell: SIMD3<Int>, normal: SIMD3<Int>, in grid: VoxelGrid) -> [HoverVertex] {
        switch normal {
        case SIMD3(0, 1, 0):
            return hoverVertices(for: .voxelFace(x: cell.x, y: cell.y, z: cell.z, face: .up), in: grid)
        case SIMD3(0, -1, 0):
            return hoverVertices(for: .voxelFace(x: cell.x, y: cell.y, z: cell.z, face: .down), in: grid)
        case SIMD3(-1, 0, 0):
            return hoverVertices(for: .voxelFace(x: cell.x, y: cell.y, z: cell.z, face: .left), in: grid)
        case SIMD3(1, 0, 0):
            return hoverVertices(for: .voxelFace(x: cell.x, y: cell.y, z: cell.z, face: .right), in: grid)
        case SIMD3(0, 0, -1):
            return hoverVertices(for: .voxelFace(x: cell.x, y: cell.y, z: cell.z, face: .back), in: grid)
        case SIMD3(0, 0, 1):
            return hoverVertices(for: .voxelFace(x: cell.x, y: cell.y, z: cell.z, face: .front), in: grid)
        default:
            return []
        }
    }

    private static func makeLibrary(device: MTLDevice?) -> MTLLibrary? {
        guard
            let device,
            let url = Bundle.module.url(forResource: "VoxelShaders", withExtension: "metal"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }

        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            print("MetalRenderer: shader library error: \(error)")
            return nil
        }
    }

    private static func makeDepthState(device: MTLDevice?) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.isDepthWriteEnabled = true
        descriptor.depthCompareFunction = .less
        return device?.makeDepthStencilState(descriptor: descriptor)
    }

    private static func makeCubeVertexBuffer(device: MTLDevice?) -> MTLBuffer? {
        let vertices = MeshFactory.makeCubeVertices()
        return device?.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<CubeVertex>.stride * vertices.count
        )
    }

    private static func makeGridPipelineState(device: MTLDevice?, library: MTLLibrary?) -> MTLRenderPipelineState? {
        guard
            let device,
            let library,
            let vertexFunction = library.makeFunction(name: "grid_vertex"),
            let fragmentFunction = library.makeFunction(name: "grid_fragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("MetalRenderer: grid pipeline error: \(error)")
            return nil
        }
    }

    private static func makeVoxelPipelineState(device: MTLDevice?, library: MTLLibrary?) -> MTLRenderPipelineState? {
        guard
            let device,
            let library,
            let vertexFunction = library.makeFunction(name: "voxel_vertex"),
            let fragmentFunction = library.makeFunction(name: "voxel_fragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("MetalRenderer: voxel pipeline error: \(error)")
            return nil
        }
    }

    private static func makeHoverPipelineState(device: MTLDevice?, library: MTLLibrary?) -> MTLRenderPipelineState? {
        guard
            let device,
            let library,
            let vertexFunction = library.makeFunction(name: "grid_vertex"),
            let fragmentFunction = library.makeFunction(name: "hover_fragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("MetalRenderer: hover pipeline error: \(error)")
            return nil
        }
    }

    private static func makePreviewPipelineState(device: MTLDevice?, library: MTLLibrary?) -> MTLRenderPipelineState? {
        guard
            let device,
            let library,
            let vertexFunction = library.makeFunction(name: "grid_vertex"),
            let fragmentFunction = library.makeFunction(name: "preview_fragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("MetalRenderer: preview pipeline error: \(error)")
            return nil
        }
    }
}
