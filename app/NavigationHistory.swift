// NavigationHistory.swift
// vulpes-browser
//
// Manages browser navigation history for back/forward functionality
// Modular, standalone system with simple stack-based history

import Foundation

/// Manages navigation history for back/forward
class NavigationHistory {

    // MARK: - Singleton
    static let shared = NavigationHistory()

    // MARK: - History State

    /// Stack of visited URLs (current page is last element)
    private var history: [String] = []

    /// Current position in history (for forward navigation after going back)
    private var currentIndex: Int = -1

    /// Maximum history size to prevent memory bloat
    var maxHistorySize: Int = 100

    // MARK: - Navigation

    /// Record a new URL visit (called when navigating to a new page)
    /// This clears any forward history if we were in the middle of the stack
    func push(_ url: String) {
        // Don't push duplicates of current page
        if currentIndex >= 0 && currentIndex < history.count && history[currentIndex] == url {
            return
        }

        // If we're not at the end of history, truncate forward history
        if currentIndex < history.count - 1 {
            history = Array(history.prefix(currentIndex + 1))
        }

        // Add new URL
        history.append(url)
        currentIndex = history.count - 1

        // Trim if too long
        if history.count > maxHistorySize {
            let excess = history.count - maxHistorySize
            history.removeFirst(excess)
            currentIndex -= excess
        }

        print("NavigationHistory: pushed \(url) (index \(currentIndex)/\(history.count - 1))")
    }

    /// Go back one page in history
    /// Returns the URL to navigate to, or nil if can't go back
    func goBack() -> String? {
        guard canGoBack else {
            print("NavigationHistory: can't go back (index \(currentIndex))")
            return nil
        }

        currentIndex -= 1
        let url = history[currentIndex]
        print("NavigationHistory: back to \(url) (index \(currentIndex)/\(history.count - 1))")
        return url
    }

    /// Go forward one page in history
    /// Returns the URL to navigate to, or nil if can't go forward
    func goForward() -> String? {
        guard canGoForward else {
            print("NavigationHistory: can't go forward (index \(currentIndex))")
            return nil
        }

        currentIndex += 1
        let url = history[currentIndex]
        print("NavigationHistory: forward to \(url) (index \(currentIndex)/\(history.count - 1))")
        return url
    }

    /// Whether we can go back
    var canGoBack: Bool {
        return currentIndex > 0
    }

    /// Whether we can go forward
    var canGoForward: Bool {
        return currentIndex < history.count - 1
    }

    /// Current URL (if any)
    var currentURL: String? {
        guard currentIndex >= 0 && currentIndex < history.count else { return nil }
        return history[currentIndex]
    }

    /// Previous URL (for display purposes)
    var previousURL: String? {
        guard currentIndex > 0 else { return nil }
        return history[currentIndex - 1]
    }

    /// Number of pages in history
    var count: Int {
        return history.count
    }

    /// Clear all history
    func clear() {
        history.removeAll()
        currentIndex = -1
        print("NavigationHistory: cleared")
    }

    // MARK: - Debug

    /// Get history summary for debugging
    var debugDescription: String {
        var desc = "NavigationHistory (\(history.count) items, current: \(currentIndex)):\n"
        for (i, url) in history.enumerated() {
            let marker = i == currentIndex ? " <<" : ""
            desc += "  [\(i)] \(url)\(marker)\n"
        }
        return desc
    }
}
