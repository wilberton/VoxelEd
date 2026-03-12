import SwiftUI

struct PanelHelpText: View {
    let text: String
    var reservedLineCount: Int = 2

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: CGFloat(max(reservedLineCount, 1)) * 16, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
