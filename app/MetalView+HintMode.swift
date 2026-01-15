// MetalView+HintMode.swift
// vulpes-browser
//
// Vimium-style hint mode for keyboard link navigation

import AppKit
import Metal
import simd

// MARK: - Hint Mode Extension

extension MetalView {

    /// Enter hint mode - show letter labels on all links
    func enterHintMode() {
        guard !linkHitBoxes.isEmpty else {
            print("MetalView: No links to hint")
            return
        }

        hintModeActive = true
        hintBuffer = ""
        hintLabels = generateHintLabels(count: linkHitBoxes.count)
        hintModeStartTime = CFAbsoluteTimeGetCurrent()

        print("MetalView: Entering hint mode with \(linkHitBoxes.count) links")
        needsDisplay = true
    }

    /// Exit hint mode
    func exitHintMode() {
        hintModeActive = false
        hintBuffer = ""
        hintLabels = []
        needsDisplay = true
    }

    /// Generate hint labels (a, s, d, f, j, k, l, ..., aa, as, ...)
    func generateHintLabels(count: Int) -> [String] {
        var labels: [String] = []

        // Single character labels first
        for char in hintChars {
            labels.append(String(char))
            if labels.count >= count { return labels }
        }

        // Two character labels
        for first in hintChars {
            for second in hintChars {
                labels.append(String(first) + String(second))
                if labels.count >= count { return labels }
            }
        }

        return labels
    }

    /// Handle keyboard input while in hint mode
    func handleHintInput(_ char: Character) {
        hintBuffer.append(char)

        // Find matching labels
        let matches = matchingHintIndices()

        if matches.count == 1 {
            // Exact match - follow the link
            let index = matches.first!
            exitHintMode()
            if index < linkHitBoxes.count {
                let hitBox = linkHitBoxes[index]
                followLink(number: hitBox.linkIndex + 1)
            }
        } else if matches.isEmpty {
            // No matches - exit hint mode
            print("MetalView: No hint matches for '\(hintBuffer)'")
            exitHintMode()
        } else {
            // Multiple matches - wait for more input
            needsDisplay = true
        }
    }

    /// Get indices of hints that match the current buffer
    func matchingHintIndices() -> Set<Int> {
        var matches = Set<Int>()
        for (index, label) in hintLabels.enumerated() {
            if label.hasPrefix(hintBuffer) {
                matches.insert(index)
            }
        }
        return matches
    }

