import SwiftUI
import AppKit
import TapticCore

/// Handles macOS application activation and window termination lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct TapticVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .environment(\.layoutDirection, state.uiLanguage.layoutDirection)
                .frame(minWidth: 780, idealWidth: 840, minHeight: 520, idealHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Playback") {
                Button(state.t(.playTrackpadButton)) {
                    state.speakOnTrackpad()
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button(state.t(.previewButton)) {
                    state.toggleSpeakerPreview()
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button(state.t(.stopTrackpadButton)) {
                    state.stopAll()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}
