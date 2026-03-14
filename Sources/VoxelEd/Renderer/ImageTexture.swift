import AppKit
import Metal

enum ImageTexture {
    static func makeTexture(device: MTLDevice, resource: String, extension fileExtension: String) -> MTLTexture? {
        let components = resource.split(separator: "/", omittingEmptySubsequences: true)
        let resourceName = components.last.map(String.init) ?? resource
        let subdirectory = components.dropLast().isEmpty ? nil : components.dropLast().joined(separator: "/")

        let url = Bundle.module.url(forResource: resourceName, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: resourceName, withExtension: fileExtension)
            ?? Bundle.module.url(forResource: resource, withExtension: fileExtension)

        guard
            let url,
            let image = NSImage(contentsOf: url),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard
            let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    static func makeSolidColorTexture(device: MTLDevice, color: SIMD4<UInt8>) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        var bytes = [color.x, color.y, color.z, color.w]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &bytes,
            bytesPerRow: 4
        )
        return texture
    }
}
