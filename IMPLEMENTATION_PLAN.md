# VoxelEd Stage 1 Implementation Plan

## Objective

Build the first working native macOS version of VoxelEd with:

- a SwiftUI app shell
- a left sidebar for tools and a 64-slot palette
- a Metal-backed 3D viewport
- a default `16x16x16` voxel model
- a visible floor grid sized to the current model
- instanced cube rendering for filled voxels
- palette-index based coloring through a `64x1` palette texture
- orbit on `Cmd+drag`
- trackpad pan and zoom

This first stage should establish the app architecture needed for later editing, hover, picking, selection, undo, and file persistence.

## Product Direction

The app is a native desktop voxel editor, not just a model viewer. That means the first build must avoid shortcuts that would block:

- precise voxel picking
- future add/remove/paint tools
- selection overlays
- undo/redo
- model resizing within `4...32`
- save/load of voxel documents

The renderer should therefore be isolated from editing logic, and the voxel model should remain authoritative on the CPU side.

## Recommended Tech Stack

- Language: Swift
- UI: SwiftUI
- Rendering view: `MTKView` bridged into SwiftUI
- Graphics API: Metal
- Math: `simd`
- App target: macOS app

## Proposed Project Layout

Use a structure close to this from the start:

```text
VoxelEd/
  VoxelEdApp.swift
  App/
    AppState.swift
    MainWindowView.swift
  UI/
    Sidebar/
      ToolPanelView.swift
      PaletteGridView.swift
      ModelInfoView.swift
    Viewport/
      MetalViewport.swift
      ViewportInputView.swift
  Model/
    VoxelGrid.swift
    VoxelDimensions.swift
    Palette.swift
    EditorTool.swift
  Renderer/
    MetalRenderer.swift
    RenderTypes.swift
    MeshFactory.swift
    GridMesh.swift
    CameraController.swift
    PaletteTexture.swift
  Shaders/
    VoxelShaders.metal
  Resources/
    DefaultPalette.json
  Docs/
    IMPLEMENTATION_NOTES.md
```

If a single Xcode target is used initially, this can still be organized as folder groups without introducing separate modules.

## Stage 1 Deliverables

The app is considered complete for stage 1 when it does all of the following:

- launches a native macOS window
- shows a left sidebar and a large viewport
- displays 64 palette cells in an `8x8` grid
- displays tool buttons for `Add`, `Remove`, and `Paint`
- renders a floor grid matching the model width/depth
- renders a test voxel model using cube instancing
- uses a palette texture and palette indices, not per-instance RGB
- supports camera orbit using `Cmd+drag`
- supports trackpad pan and zoom

Editing tools do not need to modify voxels yet, but the tool state and app state paths should exist.

## Core Design Decisions

### 1. Voxel storage

Represent the voxel model as a fixed-size 3D grid with dimensions constrained to `4...32`.

Recommended data model:

```swift
struct VoxelDimensions {
    var width: Int
    var height: Int
    var depth: Int
}

struct Voxel {
    var paletteIndex: UInt8
}

struct VoxelGrid {
    var dimensions: VoxelDimensions
    private var cells: [Voxel?]
}
```

Notes:

- `nil` means empty
- `UInt8` is sufficient for 64 colors and maps cleanly to shader input
- flat array storage is simple, predictable, and easy to diff for undo later

Required methods:

- `func index(x:y:z:) -> Int`
- `func contains(x:y:z:) -> Bool`
- `subscript(x:y:z:) -> Voxel?`
- `mutating func fillTestBaseSquare()`
- `func filledVoxels() -> [FilledVoxelInstanceSource]`

### 2. Coordinate system

Use these conventions consistently:

- `y` is up
- each voxel occupies one world unit
- model coordinates are integer grid coordinates
- rendered voxel cubes are centered at half-unit offsets
- the model is centered in world space around its `x/z` footprint

This simplifies:

- orbit camera target placement
- grid alignment
- future hit testing and face selection

### 3. CPU-authoritative model, GPU-derived instance buffer

For stage 1 and stage 2:

- keep the voxel grid on CPU as the source of truth
- rebuild the instance buffer when the voxel model changes

Do not optimize this prematurely. At a maximum of `32^3 = 32768` voxels, a full rebuild is acceptable for early editor operations.

### 4. Palette texture rather than RGB voxel colors

Store the palette in app state and upload it to a Metal texture sized `64x1`.

