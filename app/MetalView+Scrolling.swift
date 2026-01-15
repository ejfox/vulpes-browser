// MetalView+Scrolling.swift
// vulpes-browser
//
// Scroll commands for vim-style navigation

import AppKit

// MARK: - Scrolling Extension

extension MetalView {

    /// Scroll by a number of lines (positive = down, negative = up)
    func scrollBy(lines: Int) {
        let delta = Float(lines) * scrollSpeed
        scrollOffset = max(0, scrollOffset + delta)

        // Clamp to content bounds
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        scrollOffset = min(scrollOffset, maxScroll)

        updateTextDisplay()
    }

    /// Jump to the top of the page
    func scrollToTop() {
        scrollOffset = 0
        updateTextDisplay()
    }

    /// Jump to the bottom of the page
    func scrollToBottom() {
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        scrollOffset = maxScroll
        updateTextDisplay()
    }
}
