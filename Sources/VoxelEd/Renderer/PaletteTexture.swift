import Foundation
import Metal

enum PaletteTexture {
    static func makeTexture(device: MTLDevice, palette: Palette) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: palette.colors.count,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(palette.colors.count * 4)

        for color in palette.colors {
            bytes.append(UInt8(max(0, min(255, Int(color.red * 255)))))
            bytes.append(UInt8(max(0, min(255, Int(color.green * 255)))))
            bytes.append(UInt8(max(0, min(255, Int(color.blue * 255)))))
            bytes.append(UInt8(max(0, min(255, Int(color.alpha * 255)))))
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, palette.colors.count, 1),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: palette.colors.count * 4
        )

        return texture
    }
}
