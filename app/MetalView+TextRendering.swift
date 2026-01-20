// MetalView+TextRendering.swift
// vulpes-browser
//
// Text layout and vertex generation for Metal rendering.
// Handles font setup, glyph preparation, word wrapping, and special formatting.

import AppKit
import CoreText
import Metal
import simd

// MARK: - Image Placement (file-level for extension access)

struct ImagePlacement {
    let imageIndex: Int
    var x: Float
    var y: Float
    var width: Float
    var height: Float
}

// MARK: - Text Rendering Extension

extension MetalView {

    /// Update the text vertex buffer with current displayedText
    func updateTextDisplay() {
        guard let atlas = glyphAtlas else { return }

        let scale = CGFloat(metalLayer.contentsScale)
        let fontSize: CGFloat = 16.0 * scale
        let font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize, nil)
        let lineHeight: Float = Float(fontSize * 1.4)

        let text = displayedText
        let chars = Array(text.utf16)
        guard !chars.isEmpty else {
            textVertexCount = 0
            return
        }

        // Prepare fonts for different styles
        let monoFont = CTFontCreateWithName("SF Mono" as CFString, fontSize, nil)
        let h1Scale: CGFloat = 1.8
        let h2Scale: CGFloat = 1.5
        let h3Scale: CGFloat = 1.3
        let h4Scale: CGFloat = 1.15
        let h1Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h1Scale, nil)
        let h2Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h2Scale, nil)
        let h3Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h3Scale, nil)
        let h4Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h4Scale, nil)

        // Pre-compute glyphs for all characters with each font
        var glyphsNormal = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsMono = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH1 = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH2 = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH3 = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH4 = [CGGlyph](repeating: 0, count: chars.count)
        _ = CTFontGetGlyphsForCharacters(font, chars, &glyphsNormal, chars.count)
        _ = CTFontGetGlyphsForCharacters(monoFont, chars, &glyphsMono, chars.count)
        _ = CTFontGetGlyphsForCharacters(h1Font, chars, &glyphsH1, chars.count)
        _ = CTFontGetGlyphsForCharacters(h2Font, chars, &glyphsH2, chars.count)
        _ = CTFontGetGlyphsForCharacters(h3Font, chars, &glyphsH3, chars.count)
        _ = CTFontGetGlyphsForCharacters(h4Font, chars, &glyphsH4, chars.count)

        // Pre-compute space glyphs
        let spaceChar: [UniChar] = [0x0020]
        var normalSpaceGlyph: CGGlyph = 0
        var monoSpaceGlyph: CGGlyph = 0
        var h1SpaceGlyph: CGGlyph = 0
        var h2SpaceGlyph: CGGlyph = 0
        var h3SpaceGlyph: CGGlyph = 0
        var h4SpaceGlyph: CGGlyph = 0
        _ = CTFontGetGlyphsForCharacters(font, spaceChar, &normalSpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(monoFont, spaceChar, &monoSpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h1Font, spaceChar, &h1SpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h2Font, spaceChar, &h2SpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h3Font, spaceChar, &h3SpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h4Font, spaceChar, &h4SpaceGlyph, 1)

        var vertices: [Vertex] = []
        vertices.reserveCapacity(chars.count * 6)

        // Layout configuration
        let margin: Float = Float(20.0 * scale)
        let quoteIndent: Float = Float(24.0 * scale)
        let viewportWidth: Float = Float(bounds.width * scale) - margin * 2
        let targetLineWidth = VulpesConfig.shared.readableLineWidth
        let contentWidth: Float
        if targetLineWidth <= 0 {
            contentWidth = viewportWidth
        } else if let spaceEntry = atlas.entry(for: normalSpaceGlyph, font: font) {
            let readableWidth = Float(spaceEntry.advance) * max(20.0, targetLineWidth)
            contentWidth = min(viewportWidth, readableWidth)
        } else {
            contentWidth = viewportWidth
        }

        // Layout state
        var quoteDepth: Int = 0
        var penX: Float = margin
        var penY: Float = margin + Float(fontSize)
        let baseLineHeight: Float = lineHeight
        let h1LineHeight: Float = lineHeight * Float(h1Scale)
        let h2LineHeight: Float = lineHeight * Float(h2Scale)
        let h3LineHeight: Float = lineHeight * Float(h3Scale)
        let h4LineHeight: Float = lineHeight * Float(h4Scale)
        var currentLineHeight: Float = baseLineHeight
        var extraSpacingAfterHeading: Float = 0

        // Note: Scroll offset is now applied in the vertex shader via uniforms
        // This allows smooth scrolling without rebuilding all vertices

        // Colors - use CSS page style if available, otherwise defaults
        let config = VulpesConfig.shared

        // Text color priority: 1) Config override, 2) CSS page style, 3) Default
        let normalColor: SIMD4<Float>
        if let override = config.textColorOverride {
            normalColor = SIMD4<Float>(override.r, override.g, override.b, 1.0)
        } else if config.useCssColors, let cssText = pageStyle.textColor {
            normalColor = SIMD4<Float>(cssText.r, cssText.g, cssText.b, 1.0)
        } else {
            let c = config.textColor
            normalColor = SIMD4<Float>(c.r, c.g, c.b, 1.0)
        }

        // Link color priority: 1) Config, 2) CSS page style, 3) Default
        let linkColor: SIMD4<Float>
        if config.useCssColors, let cssLink = pageStyle.linkColor {
            linkColor = SIMD4<Float>(cssLink.r, cssLink.g, cssLink.b, 1.0)
        } else {
            let c = config.linkColor
            linkColor = SIMD4<Float>(c.r, c.g, c.b, 1.0)
        }

        let focusedLinkColor = SIMD4<Float>(1.0, 0.8, 0.2, 1.0)
        var currentColor = normalColor
        var currentLinkIndex = -1

        // Link hit boxes
        linkHitBoxes = []
        var currentLinkHitBox: LinkHitBox? = nil

        // Control character codes
        let linkStart: UInt16 = 0x0001
        let linkEnd: UInt16 = 0x0002
        let preStart: UInt16 = 0x0003
        let preEnd: UInt16 = 0x0004
        let emphStart: UInt16 = 0x0011
        let emphEnd: UInt16 = 0x0012
        let strongStart: UInt16 = 0x0013
        let strongEnd: UInt16 = 0x0014
        let codeStart: UInt16 = 0x0015
        let codeEnd: UInt16 = 0x0016
        let quoteStart: UInt16 = 0x0017
        let quoteEnd: UInt16 = 0x0018
        let h1Start: UInt16 = 0x0019
        let h2Start: UInt16 = 0x001A
        let h3Start: UInt16 = 0x001B
        let h4Start: UInt16 = 0x001C
        let headingEnd: UInt16 = 0x001D
        let imageMarker: UInt16 = 0x001E

        // Formatting state
        var inPre = false
        var inLink = false
        var inEmphasis = false
        var inStrong = false
        var inCode = false
        var headingLevel: Int = 0
        var pendingEntries: [GlyphAtlas.GlyphEntry] = []
        pendingEntries.reserveCapacity(32)
        var pendingWidth: Float = 0

        // Image state
        imagePlacements = []
        var inImageMarker = false
        var imageNumberBuffer: [UniChar] = []

        // Helper functions
        func lineStartX() -> Float {
            margin + quoteIndent * Float(quoteDepth)
        }

        func lineMaxX() -> Float {
            let maxX = margin + contentWidth
            return max(maxX, lineStartX() + 1.0)
        }

        func headingFont(for level: Int) -> CTFont {
            switch level {
            case 1: return h1Font
            case 2: return h2Font
            case 3: return h3Font
            default: return h4Font
            }
        }

        func headingGlyph(for level: Int, index: Int) -> CGGlyph {
            switch level {
            case 1: return glyphsH1[index]
            case 2: return glyphsH2[index]
            case 3: return glyphsH3[index]
            default: return glyphsH4[index]
            }
        }

        func headingSpaceGlyph(for level: Int) -> CGGlyph {
            switch level {
            case 1: return h1SpaceGlyph
            case 2: return h2SpaceGlyph
            case 3: return h3SpaceGlyph
            default: return h4SpaceGlyph
            }
        }

        func updateCurrentColor() {
            var base = inLink ? linkColor : normalColor
            if inLink && currentLinkIndex == focusedLinkIndex {
                base = focusedLinkColor
            }
            if headingLevel > 0 && !inLink {
                base = SIMD4<Float>(1.0, 1.0, 1.0, base.w)
            }
            if inStrong {
                base = SIMD4<Float>(
                    min(base.x * 1.15, 1.0),
                    min(base.y * 1.15, 1.0),
                    min(base.z * 1.15, 1.0),
                    base.w
                )
            }
            if inEmphasis {
                base = SIMD4<Float>(base.x * 0.9, base.y * 0.9, base.z * 0.9, base.w)
            }
            if inCode {
                base = SIMD4<Float>(base.x * 0.95, base.y * 0.95, base.z * 0.95, base.w)
            }
            currentColor = base
        }

        func appendGlyph(_ entry: GlyphAtlas.GlyphEntry, color: SIMD4<Float>) {
            let x1 = penX + Float(entry.bearing.x)
            let y1 = penY - Float(entry.bearing.y) - Float(entry.size.height)
            let x2 = x1 + Float(entry.size.width)
            let y2 = penY - Float(entry.bearing.y)

            let u0 = Float(entry.uvRect.minX)
            let u1 = Float(entry.uvRect.maxX)
            let v0 = Float(entry.uvRect.maxY)
            let v1 = Float(entry.uvRect.minY)

            vertices.append(Vertex(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(u0, v0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(u1, v0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(u0, v1), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(u1, v0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y2), texCoord: SIMD2<Float>(u1, v1), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(u0, v1), color: color))

            // Expand link hit box if we're in a link
            if currentLinkHitBox != nil {
                let hitX1 = penX + Float(entry.bearing.x)
                let hitY1 = penY - Float(entry.bearing.y) - Float(entry.size.height)
                let hitX2 = hitX1 + Float(entry.size.width)
                let hitY2 = penY - Float(entry.bearing.y)

                currentLinkHitBox!.minX = min(currentLinkHitBox!.minX, hitX1)
                currentLinkHitBox!.minY = min(currentLinkHitBox!.minY, hitY1)
                currentLinkHitBox!.maxX = max(currentLinkHitBox!.maxX, hitX2)
                currentLinkHitBox!.maxY = max(currentLinkHitBox!.maxY, hitY2)
            }

            penX += Float(entry.advance)
        }

        func flushPendingWord() {
            guard pendingWidth > 0 else { return }

            if penX + pendingWidth > lineMaxX() && penX > lineStartX() {
                penX = lineStartX()
                penY += currentLineHeight
            }

            for entry in pendingEntries {
                appendGlyph(entry, color: currentColor)
            }

            pendingEntries.removeAll(keepingCapacity: true)
            pendingWidth = 0
        }

        // Main character processing loop
        for i in 0..<chars.count {
            let char = chars[i]

            // Handle control characters
            if char == linkStart {
                flushPendingWord()
                currentLinkIndex += 1
                inLink = true
                updateCurrentColor()
                currentLinkHitBox = LinkHitBox(
                    linkIndex: currentLinkIndex,
                    minX: Float.greatestFiniteMagnitude,
                    minY: Float.greatestFiniteMagnitude,
                    maxX: -Float.greatestFiniteMagnitude,
                    maxY: -Float.greatestFiniteMagnitude
                )
                continue
            }
            if char == linkEnd {
                flushPendingWord()
                inLink = false
                updateCurrentColor()
                if var hitBox = currentLinkHitBox {
                    hitBox.minX /= Float(scale)
                    hitBox.minY /= Float(scale)
                    hitBox.maxX /= Float(scale)
                    hitBox.maxY /= Float(scale)
                    linkHitBoxes.append(hitBox)
                }
                currentLinkHitBox = nil
                continue
            }
            if char == preStart { flushPendingWord(); inPre = true; continue }
            if char == preEnd { flushPendingWord(); inPre = false; continue }

            // Image marker handling
            if char == imageMarker {
                if !inImageMarker {
                    flushPendingWord()
                    inImageMarker = true
                    imageNumberBuffer = []
                } else {
                    inImageMarker = false
                    if let numStr = String(utf16CodeUnits: imageNumberBuffer, count: imageNumberBuffer.count) as String?,
                       let imageNum = Int(numStr), imageNum > 0, imageNum <= extractedImages.count {
                        let imageIndex = imageNum - 1
                        let maxImageWidth = lineMaxX() - lineStartX()
                        let desiredWidth: Float = min(400.0 * Float(scale), maxImageWidth)

                        if penX != lineStartX() {
                            penX = lineStartX()
                            penY += currentLineHeight
                        }

                        // Check if image is cached to get real dimensions
                        let imageURL = extractedImages[imageIndex]
                        let aspectRatio: Float
                        if let entry = imageAtlas?.entry(for: imageURL) {
                            // Use real aspect ratio from cached image
                            aspectRatio = Float(entry.size.width / entry.size.height)
                        } else {
                            // Estimate 4:3 landscape until image loads
                            aspectRatio = 4.0 / 3.0
                        }

                        let imageHeight = desiredWidth / aspectRatio

                        let placement = ImagePlacement(
                            imageIndex: imageIndex,
                            x: penX / Float(scale),
                            y: penY / Float(scale),
                            width: desiredWidth / Float(scale),
                            height: imageHeight / Float(scale)
                        )
                        imagePlacements.append(placement)

                        penY += imageHeight
                        penY += currentLineHeight * 0.5
                        penX = lineStartX()
                    }
                }
                continue
            }
            if inImageMarker { imageNumberBuffer.append(char); continue }

            // Heading markers
            if char == h1Start { flushPendingWord(); headingLevel = 1; currentLineHeight = h1LineHeight; updateCurrentColor(); continue }
            if char == h2Start { flushPendingWord(); headingLevel = 2; currentLineHeight = h2LineHeight; updateCurrentColor(); continue }
            if char == h3Start { flushPendingWord(); headingLevel = 3; currentLineHeight = h3LineHeight; updateCurrentColor(); continue }
            if char == h4Start { flushPendingWord(); headingLevel = 4; currentLineHeight = h4LineHeight; updateCurrentColor(); continue }
            if char == headingEnd {
                flushPendingWord()
                headingLevel = 0
                currentLineHeight = baseLineHeight
                extraSpacingAfterHeading = baseLineHeight * 0.25
                updateCurrentColor()
                continue
            }

            // Text formatting markers
            if char == emphStart { flushPendingWord(); inEmphasis = true; updateCurrentColor(); continue }
            if char == emphEnd { flushPendingWord(); inEmphasis = false; updateCurrentColor(); continue }
            if char == strongStart { flushPendingWord(); inStrong = true; updateCurrentColor(); continue }
            if char == strongEnd { flushPendingWord(); inStrong = false; updateCurrentColor(); continue }
            if char == codeStart { flushPendingWord(); inCode = true; updateCurrentColor(); continue }
            if char == codeEnd { flushPendingWord(); inCode = false; updateCurrentColor(); continue }

            // Quote markers
            if char == quoteStart {
                flushPendingWord()
                if penX != lineStartX() { penX = lineStartX(); penY += currentLineHeight }
                quoteDepth += 1
                penX = lineStartX()
                continue
            }
            if char == quoteEnd {
                flushPendingWord()
                quoteDepth = max(0, quoteDepth - 1)
                penX = lineStartX()
                continue
            }

            // Newlines
            if char == 0x000A {
                flushPendingWord()
                penX = lineStartX()
                penY += currentLineHeight + extraSpacingAfterHeading
                extraSpacingAfterHeading = 0
                continue
            }

            // Regular character rendering
            let useMono = inPre || inCode
            let isHeading = headingLevel > 0 && !useMono
            let glyph = useMono ? glyphsMono[i] : (isHeading ? headingGlyph(for: headingLevel, index: i) : glyphsNormal[i])
            let activeFont = useMono ? monoFont : (isHeading ? headingFont(for: headingLevel) : font)

            // Pre-formatted text (no word wrapping)
            if inPre {
                if char == 0x0009 { // tab
                    if let spaceEntry = atlas.entry(for: monoSpaceGlyph, font: monoFont) {
                        penX += Float(spaceEntry.advance) * 4
                    }
                    continue
                }
                if char == 0x0020 { // space
                    if let spaceEntry = atlas.entry(for: monoSpaceGlyph, font: monoFont) {
                        penX += Float(spaceEntry.advance)
                    }
                    continue
                }
                guard let entry = atlas.entry(for: glyph, font: activeFont) else { continue }
                appendGlyph(entry, color: currentColor)
                continue
            }

            // Whitespace handling with word wrapping
            if char == 0x0020 || char == 0x0009 {
                flushPendingWord()
                if penX > lineStartX() {
                    let spaceGlyph = useMono ? monoSpaceGlyph : (isHeading ? headingSpaceGlyph(for: headingLevel) : normalSpaceGlyph)
                    if let spaceEntry = atlas.entry(for: spaceGlyph, font: activeFont) {
                        penX += Float(spaceEntry.advance)
                    }
                }
                continue
            }

            // Accumulate word
            guard let entry = atlas.entry(for: glyph, font: activeFont) else { continue }
            pendingEntries.append(entry)
            pendingWidth += Float(entry.advance)
        }

        flushPendingWord()

        // Track content height for scroll bounds
        contentHeight = penY / Float(scale)
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        if scrollOffset > maxScroll {
            scrollOffset = maxScroll
        }

        guard !vertices.isEmpty else {
            textVertexCount = 0
            return
        }

        textVertexCount = vertices.count
        textVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
        textVertexBuffer?.label = "Text Vertices"

        needsDisplay = true
    }
}
