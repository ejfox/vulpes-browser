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

    // Status bar for tabs (tmux-style)
    private var statusBar: NSVisualEffectView!
    private var statusLabel: NSTextField!
    private var statusBarHeightConstraint: NSLayoutConstraint?
    private var statusBarHideTimer: Timer?
    private let statusBarHeight: CGFloat = 22.0

    private struct BrowserTab {
        let id: UUID
        var url: String
        var content: String
        var title: String
        var displayTitle: String
        var scrollOffset: Float
        var llmRequestID: UUID?
    }

    private var tabs: [BrowserTab] = []
    private var activeTabIndex: Int = 0

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

        // Create status bar (tmux-style info line)
        statusBar = NSVisualEffectView(frame: .zero)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.material = .hudWindow
        statusBar.blendingMode = .withinWindow
        statusBar.state = .active
        contentView.addSubview(statusBar)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = NSColor(white: 0.9, alpha: 0.9)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusBar.addSubview(statusLabel)

        // Create Metal view below status bar
        metalView = MetalView(frame: .zero)
        metalView.translatesAutoresizingMaskIntoConstraints = false

        // Add views to content view (Metal view on top of blur)
        contentView.addSubview(metalView)

        // Get the content layout guide for positioning below toolbar
        // The content layout guide provides the safe area below the title bar
        let layoutGuide = contentLayoutGuide as! NSLayoutGuide

        let statusBarHeightConstraint = statusBar.heightAnchor.constraint(equalToConstant: statusBarHeight)
        self.statusBarHeightConstraint = statusBarHeightConstraint

        NSLayoutConstraint.activate([
            // Status bar goes at the BOTTOM (tmux-style)
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBarHeightConstraint,

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            // Metal view fills the content area below toolbar, above status bar
            metalView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: layoutGuide.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ])

        // Update URL bar when MetalView navigates
        metalView.onURLChange = { [weak self] url in
            self?.urlBar.stringValue = url
        }

        metalView.onContentLoaded = { [weak self] url, text in
            self?.updateActiveTabContent(url: url, text: text)
        }

        metalView.onScrollChange = { [weak self] _, _ in
            self?.updateStatusBar()
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

        NotificationCenter.default.addObserver(
            forName: .vulpesConfigReloaded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyStatusBarVisibility(animated: false)
            self?.updateStatusBar()
        }

        createInitialTab()
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
            updateActiveTabURL(url)
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

        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == "t" {
                openNewTab()
                return
            }
            if chars == "w" {
                closeCurrentTab()
                return
            }
            if let num = Int(chars), num >= 1, num <= 9 {
                switchToTab(index: num - 1)
                return
            }
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

    // MARK: - Tabs

    private func createInitialTab() {
        let home = VulpesConfig.shared.homePage
        let tab = BrowserTab(
            id: UUID(),
            url: home,
            content: "Loading \(home)...",
            title: "New Tab",
            displayTitle: "New Tab",
            scrollOffset: 0,
            llmRequestID: nil
        )
        tabs = [tab]
        activeTabIndex = 0
        updateStatusBar()
    }

    private func openNewTab() {
        saveActiveTabSnapshot()
        let home = VulpesConfig.shared.homePage
        let newTab = BrowserTab(
            id: UUID(),
            url: home,
            content: "Loading \(home)...",
            title: "New Tab",
            displayTitle: "New Tab",
            scrollOffset: 0,
            llmRequestID: nil
        )
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        updateStatusBar()
        urlBar.stringValue = home
        metalView.loadTabContent(url: home, text: "Loading \(home)...", scrollOffset: 0)
        metalView.loadURL(home)
    }

    private func closeCurrentTab() {
        guard !tabs.isEmpty else { return }
        tabs.remove(at: activeTabIndex)
        if tabs.isEmpty {
            createInitialTab()
            metalView.loadTabContent(url: tabs[0].url, text: tabs[0].content, scrollOffset: 0)
            return
        }
        activeTabIndex = min(activeTabIndex, tabs.count - 1)
        switchToTab(index: activeTabIndex)
    }

    private func switchToTab(index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        saveActiveTabSnapshot()
        activeTabIndex = index
        let tab = tabs[index]
        urlBar.stringValue = tab.url
        metalView.loadTabContent(url: tab.url, text: tab.content, scrollOffset: tab.scrollOffset)
        updateStatusBar()
    }

    private func saveActiveTabSnapshot() {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else { return }
        let snapshot = metalView.snapshotState()
        tabs[activeTabIndex].url = snapshot.url
        tabs[activeTabIndex].content = snapshot.text
        tabs[activeTabIndex].scrollOffset = snapshot.scrollOffset
    }

    private func updateActiveTabURL(_ url: String) {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else { return }
        tabs[activeTabIndex].url = url
        updateStatusBar()
    }

    private func updateActiveTabContent(url: String, text: String) {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else { return }
        tabs[activeTabIndex].url = url
        tabs[activeTabIndex].content = text
        tabs[activeTabIndex].scrollOffset = 0

        let cleaned = TitleNormalizer.cleanTitle(from: text, url: url)
        tabs[activeTabIndex].title = cleaned
        tabs[activeTabIndex].displayTitle = cleaned
        updateStatusBar()
        requestLLMTitleIfNeeded(for: tabs[activeTabIndex])
    }

    private func requestLLMTitleIfNeeded(for tab: BrowserTab) {
        let config = VulpesConfig.shared
        guard config.openRouterEnabled, !config.openRouterApiKey.isEmpty else { return }
        let requestID = UUID()
        updateTabLLMRequest(id: tab.id, requestID: requestID)
        OpenRouterClient.generateOneWordTitle(from: tab.title, url: tab.url) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleLLMTitleResult(tabID: tab.id, requestID: requestID, result: result)
            }
        }
    }

    private func updateTabLLMRequest(id: UUID, requestID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].llmRequestID = requestID
    }

    private func handleLLMTitleResult(tabID: UUID, requestID: UUID, result: Result<String, Error>) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard tabs[index].llmRequestID == requestID else { return }

        switch result {
        case .success(let title):
            tabs[index].displayTitle = title
        case .failure:
            tabs[index].displayTitle = tabs[index].title
        }
        updateStatusBar()
    }

    private func updateStatusBar() {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else {
            statusLabel.stringValue = ""
            return
        }

        let tab = tabs[activeTabIndex]
        let title = tab.displayTitle.isEmpty ? tab.title : tab.displayTitle
        let url = tab.url
        let linkCount = metalView.extractedLinks.count

        let maxScroll = max(0, metalView.contentHeight - Float(metalView.bounds.height) + 40)
        let scrollPercent: Int
        if maxScroll <= 0 {
            scrollPercent = 100
        } else {
            scrollPercent = Int(round((metalView.scrollOffset / maxScroll) * 100))
        }

        let values: [String: String] = [
            "title": title.isEmpty ? "New Tab" : title,
            "url": url,
            "scroll": "\(max(0, min(scrollPercent, 100)))%",
            "links": "\(linkCount)",
        ]

        let template = VulpesConfig.shared.statusBarTemplate
        statusLabel.stringValue = renderStatusTemplate(template, values: values)
        handleStatusBarActivity()
    }

    private func renderStatusTemplate(_ template: String, values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    private func handleStatusBarActivity() {
        if VulpesConfig.shared.statusBarAlwaysVisible {
            applyStatusBarVisibility(animated: false)
            return
        }

        applyStatusBarVisibility(animated: true)
        statusBarHideTimer?.invalidate()
        statusBarHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.applyStatusBarVisibility(animated: true, forceHidden: true)
        }
    }

    private func applyStatusBarVisibility(animated: Bool, forceHidden: Bool = false) {
        let alwaysVisible = VulpesConfig.shared.statusBarAlwaysVisible
        let shouldShow = alwaysVisible ? true : !forceHidden
        let targetHeight: CGFloat = shouldShow ? statusBarHeight : 0
        let update = {
            self.statusBarHeightConstraint?.constant = targetHeight
            self.statusBar.alphaValue = shouldShow ? 1.0 : 0.0
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.statusBar.animator().alphaValue = shouldShow ? 1.0 : 0.0
                self.statusBarHeightConstraint?.animator().constant = targetHeight
            }
        } else {
            update()
        }
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
