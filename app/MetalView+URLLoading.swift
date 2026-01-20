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

        let normalizedURL = normalizeURLStringForLoad(url)

        // Track in navigation history
        if addToHistory {
            NavigationHistory.shared.push(normalizedURL)
        }

        currentURL = normalizedURL
        baseURLForCurrentPage = URL(string: normalizedURL)
        scrollOffset = 0  // Reset scroll position for new page
        scrollVelocity = 0
        stopScrollAnimator()
        focusedLinkIndex = -1  // Reset link focus
        pageStyle = .default  // Reset page style
        displayedText = "Loading \(normalizedURL)..."
        updateTextDisplay()

        // Notify URL bar
        onURLChange?(normalizedURL)

        guard let parsedURL = URL(string: normalizedURL), parsedURL.scheme != nil else {
            displayedText = "Invalid URL\n\n\(normalizedURL)"
            updateTextDisplay()
            return
        }

        if let scheme = parsedURL.scheme?.lowercased(), scheme != "http" && scheme != "https" {
            displayedText = "Unsupported URL scheme\n\n\(normalizedURL)"
            updateTextDisplay()
            return
        }

        // Fetch in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()

            // First fetch the raw HTML
            let fetchResult: VulpesBridge.FetchResult
            switch VulpesBridge.shared.fetchWithError(url: normalizedURL) {
            case .success(let result):
                fetchResult = result
            case .failure(let failure):
                DispatchQueue.main.async {
                    self?.displayedText = "Failed to load\n\n\(normalizedURL)\n\(failure.message) (error \(failure.code))"
                    self?.updateTextDisplay()
                }
                return
            }

            // Extract text from HTML
            let text: String
            if fetchResult.status != 200 {
                // Handle non-200 responses
                if let extractedText = VulpesBridge.shared.extractText(from: fetchResult.body), !extractedText.isEmpty {
                    text = "HTTP \(fetchResult.status)\n\n\(extractedText)"
                } else {
                    text = "HTTP \(fetchResult.status)"
                }
            } else {
                text = VulpesBridge.shared.extractText(from: fetchResult.body) ?? "Failed to extract text"
            }

            // Extract page style from CSS (only for successful responses)
            var extractedPageStyle: VulpesBridge.PageStyle = .default
            if fetchResult.status == 200, let baseURL = URL(string: normalizedURL) {
                extractedPageStyle = VulpesBridge.shared.extractPageStyle(from: fetchResult.body, baseURL: baseURL)
            }
            let resolvedBaseURL = self?.computeBaseURL(from: fetchResult.body, pageURLString: normalizedURL)

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("MetalView: Loaded \(normalizedURL) in \(Int(elapsed))ms - \(text.count) chars")

            DispatchQueue.main.async {
                // Check if this is an HTTP error response
                if text.hasPrefix("HTTP ") {
                    // Parse error code from "HTTP 404" or "HTTP 500"
                    let parts = text.prefix(10).split(separator: " ")
                    if parts.count >= 2, let status = Int(parts[1]) {
                        self?.setErrorShader(forStatus: status)
                    }
                }

                self?.pageStyle = extractedPageStyle
                if let resolvedBaseURL {
                    self?.baseURLForCurrentPage = resolvedBaseURL
                }
                self?.displayedText = text
                self?.parseLinks(from: text)
                self?.updateTextDisplay()
                self?.onContentLoaded?(normalizedURL, text)
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
        baseURLForCurrentPage = URL(string: url)
        displayedText = text
        self.scrollOffset = scrollOffset
        scrollVelocity = 0
        stopScrollAnimator()
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
                    let url = String(line[urlStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolved = resolveURLString(url) ?? url
                    extractedLinks.append(resolved)
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
                    let imageURL = String(line[urlStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedImageURL = resolveURLString(imageURL) ?? imageURL

                    extractedImages.append(resolvedImageURL)

                    // Pre-fetch image into atlas
                    if let atlas = imageAtlas {
                        _ = atlas.entry(for: resolvedImageURL)
                    }
                }
            }
        }

        print("MetalView: Parsed \(extractedLinks.count) links, \(extractedImages.count) images")
    }

    func resolveURLString(_ urlString: String) -> String? {
        if urlString.isEmpty {
            return nil
        }

        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return normalizeURLStringForLoad(urlString)
        }

        if urlString.hasPrefix("//") {
            let scheme = baseURLForCurrentPage?.scheme ?? URL(string: currentURL)?.scheme ?? "https"
            return normalizeURLStringForLoad(scheme + ":" + urlString)
        }

        guard let baseURL = baseURLForCurrentPage ?? URL(string: currentURL) else {
            return nil
        }

        if let resolvedURL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL {
            return normalizeURLStringForLoad(resolvedURL.absoluteString)
        }

        return nil
    }

    private func computeBaseURL(from html: Data, pageURLString: String) -> URL? {
        guard let pageURL = URL(string: pageURLString) else {
            return nil
        }

        guard let baseHref = extractBaseHref(from: html) else {
            return pageURL
        }

        let trimmed = baseHref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return pageURL
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            let normalized = normalizeURLStringForLoad(trimmed)
            return URL(string: normalized) ?? pageURL
        }

        if trimmed.hasPrefix("//") {
            let scheme = pageURL.scheme ?? "https"
            let normalized = normalizeURLStringForLoad(scheme + ":" + trimmed)
            return URL(string: normalized) ?? pageURL
        }

        let resolved = URL(string: trimmed, relativeTo: pageURL)?.absoluteURL ?? pageURL
        let normalized = normalizeURLStringForLoad(resolved.absoluteString)
        return URL(string: normalized) ?? resolved
    }

    private func extractBaseHref(from html: Data) -> String? {
        let htmlString = String(decoding: html, as: UTF8.self)
        let lower = htmlString.lowercased()
        guard let baseStart = lower.range(of: "<base") else {
            return nil
        }

        guard let tagEnd = lower[baseStart.lowerBound...].firstIndex(of: ">") else {
            return nil
        }

        let tag = String(htmlString[baseStart.lowerBound...tagEnd])
        return extractAttribute("href", from: tag)
    }

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let lower = tag.lowercased()
        guard let nameRange = lower.range(of: name.lowercased() + "=") else {
            return nil
        }

        var index = nameRange.upperBound
        while index < lower.endIndex, lower[index].isWhitespace {
            index = lower.index(after: index)
        }
        if index == lower.endIndex {
            return nil
        }

        let quoteChar = lower[index]
        if quoteChar == "\"" || quoteChar == "'" {
            let valueStart = lower.index(after: index)
            guard let valueEnd = lower[valueStart...].firstIndex(of: quoteChar) else {
                return nil
            }
            return String(tag[valueStart..<valueEnd])
        }

        var valueEnd = index
        while valueEnd < lower.endIndex, !lower[valueEnd].isWhitespace, lower[valueEnd] != ">" {
            valueEnd = lower.index(after: valueEnd)
        }
        return String(tag[index..<valueEnd])
    }

    private func normalizeURLStringForLoad(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if VulpesConfig.shared.allowHttp {
            return trimmed
        }

        guard let url = URL(string: trimmed) else {
            return trimmed
        }

        let scheme = url.scheme?.lowercased()
        if scheme != "http" {
            return trimmed
        }

        if isLocalhost(url) {
            return trimmed
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return trimmed
        }

        components.scheme = "https"
        return components.url?.absoluteString ?? trimmed
    }

    private func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
