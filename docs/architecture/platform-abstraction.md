# macOS Framework Integration

## Philosophy

**This is a macOS-only browser. Forever.**

No cross-platform abstractions. No lowest-common-denominator compromises. We use macOS frameworks directly and embrace the platform fully.

## Tech Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                    Swift + AppKit Shell                          │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  AppDelegate  │  WindowController  │  VulpesView (MTKView) │ │
│  └─────────────────────────────────────────────────────────────┘ │
└────────────────────────────────┬────────────────────────────────┘
                                 │ C ABI
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                       libvulpes (Zig)                            │
│                                                                  │
│  macOS Framework Bindings:                                       │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Metal           │  Core Text        │  Security.framework  │ │
│  │  (Rendering)     │  (Text/Fonts)     │  (TLS/Certs)         │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Zig Standard Library:                                           │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  std.http (HTTP client)  │  std.mem (allocators)            │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Metal Rendering

### Overview

All rendering is done via Metal. Core Text rasterizes glyphs, which are uploaded to Metal textures for GPU-accelerated drawing.

### Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  libvulpes  │────▶│  Core Text  │────▶│    Metal    │
│  (Zig)      │     │  (Glyphs)   │     │  (GPU)      │
└─────────────┘     └─────────────┘     └─────────────┘
      │                   │                   │
      │                   ▼                   ▼
      │             CGBitmapContext     MTLTexture
      │                   │                   │
      │                   └───────────────────┘
      │                          │
      ▼                          ▼
  RenderCommands          Texture Atlas
```

### VulpesView (MTKView)

```swift
import AppKit
import MetalKit

class VulpesView: MTKView {
    private var vulpesContext: OpaquePointer?
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var textureAtlas: TextureAtlas!

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = vulpesContext,
              let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        // Get render commands from libvulpes
        var commands = UnsafeMutablePointer<VulpesRenderCommand>.allocate(capacity: 10000)
        defer { commands.deallocate() }

        let count = vulpes_get_render_commands(ctx, commands, 10000)

        // Execute render commands
        encoder.setRenderPipelineState(pipelineState)

