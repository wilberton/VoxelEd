# VXM Chunked Voxel Format

This document proposes the canonical single-file voxel format for the editor and game runtime.

Goals:

- single file
- exact palette-index storage
- simple C parsing
- no arbitrary small-volume limit
- no dependence on PNG or image tooling
- room for animation and future editor metadata
- compact on disk without fragile bit packing

## File Layout

The file is a sequence of:

1. fixed-size file header
2. zero or more chunks

All integer fields are little-endian.

## File Header

Offset | Size | Field | Notes
--- | --- | --- | ---
0 | 4 | magic | ASCII `"VXM1"`
4 | 2 | versionMajor | Start at `1`
6 | 2 | versionMinor | Start at `0`
8 | 4 | chunkCount | Number of chunks following the header
12 | 4 | reserved | Set to `0` for now

Header size: 16 bytes.

## Chunk Layout

Each chunk has:

Offset | Size | Field | Notes
--- | --- | --- | ---
0 | 4 | chunkId | FourCC, e.g. `"HEAD"`, `"PLTE"`
4 | 4 | chunkSize | Payload size in bytes, not including this 8-byte chunk header
8 | N | payload | Chunk-specific data

Unknown chunks should be skipped using `chunkSize`.

## Required Chunks

These chunks are required in every file:

- `HEAD`
- `PLTE`
- `VOXD`

## `HEAD` Chunk

Core sprite/model metadata.

Offset | Size | Field | Notes
--- | --- | --- | ---
0 | 2 | width | Volume width in voxels
2 | 2 | height | Volume height in voxels
4 | 2 | depth | Volume depth in voxels
6 | 2 | frameCount | Number of voxel frames
8 | 2 | animationCount | Number of animation records
10 | 2 | flags | Reserved for future use, set to `0`
12 | 4 | reserved | Set to `0`

Payload size: 16 bytes.

This removes the old 8-bit-per-axis and packed-index limits. A `32x32x32` model is valid.

## `PLTE` Chunk

Stores the palette used by the voxel data.

Payload:

- exactly 64 palette entries
- each entry is 3 bytes: `R`, `G`, `B`

Payload size: `64 * 3 = 192` bytes.

Rules:

- palette index `0` is reserved for empty voxel and its RGB value is ignored by the runtime
- palette indices `1...63` are drawable colors

If we later need alpha or material flags, those should go in a separate chunk, not by changing the meaning of the palette bytes.

## `VOXD` Chunk

Stores voxel frame data.

The payload begins with a frame table:

Offset | Size | Field | Notes
--- | --- | --- | ---
0 | 4 | encoding | `0 = dense`, `1 = sparse-diff`
4 | 4 | reserved | Set to `0`

After that, frame payloads are stored according to `encoding`.

### Dense Encoding

Recommended for the first implementation.

For each frame, store exactly:

- `width * height * depth` bytes

Each byte is a palette index:

- `0` means empty
- `1...63` mean filled voxel with that palette entry

Voxel order:

- `index = x + z * width + y * width * depth`

This matches the existing engine traversal.

Dense payload size:

- `8 + frameCount * width * height * depth`

Why this is the right default:

- trivial to read in C and Swift
- excellent input for later external compression in your packer
- no per-voxel index overhead
- no shape/index bit packing limits

### Sparse-Diff Encoding

Reserve for a later optimization if needed.

Suggested layout:

- frame 0: full dense frame
- frames 1..N: `u32 changedVoxelCount`, followed by repeated entries:
  - `u32 linearIndex`
  - `u8 paletteIndex`

This should only be used if you confirm it beats dense storage after your existing game-data packer runs.

For now, dense-only is the better choice.

## `ANIM` Chunk

Animation metadata for JS/game logic to query through the engine.

Implemented layout:

Offset | Size | Field | Notes
--- | --- | --- | ---
0 | 2 | animationCount | Must match `HEAD.animationCount`
2 | 2 | reserved | Set to `0`

Then `animationCount` animation records.

Each animation record:

Offset | Size | Field | Notes
--- | --- | --- | ---
0 | 32 | name | Null-terminated UTF-8, max 31 bytes plus terminator
32 | 2 | fps | Playback rate
34 | 2 | flags | Reserved for future use, currently `0`
36 | 2 | sequenceLength | Number of valid entries in the frame index table, max `32`
38 | 2 | reserved | Set to `0`
40 | 64 | frameIndices | 32 little-endian `u16` frame indices

Record size: 104 bytes.

Rules:

- only the first `sequenceLength` entries in `frameIndices` are used
- frame indices refer to entries in the global frame table stored in `VOXD`
- this allows multiple animations to reuse the same voxel frames in arbitrary orders

## Optional Future Chunks

- `PIVO`: pivot/origin metadata
- `NOTE`: editor notes
- `THMB`: thumbnail image
- `SHAP`: per-voxel shape stream if shaped voxels return later
- `EDTR`: editor-only state such as selections, guides, or viewport settings

These should all be optional so runtime code can ignore them safely.

## Recommended First Implementation

Write and support only:

- header
- `HEAD`
- `PLTE`
- `VOXD` with dense encoding
- `ANIM` with zero records for now

That gives:

- one file
- palette indices preserved exactly
- animation-ready structure
- easy loader implementation in both Swift and C

## Size Considerations

For a `32x32x32` frame:

- one dense frame = `32768` bytes
- 16 frames = `524288` bytes before outer game-package compression

This sounds larger than a hand-packed sparse format, but because your game data is already packed/compressed later, dense byte arrays are often a better tradeoff:

- simpler format
- faster load
- no index packing limits
- compressor sees long runs of `0` and repeated patterns clearly

The correct place to optimize size now is the outer game-data packer, not the on-disk voxel file itself.

## Decision Summary

Canonical format:

- `.vxm`
- chunked binary
- palette indices, not final colors
- dense frame storage first
- animation metadata in the same file

This should replace:

- the old packed `VX` binary voxel file
- the separate JS metadata file
