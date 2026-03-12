import AppKit
import Foundation
import UniformTypeIdentifiers

struct LoadedVoxelDocument {
    var frames: [VoxelGrid]
    var palette: Palette
    var animations: [VoxelAnimation]
}

enum VoxelFileError: LocalizedError {
    case fileTooSmall
    case invalidMagic
    case invalidChunkHeader
    case truncatedChunk(String)
    case missingChunk(String)
    case invalidHeadChunkSize(Int)
    case invalidPaletteChunkSize(Int)
    case invalidAnimChunkSize(Int)
    case unsupportedDimensions(VoxelDimensions)
    case unsupportedFrameCount(Int)
    case unsupportedVoxelEncoding(UInt32)
    case invalidVoxelDataSize(expected: Int, actual: Int)
    case inconsistentAnimationCount(expected: Int, actual: Int)
    case inconsistentFrameDimensions

    var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "The file is too small to be a VXM model."
        case .invalidMagic:
            return "The file does not start with a valid VXM header."
        case .invalidChunkHeader:
            return "The file contains an invalid chunk header."
        case let .truncatedChunk(chunkId):
            return "The \(chunkId) chunk extends past the end of the file."
        case let .missingChunk(chunkId):
            return "The file is missing the required \(chunkId) chunk."
        case let .invalidHeadChunkSize(size):
            return "The HEAD chunk has an invalid size of \(size) bytes."
        case let .invalidPaletteChunkSize(size):
            return "The PLTE chunk has an invalid size of \(size) bytes."
        case let .invalidAnimChunkSize(size):
            return "The ANIM chunk has an invalid size of \(size) bytes."
        case let .unsupportedDimensions(dimensions):
            return "The file dimensions \(dimensions.displayString) are outside the editor's supported range of \(VoxelDimensions.minSize)-\(VoxelDimensions.maxSize) per axis."
        case let .unsupportedFrameCount(count):
            return "The file declares \(count) frames, but at least one frame is required."
        case let .unsupportedVoxelEncoding(encoding):
            return "The VOXD chunk uses unsupported encoding \(encoding)."
        case let .invalidVoxelDataSize(expected, actual):
            return "The VOXD chunk has \(actual) bytes of frame data, but \(expected) bytes were expected."
        case let .inconsistentAnimationCount(expected, actual):
            return "HEAD declares \(expected) animations, but ANIM contains \(actual)."
        case .inconsistentFrameDimensions:
            return "All frames in a VXM document must have identical dimensions."
        }
    }
}

enum VoxelFileFormat {
    private struct Chunk {
        var id: String
        var payload: Data
    }

    private struct HeaderChunk {
        var dimensions: VoxelDimensions
        var frameCount: Int
        var animationCount: Int
    }

    static let `extension` = "vxm"
    static let versionMajor: UInt16 = 1
    static let versionMinor: UInt16 = 0
    static let denseVoxelEncoding: UInt32 = 0
    static let contentType = UTType(filenameExtension: VoxelFileFormat.extension) ?? .data
    static let animationRecordSize = 104

