import SwiftUI
import simd

struct OrientationAxes: Equatable, Sendable {
    var x = SIMD2<Float>(1, 0)
    var y = SIMD2<Float>(0, -1)
    var z = SIMD2<Float>(0.7, 0.7)
}

@MainActor
final class OrientationOverlayState: ObservableObject {
    @Published var axes = OrientationAxes()
}

struct OrientationAxesOverlay: View {
    let axes: OrientationAxes

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let length = min(geometry.size.width, geometry.size.height) * 0.28

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.28))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))

                axisLine(label: "X", direction: axes.x, color: .red, center: center, length: length)
                axisLine(label: "Y", direction: axes.y, color: .green, center: center, length: length)
                axisLine(label: "Z", direction: axes.z, color: .blue, center: center, length: length)
            }
        }
        .frame(width: 92, height: 92)
        .padding(14)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func axisLine(label: String, direction: SIMD2<Float>, color: Color, center: CGPoint, length: CGFloat) -> some View {
        let end = CGPoint(
            x: center.x + CGFloat(direction.x) * length,
            y: center.y + CGFloat(direction.y) * length
        )

        Path { path in
            path.move(to: center)
            path.addLine(to: end)
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .position(
                x: center.x + CGFloat(direction.x) * (length + 10),
                y: center.y + CGFloat(direction.y) * (length + 10)
            )
    }
}