        for i in 0..<Int(count) {
            let cmd = commands[i]
            switch cmd.type {
            case .drawGlyph:
                drawGlyph(cmd.glyph, encoder: encoder)
            case .drawRect:
                drawRect(cmd.rect, encoder: encoder)
            case .drawLine:
                drawLine(cmd.line, encoder: encoder)
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawGlyph(_ glyph: VulpesGlyph, encoder: MTLRenderCommandEncoder) {
        // Look up or create texture for glyph
        let texture = textureAtlas.getTexture(for: glyph)
        encoder.setFragmentTexture(texture, index: 0)
        // Draw quad at glyph position
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
```

### Texture Atlas

Glyph textures are cached in an atlas for efficient GPU memory usage:

```swift
class TextureAtlas {
    private var atlas: MTLTexture
    private var glyphCache: [GlyphKey: GlyphEntry] = [:]
    private var nextPosition: (x: Int, y: Int) = (0, 0)
    private var rowHeight: Int = 0

    struct GlyphKey: Hashable {
        let fontName: String
        let fontSize: CGFloat
        let glyphID: CGGlyph
    }

    struct GlyphEntry {
        let textureRect: CGRect  // UV coordinates in atlas
        let size: CGSize
        let bearing: CGPoint
        let advance: CGFloat
    }

    func getTexture(for glyph: VulpesGlyph) -> GlyphEntry {
        let key = GlyphKey(
            fontName: glyph.fontName,
            fontSize: glyph.fontSize,
            glyphID: glyph.glyphID
        )

        if let cached = glyphCache[key] {
            return cached
        }

        // Rasterize via Core Text
        let entry = rasterizeGlyph(glyph)
        glyphCache[key] = entry
        return entry
    }

    private func rasterizeGlyph(_ glyph: VulpesGlyph) -> GlyphEntry {
        // Create Core Text font
        let font = CTFontCreateWithName(glyph.fontName as CFString, glyph.fontSize, nil)

        // Get glyph bounding box
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, [glyph.glyphID], &boundingRect, 1)

        // Create bitmap context
        let width = Int(ceil(boundingRect.width))
        let height = Int(ceil(boundingRect.height))
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // Draw glyph
        var position = CGPoint(x: -boundingRect.origin.x, y: -boundingRect.origin.y)
        CTFontDrawGlyphs(font, [glyph.glyphID], &position, 1, context)

        // Upload to atlas texture
        // ... (copy bitmap data to atlas at nextPosition)

        return GlyphEntry(...)
    }
}
```

## Core Text Integration

### Font Loading

```zig
// platform/fonts/coretext.zig
const cf = @cImport(@cInclude("CoreFoundation/CoreFoundation.h"));
const ct = @cImport(@cInclude("CoreText/CoreText.h"));
const cg = @cImport(@cInclude("CoreGraphics/CoreGraphics.h"));

pub const Font = struct {
    ct_font: ct.CTFontRef,

    pub fn init(family: []const u8, size: f32) !Font {
        const cf_family = cf.CFStringCreateWithBytes(
            null,
            family.ptr,
            @intCast(family.len),
            cf.kCFStringEncodingUTF8,
            false,
        ) orelse return error.FontNotFound;
        defer cf.CFRelease(cf_family);

        const ct_font = ct.CTFontCreateWithName(cf_family, size, null);
        if (ct_font == null) return error.FontNotFound;

        return Font{ .ct_font = ct_font };
    }

    pub fn deinit(self: *Font) void {
        cf.CFRelease(self.ct_font);
    }

    pub fn getMetrics(self: *Font) FontMetrics {
        return FontMetrics{
            .ascent = ct.CTFontGetAscent(self.ct_font),
            .descent = ct.CTFontGetDescent(self.ct_font),
            .leading = ct.CTFontGetLeading(self.ct_font),
            .units_per_em = ct.CTFontGetUnitsPerEm(self.ct_font),
        };
    }

    pub fn getGlyphAdvances(self: *Font, glyphs: []const ct.CGGlyph) []f64 {
        var advances: [256]cg.CGSize = undefined;
        _ = ct.CTFontGetAdvancesForGlyphs(
            self.ct_font,
            ct.kCTFontOrientationDefault,
            glyphs.ptr,
            &advances,
            @intCast(glyphs.len),
        );
        // Convert to f64 array
        // ...
    }
};

pub const FontMetrics = struct {
    ascent: f64,
    descent: f64,
    leading: f64,
    units_per_em: u32,
};
```

### Text Measurement

```zig
pub fn measureText(font: *Font, text: []const u8) TextMetrics {
    // Create attributed string
    const cf_string = cf.CFStringCreateWithBytes(
        null,
        text.ptr,
        @intCast(text.len),
        cf.kCFStringEncodingUTF8,
        false,
    ) orelse return TextMetrics{};
    defer cf.CFRelease(cf_string);

    const attributes = cf.CFDictionaryCreateMutable(null, 1, null, null);
    cf.CFDictionarySetValue(attributes, ct.kCTFontAttributeName, font.ct_font);
    defer cf.CFRelease(attributes);

    const attr_string = ct.CFAttributedStringCreate(null, cf_string, attributes);
    defer cf.CFRelease(attr_string);

    // Create line and measure
    const line = ct.CTLineCreateWithAttributedString(attr_string);
    defer cf.CFRelease(line);

    var ascent: cg.CGFloat = 0;
    var descent: cg.CGFloat = 0;
    var leading: cg.CGFloat = 0;
    const width = ct.CTLineGetTypographicBounds(line, &ascent, &descent, &leading);

    return TextMetrics{
        .width = width,
        .height = ascent + descent + leading,
        .ascent = ascent,
        .descent = descent,
    };
}

pub const TextMetrics = struct {
    width: f64 = 0,
    height: f64 = 0,
    ascent: f64 = 0,
    descent: f64 = 0,
};
```

## Security.framework Integration

### TLS Certificate Validation

All HTTPS connections use Security.framework for certificate validation, leveraging the macOS system trust store and keychain.

```zig
// platform/tls/security.zig
const sec = @cImport(@cInclude("Security/Security.h"));
const cf = @cImport(@cInclude("CoreFoundation/CoreFoundation.h"));

pub const TlsContext = struct {
    ssl_context: sec.SSLContextRef,

    pub fn init(hostname: []const u8) !TlsContext {
        const ssl_ctx = sec.SSLCreateContext(
            null,
            sec.kSSLClientSide,
            sec.kSSLStreamType,
        ) orelse return error.TlsInitFailed;

        // Set peer hostname for SNI and cert validation
        const status = sec.SSLSetPeerDomainName(
            ssl_ctx,
            hostname.ptr,
            hostname.len,
        );
        if (status != sec.errSecSuccess) return error.TlsConfigFailed;

        return TlsContext{ .ssl_context = ssl_ctx };
    }

    pub fn deinit(self: *TlsContext) void {
        cf.CFRelease(self.ssl_context);
    }

    pub fn handshake(self: *TlsContext) !void {
        var status = sec.SSLHandshake(self.ssl_context);

        while (status == sec.errSSLWouldBlock) {
            // Non-blocking I/O - retry
            status = sec.SSLHandshake(self.ssl_context);
        }

        switch (status) {
            sec.errSecSuccess => {},
            sec.errSSLXCertChainInvalid => return error.CertificateInvalid,
            sec.errSSLCertExpired => return error.CertificateExpired,
            sec.errSSLHostNameMismatch => return error.HostnameMismatch,
            else => return error.TlsHandshakeFailed,
        }
    }

    pub fn getCertificateInfo(self: *TlsContext) ?CertInfo {
        var trust: sec.SecTrustRef = null;
        const status = sec.SSLCopyPeerTrust(self.ssl_context, &trust);
        if (status != sec.errSecSuccess or trust == null) return null;
        defer cf.CFRelease(trust);

        const cert_count = sec.SecTrustGetCertificateCount(trust);
        if (cert_count == 0) return null;

        const cert = sec.SecTrustGetCertificateAtIndex(trust, 0);
        // Extract certificate details...

        return CertInfo{
            .subject = getSubjectName(cert),
            .issuer = getIssuerName(cert),
            .valid_from = getNotBefore(cert),
            .valid_until = getNotAfter(cert),
        };
    }
};

pub const CertInfo = struct {
    subject: []const u8,
    issuer: []const u8,
    valid_from: i64,
    valid_until: i64,
};
```

### Networking with std.http + Security.framework

```zig
const std = @import("std");
const security = @import("platform/tls/security.zig");

pub const HttpClient = struct {
    allocator: std.mem.Allocator,

    pub fn fetch(self: *HttpClient, url: []const u8) !Response {
        const uri = try std.Uri.parse(url);

        if (std.mem.eql(u8, uri.scheme, "https")) {
            return self.fetchHttps(uri);
        } else if (std.mem.eql(u8, uri.scheme, "http")) {
            // HTTP only allowed if explicitly configured
            if (!config.allow_http) return error.HttpNotAllowed;
            return self.fetchHttp(uri);
        }

        return error.UnsupportedScheme;
    }

    fn fetchHttps(self: *HttpClient, uri: std.Uri) !Response {
        // Establish TCP connection
        const stream = try std.net.tcpConnectToHost(
            self.allocator,
            uri.host.?,
            uri.port orelse 443,
        );
        defer stream.close();

        // TLS handshake via Security.framework
        var tls = try security.TlsContext.init(uri.host.?);
        defer tls.deinit();

        try tls.setIOCallbacks(stream);
        try tls.handshake();

        // HTTP request over TLS
        var client = std.http.Client{ .allocator = self.allocator };
        // ... perform HTTP request
    }
};
```

## Build Configuration

```zig
// build.zig
pub fn build(b: *std.Build) void {
    // macOS only - no target options needed
    const target = b.resolveTargetQuery(.{
        .os_tag = .macos,
        .cpu_arch = null,  // Build for host architecture
    });
    const optimize = b.standardOptimizeOption(.{});

    // libvulpes static library
    const libvulpes = b.addStaticLibrary(.{
        .name = "vulpes",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link macOS frameworks
    libvulpes.linkFramework("CoreText");
    libvulpes.linkFramework("CoreFoundation");
    libvulpes.linkFramework("CoreGraphics");
    libvulpes.linkFramework("Security");
    libvulpes.linkFramework("Metal");

    // Install headers for Swift interop
    libvulpes.installHeader(b.path("src/vulpes.h"), "vulpes.h");

    b.installArtifact(libvulpes);
}
```

## Swift Package Integration

The Swift app consumes libvulpes via a module map:

```swift
// Package.swift
import PackageDescription

let package = Package(
    name: "VulpesBrowser",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vulpes", targets: ["Vulpes"]),
    ],
    targets: [
        .systemLibrary(
            name: "libvulpes",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "Vulpes",
            dependencies: ["libvulpes"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
    ]
)
```

## SIMD Optimizations (Apple Silicon)

For text processing and layout on ARM64:

```zig
const std = @import("std");
const builtin = @import("builtin");

pub const SimdBackend = if (builtin.cpu.arch == .aarch64)
    @import("simd/neon.zig")
else
    @import("simd/scalar.zig");

// simd/neon.zig - ARM NEON for Apple Silicon
pub fn findNewlines(data: []const u8) []usize {
    const needle: @Vector(16, u8) = @splat('\n');
    var positions: [256]usize = undefined;
    var count: usize = 0;

    var i: usize = 0;
    while (i + 16 <= data.len) : (i += 16) {
        const chunk: @Vector(16, u8) = data[i..][0..16].*;
        const matches = chunk == needle;
        const mask: u16 = @bitCast(matches);

        var m = mask;
        while (m != 0) {
            const bit_pos = @ctz(m);
            positions[count] = i + bit_pos;
            count += 1;
            m &= m - 1;
        }
    }

    // Handle remaining bytes
    while (i < data.len) : (i += 1) {
        if (data[i] == '\n') {
            positions[count] = i;
            count += 1;
        }
    }

    return positions[0..count];
}
```

## See Also

- [overview.md](overview.md) - Architecture overview
- [libvulpes-core.md](libvulpes-core.md) - Core library design
- [../technical/rendering.md](../technical/rendering.md) - Metal rendering details
