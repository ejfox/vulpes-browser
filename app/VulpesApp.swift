// VulpesApp.swift
// vulpes-browser
//
// SwiftUI App entry point - minimal wrapper that delegates to AppKit
//
// Architecture Note:
// We use SwiftUI's @main entry point for modern app lifecycle management,
// but immediately hand off to AppKit for the actual window management.
// This gives us the best of both worlds:
// - Modern app lifecycle (no need for AppDelegate boilerplate)
// - Full AppKit control for keyboard handling and Metal integration

import SwiftUI

@main
struct VulpesApp: App {
    // MARK: - App Delegate Adapter
    // Using NSApplicationDelegateAdaptor to bridge SwiftUI lifecycle to AppKit
    // This allows us to use AppKit's NSWindow directly while still benefiting
    // from SwiftUI's app lifecycle management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty Settings scene - we manage windows directly through AppKit
        // The main window is created in AppDelegate.applicationDidFinishLaunching
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppKit Bridge
// NSApplicationDelegate that creates and manages the main AppKit window
// This is where the real initialization happens

class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong reference to the main window to prevent deallocation
    var mainWindow: MainWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the main browser window
        // MainWindow handles its own setup including Metal view integration
        mainWindow = MainWindow()

        // Make the window visible and key
        mainWindow?.makeKeyAndOrderFront(nil)

        // Activate the app (brings to foreground)
        NSApp.activate(ignoringOtherApps: true)

        // TODO: Initialize libvulpes here
        // VulpesBridge.shared.initialize()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // TODO: Clean shutdown of libvulpes
        // VulpesBridge.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Standard macOS behavior: quit when last window closes
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Required for modern macOS - we don't use state restoration yet
        return false
    }
}
