// GlyphAtlas.swift
// vulpes-browser
//
// Minimal glyph atlas for test text rendering.

import CoreText
import Metal

final class GlyphAtlas {
    struct GlyphKey: Hashable {
        let fontName: String
        let fontSize: CGFloat
        let glyphID: CGGlyph
    }

    struct GlyphEntry {
        let uvRect: CGRect
        let size: CGSize
        let bearing: CGPoint
        let advance: CGFloat
    }

    let texture: MTLTexture

    private let size: Int
    private var nextX: Int = 0
    private var nextY: Int = 0
    private var rowHeight: Int = 0
    private var entries: [GlyphKey: GlyphEntry] = [:]
    private let padding: Int = 1

    init?(device: MTLDevice, size: Int = 1024) {
        self.size = size

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        self.texture = texture
        self.texture.label = "Glyph Atlas"
    }

    func entry(for glyph: CGGlyph, font: CTFont) -> GlyphEntry? {
        let fontName = CTFontCopyPostScriptName(font) as String
        let fontSize = CTFontGetSize(font)
        let key = GlyphKey(fontName: fontName, fontSize: fontSize, glyphID: glyph)

        if let cached = entries[key] {
            return cached
        }

        var boundingRect = CGRect.zero
        _ = CTFontGetBoundingRectsForGlyphs(font, .default, [glyph], &boundingRect, 1)

        var advance = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(font, .default, [glyph], &advance, 1)

        let glyphWidth = max(1, Int(ceil(boundingRect.width)))
        let glyphHeight = max(1, Int(ceil(boundingRect.height)))

        var bitmap = [UInt8](repeating: 0, count: glyphWidth * glyphHeight)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &bitmap,
            width: glyphWidth,
            height: glyphHeight,
            bitsPerComponent: 8,
            bytesPerRow: glyphWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: glyphWidth, height: glyphHeight))
        context.setFillColor(gray: 1.0, alpha: 1.0)

        context.translateBy(x: 0, y: CGFloat(glyphHeight))
        context.scaleBy(x: 1.0, y: -1.0)

        var position = CGPoint(x: -boundingRect.origin.x, y: -boundingRect.origin.y)
        CTFontDrawGlyphs(font, [glyph], &position, 1, context)

        if nextX + glyphWidth + padding > size {
            nextX = 0
            nextY += rowHeight + padding
            rowHeight = 0
        }

        if nextY + glyphHeight + padding > size {
            return nil
        }

        let region = MTLRegion(
            origin: MTLOrigin(x: nextX, y: nextY, z: 0),
            size: MTLSize(width: glyphWidth, height: glyphHeight, depth: 1)
        )

        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: bitmap,
            bytesPerRow: glyphWidth
        )

        let uvRect = CGRect(
            x: CGFloat(nextX) / CGFloat(size),
            y: CGFloat(nextY) / CGFloat(size),
            width: CGFloat(glyphWidth) / CGFloat(size),
            height: CGFloat(glyphHeight) / CGFloat(size)
        )

        let entry = GlyphEntry(
            uvRect: uvRect,
            size: CGSize(width: glyphWidth, height: glyphHeight),
            bearing: CGPoint(x: boundingRect.origin.x, y: boundingRect.origin.y),
            advance: advance.width
        )

        entries[key] = entry

        nextX += glyphWidth + padding
        rowHeight = max(rowHeight, glyphHeight)

        return entry
    }
}