Per voxel instance:

- store only position and palette index

In the fragment shader:

- sample the palette texture using the palette index

This preserves the intended color workflow and enables later palette editing without rewriting voxel color data.

## Application State Plan

Create a central observable app state for stage 1:

```swift
final class AppState: ObservableObject {
    @Published var voxelGrid: VoxelGrid
    @Published var selectedTool: EditorTool
    @Published var selectedPaletteIndex: UInt8
    @Published var palette: Palette
}
```

Keep camera state outside `AppState` unless there is a clear reason to share it with the UI. For now, the viewport can own camera state.

Future additions expected here:

- selection state
- hover state
- document metadata
- undo stack integration
- active transform mode

## UI Plan

### Main window layout

Use a two-column layout:

- left sidebar with fixed width around `240-280`
- main viewport fills the remaining space

Recommended SwiftUI composition:

- `MainWindowView`
- `ToolPanelView`
- `PaletteGridView`
- `ModelInfoView`
- `MetalViewport`

### Sidebar contents

#### Tool section

Buttons:

- `Add`
- `Remove`
- `Paint`

Stage 1 behavior:

- selection only
- visible active state
- callbacks already wired into app state

Reserve space for later tools:

- `Select`
- `Box Select`
- `Eyedropper`

#### Palette section

An `8x8` grid of swatches:

- 64 total slots
- placeholder colors for now
- selected swatch highlighted

Requirements:

- index-based selection
- no editing of colors in stage 1
- palette should come from a model object or resource file, not hardcoded directly in the shader

#### Model section

Display:

- current dimensions
- future resize hooks placeholder

This section should anticipate later controls:

- width/height/depth steppers or segmented presets
- new model/reset actions

## Rendering Plan

### Metal view integration

Bridge `MTKView` into SwiftUI with `NSViewRepresentable`.

Responsibilities of the bridge:

- create and own the `MTKView`
- connect it to `MetalRenderer`
- route mouse and gesture input to camera control code
- expose resize updates

### Renderer responsibilities

`MetalRenderer` should own:

- `MTLDevice`
- `MTLCommandQueue`
- pipeline states
- depth state
- cube vertex/index buffers
- voxel instance buffer
- grid vertex buffer
- palette texture
- uniform buffers

Public API should look roughly like:

```swift
final class MetalRenderer: NSObject, MTKViewDelegate {
    func updateVoxelGrid(_ grid: VoxelGrid)
    func updatePalette(_ palette: Palette)
    func drawableSizeDidChange(to size: CGSize)
}
```

The renderer should not decide editing behavior. It only renders the current scene state.

### Render passes

Use one render pass with separate draw calls:

1. Draw floor grid.
2. Draw instanced voxels.

That is enough for stage 1. A later overlay pass may handle:

- hover highlights
- selected voxel outlines
- gizmos

### Grid rendering

Render the grid on the ground plane:

- aligned with the voxel model footprint
- sized from current width/depth
- centered consistently with the voxel model transform

Grid requirements:

- visible but understated
- should not overpower voxel colors
- depth tested so voxels sit naturally on the plane

### Cube rendering

Use a single shared cube mesh and one instance per filled voxel.

Per-instance data should include:

- world or model position
- palette index

Suggested struct:

```swift
struct VoxelInstanceGPU {
    var position: SIMD3<Float>
    var paletteIndex: UInt32
}
```

Use `UInt32` on the GPU side for alignment simplicity even if the model stores `UInt8`.

### Shader responsibilities

Vertex shader:

- transform cube vertex by instance position
- compute world normal
- apply view-projection transform

Fragment shader:

- sample palette texture from palette index
- apply simple directional lighting

Lighting model:

- `ambient + diffuse`
- diffuse from `max(dot(normal, lightDir), 0)`

This is enough to read voxel shapes clearly without introducing complexity.

### Uniforms

Define a uniform buffer containing at least:

- view-projection matrix
- model/world offset if needed
- light direction

Future stages may add:

- hover highlight index
- selection mask flags
- overlay colors

## Camera and Input Plan

The viewport should own a dedicated camera controller object.

### Camera state

Recommended camera parameters:

- orbit target
- yaw
- pitch
- distance
- pan offset

Derived each frame:

- camera position
- view matrix
- projection matrix

### Input behaviors

Stage 1 interactions:

