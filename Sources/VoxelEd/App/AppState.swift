import AppKit
import Foundation
import SwiftUI

private enum UnsavedChangesResolution {
    case save
    case discard
    case cancel
}

struct CubeToolState: Equatable, Sendable {
    var originCell: SIMD3<Int>
    var uAxis: SIMD3<Int>
    var vAxis: SIMD3<Int>
    var normalAxis: SIMD3<Int>
    var secondCorner: SIMD3<Int>?
}

private struct DocumentSnapshot: Equatable {
    var frames: [VoxelGrid]
    var palette: Palette
    var animations: [VoxelAnimation]
    var currentFrameIndex: Int
    var selectedAnimationIndex: Int?
}

@MainActor
final class AppState: ObservableObject {
    private let maxHistoryCount = 100

    private var undoStack: [DocumentSnapshot] = []
    private var redoStack: [DocumentSnapshot] = []
    private var savedReferenceFrames: [VoxelGrid]
    private var savedReferencePalette: Palette
    private var savedReferenceAnimations: [VoxelAnimation]
    private var currentFileURLStorage: URL?
    private var isApplyingSnapshot = false
    private var playbackTask: Task<Void, Never>?
    private var transientMessageTask: Task<Void, Never>?
    private var playbackSequencePosition = 0

    @Published private(set) var frames: [VoxelGrid]
    @Published var voxelGrid: VoxelGrid {
        didSet {
            guard !isApplyingSnapshot, frames.indices.contains(currentFrameIndex) else {
                return
            }
            frames[currentFrameIndex] = voxelGrid
            updateDirtyFlag()
        }
    }
    @Published var currentFrameIndex: Int {
        didSet {
            guard !isApplyingSnapshot, frames.indices.contains(currentFrameIndex) else {
                return
            }
            syncCurrentFrameToVoxelGrid()
        }
    }
    @Published var selectedTool: EditorTool
    @Published var selectedPaletteIndex: UInt8
    @Published var palette: Palette {
        didSet {
            guard !isApplyingSnapshot else {
                return
            }
            updateDirtyFlag()
        }
    }
    @Published var animations: [VoxelAnimation] {
        didSet {
            guard !isApplyingSnapshot else {
                return
            }
            updateDirtyFlag()
        }
    }
    @Published var selectedAnimationIndex: Int? {
        didSet {
            guard !isApplyingSnapshot else {
                return
            }
            syncCurrentFrameToSelectedAnimation()
            if isPlaying {
                restartPlayback()
            }
        }
    }
    @Published var cubeToolState: CubeToolState?
    @Published var isPlaying = false
    @Published var isXSymmetryEnabled = false
    @Published var edgeOpacity: Float = 0.5
    @Published private(set) var cameraResetToken = 0
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var transientMessage: String?
    @Published var showingNewDocumentSheet = false
    @Published var fileErrorMessage: String?

    init(
        voxelGrid: VoxelGrid = .makeTestModel(),
        selectedTool: EditorTool = .cube,
        selectedPaletteIndex: UInt8 = 1,
        palette: Palette = PalettePreset.defaultPreset.palette
    ) {
        self.frames = [voxelGrid]
        self.voxelGrid = voxelGrid
        self.currentFrameIndex = 0
        self.savedReferenceFrames = [voxelGrid]
        self.selectedTool = selectedTool
        self.selectedPaletteIndex = selectedPaletteIndex
        self.palette = palette
        self.savedReferencePalette = palette
        self.animations = []
        self.savedReferenceAnimations = []
        self.selectedAnimationIndex = nil
        self.currentFileURL = nil
        self.currentFileURLStorage = nil
    }

    deinit {
        playbackTask?.cancel()
    }

    var frameCount: Int {
        frames.count
    }

    var animationCount: Int {
        animations.count
    }

    var estimatedFileSizeBytes: Int {
        VoxelFileFormat.estimatedDocumentSize(frames: frames, animations: animations)
    }

    var selectedAnimation: VoxelAnimation? {
        guard let selectedAnimationIndex, animations.indices.contains(selectedAnimationIndex) else {
            return nil
        }
        return animations[selectedAnimationIndex]
    }

