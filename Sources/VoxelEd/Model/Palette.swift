import SwiftUI
import AppKit

enum PaletteImportError: LocalizedError {
    case unreadableImage
    case invalidDimensions(width: Int, height: Int)
    case pixelBufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The selected file could not be read as an image."
        case let .invalidDimensions(width, height):
            return "Palette image must be exactly 64x1 pixels. Received \(width)x\(height)."
        case .pixelBufferCreationFailed:
            return "Failed to read pixel data from the palette image."
        }
    }
}

struct PaletteColor: Equatable, Sendable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    var swatchColor: Color {
        Color(
            .sRGB,
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }

    init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor, alpha: Float? = nil) {
        let rgbColor = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Float(rgbColor.redComponent)
        self.green = Float(rgbColor.greenComponent)
        self.blue = Float(rgbColor.blueComponent)
        self.alpha = alpha ?? Float(rgbColor.alphaComponent)
    }

    init(hue: Float, saturation: Float, brightness: Float, alpha: Float) {
        let color = NSColor(
            hue: CGFloat(max(0, min(1, hue))),
            saturation: CGFloat(max(0, min(1, saturation))),
            brightness: CGFloat(max(0, min(1, brightness))),
            alpha: CGFloat(max(0, min(1, alpha)))
        )
        self.init(nsColor: color, alpha: alpha)
    }

    var hsvComponents: (hue: Float, saturation: Float, brightness: Float) {
        let color = NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (Float(hue), Float(saturation), Float(brightness))
    }
}

struct Palette: Equatable, Sendable {
    static let expectedColorCount = 64

    var colors: [PaletteColor]

    init(colors: [PaletteColor]) {
        if colors.count >= Self.expectedColorCount {
            self.colors = Array(colors.prefix(Self.expectedColorCount))
        } else {
            self.colors = colors + Array(
                repeating: PaletteColor(red: 0, green: 0, blue: 0, alpha: 1),
                count: Self.expectedColorCount - colors.count
            )
        }
    }

    subscript(index: Int) -> PaletteColor {
        colors[index]
    }

    func replacingColor(at index: Int, with color: PaletteColor) -> Palette {
        guard colors.indices.contains(index) else {
            return self
        }

        var updatedColors = colors
        updatedColors[index] = color
        return Palette(colors: updatedColors)
    }

    func rgbBytes(at index: Int) -> (UInt8, UInt8, UInt8) {
        let color = colors[index]
        return (
            Self.floatToByte(color.red),
            Self.floatToByte(color.green),
            Self.floatToByte(color.blue)
        )
    }

    static func fromRGBBytes(_ bytes: [UInt8]) -> Palette {
        var colors: [PaletteColor] = []
        colors.reserveCapacity(expectedColorCount)

        for index in 0..<expectedColorCount {
            let byteIndex = index * 3
            guard byteIndex + 2 < bytes.count else {
                break
            }

            let alpha: Float = index == 0 ? 0.0 : 1.0
            colors.append(
                PaletteColor(
                    red: Float(bytes[byteIndex]) / 255.0,
                    green: Float(bytes[byteIndex + 1]) / 255.0,
                    blue: Float(bytes[byteIndex + 2]) / 255.0,
                    alpha: alpha
                )
            )
        }

        return Palette(colors: colors)
    }

    private static func floatToByte(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, Int((value * 255.0).rounded()))))
    }
}

extension Palette {
    static let placeholder = PalettePreset.defaultPreset.palette
    static func loadPNG(from url: URL) throws -> Palette {
        guard
            let image = NSImage(contentsOf: url),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw PaletteImportError.unreadableImage
        }

        guard cgImage.width == expectedColorCount, cgImage.height == 1 else {
            throw PaletteImportError.invalidDimensions(width: cgImage.width, height: cgImage.height)
        }

        let bytesPerPixel = 4
        let bytesPerRow = expectedColorCount * bytesPerPixel
        var pixels = Array(repeating: UInt8(0), count: bytesPerRow)

        guard
            let context = CGContext(
                data: &pixels,
                width: expectedColorCount,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw PaletteImportError.pixelBufferCreationFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: expectedColorCount, height: 1))

        let colors = (0..<expectedColorCount).map { index in
            let byteIndex = index * bytesPerPixel
            return PaletteColor(
                red: Float(pixels[byteIndex]) / 255.0,
                green: Float(pixels[byteIndex + 1]) / 255.0,
                blue: Float(pixels[byteIndex + 2]) / 255.0,
                alpha: index == 0 ? 0.0 : 1.0
            )
        }

        return Palette(colors: colors)
    }
}
