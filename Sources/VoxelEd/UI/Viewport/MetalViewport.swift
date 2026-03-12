import SwiftUI
import simd

struct MetalViewport: NSViewRepresentable {
    @ObservedObject var appState: AppState
    @ObservedObject var orientationOverlayState: OrientationOverlayState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, orientationOverlayState: orientationOverlayState)
    }

    func makeNSView(context: Context) -> ViewportInputView {
        let view = ViewportInputView(frame: .zero)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator.renderer
        view.inputHandler = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: ViewportInputView, context: Context) {
        context.coordinator.update(appState: appState)
    }

    @MainActor
    final class Coordinator: NSObject, ViewportInputHandling {
        enum CubeOperation {
            case fill
            case carve
            case paintExisting
        }

        enum PrimaryToolMode {
            case add
            case remove
            case paint
            case bucket
            case cube
        }

        private(set) var appState: AppState
        let orientationOverlayState: OrientationOverlayState
        let renderer: MetalRenderer
        weak var view: ViewportInputView?
        private var lastHoverPoint: CGPoint?
        private var groupedEditOriginalGrid: VoxelGrid?
        private var lastRay: Ray?
        private var lastModifierFlags: NSEvent.ModifierFlags = []
        private var lastCameraResetToken: Int

        init(appState: AppState, orientationOverlayState: OrientationOverlayState) {
            self.appState = appState
            self.orientationOverlayState = orientationOverlayState
            self.renderer = MetalRenderer()
            self.lastCameraResetToken = appState.cameraResetToken
        }

        func attach(to view: ViewportInputView) {
            self.view = view
            renderer.attach(to: view)
            renderer.update(appState: appState)
            renderer.cameraController.recenter(on: appState.voxelGrid.dimensions)
            updateOrientationAxes()
        }

        func update(appState: AppState) {
            self.appState = appState
            renderer.update(appState: appState)
            if appState.cameraResetToken != lastCameraResetToken {
                lastCameraResetToken = appState.cameraResetToken
                renderer.cameraController.recenter(on: appState.voxelGrid.dimensions)
            }
            updateOrientationAxes()
            refreshHover()
        }

        func viewportDidOrbit(delta: CGSize) {
            renderer.cameraController.orbit(delta: delta)
            updateOrientationAxes()
            refreshHover()
        }

        func viewportDidPan(delta: CGSize) {
            renderer.cameraController.pan(delta: delta)
            updateOrientationAxes()
            refreshHover()
        }

        func viewportDidZoom(delta: CGFloat) {
            renderer.cameraController.zoom(delta: delta)
            updateOrientationAxes()
            refreshHover()
        }

        func viewportDidShiftFrame(x: Int, y: Int, z: Int) {
            appState.shiftCurrentFrame(x: x, y: y, z: z)
            renderer.update(appState: appState)
            refreshHover()
        }

        func viewportDidHover(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
            lastHoverPoint = point
            lastModifierFlags = modifiers

            if modifiers.contains(.command) {
                lastRay = nil
                renderer.updateHover(nil, in: appState.voxelGrid)
                renderer.updateCubePreview(nil, in: appState.voxelGrid)
                renderer.updatePreviewGrid(nil)
                return
            }

            guard let view else {
                return
            }

            let viewportSize = view.bounds.size
            guard let ray = renderer.cameraController.screenRay(at: point, viewportSize: viewportSize) else {
                lastRay = nil
                renderer.updateHover(nil, in: appState.voxelGrid)
                renderer.updateCubePreview(nil, in: appState.voxelGrid)
                renderer.updatePreviewGrid(nil)
                return
            }
            lastRay = ray

            let includeGround = appState.selectedTool == .add || appState.selectedTool == .cube || appState.cubeToolState != nil
            let hover = appState.voxelGrid.raycast(ray, includeGround: includeGround)?.target
            updateCubePreview(with: hover, ray: ray, modifiers: modifiers)

            if let cubeToolState = appState.cubeToolState, appState.selectedTool == .cube {
                let handle = cubeHandle(for: cubeToolState, ray: ray, modifiers: modifiers)
                renderer.updateHoverFace(cell: handle?.cell, normal: handle?.normal, in: appState.voxelGrid)
            } else if appState.selectedTool == .add || appState.selectedTool == .paint {
                renderer.updatePreviewGrid(singleActionPreviewGrid(for: hover, modifiers: modifiers))
                renderer.updateHover(hover, in: appState.voxelGrid)
            } else {
                renderer.updatePreviewGrid(nil)
                renderer.updateHover(hover, in: appState.voxelGrid)
            }
        }

        func viewportModifiersDidChange(_ modifiers: NSEvent.ModifierFlags) {
            lastModifierFlags = modifiers
            refreshHover()
        }

        func viewportDidPrimaryDown(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
            if resolvedToolMode(for: modifiers) == .paint {
                groupedEditOriginalGrid = appState.voxelGrid
            }
        }

        func viewportDidPrimaryClick(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
            viewportDidHover(at: point, modifiers: modifiers)

            let toolMode = resolvedToolMode(for: modifiers)
            if toolMode == .cube {
                handleCubeClick(modifiers: modifiers)
                return
            }

            applyTool(toolMode, isGrouped: toolMode == .paint, modifiers: modifiers)
        }

        func viewportDidPrimaryDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
            let toolMode = resolvedToolMode(for: modifiers)
            guard toolMode == .paint else {
                return
            }
            viewportDidHover(at: point, modifiers: modifiers)
            applyTool(.paint, isGrouped: true, modifiers: modifiers)
        }

        func viewportDidPrimaryUp(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
            guard let originalGrid = groupedEditOriginalGrid else {
                return
            }

            groupedEditOriginalGrid = nil
            viewportDidHover(at: point, modifiers: modifiers)
            appState.finalizeGroupedChange(from: originalGrid)
        }

        func viewportDidCancelAction() {
            groupedEditOriginalGrid = nil
            appState.cubeToolState = nil
            renderer.updateCubePreview(nil, in: appState.voxelGrid)
            renderer.updatePreviewGrid(nil)
            refreshHover()
        }

        private func applyTool(_ toolMode: PrimaryToolMode, isGrouped: Bool, modifiers: NSEvent.ModifierFlags) {
            guard let hover = renderer.currentHover else {
                return
            }

            var updatedGrid = appState.voxelGrid
            switch toolMode {
            case .remove:
                guard let cell = hover.deleteCell else {
                    return
                }
                applySymmetricSingleCellEdit(to: &updatedGrid, cell: cell) { grid, target in
                    grid[target.x, target.y, target.z] = VoxelGrid.emptyPaletteIndex
                }

            case .add:
                if modifiers.contains(.shift) {
                    guard let cell = hover.deleteCell else {
                        return
                    }
                    let paletteIndex = updatedGrid[cell.x, cell.y, cell.z]
                    guard paletteIndex != VoxelGrid.emptyPaletteIndex else {
                        return
                    }
                    appState.selectedPaletteIndex = paletteIndex
                    refreshHover()
                    return
                }
                let target = hover.addCell
                guard appState.voxelGrid.contains(x: target.x, y: target.y, z: target.z) else {
                    return
                }
                guard appState.selectedPaletteIndex != VoxelGrid.emptyPaletteIndex else {
                    return
                }
                applySymmetricSingleCellEdit(to: &updatedGrid, cell: target) { grid, targetCell in
                    grid[targetCell.x, targetCell.y, targetCell.z] = appState.selectedPaletteIndex
                }

            case .paint:
                guard let cell = hover.deleteCell else {
                    return
                }
                if modifiers.contains(.shift) {
                    let paletteIndex = updatedGrid[cell.x, cell.y, cell.z]
                    guard paletteIndex != VoxelGrid.emptyPaletteIndex else {
                        return
                    }
                    appState.selectedPaletteIndex = paletteIndex
                    refreshHover()
                    return
                }
                guard appState.selectedPaletteIndex != VoxelGrid.emptyPaletteIndex else {
                    return
                }
                guard updatedGrid[cell.x, cell.y, cell.z] != VoxelGrid.emptyPaletteIndex else {
                    return
                }
                guard updatedGrid[cell.x, cell.y, cell.z] != appState.selectedPaletteIndex else {
                    return
                }
                applySymmetricSingleCellEdit(to: &updatedGrid, cell: cell) { grid, targetCell in
                    guard grid[targetCell.x, targetCell.y, targetCell.z] != VoxelGrid.emptyPaletteIndex else {
                        return
                    }
                    grid[targetCell.x, targetCell.y, targetCell.z] = appState.selectedPaletteIndex
                }
            case .bucket:
                guard let cell = hover.deleteCell else {
                    return
                }
                if modifiers.contains(.shift) {
                    let paletteIndex = updatedGrid[cell.x, cell.y, cell.z]
                    guard paletteIndex != VoxelGrid.emptyPaletteIndex else {
                        return
                    }
                    appState.selectedPaletteIndex = paletteIndex
                    refreshHover()
                    return
                }
                updatedGrid = applySymmetricBucketFill(to: updatedGrid, from: cell)
            case .cube:
                return
            }

            guard updatedGrid != appState.voxelGrid else {
                return
            }

            if isGrouped {
                appState.setCurrentGridForGroupedEdit(updatedGrid)
            } else {
                appState.applyGridChange(updatedGrid)
            }

            renderer.update(appState: appState)
            refreshHover()
        }

        private func resolvedToolMode(for modifiers: NSEvent.ModifierFlags) -> PrimaryToolMode {
            if appState.selectedTool == .cube {
                return .cube
            }
            if appState.selectedTool == .paint {
                if modifiers.contains(.control) {
                    return .bucket
                }
                return .paint
            }
            if modifiers.contains(.shift) {
                return .add
            }

            if modifiers.contains(.option) {
                return .remove
            }
            if modifiers.contains(.control) {
                return .paint
            }
            return .add
        }

        private func handleCubeClick(modifiers: NSEvent.ModifierFlags) {
            if modifiers.contains(.shift) {
                guard
                    let cell = renderer.currentHover?.deleteCell
                else {
                    return
                }
                let paletteIndex = appState.voxelGrid[cell.x, cell.y, cell.z]
                guard paletteIndex != VoxelGrid.emptyPaletteIndex else {
                    return
                }
                appState.selectedPaletteIndex = paletteIndex
                refreshHover()
                return
            }

            if let cubeToolState = appState.cubeToolState {
                if cubeToolState.secondCorner == nil {
                    guard let secondCorner = projectedCubePlaneCell(for: cubeToolState, ray: lastRay) else {
                        return
                    }
                    appState.cubeToolState = CubeToolState(
                        originCell: cubeToolState.originCell,
                        uAxis: cubeToolState.uAxis,
                        vAxis: cubeToolState.vAxis,
                        normalAxis: cubeToolState.normalAxis,
                        secondCorner: secondCorner
                    )
                } else {
                    finalizeCube(using: cubeToolState, modifiers: modifiers)
                }
            } else {
                guard
                    let hover = renderer.currentHover,
                    let cubeToolState = cubeToolState(for: hover)
                else {
                    return
                }
                appState.cubeToolState = cubeToolState
            }

            refreshHover()
        }

        private func finalizeCube(using cubeToolState: CubeToolState, modifiers: NSEvent.ModifierFlags) {
            guard
                cubeToolState.secondCorner != nil,
                let previewBox = cubePreviewBox(for: cubeToolState, ray: lastRay, modifiers: modifiers)
            else {
                return
            }

            let cubeOperation = cubeOperation(for: modifiers)
            guard cubeOperation == .carve || appState.selectedPaletteIndex != VoxelGrid.emptyPaletteIndex else {
                return
            }

            var grid = appState.voxelGrid
            applySymmetricBoxEdit(to: &grid, previewBox: previewBox) { targetGrid, x, y, z in
                switch cubeOperation {
                case .fill:
                    targetGrid[x, y, z] = appState.selectedPaletteIndex
                case .carve:
                    targetGrid[x, y, z] = VoxelGrid.emptyPaletteIndex
                case .paintExisting:
                    guard targetGrid[x, y, z] != VoxelGrid.emptyPaletteIndex else {
                        return
                    }
                    targetGrid[x, y, z] = appState.selectedPaletteIndex
                }
            }
            appState.applyGridChange(grid)
            appState.cubeToolState = nil
            renderer.update(appState: appState)
            renderer.updateCubePreview(nil, in: appState.voxelGrid)
            renderer.updatePreviewGrid(nil)
        }

        private func updateCubePreview(with hover: HoverTarget?, ray: Ray, modifiers: NSEvent.ModifierFlags) {
            guard let cubeToolState = appState.cubeToolState, appState.selectedTool == .cube else {
                renderer.updateCubePreview(nil, in: appState.voxelGrid)
                renderer.updatePreviewGrid(nil)
                return
            }

            let previewBox = cubePreviewBox(for: cubeToolState, ray: ray, modifiers: modifiers)
            renderer.updateCubePreview(nil, in: appState.voxelGrid)
            renderer.updatePreviewGrid(cubePreviewGrid(for: previewBox, modifiers: modifiers))
        }

        private func cubeHandle(for cubeToolState: CubeToolState, ray: Ray, modifiers: NSEvent.ModifierFlags) -> (cell: SIMD3<Int>, normal: SIMD3<Int>)? {
            let direction = extrusionDirection(for: cubeToolState, modifiers: modifiers)
            let cubeOperation = cubeOperation(for: modifiers)

            if cubeToolState.secondCorner == nil {
                guard let baseCell = projectedCubePlaneCell(for: cubeToolState, ray: ray) else {
                    return nil
                }
                let cell: SIMD3<Int> = switch cubeOperation {
                case .fill:
                    baseCell
                case .carve:
                    SIMD3(
                        baseCell.x + direction.x,
                        baseCell.y + direction.y,
                        baseCell.z + direction.z
                    )
                case .paintExisting:
                    SIMD3(
                        baseCell.x - cubeToolState.normalAxis.x,
                        baseCell.y - cubeToolState.normalAxis.y,
                        baseCell.z - cubeToolState.normalAxis.z
                    )
                }
                return (cell, direction)
            }

            guard
                let secondCorner = cubeToolState.secondCorner,
                let depth = previewExtrusionDepth(for: cubeToolState, ray: Optional(ray), modifiers: modifiers)
            else {
                return nil
            }

            let handleOffset = cubeOperation == .carve ? depth : (depth - 1)
            let cell = SIMD3(
                secondCorner.x + (direction.x * handleOffset),
                secondCorner.y + (direction.y * handleOffset),
                secondCorner.z + (direction.z * handleOffset)
            )
            return (cell, direction)
        }

        private func cubePreviewBox(for cubeToolState: CubeToolState, ray: Ray?, modifiers: NSEvent.ModifierFlags) -> CubePreviewBox? {
            let baseEnd = cubeToolState.secondCorner ?? projectedCubePlaneCell(for: cubeToolState, ray: ray) ?? cubeToolState.originCell
            let baseMin = SIMD3(
                min(cubeToolState.originCell.x, baseEnd.x),
                min(cubeToolState.originCell.y, baseEnd.y),
                min(cubeToolState.originCell.z, baseEnd.z)
            )
            let baseMax = SIMD3(
                max(cubeToolState.originCell.x, baseEnd.x),
                max(cubeToolState.originCell.y, baseEnd.y),
                max(cubeToolState.originCell.z, baseEnd.z)
            )

            guard cubeToolState.secondCorner != nil else {
                let previewBox: CubePreviewBox
                switch cubeOperation(for: modifiers) {
                case .fill:
                    previewBox = CubePreviewBox(minCell: baseMin, maxCell: baseMax)
                case .carve:
                    let direction = extrusionDirection(for: cubeToolState, modifiers: modifiers)
                    previewBox = CubePreviewBox(
                        minCell: SIMD3(
                            baseMin.x + direction.x,
                            baseMin.y + direction.y,
                            baseMin.z + direction.z
                        ),
                        maxCell: SIMD3(
                            baseMax.x + direction.x,
                            baseMax.y + direction.y,
                            baseMax.z + direction.z
                        )
                    )
                case .paintExisting:
                    previewBox = CubePreviewBox(
                        minCell: SIMD3(
                            baseMin.x - cubeToolState.normalAxis.x,
                            baseMin.y - cubeToolState.normalAxis.y,
                            baseMin.z - cubeToolState.normalAxis.z
                        ),
                        maxCell: SIMD3(
                            baseMax.x - cubeToolState.normalAxis.x,
                            baseMax.y - cubeToolState.normalAxis.y,
                            baseMax.z - cubeToolState.normalAxis.z
                        )
                    )
                }

                return CubePreviewBox(
                    minCell: SIMD3(
                        max(0, min(previewBox.minCell.x, previewBox.maxCell.x)),
                        max(0, min(previewBox.minCell.y, previewBox.maxCell.y)),
                        max(0, min(previewBox.minCell.z, previewBox.maxCell.z))
                    ),
                    maxCell: SIMD3(
                        min(appState.voxelGrid.dimensions.width - 1, max(previewBox.minCell.x, previewBox.maxCell.x)),
                        min(appState.voxelGrid.dimensions.height - 1, max(previewBox.minCell.y, previewBox.maxCell.y)),
                        min(appState.voxelGrid.dimensions.depth - 1, max(previewBox.minCell.z, previewBox.maxCell.z))
                    )
                )
            }

            let depth = previewExtrusionDepth(for: cubeToolState, ray: ray, modifiers: modifiers) ?? 1
            let normal = extrusionDirection(for: cubeToolState, modifiers: modifiers)
            let cubeOperation = cubeOperation(for: modifiers)
            let (startOffset, endOffset): (Int, Int) = switch cubeOperation {
            case .fill:
                (0, depth - 1)
            case .carve:
                (1, depth)
            case .paintExisting:
                normal == cubeToolState.normalAxis ? (-1, depth - 2) : (1, depth)
            }

            let minCell = SIMD3(
                normal.x < 0 ? baseMin.x + (endOffset * normal.x) : baseMin.x + (startOffset * normal.x),
                normal.y < 0 ? baseMin.y + (endOffset * normal.y) : baseMin.y + (startOffset * normal.y),
                normal.z < 0 ? baseMin.z + (endOffset * normal.z) : baseMin.z + (startOffset * normal.z)
            )

            let maxCell = SIMD3(
                normal.x > 0 ? baseMax.x + (endOffset * normal.x) : baseMax.x + (startOffset * normal.x),
                normal.y > 0 ? baseMax.y + (endOffset * normal.y) : baseMax.y + (startOffset * normal.y),
                normal.z > 0 ? baseMax.z + (endOffset * normal.z) : baseMax.z + (startOffset * normal.z)
            )

            return CubePreviewBox(
                minCell: SIMD3(
                    max(0, min(minCell.x, maxCell.x)),
                    max(0, min(minCell.y, maxCell.y)),
                    max(0, min(minCell.z, maxCell.z))
                ),
                maxCell: SIMD3(
                    min(appState.voxelGrid.dimensions.width - 1, max(minCell.x, maxCell.x)),
                    min(appState.voxelGrid.dimensions.height - 1, max(minCell.y, maxCell.y)),
                    min(appState.voxelGrid.dimensions.depth - 1, max(minCell.z, maxCell.z))
                )
            )
        }

        private func projectedCubePlaneCell(for cubeToolState: CubeToolState, ray: Ray?) -> SIMD3<Int>? {
            guard let ray else {
                return nil
            }

            let planeOrigin = appState.voxelGrid.worldMin(
                x: cubeToolState.originCell.x,
                y: cubeToolState.originCell.y,
                z: cubeToolState.originCell.z
            )
            let planeNormal = SIMD3<Float>(
                Float(cubeToolState.normalAxis.x),
                Float(cubeToolState.normalAxis.y),
                Float(cubeToolState.normalAxis.z)
            )

            let denominator = simd_dot(ray.direction, planeNormal)
            guard abs(denominator) > 0.0001 else {
                return nil
            }

            let distance = simd_dot(planeOrigin - ray.origin, planeNormal) / denominator
            guard distance >= 0 else {
                return nil
            }

            let point = ray.origin + (ray.direction * distance)
            let relative = point - planeOrigin

            let u = Int(floor(simd_dot(relative, SIMD3<Float>(
                Float(cubeToolState.uAxis.x),
                Float(cubeToolState.uAxis.y),
                Float(cubeToolState.uAxis.z)
            ))))
            let v = Int(floor(simd_dot(relative, SIMD3<Float>(
                Float(cubeToolState.vAxis.x),
                Float(cubeToolState.vAxis.y),
                Float(cubeToolState.vAxis.z)
            ))))

            let cell = SIMD3(
                cubeToolState.originCell.x + (cubeToolState.uAxis.x * u) + (cubeToolState.vAxis.x * v),
                cubeToolState.originCell.y + (cubeToolState.uAxis.y * u) + (cubeToolState.vAxis.y * v),
                cubeToolState.originCell.z + (cubeToolState.uAxis.z * u) + (cubeToolState.vAxis.z * v)
            )
            return SIMD3(
                min(max(cell.x, 0), appState.voxelGrid.dimensions.width - 1),
                min(max(cell.y, 0), appState.voxelGrid.dimensions.height - 1),
                min(max(cell.z, 0), appState.voxelGrid.dimensions.depth - 1)
            )
        }

        private func previewExtrusionDepth(for cubeToolState: CubeToolState, ray: Ray?, modifiers: NSEvent.ModifierFlags) -> Int? {
            guard
                let secondCorner = cubeToolState.secondCorner,
                let ray
            else {
                return nil
            }

            let anchor = appState.voxelGrid.worldMin(x: secondCorner.x, y: secondCorner.y, z: secondCorner.z)
            let direction = extrusionDirection(for: cubeToolState, modifiers: modifiers)
            let operation = cubeOperation(for: modifiers)
            let extrusionAxis = SIMD3<Float>(
                Float(direction.x),
                Float(direction.y),
                Float(direction.z)
            )

            let cameraForward = simd_normalize(renderer.cameraController.focusPoint - renderer.cameraController.cameraPosition)
            var planeNormal = cameraForward - (simd_dot(cameraForward, extrusionAxis) * extrusionAxis)
            if simd_length_squared(planeNormal) < 0.0001 {
                planeNormal = SIMD3<Float>(
                    Float(cubeToolState.uAxis.x),
                    Float(cubeToolState.uAxis.y),
                    Float(cubeToolState.uAxis.z)
                )
            } else {
                planeNormal = simd_normalize(planeNormal)
            }

            let denominator = simd_dot(ray.direction, planeNormal)
            guard abs(denominator) > 0.0001 else {
                return 1
            }

            let distance = simd_dot(anchor - ray.origin, planeNormal) / denominator
            let point = ray.origin + (ray.direction * max(distance, 0))
            let signedProjection: Float
            if operation == .paintExisting {
                let baseNormal = SIMD3<Float>(
                    Float(cubeToolState.normalAxis.x),
                    Float(cubeToolState.normalAxis.y),
                    Float(cubeToolState.normalAxis.z)
                )
                signedProjection = simd_dot(point - anchor, baseNormal)
            } else {
                signedProjection = simd_dot(point - anchor, extrusionAxis)
            }

            let rawDepth = Int(floor(max(abs(signedProjection), 0))) + 1
            let maxDepth: Int
            switch direction {
            case let normal where normal.x != 0:
                maxDepth = normal.x > 0 ? appState.voxelGrid.dimensions.width - secondCorner.x : secondCorner.x + 1
            case let normal where normal.y != 0:
                maxDepth = normal.y > 0 ? appState.voxelGrid.dimensions.height - secondCorner.y : secondCorner.y + 1
            default:
                maxDepth = direction.z > 0 ? appState.voxelGrid.dimensions.depth - secondCorner.z : secondCorner.z + 1
            }

            return max(1, min(maxDepth, rawDepth))
        }

        private func cubeOperation(for modifiers: NSEvent.ModifierFlags) -> CubeOperation {
            if modifiers.contains(.option) {
                return .carve
            }
            if modifiers.contains(.control) {
                return .paintExisting
            }
            return .fill
        }

        private func extrusionDirection(for cubeToolState: CubeToolState, modifiers: NSEvent.ModifierFlags) -> SIMD3<Int> {
            let normal = cubeToolState.normalAxis
            switch cubeOperation(for: modifiers) {
            case .carve:
                return SIMD3(-normal.x, -normal.y, -normal.z)
            case .paintExisting:
                guard let signedProjection = signedCubeProjection(for: cubeToolState, ray: lastRay) else {
                    return normal
                }
                return signedProjection < 0 ? SIMD3(-normal.x, -normal.y, -normal.z) : normal
            case .fill:
                return normal
            }
        }

        private func signedCubeProjection(for cubeToolState: CubeToolState, ray: Ray?) -> Float? {
            guard
                let secondCorner = cubeToolState.secondCorner,
                let ray
            else {
                return nil
            }

            let anchor = appState.voxelGrid.worldMin(x: secondCorner.x, y: secondCorner.y, z: secondCorner.z)
            let baseNormal = SIMD3<Float>(
                Float(cubeToolState.normalAxis.x),
                Float(cubeToolState.normalAxis.y),
                Float(cubeToolState.normalAxis.z)
            )

            let cameraForward = simd_normalize(renderer.cameraController.focusPoint - renderer.cameraController.cameraPosition)
            var planeNormal = cameraForward - (simd_dot(cameraForward, baseNormal) * baseNormal)
            if simd_length_squared(planeNormal) < 0.0001 {
                planeNormal = SIMD3<Float>(
                    Float(cubeToolState.uAxis.x),
                    Float(cubeToolState.uAxis.y),
                    Float(cubeToolState.uAxis.z)
                )
            } else {
                planeNormal = simd_normalize(planeNormal)
            }

            let denominator = simd_dot(ray.direction, planeNormal)
            guard abs(denominator) > 0.0001 else {
                return 0
            }

            let distance = simd_dot(anchor - ray.origin, planeNormal) / denominator
            let point = ray.origin + (ray.direction * max(distance, 0))
            return simd_dot(point - anchor, baseNormal)
        }

        private func cubeToolState(for hover: HoverTarget) -> CubeToolState? {
            switch hover {
            case let .ground(x, z):
                return CubeToolState(
                    originCell: SIMD3(x, 0, z),
                    uAxis: SIMD3(1, 0, 0),
                    vAxis: SIMD3(0, 0, 1),
                    normalAxis: SIMD3(0, 1, 0),
                    secondCorner: nil
                )

            case let .voxelFace(_, _, _, face):
                let startCell = hover.addCell
                guard appState.voxelGrid.contains(x: startCell.x, y: startCell.y, z: startCell.z) else {
                    return nil
                }

                let axes: (SIMD3<Int>, SIMD3<Int>, SIMD3<Int>) = switch face {
                case .up, .down:
                    (SIMD3(1, 0, 0), SIMD3(0, 0, 1), face.vector)
                case .left, .right:
                    (SIMD3(0, 1, 0), SIMD3(0, 0, 1), face.vector)
                case .front, .back:
                    (SIMD3(1, 0, 0), SIMD3(0, 1, 0), face.vector)
                }

                return CubeToolState(
                    originCell: SIMD3(startCell.x, startCell.y, startCell.z),
                    uAxis: axes.0,
                    vAxis: axes.1,
                    normalAxis: axes.2,
                    secondCorner: nil
                )
            }
        }

        private func cubePreviewGrid(for previewBox: CubePreviewBox?, modifiers: NSEvent.ModifierFlags) -> VoxelGrid? {
            guard let previewBox else {
                return nil
            }

            guard
                previewBox.minCell.x <= previewBox.maxCell.x,
                previewBox.minCell.y <= previewBox.maxCell.y,
                previewBox.minCell.z <= previewBox.maxCell.z
            else {
                return nil
            }

            let operation = cubeOperation(for: modifiers)
            guard operation == .carve || appState.selectedPaletteIndex != VoxelGrid.emptyPaletteIndex else {
                return nil
            }

            var grid = appState.voxelGrid
            applySymmetricBoxEdit(to: &grid, previewBox: previewBox) { targetGrid, x, y, z in
                switch operation {
                case .fill:
                    targetGrid[x, y, z] = appState.selectedPaletteIndex
                case .carve:
                    targetGrid[x, y, z] = VoxelGrid.emptyPaletteIndex
                case .paintExisting:
                    guard targetGrid[x, y, z] != VoxelGrid.emptyPaletteIndex else {
                        return
                    }
                    targetGrid[x, y, z] = appState.selectedPaletteIndex
                }
            }
            return grid
        }

        private func applySymmetricSingleCellEdit(
            to grid: inout VoxelGrid,
            cell: SIMD3<Int>,
            edit: (inout VoxelGrid, SIMD3<Int>) -> Void
        ) {
            edit(&grid, cell)
            guard appState.isXSymmetryEnabled, let mirroredCell = mirroredCell(for: cell), mirroredCell != cell else {
                return
            }
            edit(&grid, mirroredCell)
        }

        private func applySymmetricBoxEdit(
            to grid: inout VoxelGrid,
            previewBox: CubePreviewBox,
            edit: (inout VoxelGrid, Int, Int, Int) -> Void
        ) {
            forEachCell(in: previewBox) { x, y, z in
                edit(&grid, x, y, z)
            }

            guard appState.isXSymmetryEnabled, let mirroredBox = mirroredBox(for: previewBox) else {
                return
            }

            forEachCell(in: mirroredBox) { x, y, z in
                edit(&grid, x, y, z)
            }
        }

        private func applySymmetricBucketFill(to grid: VoxelGrid, from cell: SIMD3<Int>) -> VoxelGrid {
            var result = grid.bucketFilled(
                from: SIMD3(cell.x, cell.y, cell.z),
                replacementPaletteIndex: appState.selectedPaletteIndex
            )

            guard appState.isXSymmetryEnabled, let mirroredCell = mirroredCell(for: cell), mirroredCell != cell else {
                return result
            }

            result = result.bucketFilled(
                from: mirroredCell,
                replacementPaletteIndex: appState.selectedPaletteIndex
            )
            return result
        }

        private func mirroredCell(for cell: SIMD3<Int>) -> SIMD3<Int>? {
            let mirroredX = appState.voxelGrid.dimensions.width - 1 - cell.x
            let mirrored = SIMD3(mirroredX, cell.y, cell.z)
            return appState.voxelGrid.contains(x: mirrored.x, y: mirrored.y, z: mirrored.z) ? mirrored : nil
        }

        private func mirroredBox(for previewBox: CubePreviewBox) -> CubePreviewBox? {
            let width = appState.voxelGrid.dimensions.width
            let mirroredMinX = width - 1 - previewBox.maxCell.x
            let mirroredMaxX = width - 1 - previewBox.minCell.x
            let minX = min(mirroredMinX, mirroredMaxX)
            let maxX = max(mirroredMinX, mirroredMaxX)
            guard minX <= maxX else {
                return nil
            }
            return CubePreviewBox(
                minCell: SIMD3(minX, previewBox.minCell.y, previewBox.minCell.z),
                maxCell: SIMD3(maxX, previewBox.maxCell.y, previewBox.maxCell.z)
            )
        }

        private func forEachCell(in previewBox: CubePreviewBox, body: (Int, Int, Int) -> Void) {
            for x in previewBox.minCell.x...previewBox.maxCell.x {
                for y in previewBox.minCell.y...previewBox.maxCell.y {
                    for z in previewBox.minCell.z...previewBox.maxCell.z {
                        body(x, y, z)
                    }
                }
            }
        }

        private func singleActionPreviewGrid(for hover: HoverTarget?, modifiers: NSEvent.ModifierFlags) -> VoxelGrid? {
            guard let hover else {
                return nil
            }

            let effectiveTool = resolvedToolMode(for: modifiers)
            var grid = appState.voxelGrid

            switch effectiveTool {
            case .add:
                if modifiers.contains(.shift) {
                    return nil
                }
                let target = hover.addCell
                guard grid.contains(x: target.x, y: target.y, z: target.z) else {
                    return nil
                }
                guard appState.selectedPaletteIndex != VoxelGrid.emptyPaletteIndex else {
                    return nil
                }
                guard grid[target.x, target.y, target.z] != appState.selectedPaletteIndex else {
                    return nil
                }
                grid[target.x, target.y, target.z] = appState.selectedPaletteIndex
                return grid

            case .remove:
                guard let cell = hover.deleteCell else {
                    return nil
                }
                guard grid[cell.x, cell.y, cell.z] != VoxelGrid.emptyPaletteIndex else {
                    return nil
                }
                grid[cell.x, cell.y, cell.z] = VoxelGrid.emptyPaletteIndex
                return grid

            case .paint:
                guard let cell = hover.deleteCell else {
                    return nil
                }
                if modifiers.contains(.shift) {
                    return nil
                }
                guard appState.selectedPaletteIndex != VoxelGrid.emptyPaletteIndex else {
                    return nil
                }
                guard grid[cell.x, cell.y, cell.z] != VoxelGrid.emptyPaletteIndex else {
                    return nil
                }
                guard grid[cell.x, cell.y, cell.z] != appState.selectedPaletteIndex else {
                    return nil
                }
                grid[cell.x, cell.y, cell.z] = appState.selectedPaletteIndex
                return grid

            case .bucket:
                guard let cell = hover.deleteCell else {
                    return nil
                }
                if modifiers.contains(.shift) {
                    return nil
                }
                let preview = grid.bucketFilled(
                    from: SIMD3(cell.x, cell.y, cell.z),
                    replacementPaletteIndex: appState.selectedPaletteIndex
                )
                return preview == grid ? nil : preview

            case .cube:
                return nil
            }
        }

        private func refreshHover() {
            guard let lastHoverPoint else {
                return
            }
            viewportDidHover(at: lastHoverPoint, modifiers: lastModifierFlags)
        }

        private func updateOrientationAxes() {
            let axes = renderer.cameraController.orientationAxes()
            if orientationOverlayState.axes != axes {
                orientationOverlayState.axes = axes
            }
        }
    }
}
