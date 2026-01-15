// MetalView+LinkNavigation.swift
// vulpes-browser
//
// Link navigation helpers for keyboard-driven browsing

import AppKit
import simd

// MARK: - Link Navigation Extension

extension MetalView {

    /// Focus the first link (called when Tab from URL bar)
    func focusFirstLink() {
        guard !extractedLinks.isEmpty else { return }
        focusedLinkIndex = 0
        updateTextDisplay()
    }

    /// Focus the last link (called when Shift+Tab from URL bar)
    func focusLastLink() {
        guard !extractedLinks.isEmpty else { return }
        focusedLinkIndex = extractedLinks.count - 1
        updateTextDisplay()
    }

    /// Cycle to the next link (Tab key)
    func cycleToNextLink() {
        guard !extractedLinks.isEmpty else { return }

        focusedLinkIndex += 1
        if focusedLinkIndex >= extractedLinks.count {
            // Wrap to URL bar
            focusedLinkIndex = -1
            onRequestURLBarFocus?()
            return
        }

        updateTextDisplay()
    }

    /// Cycle to the previous link (Shift+Tab key)
    func cycleToPrevLink() {
        guard !extractedLinks.isEmpty else { return }

        focusedLinkIndex -= 1
        if focusedLinkIndex < -1 {
            focusedLinkIndex = extractedLinks.count - 1
        } else if focusedLinkIndex == -1 {
            onRequestURLBarFocus?()
            return
        }

        updateTextDisplay()
    }

    /// Follow a link by number (1-indexed)
    func followLink(number: Int) {
        let index = number - 1  // Links are 1-indexed
        guard index >= 0 && index < extractedLinks.count else {
            print("MetalView: No link \(number) (have \(extractedLinks.count) links)")
            return
        }

        // Spawn particles from the link (if we have a hit box for it)
        if let hitBox = linkHitBoxes.first(where: { $0.linkIndex == index }) {
            spawnParticlesFromLink(hitBox: hitBox, color: SIMD3<Float>(0.4, 0.6, 1.0))
        }

        var url = extractedLinks[index]

        // Handle relative URLs
        if url.hasPrefix("/") {
            // Construct absolute URL from current page
            if let currentURLObj = URL(string: currentURL),
               let baseURL = URL(string: "/", relativeTo: currentURLObj) {
                url = baseURL.absoluteString.dropLast() + url
            }
        }

        print("MetalView: Following link \(number): \(url)")
        loadURL(url)
    }
}
