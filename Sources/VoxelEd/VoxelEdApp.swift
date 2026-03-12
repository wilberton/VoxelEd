import AppKit
import SwiftUI

@main
struct VoxelEdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.appState = appState
                }
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About VoxelEd") {
                    appDelegate.showAboutPanel()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New") {
                    appState.requestNewDocument()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Open...") {
                    appState.requestOpenDocument()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.requestSaveDocument()
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Save As...") {
                    appState.requestSaveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!appState.canUndo)

                Button("Redo") {
                    appState.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }

            CommandMenu("Tools") {
                Button("Cube Tool") {
                    appState.selectedTool = .cube
                }
                .keyboardShortcut("q", modifiers: [])

                Button("Add Tool") {
                    appState.selectedTool = .add
                }
                .keyboardShortcut("w", modifiers: [])

                Button("Paint Tool") {
                    appState.selectedTool = .paint
                }
                .keyboardShortcut("e", modifiers: [])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let aboutDescription = "VoxelEd is a native macOS editor for building, animating, and previewing palette-based voxel models."
    private var appIconImage: NSImage?
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if
            let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
            let iconImage = NSImage(contentsOf: iconURL)
        {
            appIconImage = iconImage
            NSApp.applicationIconImage = iconImage
            NSApp.dockTile.display()

            DispatchQueue.main.async {
                NSApp.applicationIconImage = iconImage
                NSApp.dockTile.display()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState else {
            return .terminateNow
        }
        return appState.confirmQuitIfNeeded() ? .terminateNow : .terminateCancel
    }

    @MainActor
    func showAboutPanel() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationVersion: " ",
            .credits: NSAttributedString(string: aboutDescription)
        ]

        if let appIconImage {
            options[.applicationIcon] = appIconImage
        }

        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
