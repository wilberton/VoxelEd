import SwiftUI

struct InlineColorWheelPicker: View {
    @Binding var color: PaletteColor

    @State private var hue: Float = 0
    @State private var saturation: Float = 0
    @State private var brightness: Float = 0

    private let wheelSize: CGFloat = 180

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            wheel

            VStack(spacing: 12) {
                brightnessSlider

                RoundedRectangle(cornerRadius: 10)
                    .fill(color.swatchColor)
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
        }
        .onAppear {
            syncFromColor()
        }
    }

    private var wheel: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size * 0.5
            let indicatorRadius = CGFloat(saturation) * radius
            let angle = CGFloat(hue) * 2 * .pi
            let indicator = CGPoint(
                x: radius + cos(angle) * indicatorRadius,
                y: radius - sin(angle) * indicatorRadius
            )

            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, Color(red: 1, green: 0, blue: 1), .red]),
                            center: .center
                        )
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [.white, .white.opacity(0)]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    .blendMode(.screen)

                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .position(indicator)
                    .shadow(radius: 1)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateHueSaturation(at: value.location, in: CGSize(width: size, height: size))
                    }
            )
        }
        .frame(width: wheelSize, height: wheelSize)
    }

    private var brightnessSlider: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let y = CGFloat(1 - brightness) * height

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                PaletteColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).swatchColor,
                                .black
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)

                Capsule()
                    .fill(Color.white)
                    .frame(width: 26, height: 6)
                    .overlay(Capsule().stroke(Color.black.opacity(0.35), lineWidth: 1))
                    .offset(y: min(max(y - 3, 0), height - 6))
                    .shadow(radius: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedY = min(max(value.location.y, 0), height)
                        brightness = Float(1 - (clampedY / height))
                        pushColor()
                    }
            )
        }
        .frame(width: 28, height: wheelSize)
    }

    private func updateHueSaturation(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = location.x - center.x
        let dy = center.y - location.y
        let radius = min(size.width, size.height) * 0.5

        let distance = min(sqrt((dx * dx) + (dy * dy)), radius)
        saturation = Float(distance / radius)

        var angle = atan2(dy, dx)
        if angle < 0 {
            angle += 2 * .pi
        }
        hue = Float(angle / (2 * .pi))
        pushColor()
    }

    private func syncFromColor() {
        let hsv = color.hsvComponents
        hue = hsv.hue
        saturation = hsv.saturation
        brightness = hsv.brightness
    }

    private func pushColor() {
        color = PaletteColor(hue: hue, saturation: saturation, brightness: brightness, alpha: color.alpha)
    }
}
