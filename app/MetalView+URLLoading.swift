// MetalView+URLLoading.swift
// vulpes-browser
//
// URL loading, navigation history, and link/image parsing.

import AppKit

// MARK: - URL Loading Extension

extension MetalView {

    /// Load a URL and display extracted text
    /// - Parameters:
    ///   - url: The URL to load
    ///   - addToHistory: Whether to add this URL to navigation history (default: true)
    func loadURL(_ url: String, addToHistory: Bool = true) {
        // Clear any previous error state
        clearErrorState()

        // Trigger transition effect
        triggerPageTransition()

        // Track in navigation history
        if addToHistory {
            NavigationHistory.shared.push(url)
        }

        currentURL = url
        scrollOffset = 0  // Reset scroll position for new page
        focusedLinkIndex = -1  // Reset link focus
        displayedText = "Loading \(url)..."
        updateTextDisplay()

        // Notify URL bar
        onURLChange?(url)

        // Fetch in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()

            guard let text = VulpesBridge.shared.fetchAndExtract(url: url) else {
                DispatchQueue.main.async {
                    self?.displayedText = "Failed to load \(url)"
                    self?.updateTextDisplay()
                }
                return
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("MetalView: Loaded \(url) in \(Int(elapsed))ms - \(text.count) chars")

            DispatchQueue.main.async {
                // Check if this is an HTTP error response
                if text.hasPrefix("HTTP ") {
                    // Parse error code from "HTTP 404" or "HTTP 500"
                    let parts = text.prefix(10).split(separator: " ")
                    if parts.count >= 2, let status = Int(parts[1]) {
                        self?.setErrorShader(forStatus: status)
                    }
                }

                self?.displayedText = text
                self?.parseLinks(from: text)
                self?.updateTextDisplay()
                self?.onContentLoaded?(url, text)
            }
        }
    }

    /// Snapshot current state for tab switching
    func snapshotState() -> (url: String, text: String, scrollOffset: Float) {
        return (currentURL, displayedText, scrollOffset)
    }

    /// Load saved tab content without fetching
    func loadTabContent(url: String, text: String, scrollOffset: Float) {
        currentURL = url
        displayedText = text
        self.scrollOffset = scrollOffset
        focusedLinkIndex = -1
        parseLinks(from: text)
        updateTextDisplay()
        onURLChange?(url)
        needsDisplay = true
    }

    /// Go back in navigation history
    func goBack() {
        guard let url = NavigationHistory.shared.goBack() else {
            print("MetalView: Can't go back - at start of history")
            return
        }
        loadURL(url, addToHistory: false)
    }

    /// Go forward in navigation history
    func goForward() {
        guard let url = NavigationHistory.shared.goForward() else {
            print("MetalView: Can't go forward - at end of history")
            return
        }
        loadURL(url, addToHistory: false)
    }

    /// Parse links and images from the extracted text sections
    func parseLinks(from text: String) {
        extractedLinks = []
        extractedImages = []

        // Find the Links: section
        if let linksRange = text.range(of: "---\nLinks:\n") {
            let afterLinks = text[linksRange.upperBound...]

            // Find where Images section starts (or end of string)
            let linksEnd: String.Index
            if let imagesRange = afterLinks.range(of: "---\nImages:\n") {
                linksEnd = imagesRange.lowerBound
            } else {
                linksEnd = afterLinks.endIndex
            }

            let linksSection = String(afterLinks[..<linksEnd])

            // Parse each line like "[1] https://..."
            for line in linksSection.components(separatedBy: "\n") {
                // Skip empty lines and section markers
                guard !line.isEmpty, !line.hasPrefix("---") else { continue }

                // Extract URL after "] "
                if let bracketEnd = line.firstIndex(of: "]"),
                   let spaceAfter = line.index(bracketEnd, offsetBy: 1, limitedBy: line.endIndex),
                   line[spaceAfter] == " " {
                    let urlStart = line.index(after: spaceAfter)
                    let url = String(line[urlStart...])
                    extractedLinks.append(url)
                }
            }
        }

        // Find the Images: section
        if let imagesRange = text.range(of: "---\nImages:\n") {
            let imagesSection = String(text[imagesRange.upperBound...])

            // Parse each line like "[1] https://..."
            for line in imagesSection.components(separatedBy: "\n") {
                // Skip empty lines
                guard !line.isEmpty else { continue }

                // Extract URL after "] "
                if let bracketEnd = line.firstIndex(of: "]"),
                   let spaceAfter = line.index(bracketEnd, offsetBy: 1, limitedBy: line.endIndex),
                   line[spaceAfter] == " " {
                    let urlStart = line.index(after: spaceAfter)
                    var imageURL = String(line[urlStart...])

                    // Resolve relative URLs
                    if imageURL.hasPrefix("/") {
                        if let currentURLObj = URL(string: currentURL),
                           let baseURL = URL(string: "/", relativeTo: currentURLObj) {
                            imageURL = baseURL.absoluteString.dropLast() + imageURL
                        }
                    }

                    extractedImages.append(imageURL)

                    // Pre-fetch image into atlas
                    if let atlas = imageAtlas {
                        _ = atlas.entry(for: imageURL)
                    }
                }
            }
        }

        print("MetalView: Parsed \(extractedLinks.count) links, \(extractedImages.count) images")
    }
}