    static func loadDocument(from url: URL) throws -> LoadedVoxelDocument {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func saveDocument(frames: [VoxelGrid], palette: Palette, animations: [VoxelAnimation], to url: URL) throws {
        let data = try encode(frames: frames, palette: palette, animations: animations)
        try data.write(to: url, options: .atomic)
    }

    static func estimatedDocumentSize(frames: [VoxelGrid], animations: [VoxelAnimation]) -> Int {
        guard let firstFrame = frames.first else {
            return 0
        }

        let chunkHeaderSize = 8
        let fileHeaderSize = 16
        let headChunkSize = chunkHeaderSize + 16
        let paletteChunkSize = chunkHeaderSize + (Palette.expectedColorCount * 3)
        let voxelChunkSize = chunkHeaderSize + 8 + (firstFrame.dimensions.voxelCount * frames.count)
        let animChunkSize = chunkHeaderSize + 4 + (animations.count * animationRecordSize)

        return fileHeaderSize + headChunkSize + paletteChunkSize + voxelChunkSize + animChunkSize
    }

    static func decode(_ data: Data) throws -> LoadedVoxelDocument {
        guard data.count >= 16 else {
            throw VoxelFileError.fileTooSmall
        }

        guard String(data: data.prefix(4), encoding: .ascii) == "VXM1" else {
            throw VoxelFileError.invalidMagic
        }

        let chunkCount = Int(readUInt32(from: data, offset: 8))
        var cursor = 16
        var chunks: [String: Data] = [:]
        chunks.reserveCapacity(chunkCount)

        for _ in 0..<chunkCount {
            guard cursor + 8 <= data.count else {
                throw VoxelFileError.invalidChunkHeader
            }

            let chunkId = String(data: data[cursor..<(cursor + 4)], encoding: .ascii) ?? "????"
            let payloadSize = Int(readUInt32(from: data, offset: cursor + 4))
            let payloadStart = cursor + 8
            let payloadEnd = payloadStart + payloadSize

            guard payloadEnd <= data.count else {
                throw VoxelFileError.truncatedChunk(chunkId)
            }

            chunks[chunkId] = Data(data[payloadStart..<payloadEnd])
            cursor = payloadEnd
        }

        guard let headData = chunks["HEAD"] else {
            throw VoxelFileError.missingChunk("HEAD")
        }
        guard let paletteData = chunks["PLTE"] else {
            throw VoxelFileError.missingChunk("PLTE")
        }
        guard let voxelData = chunks["VOXD"] else {
            throw VoxelFileError.missingChunk("VOXD")
        }

        let header = try decodeHeaderChunk(headData)
        let palette = try decodePaletteChunk(paletteData)
        let frames = try decodeVoxelChunk(voxelData, header: header)

        let animations: [VoxelAnimation]
        if let animData = chunks["ANIM"] {
            animations = try decodeAnimations(animData, frameCount: header.frameCount)
            let animationCount = animations.count
            guard animationCount == header.animationCount else {
                throw VoxelFileError.inconsistentAnimationCount(expected: header.animationCount, actual: animationCount)
            }
        } else if header.animationCount != 0 {
            throw VoxelFileError.missingChunk("ANIM")
        } else {
            animations = []
        }

        return LoadedVoxelDocument(frames: frames, palette: palette, animations: animations)
    }

    static func encode(frames: [VoxelGrid], palette: Palette, animations: [VoxelAnimation]) throws -> Data {
        guard let firstFrame = frames.first else {
            throw VoxelFileError.unsupportedFrameCount(0)
        }
        guard frames.allSatisfy({ $0.dimensions == firstFrame.dimensions }) else {
            throw VoxelFileError.inconsistentFrameDimensions
        }

        let sanitizedAnimations = animations.map { animation in
            var animation = animation
            animation.frameIndices = Array(animation.frameIndices.filter { (0..<frames.count).contains($0) }.prefix(VoxelAnimation.maxFrameIndices))
            animation.fps = max(1, animation.fps)
            return animation
        }

        let headChunk = encodeChunk(id: "HEAD", payload: encodeHeaderChunk(dimensions: firstFrame.dimensions, frameCount: frames.count, animationCount: sanitizedAnimations.count))
        let paletteChunk = encodeChunk(id: "PLTE", payload: encodePaletteChunk(palette))
        let voxelChunk = encodeChunk(id: "VOXD", payload: encodeVoxelChunk(frames))
        let animChunk = encodeChunk(id: "ANIM", payload: encodeAnimationChunk(sanitizedAnimations))
        let chunks = [headChunk, paletteChunk, voxelChunk, animChunk]

        var data = Data()
        data.append(contentsOf: Array("VXM1".utf8))
        appendUInt16(versionMajor, to: &data)
        appendUInt16(versionMinor, to: &data)
        appendUInt32(UInt32(chunks.count), to: &data)
        appendUInt32(0, to: &data)

        for chunk in chunks {
            data.append(chunk)
        }

        return data
    }

    @MainActor
    static func savePanel(startingAt url: URL?) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = url?.lastPathComponent ?? "Untitled.\(self.extension)"
        return panel
    }