- `Cmd+drag`: orbit
- trackpad pinch: zoom
- trackpad pan / scroll gesture: pan target

Implementation guidance:

- handle input at the `NSView` layer, not pure SwiftUI gesture modifiers
- use event-based camera manipulation for predictable macOS behavior

Constraints:

- clamp pitch to avoid camera flipping
- clamp distance to sensible min/max
- scale pan and zoom sensitivity relative to model size

### Why this matters for later editing

The camera controller must be reusable by:

- ray generation from cursor position
- voxel hover hit tests
- face targeting for add/remove
- framing the model after resize

Do not bury view/projection matrix computation deep inside shader-only setup. Keep it accessible to interaction code.

## Test Scene Plan

Create a default voxel grid:

- dimensions `16x16x16`
- fill a square patch on `y = 0`

A concrete first fill pattern:

- fill `x = 4...11`
- fill `z = 4...11`
- set all filled voxels to a placeholder palette index such as `8`

That produces:

- a readable instancing test
- a clear relationship between grid and voxel model
- a useful camera target at startup

## Concrete Milestones

### Milestone 1: Project bootstrap

Create the Xcode project and basic app shell.

Tasks:

- create macOS SwiftUI app target
- add folder groups matching the structure above
- verify the app launches to a blank split layout

Acceptance:

- app builds
- window opens
- sidebar and empty viewport region are visible

### Milestone 2: Domain model and state

Implement the core editor data types.

Tasks:

- add `VoxelDimensions`
- add `VoxelGrid`
- add `Palette`
- add `EditorTool`
- add `AppState`
- generate a default `16x16x16` test model

Acceptance:

- app state initializes without renderer involvement
- filled voxel count is correct for the test scene

### Milestone 3: Sidebar UI

Build the left panel.

Tasks:

- tool button list with selected state
- 64-swatch palette grid
- model size display

Acceptance:

- tool selection updates app state
- palette selection updates app state
- layout is usable and visually stable

### Milestone 4: Metal integration

Bring up the viewport and renderer.

Tasks:

- create `MTKView` bridge
- initialize Metal device and command queue
- configure render pass and depth state

Acceptance:

- viewport clears every frame
- resizing works without errors

### Milestone 5: Grid rendering

Render the model-aligned floor grid.

Tasks:

- generate grid line vertices from model dimensions
- define grid shader path or shared simple shader path
- center grid under the model

Acceptance:

- visible grid sized to `16x16`
- camera view shows the grid clearly

### Milestone 6: Instanced voxel rendering

Draw the test voxel model.

Tasks:

- build cube mesh buffers
- define instance buffer type
- generate instance data from filled voxels
- submit instanced draw call

Acceptance:

- visible cube instances in the expected floor patch
- positions align to the grid

### Milestone 7: Palette texture pipeline

Switch voxel color source to indexed palette rendering.

Tasks:

- define placeholder 64-color palette
- upload `64x1` Metal texture
- pass palette index via instance buffer
- sample texture in fragment shader

Acceptance:

- rendered voxels use palette color from index
- changing the selected placeholder palette asset changes render colors correctly

### Milestone 8: Camera controls

Implement orbit, pan, and zoom.

Tasks:

- add camera controller
- add `Cmd+drag` orbit
- add trackpad pan
- add trackpad pinch zoom
- clamp movement limits

Acceptance:

- orbit is stable and intuitive
- pan/zoom work on a Mac trackpad
- model remains easy to inspect from all useful angles

### Milestone 9: Integration cleanup

Harden the initial build for the next feature stage.

Tasks:

- make renderer update cleanly when voxel grid changes
- make palette update cleanly when palette changes
- document coordinate and buffer conventions
- remove temporary debug code

Acceptance:

- stage 1 feature set is stable
- code is ready for picking and editing work

## File-by-File Build Plan

### `/VoxelEdApp.swift`

Responsibilities:

- create `AppState`
- launch main window
- host `MainWindowView`

### `/App/AppState.swift`

Responsibilities:

- observable editor-wide UI state
- hold voxel grid, palette, selected tool, selected swatch

### `/App/MainWindowView.swift`

Responsibilities:

- compose sidebar and viewport
- provide app state to child views

### `/Model/VoxelDimensions.swift`

Responsibilities:

- dimension validation
- clamping to `4...32`

### `/Model/VoxelGrid.swift`

Responsibilities:

