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

class MainWindow: NSWindow, NSTextFieldDelegate, NSToolbarDelegate {

    // MARK: - Properties

    // The Metal view that renders the browser content
    private var metalView: MetalView!

    // URL bar for navigation
    private var urlBar: NSTextField!

    // Toolbar item identifiers
    private let urlBarItemIdentifier = NSToolbarItem.Identifier("urlBar")

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
        title = ""  // Empty title since we have URL bar

        // Center on screen for first launch
        center()

        // Minimum size to prevent unusably small windows
        minSize = NSSize(width: 400, height: 300)

        // Enable automatic content view resizing
        contentView?.autoresizingMask = [.width, .height]

        // Modern unified title bar appearance
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        styleMask.insert(.fullSizeContentView)

        // Frosted glass background (like Ghostty)
        backgroundColor = .clear
        isOpaque = false

        // Allow window to become key and main
        // (Important for receiving keyboard events)
        isReleasedWhenClosed = false

        // Set up toolbar with URL bar
        setupToolbar()

        // TODO: Consider fullscreen support
        // collectionBehavior = [.fullScreenPrimary]
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
    }

    private func setupMetalView() {
        guard let contentView = contentView else {
            fatalError("MainWindow: contentView is nil")
        }

        // Add frosted glass blur effect (like Ghostty)
        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow  // Dark frosted glass
        visualEffect.state = .active
        contentView.addSubview(visualEffect)

        // Create Metal view using full content area (toolbar is above)
        metalView = MetalView(frame: contentView.bounds)
        metalView.autoresizingMask = [.width, .height]

        // Add views to content view (Metal view on top of blur)
        contentView.addSubview(metalView)

        // Update URL bar when MetalView navigates
        metalView.onURLChange = { [weak self] url in
            self?.urlBar.stringValue = url
        }

        // Focus URL bar when Tab cycles past last link
        metalView.onRequestURLBarFocus = { [weak self] in
            self?.makeFirstResponder(self?.urlBar)
        }

        // Listen for / key to focus URL bar (vim-style)
        NotificationCenter.default.addObserver(
            forName: .focusURLBar,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.focusURLBarWithAnimation()
        }
    }

    private func focusURLBarWithAnimation() {
        // Focus and select all text
        makeFirstResponder(urlBar)
        urlBar.selectText(nil)

        // Subtle pulse animation on the URL bar
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            urlBar.animator().alphaValue = 0.7
        } completionHandler: { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.urlBar.animator().alphaValue = 1.0
            }
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == urlBarItemIdentifier {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)

            // Create URL bar
            urlBar = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
            urlBar.stringValue = "https://ejfox.com"
            urlBar.placeholderString = "Enter URL..."
            urlBar.bezelStyle = .roundedBezel
            urlBar.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            urlBar.focusRingType = .default
            urlBar.delegate = self
            urlBar.lineBreakMode = .byTruncatingTail
            urlBar.cell?.truncatesLastVisibleLine = true

            item.view = urlBar
            item.minSize = NSSize(width: 200, height: 24)
            item.maxSize = NSSize(width: 800, height: 24)

            return item
        }
        return nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, urlBarItemIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [urlBarItemIdentifier, .flexibleSpace]
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

    // Handle Tab key in URL bar to move focus to MetalView
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertTab(_:)) {
            makeFirstResponder(metalView)
            metalView.focusFirstLink()
            return true
        }
        if commandSelector == #selector(insertBacktab(_:)) {
            makeFirstResponder(metalView)
            metalView.focusLastLink()
            return true
        }
        return false
    }

    // MARK: - Keyboard Event Handling

    override func keyDown(with event: NSEvent) {
        // Cmd+L focuses URL bar (standard browser shortcut)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "l" {
            makeFirstResponder(urlBar)
            urlBar.selectText(nil)  // Select all text
            return
        }

        // Escape focuses MetalView (exit URL bar)
        if event.keyCode == 53 {  // Escape key
            makeFirstResponder(metalView)
            return
        }

        // Forward to first responder
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