    func applyGridChange(_ newGrid: VoxelGrid) {
        var snapshot = currentSnapshot()
        snapshot.frames[currentFrameIndex] = newGrid
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func flipCurrentFrameX() {
        cubeToolState = nil
        applyGridChange(voxelGrid.flippedX())
    }

    func rotateCurrentFrame90() {
        cubeToolState = nil
        applyGridChange(voxelGrid.rotated90Y())
        requestCameraReset()
    }

    func shiftCurrentFrame(x dx: Int, y dy: Int, z dz: Int) {
        guard dx != 0 || dy != 0 || dz != 0 else {
            return
        }
        cubeToolState = nil
        applyGridChange(voxelGrid.shifted(x: dx, y: dy, z: dz))
    }

    func cropAllFrames() {
        cubeToolState = nil

        let combinedBounds = frames.compactMap(\.occupiedBounds).reduce(nil as VoxelBounds?) { partial, bounds in
            guard let partial else {
                return bounds
            }
            return VoxelBounds(
                min: SIMD3(
                    min(partial.min.x, bounds.min.x),
                    min(partial.min.y, bounds.min.y),
                    min(partial.min.z, bounds.min.z)
                ),
                max: SIMD3(
                    max(partial.max.x, bounds.max.x),
                    max(partial.max.y, bounds.max.y),
                    max(partial.max.z, bounds.max.z)
                )
            )
        }

        let croppedFrames = frames.map { $0.cropped(using: combinedBounds) }
        var snapshot = currentSnapshot()
        snapshot.frames = croppedFrames
        snapshot.currentFrameIndex = min(snapshot.currentFrameIndex, croppedFrames.count - 1)
        commitChange(from: currentSnapshot(), to: snapshot)
        requestCameraReset()
    }

    func cullAllFrames() {
        cubeToolState = nil

        var culledCount = 0
        let culledFrames = frames.map { frame -> VoxelGrid in
            let result = frame.culledHiddenVoxels()
            culledCount += result.culledCount
            return result.grid
        }

        if culledFrames != frames {
            var snapshot = currentSnapshot()
            snapshot.frames = culledFrames
            commitChange(from: currentSnapshot(), to: snapshot)
        }

        showTransientMessage("\(culledCount) voxel\(culledCount == 1 ? "" : "s") culled")
    }

    func setCurrentGridForGroupedEdit(_ newGrid: VoxelGrid) {
        guard frames.indices.contains(currentFrameIndex) else {
            return
        }
        voxelGrid = newGrid
    }

    func resizeAllFrames(to dimensions: VoxelDimensions) {
        cubeToolState = nil
        let resizedFrames = frames.map { $0.resized(to: dimensions) }
        var snapshot = currentSnapshot()
        snapshot.frames = resizedFrames
        commitChange(from: currentSnapshot(), to: snapshot)
        requestCameraReset()
    }

    func newGrid(dimensions: VoxelDimensions) {
        stopPlayback()
        cubeToolState = nil
        let newGrid = VoxelGrid(dimensions: dimensions)
        resetDocument(frames: [newGrid], palette: palette, animations: [], currentFrameIndex: 0, selectedAnimationIndex: nil, url: nil)
    }

    func loadDocument(frames newFrames: [VoxelGrid], palette newPalette: Palette, animations newAnimations: [VoxelAnimation], from url: URL) {
        stopPlayback()
        cubeToolState = nil
        if Int(selectedPaletteIndex) >= Palette.expectedColorCount {
            selectedPaletteIndex = 1
        }
        resetDocument(
            frames: newFrames,
            palette: newPalette,
            animations: sanitizedAnimations(newAnimations, frameCount: newFrames.count),
            currentFrameIndex: 0,
            selectedAnimationIndex: nil,
            url: url
        )
    }

    func saveCurrentDocument(to url: URL) throws {
        try VoxelFileFormat.saveDocument(frames: frames, palette: palette, animations: animations, to: url)
        markDocumentBaseline(frames: frames, palette: palette, animations: animations, url: url)
    }

    func requestNewDocument() {
        guard confirmDiscardOrSaveIfNeeded() else {
            return
        }
        showingNewDocumentSheet = true
    }

    func requestOpenDocument() {
        guard confirmDiscardOrSaveIfNeeded() else {
            return
        }

        do {
            try openDocument()
        } catch {
            presentFileError(error)
        }
    }

    func requestSaveDocument() {
        do {
            _ = try performSave()
        } catch {
            presentFileError(error)
        }
    }

    func requestSaveDocumentAs() {
        do {
            _ = try performSave(forceSaveAs: true)
        } catch {
            presentFileError(error)
        }
    }

    func confirmQuitIfNeeded() -> Bool {
        guard hasUnsavedChanges else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes before quitting?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                return try performSave()
            } catch {
                presentFileError(error)
                return false
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func dismissFileError() {
        fileErrorMessage = nil
    }

    func finalizeGroupedChange(from originalGrid: VoxelGrid) {
        var originalSnapshot = currentSnapshot()
        originalSnapshot.frames[currentFrameIndex] = originalGrid
        commitChange(from: originalSnapshot, to: currentSnapshot())
    }

    func previewPaletteColor(at index: Int, to color: PaletteColor) {
        palette = palette.replacingColor(at: index, with: color)
    }

    func applyPalette(_ newPalette: Palette) {
        var snapshot = currentSnapshot()
        snapshot.palette = newPalette
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func restorePalette(_ originalPalette: Palette) {
        palette = originalPalette
    }

    func commitPaletteChange(from originalPalette: Palette) {
        var snapshot = currentSnapshot()
        snapshot.palette = originalPalette
        commitChange(from: snapshot, to: currentSnapshot())
    }

    func selectFrame(_ index: Int) {
        guard frames.indices.contains(index) else {
            return
        }
        currentFrameIndex = index
    }

    func addFrame() {
        let newFrame = VoxelGrid(dimensions: voxelGrid.dimensions)
        var snapshot = currentSnapshot()
        snapshot.frames.append(newFrame)
        snapshot.currentFrameIndex = snapshot.frames.count - 1
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func duplicateCurrentFrame() {
        var snapshot = currentSnapshot()
        snapshot.frames.append(voxelGrid)
        snapshot.currentFrameIndex = snapshot.frames.count - 1
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func deleteCurrentFrame() {
        guard frames.count > 1 else {
            return
        }

        var snapshot = currentSnapshot()
        snapshot.frames.remove(at: currentFrameIndex)
        snapshot.currentFrameIndex = min(currentFrameIndex, snapshot.frames.count - 1)
        snapshot.animations = removeFrameIndexFromAnimations(snapshot.animations, deletedFrameIndex: currentFrameIndex)
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func addAnimation() {
        var snapshot = currentSnapshot()
        let newIndex = snapshot.animations.count
        snapshot.animations.append(VoxelAnimation(name: "Anim \(newIndex + 1)", frameIndices: [currentFrameIndex]))
        snapshot.selectedAnimationIndex = newIndex
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func duplicateSelectedAnimation() {
        guard let selectedAnimationIndex, animations.indices.contains(selectedAnimationIndex) else {
            return
        }

        var snapshot = currentSnapshot()
        var animation = snapshot.animations[selectedAnimationIndex]
        animation.id = UUID()
        animation.name += " Copy"
        snapshot.animations.insert(animation, at: selectedAnimationIndex + 1)
        snapshot.selectedAnimationIndex = selectedAnimationIndex + 1
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func deleteSelectedAnimation() {
        guard let selectedAnimationIndex, animations.indices.contains(selectedAnimationIndex) else {
            return
        }

        var snapshot = currentSnapshot()
        snapshot.animations.remove(at: selectedAnimationIndex)
        snapshot.selectedAnimationIndex = snapshot.animations.isEmpty ? nil : min(selectedAnimationIndex, snapshot.animations.count - 1)
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    func selectAnimation(_ index: Int?) {
        selectedAnimationIndex = validatedAnimationIndex(index, animations: animations)
    }

    func renameSelectedAnimation(_ name: String) {
        updateSelectedAnimation { animation in
            animation.name = String(name.prefix(31))
        }
    }

    func setSelectedAnimationFPS(_ fps: Int) {
        updateSelectedAnimation { animation in
            animation.fps = max(1, fps)
        }
        if isPlaying {
            restartPlayback()
        }
    }

    func appendCurrentFrameToSelectedAnimation() {
        updateSelectedAnimation { animation in
            guard animation.frameIndices.count < VoxelAnimation.maxFrameIndices else {
                return
            }
            animation.frameIndices.append(currentFrameIndex)
        }
    }

    func removeFrameFromSelectedAnimation(at sequenceIndex: Int) {
        updateSelectedAnimation { animation in
            guard animation.frameIndices.indices.contains(sequenceIndex) else {
                return
            }
            animation.frameIndices.remove(at: sequenceIndex)
        }
    }

    func selectAnimationSequenceFrame(at sequenceIndex: Int) {
        guard
            let selectedAnimation,
            selectedAnimation.frameIndices.indices.contains(sequenceIndex)
        else {
            return
        }
        playbackSequencePosition = sequenceIndex
        currentFrameIndex = selectedAnimation.frameIndices[sequenceIndex]
    }

    func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    func stopPlayback() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func restartPlayback() {
        stopPlayback()
        startPlayback()
    }

    func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }

        redoStack.append(currentSnapshot())
        apply(snapshot: previous)
        updateHistoryFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else {
            return
        }

        undoStack.append(currentSnapshot())
        apply(snapshot: next)
        updateHistoryFlags()
    }

    private func startPlayback() {
        if selectedAnimationIndex == nil, !animations.isEmpty {
            selectedAnimationIndex = 0
        }

        let fps = UInt64(selectedAnimation?.fps ?? VoxelAnimation.defaultFPS)
        if let selectedAnimation {
            guard !selectedAnimation.playbackFrameIndices.isEmpty else {
                return
            }
            playbackSequencePosition = max(0, selectedAnimation.playbackFrameIndices.firstIndex(of: currentFrameIndex) ?? 0)
        } else if frames.count <= 1 {
            return
        }

        stopPlayback()
        isPlaying = true
        playbackTask = Task { [weak self] in
            guard let self else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000 / fps)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard self.isPlaying else {
                        return
                    }
                    self.advancePlaybackFrame()
                }
            }
        }
    }

    private func advancePlaybackFrame() {
        if advanceSelectedAnimationPlaybackFrame() {
            return
        }

        guard !frames.isEmpty else {
            return
        }
        currentFrameIndex = (currentFrameIndex + 1) % frames.count
    }

    private func currentSnapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            frames: frames,
            palette: palette,
            animations: animations,
            currentFrameIndex: currentFrameIndex,
            selectedAnimationIndex: selectedAnimationIndex
        )
    }

    private func commitChange(from oldSnapshot: DocumentSnapshot, to newSnapshot: DocumentSnapshot) {
        guard oldSnapshot != newSnapshot else {
            return
        }

        undoStack.append(oldSnapshot)
        if undoStack.count > maxHistoryCount {
            undoStack.removeFirst(undoStack.count - maxHistoryCount)
        }

        redoStack.removeAll()
        apply(snapshot: newSnapshot)
        updateHistoryFlags()
    }

    private func apply(snapshot: DocumentSnapshot) {
        guard !snapshot.frames.isEmpty else {
            return
        }

        isApplyingSnapshot = true
        frames = snapshot.frames
        palette = snapshot.palette
        animations = snapshot.animations
        selectedAnimationIndex = validatedAnimationIndex(snapshot.selectedAnimationIndex, animations: snapshot.animations)
        currentFrameIndex = min(max(snapshot.currentFrameIndex, 0), snapshot.frames.count - 1)
        voxelGrid = snapshot.frames[currentFrameIndex]
        playbackSequencePosition = 0
        isApplyingSnapshot = false
        updateDirtyFlag()
    }

    private func syncCurrentFrameToVoxelGrid() {
        guard frames.indices.contains(currentFrameIndex) else {
            return
        }

        isApplyingSnapshot = true
        voxelGrid = frames[currentFrameIndex]
        isApplyingSnapshot = false
    }

    private func syncCurrentFrameToSelectedAnimation() {
        guard let selectedAnimation else {
            return
        }
        if let firstFrameIndex = selectedAnimation.playbackFrameIndices.first, frames.indices.contains(firstFrameIndex) {
            currentFrameIndex = firstFrameIndex
        }
    }

    private func updateHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        updateDirtyFlag()
    }

    private func requestCameraReset() {
        cameraResetToken &+= 1
    }

    private func confirmDiscardOrSaveIfNeeded() -> Bool {
        guard hasUnsavedChanges else {
            return true
        }

        switch promptForUnsavedChanges() {
        case .save:
            do {
                return try performSave()
            } catch {
                presentFileError(error)
                return false
            }
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func promptForUnsavedChanges() -> UnsavedChangesResolution {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "This volume has unsaved changes. Save before continuing, discard them, or cancel."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func markDocumentBaseline(frames: [VoxelGrid], palette: Palette, animations: [VoxelAnimation], url: URL?) {
        savedReferenceFrames = frames
        savedReferencePalette = palette
        savedReferenceAnimations = animations
        currentFileURLStorage = url
        currentFileURL = url
        updateDirtyFlag()
    }

    private func resetDocument(frames: [VoxelGrid], palette: Palette, animations: [VoxelAnimation], currentFrameIndex: Int, selectedAnimationIndex: Int?, url: URL?) {
        let resolvedAnimationIndex: Int? = {
            if let selectedAnimationIndex {
                return validatedAnimationIndex(selectedAnimationIndex, animations: animations)
            }
            return animations.isEmpty ? nil : 0
        }()

        undoStack.removeAll()
        redoStack.removeAll()
        apply(snapshot: DocumentSnapshot(
            frames: frames,
            palette: palette,
            animations: animations,
            currentFrameIndex: currentFrameIndex,
            selectedAnimationIndex: resolvedAnimationIndex
        ))
        markDocumentBaseline(frames: frames, palette: palette, animations: animations, url: url)
        updateHistoryFlags()
        requestCameraReset()
    }

    private func updateDirtyFlag() {
        hasUnsavedChanges = frames != savedReferenceFrames || palette != savedReferencePalette || animations != savedReferenceAnimations
    }

    private func validatedAnimationIndex(_ index: Int?, animations: [VoxelAnimation]) -> Int? {
        guard let index, animations.indices.contains(index) else {
            return nil
        }
        return index
    }

    private func sanitizedAnimations(_ animations: [VoxelAnimation], frameCount: Int) -> [VoxelAnimation] {
        animations.map { animation in
            var animation = animation
            animation.frameIndices = Array(
                animation.frameIndices
                    .filter { (0..<frameCount).contains($0) }
                    .prefix(VoxelAnimation.maxFrameIndices)
            )
            animation.fps = max(1, animation.fps)
            return animation
        }
    }

    private func shiftAnimationFrameIndices(in animations: [VoxelAnimation], startingAt frameIndex: Int, delta: Int) -> [VoxelAnimation] {
        animations.map { animation in
            var animation = animation
            animation.frameIndices = animation.frameIndices.map { $0 >= frameIndex ? $0 + delta : $0 }
            return animation
        }
    }

    private func removeFrameIndexFromAnimations(_ animations: [VoxelAnimation], deletedFrameIndex: Int) -> [VoxelAnimation] {
        animations.map { animation in
            var animation = animation
            animation.frameIndices = animation.frameIndices.compactMap { index in
                if index == deletedFrameIndex {
                    return nil
                }
                return index > deletedFrameIndex ? index - 1 : index
            }
            return animation
        }
    }

    private func updateSelectedAnimation(_ update: (inout VoxelAnimation) -> Void) {
        guard let selectedAnimationIndex, animations.indices.contains(selectedAnimationIndex) else {
            return
        }
        var snapshot = currentSnapshot()
        update(&snapshot.animations[selectedAnimationIndex])
        snapshot.animations = sanitizedAnimations(snapshot.animations, frameCount: snapshot.frames.count)
        commitChange(from: currentSnapshot(), to: snapshot)
    }

    private func advanceSelectedAnimationPlaybackFrame() -> Bool {
        guard let selectedAnimation else {
            return false
        }
        let indices = selectedAnimation.playbackFrameIndices
        guard !indices.isEmpty else {
            return false
        }
        playbackSequencePosition = (playbackSequencePosition + 1) % indices.count
        let nextFrame = indices[playbackSequencePosition]
        guard frames.indices.contains(nextFrame) else {
            return false
        }
        currentFrameIndex = nextFrame
        return true
    }

    @discardableResult
    private func performSave(forceSaveAs: Bool = false) throws -> Bool {
        if !forceSaveAs, let currentFileURL {
            try saveCurrentDocument(to: currentFileURL)
            return true
        }

        let panel = VoxelFileFormat.savePanel(startingAt: currentFileURL)
        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return false
        }

        let targetURL = selectedURL.pathExtension.isEmpty
            ? selectedURL.appendingPathExtension(VoxelFileFormat.extension)
            : selectedURL

        try saveCurrentDocument(to: targetURL)
        return true
    }

    private func openDocument() throws {
        let panel = VoxelFileFormat.openPanel()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let document = try VoxelFileFormat.loadDocument(from: url)
        loadDocument(frames: document.frames, palette: document.palette, animations: document.animations, from: url)
    }

    private func presentFileError(_ error: Error) {
        fileErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func showTransientMessage(_ message: String) {
        transientMessageTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            transientMessage = message
        }

        transientMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    self?.transientMessage = nil
                }
            }
        }
    }
}
