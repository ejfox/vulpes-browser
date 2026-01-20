// MetalView+Scrolling.swift
// vulpes-browser
//
// Scroll commands for vim-style navigation

import AppKit
import Darwin

// MARK: - Scrolling Extension

extension MetalView {

    /// Scroll by a number of lines (positive = down, negative = up)
    func scrollBy(lines: Int) {
        let delta = Float(lines) * scrollSpeed
        if VulpesConfig.shared.smoothScrolling {
            applyInertialImpulse(delta)
        } else {
            applyDirectScroll(delta)
        }
    }

    /// Jump to the top of the page
    func scrollToTop() {
        if VulpesConfig.shared.smoothScrolling {
            applyInertialImpulse(-scrollOffset)
        } else {
            applyDirectScroll(-scrollOffset)
        }
    }

    /// Jump to the bottom of the page
    func scrollToBottom() {
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        let delta = maxScroll - scrollOffset
        if VulpesConfig.shared.smoothScrolling {
            applyInertialImpulse(delta)
        } else {
            applyDirectScroll(delta)
        }
    }

    private func clampScroll(_ value: Float) -> Float {
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        return max(0, min(value, maxScroll))
    }

    func applyDirectScroll(_ delta: Float) {
        _ = setScrollOffset(scrollOffset + delta)
    }

    func applyInertialImpulse(_ delta: Float) {
        let before = scrollOffset
        let after = setScrollOffset(scrollOffset + delta)
        guard after != before else { return }

        let impulseScale: Float = 12.0
        scrollVelocity += delta * impulseScale
        scrollVelocity = max(-6000.0, min(scrollVelocity, 6000.0))
        startScrollAnimator()
    }

    private func setScrollOffset(_ value: Float) -> Float {
        let clamped = clampScroll(value)
        scrollOffset = clamped
        onScrollChange?(scrollOffset, contentHeight)
        needsDisplay = true
        return clamped
    }

    private func startScrollAnimator() {
        if scrollAnimator != nil {
            return
        }

        lastScrollUpdate = CFAbsoluteTimeGetCurrent()
        scrollAnimator = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.updateInertialScroll()
        }
    }

    func stopScrollAnimator() {
        scrollAnimator?.invalidate()
        scrollAnimator = nil
    }

    private func updateInertialScroll() {
        let now = CFAbsoluteTimeGetCurrent()
        let deltaTime = Float(now - lastScrollUpdate)
        lastScrollUpdate = now

        if abs(scrollVelocity) < 5.0 {
            scrollVelocity = 0
            stopScrollAnimator()
            return
        }

        let delta = scrollVelocity * deltaTime
        let before = scrollOffset
        let after = setScrollOffset(scrollOffset + delta)

        if after == before {
            scrollVelocity = 0
            stopScrollAnimator()
            return
        }

        let decay = pow(0.90, deltaTime * 60.0)
        scrollVelocity *= decay

        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        if (after <= 0 && scrollVelocity < 0) || (after >= maxScroll && scrollVelocity > 0) {
            scrollVelocity = 0
            stopScrollAnimator()
        }
    }
}
