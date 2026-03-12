# VoxelEd

VoxelEd is a native macOS voxel editor built with SwiftUI and Metal.

It supports palette-based voxel editing, instanced 3D preview rendering, animation frames, `.vxm` save/load, and editing tools for adding, painting, cuboids, symmetry, cropping, culling, and palette management.

## Build

```sh
swift build
```

## Run

```sh
swift run VoxelEd
```

## Project Notes

- App UI and document state live under `Sources/VoxelEd/App` and `Sources/VoxelEd/UI`
- Metal rendering lives under `Sources/VoxelEd/Renderer`
- Voxel/file format model code lives under `Sources/VoxelEd/Model`
- Built-in palette presets are sourced from `Palettes/`
