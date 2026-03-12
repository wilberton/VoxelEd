import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var orientationOverlayState = OrientationOverlayState()

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)

            ZStack {
                MetalViewport(appState: appState, orientationOverlayState: orientationOverlayState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    HStack {
                        Spacer()
                        OrientationAxesOverlay(axes: orientationOverlayState.axes)
                    }
                    Spacer()
                    if let transientMessage = appState.transientMessage {
                        Text(transientMessage)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
                            .transition(.opacity)
                            .padding(.bottom, 20)
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.35), value: appState.transientMessage)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState())
}