    @MainActor
    static func openPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel
    }

    private static func decodeHeaderChunk(_ data: Data) throws -> HeaderChunk {
        guard data.count == 16 else {
            throw VoxelFileError.invalidHeadChunkSize(data.count)
        }

        let dimensions = VoxelDimensions(
            width: Int(readUInt16(from: data, offset: 0)),
            height: Int(readUInt16(from: data, offset: 2)),
            depth: Int(readUInt16(from: data, offset: 4))
        )

        let rawWidth = Int(readUInt16(from: data, offset: 0))
        let rawHeight = Int(readUInt16(from: data, offset: 2))
        let rawDepth = Int(readUInt16(from: data, offset: 4))
        guard dimensions.width == rawWidth, dimensions.height == rawHeight, dimensions.depth == rawDepth else {
            throw VoxelFileError.unsupportedDimensions(dimensions)
        }

        let frameCount = Int(readUInt16(from: data, offset: 6))
        guard frameCount > 0 else {
            throw VoxelFileError.unsupportedFrameCount(frameCount)
        }

        return HeaderChunk(
            dimensions: dimensions,
            frameCount: frameCount,
            animationCount: Int(readUInt16(from: data, offset: 8))
        )
    }

    private static func decodePaletteChunk(_ data: Data) throws -> Palette {
        guard data.count == Palette.expectedColorCount * 3 else {
            throw VoxelFileError.invalidPaletteChunkSize(data.count)
        }

        return Palette.fromRGBBytes(Array(data))
    }

    private static func decodeVoxelChunk(_ data: Data, header: HeaderChunk) throws -> [VoxelGrid] {
        guard data.count >= 8 else {
            throw VoxelFileError.truncatedChunk("VOXD")
        }

        let encoding = readUInt32(from: data, offset: 0)
        guard encoding == denseVoxelEncoding else {
            throw VoxelFileError.unsupportedVoxelEncoding(encoding)
        }

        let frameData = data.dropFirst(8)
        let expectedFrameSize = header.dimensions.voxelCount
        let expectedTotalSize = expectedFrameSize * header.frameCount
        guard frameData.count == expectedTotalSize else {
            throw VoxelFileError.invalidVoxelDataSize(expected: expectedTotalSize, actual: frameData.count)
        }

        var frames: [VoxelGrid] = []
        frames.reserveCapacity(header.frameCount)

        for frameIndex in 0..<header.frameCount {
            var grid = VoxelGrid(dimensions: header.dimensions)
            let frameStart = frameIndex * expectedFrameSize
            let frameBytes = Array(frameData.dropFirst(frameStart).prefix(expectedFrameSize))
            var index = 0

            for y in 0..<header.dimensions.height {
                for z in 0..<header.dimensions.depth {
                    for x in 0..<header.dimensions.width {
                        grid[x, y, z] = frameBytes[index]
                        index += 1
                    }
                }
            }

            frames.append(grid)
        }

        return frames
    }

    private static func decodeAnimations(_ data: Data, frameCount: Int) throws -> [VoxelAnimation] {
        guard data.count >= 4 else {
            throw VoxelFileError.invalidAnimChunkSize(data.count)
        }

        let animationCount = Int(readUInt16(from: data, offset: 0))
        let recordSize = animationRecordSize
        let expectedSize = 4 + (animationCount * recordSize)
        guard data.count == expectedSize else {
            throw VoxelFileError.invalidAnimChunkSize(data.count)
        }

        var animations: [VoxelAnimation] = []
        animations.reserveCapacity(animationCount)

        for animationIndex in 0..<animationCount {
            let offset = 4 + (animationIndex * recordSize)
            let nameBytes = Array(data[offset..<(offset + 32)])
            let nameTerminator = nameBytes.firstIndex(of: 0) ?? nameBytes.count
            let name = String(decoding: nameBytes.prefix(nameTerminator), as: UTF8.self)
            let fps = Int(readUInt16(from: data, offset: offset + 32))
            let sequenceCount = Int(readUInt16(from: data, offset: offset + 36))
            let clampedSequenceCount = min(sequenceCount, VoxelAnimation.maxFrameIndices)

            var frameIndices: [Int] = []
            frameIndices.reserveCapacity(clampedSequenceCount)
            for sequenceIndex in 0..<clampedSequenceCount {
                let frameIndex = Int(readUInt16(from: data, offset: offset + 40 + (sequenceIndex * 2)))
                guard (0..<frameCount).contains(frameIndex) else {
                    continue
                }
                frameIndices.append(frameIndex)
            }

            animations.append(
                VoxelAnimation(
                    name: name.isEmpty ? "Anim \(animationIndex + 1)" : name,
                    fps: fps,
                    frameIndices: frameIndices
                )
            )
        }

        return animations
    }

    private static func encodeHeaderChunk(dimensions: VoxelDimensions, frameCount: Int, animationCount: Int) -> Data {
        var data = Data()
        appendUInt16(UInt16(dimensions.width), to: &data)
        appendUInt16(UInt16(dimensions.height), to: &data)
        appendUInt16(UInt16(dimensions.depth), to: &data)
        appendUInt16(UInt16(frameCount), to: &data)
        appendUInt16(UInt16(animationCount), to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(0, to: &data)
        return data
    }

    private static func encodePaletteChunk(_ palette: Palette) -> Data {
        var data = Data()
        data.reserveCapacity(Palette.expectedColorCount * 3)

        for index in 0..<Palette.expectedColorCount {
            let (red, green, blue) = palette.rgbBytes(at: index)
            data.append(red)
            data.append(green)
            data.append(blue)
        }

        return data
    }

    private static func encodeVoxelChunk(_ frames: [VoxelGrid]) -> Data {
        var data = Data()
        appendUInt32(denseVoxelEncoding, to: &data)
        appendUInt32(0, to: &data)
        let dimensions = frames[0].dimensions
        data.reserveCapacity(8 + (dimensions.voxelCount * frames.count))

        for frame in frames {
            for y in 0..<frame.dimensions.height {
                for z in 0..<frame.dimensions.depth {
                    for x in 0..<frame.dimensions.width {
                        data.append(frame[x, y, z])
                    }
                }
            }
        }

        return data
    }

    private static func encodeAnimationChunk(_ animations: [VoxelAnimation]) -> Data {
        var data = Data()
        appendUInt16(UInt16(animations.count), to: &data)
        appendUInt16(0, to: &data)

        for animation in animations {
            let utf8Name = Array(animation.name.utf8.prefix(31))
            data.append(contentsOf: utf8Name)
            if utf8Name.count < 32 {
                data.append(contentsOf: Array(repeating: 0, count: 32 - utf8Name.count))
            }
            appendUInt16(UInt16(max(1, animation.fps)), to: &data)
            appendUInt16(0, to: &data)
            appendUInt16(UInt16(min(animation.frameIndices.count, VoxelAnimation.maxFrameIndices)), to: &data)
            appendUInt16(0, to: &data)

            for frameIndex in animation.frameIndices.prefix(VoxelAnimation.maxFrameIndices) {
                appendUInt16(UInt16(frameIndex), to: &data)
            }
            let paddingCount = VoxelAnimation.maxFrameIndices - min(animation.frameIndices.count, VoxelAnimation.maxFrameIndices)
            for _ in 0..<paddingCount {
                appendUInt16(0, to: &data)
            }
        }

        return data
    }

    private static func encodeChunk(id: String, payload: Data) -> Data {
        var data = Data()
        data.append(contentsOf: Array(id.utf8.prefix(4)))
        if id.utf8.count < 4 {
            data.append(contentsOf: Array(repeating: 0, count: 4 - id.utf8.count))
        }
        appendUInt32(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    private static func readUInt16(from data: Data, offset: Int) -> UInt16 {
        let start = data.index(data.startIndex, offsetBy: offset)
        let next = data.index(after: start)
        return UInt16(data[start]) | (UInt16(data[next]) << 8)
    }

    private static func readUInt32(from data: Data, offset: Int) -> UInt32 {
        let b0 = data.index(data.startIndex, offsetBy: offset)
        let b1 = data.index(after: b0)
        let b2 = data.index(after: b1)
        let b3 = data.index(after: b2)
        return UInt32(data[b0]) |
        (UInt32(data[b1]) << 8) |
        (UInt32(data[b2]) << 16) |
        (UInt32(data[b3]) << 24)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00ff))
        data.append(UInt8((value >> 8) & 0x00ff))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x000000ff))
        data.append(UInt8((value >> 8) & 0x000000ff))
        data.append(UInt8((value >> 16) & 0x000000ff))
        data.append(UInt8((value >> 24) & 0x000000ff))
    }
}
