// MainWindow.swift
// vulpes-browser
//
// Main AppKit window that hosts the Metal rendering view
//
// Architecture Note:
// We use NSWindow directly (not NSWindowController) for simplicity.
// The window owns a MetalView that handles all rendering.
// Keyboard events flow: NSWindow -> MetalView -> libvulpes

import AppKit

class MainWindow: NSWindow, NSTextFieldDelegate {

    // MARK: - Properties

    // The Metal view that renders the browser content
    private var metalView: MetalView!

    // URL bar for navigation
    private var urlBar: NSTextField!

    // MARK: - Initialization

    init() {
        // Default window size - reasonable for a browser
        let contentRect = NSRect(x: 0, y: 0, width: 1200, height: 800)

        // Standard browser-like window style
        let styleMask: NSWindow.StyleMask = [
            .titled,           // Has a title bar
            .closable,         // Can be closed
            .miniaturizable,   // Can be minimized
            .resizable,        // Can be resized
        ]

        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,  // Standard double-buffered backing
            defer: false         // Create the window immediately
        )

        setupWindow()
        setupMetalView()
    }

    // MARK: - Setup

    private func setupWindow() {
        // Window title - will eventually show current page title
        title = "Vulpes"

        // Center on screen for first launch
        center()

        // Minimum size to prevent unusably small windows
        minSize = NSSize(width: 400, height: 300)

        // Enable automatic content view resizing
        contentView?.autoresizingMask = [.width, .height]

        // Modern appearance settings
        titlebarAppearsTransparent = false

        // Allow window to become key and main
        // (Important for receiving keyboard events)
        isReleasedWhenClosed = false

        // TODO: Consider fullscreen support
        // collectionBehavior = [.fullScreenPrimary]
    }

    private func setupMetalView() {
        guard let contentView = contentView else {
            fatalError("MainWindow: contentView is nil")
        }

        let urlBarHeight: CGFloat = 32

        // Create URL bar container
        let urlBarContainer = NSView(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - urlBarHeight,
            width: contentView.bounds.width,
            height: urlBarHeight
        ))
        urlBarContainer.autoresizingMask = [.width, .minYMargin]
        urlBarContainer.wantsLayer = true
        urlBarContainer.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1.0).cgColor

        // Create URL bar text field
        urlBar = NSTextField(frame: NSRect(
            x: 8,
            y: 4,
            width: contentView.bounds.width - 16,
            height: 24
        ))
        urlBar.autoresizingMask = [.width]
        urlBar.stringValue = "https://ejfox.com"
        urlBar.placeholderString = "Enter URL..."
        urlBar.bezelStyle = .roundedBezel
        urlBar.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        urlBar.focusRingType = .none
        urlBar.delegate = self
        urlBarContainer.addSubview(urlBar)

        // Create Metal view below URL bar
        metalView = MetalView(frame: NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - urlBarHeight
        ))
        metalView.autoresizingMask = [.width, .height]

        // Add views to content view
        contentView.addSubview(metalView)
        contentView.addSubview(urlBarContainer)

        // Start with URL bar focused for keyboard-first UX
        makeFirstResponder(urlBar)
    }

    // MARK: - URL Bar Actions

    func controlTextDidEndEditing(_ obj: Notification) {
        // Handle Enter key in URL bar
        guard let textField = obj.object as? NSTextField, textField == urlBar else { return }

        var url = textField.stringValue.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty {
            // Add https:// if no scheme
            if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                url = "https://" + url
            }
            urlBar.stringValue = url
            metalView.loadURL(url)
            makeFirstResponder(metalView)
        }
    }

    // MARK: - Keyboard Event Handling
    //
    // Keyboard Event Flow:
    // 1. NSWindow receives key events
    // 2. Events are dispatched to the first responder (MetalView)
    // 3. MetalView converts to libvulpes key codes
    // 4. libvulpes processes and returns render commands
    //
    // Note: For vim-style navigation, we need to handle:
    // - Regular key presses (keyDown)
    // - Key repeats (handled automatically by AppKit)
    // - Modifier keys (flagsChanged)
    // - Text input for search/command entry (insertText via NSTextInputClient)
    //
    // The MetalView should implement NSTextInputClient for proper
    // text input handling, especially for international keyboards
    // and IME support.

    override func keyDown(with event: NSEvent) {
        // Forward to first responder (MetalView)
        // Don't call super - we handle all keyboard input ourselves
        // This prevents the system beep on unhandled keys
        if let responder = firstResponder, responder !== self {
            responder.keyDown(with: event)
        }
    }

    // MARK: - Window Lifecycle

    override func close() {
        // TODO: Notify libvulpes of window close
        // This allows saving state, cleaning up resources, etc.
        super.close()
    }

    // MARK: - Future Enhancements
    //
    // TODO: Tab support
    // - NSWindow with tab group support
    // - Each tab has its own libvulpes state
    //
    // TODO: Split view support
    // - Multiple MetalViews in a single window
    // - Shared glyph atlas for efficiency
    //
    // TODO: Toolbar
    // - Address bar
    // - Back/forward buttons
    // - Minimal chrome, keyboard-driven
}
