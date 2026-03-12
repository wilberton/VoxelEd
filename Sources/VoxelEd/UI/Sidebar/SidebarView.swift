import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingResizeSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FilePanelView(
                    hasUnsavedChanges: appState.hasUnsavedChanges,
                    currentFileName: appState.currentFileURL?.lastPathComponent ?? "Untitled",
                    onLoad: appState.requestOpenDocument,
                    onSave: appState.requestSaveDocument,
                    onSaveAs: appState.requestSaveDocumentAs,
                    onNew: appState.requestNewDocument
                )

                PaletteGridView(
                    palette: appState.palette,
                    onSelectPreset: { presetID in
                        guard let preset = PalettePreset.builtIn.first(where: { $0.id == presetID }) else {
                            return
                        }
                        appState.applyPalette(preset.palette)
                    },
                    onLoadPalette: handleLoadPaletteTapped,
                    onPreviewPaletteColor: appState.previewPaletteColor,
                    onRestorePalette: appState.restorePalette,
                    onCommitPaletteChange: appState.commitPaletteChange,
                    selectedPaletteIndex: $appState.selectedPaletteIndex
                )

                ToolPanelView(
                    selectedTool: $appState.selectedTool,
                    isXSymmetryEnabled: $appState.isXSymmetryEnabled,
                    onClear: {
                        appState.applyGridChange(appState.voxelGrid.cleared())
                        appState.cubeToolState = nil
                    },
                    onFlipX: appState.flipCurrentFrameX,
                    onRotate90: appState.rotateCurrentFrame90,
                    onCull: appState.cullAllFrames,
                    onCrop: appState.cropAllFrames,
                    onResize: { showingResizeSheet = true }
                )

                AnimationPanelView(
                    frameCount: appState.frameCount,
                    currentFrameIndex: appState.currentFrameIndex,
                    isPlaying: appState.isPlaying,
                    animations: appState.animations,
                    selectedAnimationIndex: appState.selectedAnimationIndex,
                    onTogglePlayback: appState.togglePlayback,
                    onSelectFrame: appState.selectFrame,
                    onAddFrame: appState.addFrame,
                    onDeleteFrame: appState.deleteCurrentFrame,
                    onDuplicateFrame: appState.duplicateCurrentFrame,
                    onAddAnimation: appState.addAnimation,
                    onDeleteAnimation: appState.deleteSelectedAnimation,
                    onDuplicateAnimation: appState.duplicateSelectedAnimation,
                    onSelectAnimation: appState.selectAnimation,
                    onRenameAnimation: appState.renameSelectedAnimation,
                    onSetAnimationFPS: appState.setSelectedAnimationFPS,
                    onAppendCurrentFrameToAnimation: appState.appendCurrentFrameToSelectedAnimation,
                    onSelectAnimationSequenceFrame: appState.selectAnimationSequenceFrame,
                    onRemoveAnimationSequenceFrame: appState.removeFrameFromSelectedAnimation
                )

                ModelInfoView(
                    dimensions: appState.voxelGrid.dimensions,
                    filledVoxelCount: appState.voxelGrid.filledVoxelCount,
                    frameCount: appState.frameCount,
                    animationCount: appState.animationCount,
                    estimatedFileSizeBytes: appState.estimatedFileSizeBytes
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showingResizeSheet) {
            VolumeSizeSheet(
                title: "Resize Volume",
                initialDimensions: appState.voxelGrid.dimensions,
                actionLabel: "Resize",
                onConfirm: { dimensions in
                    appState.resizeAllFrames(to: dimensions)
                }
            )
        }
        .sheet(isPresented: $appState.showingNewDocumentSheet) {
            VolumeSizeSheet(
                title: "New Volume",
                initialDimensions: VoxelDimensions(width: 16, height: 16, depth: 16),
                actionLabel: "Create",
                onConfirm: { dimensions in
                    appState.newGrid(dimensions: dimensions)
                }
            )
        }
        .alert("File Error", isPresented: Binding(
            get: { appState.fileErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    appState.dismissFileError()
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.fileErrorMessage ?? "An unknown file error occurred.")
        }
    }

    private func handleLoadPaletteTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.title = "Load Palette"
        panel.message = "Choose a 64x1 PNG image to replace the current palette."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            appState.applyPalette(try Palette.loadPNG(from: url))
        } catch {
            appState.fileErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState())
}