    /// Build vertex buffer for hint labels overlay
    func buildHintVertices() -> (MTLBuffer?, Int) {
        guard hintModeActive, !hintLabels.isEmpty, let atlas = glyphAtlas else {
            return (nil, 0)
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(hintLabels.count * 24) // ~4 chars per hint, 6 verts per char

        let scale = Float(metalLayer.contentsScale)
        let fontSize: CGFloat = 14.0 * CGFloat(scale)
        let font = CTFontCreateWithName("SF Mono" as CFString, fontSize, nil)

        let matchingIndices = matchingHintIndices()

        for (index, label) in hintLabels.enumerated() {
            guard index < linkHitBoxes.count else { continue }
            let hitBox = linkHitBoxes[index]

            // Skip hints not matching current buffer
            let isMatching = matchingIndices.contains(index)

            // Position hint at the start of the link
            let hintX = hitBox.minX * scale
            let hintY = (hitBox.minY - scrollOffset) * scale

            // Skip if off-screen
            if hintY < -50 * scale || hintY > Float(bounds.height) * scale + 50 * scale {
                continue
            }

            // Background color - brighter for matching hints
            let bgColor: SIMD4<Float>
            let textColor: SIMD4<Float>
            if isMatching {
                bgColor = SIMD4<Float>(1.0, 0.9, 0.3, 0.95)  // Yellow
                textColor = SIMD4<Float>(0.1, 0.1, 0.1, 1.0)  // Dark
            } else {
                bgColor = SIMD4<Float>(0.3, 0.3, 0.3, 0.8)   // Gray
                textColor = SIMD4<Float>(0.6, 0.6, 0.6, 1.0)  // Light gray
            }

            // Calculate hint background size
            var hintWidth: Float = 4 * scale  // Padding
            for char in label {
                let chars: [UniChar] = [UniChar(char.asciiValue ?? 0)]
                var glyph: CGGlyph = 0
                CTFontGetGlyphsForCharacters(font, chars, &glyph, 1)
                if let entry = atlas.entry(for: glyph, font: font) {
                    hintWidth += Float(entry.advance)
                }
            }
            hintWidth += 4 * scale  // Padding

            let hintHeight: Float = Float(fontSize) + 4 * scale

            // Draw background quad
            let x1 = hintX
            let y1 = hintY - 2 * scale
            let x2 = hintX + hintWidth
            let y2 = hintY + hintHeight

            // Background triangles
            vertices.append(Vertex(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(0, 0), color: bgColor))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: bgColor))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: bgColor))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: bgColor))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y2), texCoord: SIMD2<Float>(1, 1), color: bgColor))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: bgColor))
        }

        guard !vertices.isEmpty else { return (nil, 0) }

        let buffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
        buffer?.label = "Hint Background Vertices"

        return (buffer, vertices.count)
    }

    /// Build text vertices for hint labels
    func buildHintTextVertices() -> (MTLBuffer?, Int) {
        guard hintModeActive, !hintLabels.isEmpty, let atlas = glyphAtlas else {
            return (nil, 0)
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(hintLabels.count * 24)

        let scale = Float(metalLayer.contentsScale)
        let fontSize: CGFloat = 14.0 * CGFloat(scale)
        let font = CTFontCreateWithName("SF Mono" as CFString, fontSize, nil)

        let matchingIndices = matchingHintIndices()

        for (index, label) in hintLabels.enumerated() {
            guard index < linkHitBoxes.count else { continue }
            let hitBox = linkHitBoxes[index]

            let isMatching = matchingIndices.contains(index)

            let hintX = hitBox.minX * scale + 4 * scale  // Padding offset
            let hintY = (hitBox.minY - scrollOffset) * scale + Float(fontSize) - 2 * scale

            // Skip if off-screen
            if hintY < -50 * scale || hintY > Float(bounds.height) * scale + 50 * scale {
                continue
            }

            let textColor: SIMD4<Float> = isMatching
                ? SIMD4<Float>(0.1, 0.1, 0.1, 1.0)
                : SIMD4<Float>(0.6, 0.6, 0.6, 1.0)

            var penX = hintX
            for char in label {
                let chars: [UniChar] = [UniChar(char.asciiValue ?? 0)]
                var glyph: CGGlyph = 0
                CTFontGetGlyphsForCharacters(font, chars, &glyph, 1)

                guard let entry = atlas.entry(for: glyph, font: font) else { continue }

                let x1 = penX + Float(entry.bearing.x)
                let y1 = hintY - Float(entry.bearing.y)
                let x2 = x1 + Float(entry.size.width)
                let y2 = y1 + Float(entry.size.height)

                let u1 = Float(entry.uvRect.minX)
                let v1 = Float(entry.uvRect.maxY)  // Flipped for correct orientation
                let u2 = Float(entry.uvRect.maxX)
                let v2 = Float(entry.uvRect.minY)  // Flipped for correct orientation

                vertices.append(Vertex(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(u1, v1), color: textColor))
                vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(u2, v1), color: textColor))
                vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(u1, v2), color: textColor))
                vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(u2, v1), color: textColor))
                vertices.append(Vertex(position: SIMD2<Float>(x2, y2), texCoord: SIMD2<Float>(u2, v2), color: textColor))
                vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(u1, v2), color: textColor))

                penX += Float(entry.advance)
            }
        }

        guard !vertices.isEmpty else { return (nil, 0) }

        let buffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
        buffer?.label = "Hint Text Vertices"

        return (buffer, vertices.count)
    }
}