- voxel storage
- indexing helpers
- test scene generation
- enumeration of filled voxels for rendering

### `/Model/Palette.swift`

Responsibilities:

- define 64 colors
- expose GPU upload format

### `/Model/EditorTool.swift`

Responsibilities:

- enumerate current tool set
- support future extension

### `/UI/Sidebar/ToolPanelView.swift`

Responsibilities:

- render tool buttons
- bind tool selection

### `/UI/Sidebar/PaletteGridView.swift`

Responsibilities:

- render `8x8` swatch grid
- bind selected palette index

### `/UI/Sidebar/ModelInfoView.swift`

Responsibilities:

- show current dimensions
- reserve future resize area

### `/UI/Viewport/MetalViewport.swift`

Responsibilities:

- SwiftUI bridge for the viewport
- connect `AppState` to renderer updates

### `/UI/Viewport/ViewportInputView.swift`

Responsibilities:

- custom `NSView` or `MTKView` subclass for event handling
- route mouse and gesture input to the camera controller

### `/Renderer/MetalRenderer.swift`

Responsibilities:

- setup Metal
- manage draw lifecycle
- own buffers/textures/pipelines
- render grid and voxels

### `/Renderer/RenderTypes.swift`

Responsibilities:

- define Swift/Metal shared-compatible structs
- document alignment assumptions

### `/Renderer/MeshFactory.swift`

Responsibilities:

- generate cube mesh vertex/index data

### `/Renderer/GridMesh.swift`

Responsibilities:

- generate line geometry for the floor grid based on dimensions

### `/Renderer/CameraController.swift`

Responsibilities:

- orbit/pan/zoom state
- generate view/projection matrices
- expose ray-generation hooks later

### `/Renderer/PaletteTexture.swift`

Responsibilities:

- convert palette model to `64x1` Metal texture

### `/Shaders/VoxelShaders.metal`

Responsibilities:

- grid shaders or shared simple-color path
- voxel vertex shader
- voxel fragment shader
- palette sampling and simple lighting

## Acceptance Criteria For Stage 1

The stage is done when all of these are true:

- the app builds and runs locally on macOS
- the UI layout matches the intended editor shell
- the test `16x16x16` scene appears correctly
- the floor grid size matches model dimensions
- voxels are rendered as instanced cubes
- color comes from palette lookup via texture
- camera orbit uses `Cmd+drag`
- pan and zoom work with a trackpad
- code structure clearly separates UI, model, renderer, and interaction concerns

## Stage 2 Preview

Once stage 1 is complete, the next implementation stage should focus on actual editing.

Priority order:

1. cursor ray generation from viewport coordinates
2. voxel hit testing and visible-face targeting
3. click-to-add, click-to-remove, and click-to-paint
4. hover preview and selection highlight
5. undo/redo command stack
6. model resize controls within `4...32`

## Stage 3 Preview

After direct editing works:

1. selection tools
2. box selection and multi-voxel operations
3. fill and eyedropper
4. document save/load
5. palette import/edit support
6. performance cleanup if needed

## Key Risks And Mitigations

### Risk: Input handling in SwiftUI is too limited for precise viewport control

Mitigation:

- handle interaction in the AppKit/`MTKView` layer

### Risk: coordinate mismatches between grid, voxel model, and camera

Mitigation:

- define and document world/model alignment once
- keep all transforms in one place

### Risk: Swift/Metal buffer alignment bugs

Mitigation:

- use explicit GPU structs
- keep shared data layouts simple and padded where necessary

### Risk: early renderer shortcuts block later selection/editing

Mitigation:

- keep the voxel grid CPU-authoritative
- keep camera math accessible outside draw code
- preserve clear seams for raycasting and hover logic

## Suggested First Build Sequence

Follow this order during implementation:

1. bootstrap the macOS SwiftUI app
2. build `AppState`, `VoxelGrid`, and `Palette`
3. build sidebar UI with tool and swatch selection
4. integrate `MTKView`
5. render clear color and then floor grid
6. render instanced cubes from test voxel data
7. add palette texture lookup in the shader
8. add camera controller and input handling
9. refactor and document seams needed for stage 2 editing

## Notes For Future Me

- Do not hardcode RGB values into voxel instance data.
- Do not put editing rules directly into `MetalRenderer`.
- Do not make picking depend on ad hoc render-only transforms.
- Prefer simple, explicit types over clever abstractions for the first working build.
