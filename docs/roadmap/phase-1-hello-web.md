# Phase 1: Hello Web

## Goal

Load a URL and display its text content in a native macOS window with Metal rendering. The absolute minimum viable browser with GPU-accelerated text from day one.

## Platform

**macOS only.** This phase establishes the Swift/AppKit shell and Metal rendering pipeline that will be refined in later phases.

## Success Criteria

A native macOS window displaying:
```
Example Domain

This domain is for use in illustrative examples in documents.
You may use this domain in literature without prior coordination
or asking for permission.

More information...
[1] https://www.iana.org/domains/example
```

Rendered with Metal, in a proper macOS window with standard chrome.

## Tech Stack

- **Networking:** Zig `std.http` client
- **Rendering:** Metal (from day 1)
- **Shell:** Swift/AppKit
- **Core Logic:** Zig compiled as static library

## Scope

### In Scope

- [x] Project setup (build.zig, Swift/Xcode integration)
- [ ] Metal rendering pipeline setup
- [ ] Basic glyph atlas for text rendering
- [ ] HTTP/HTTPS GET requests via Zig std.http
- [ ] Basic URL parsing
- [ ] Naive HTML "parsing" (can be regex/simple)
- [ ] Text extraction from HTML
- [ ] Link enumeration (numbered list at end)
- [ ] Basic error handling
- [ ] Swift/AppKit window shell

### Out of Scope

- CSS parsing
- Proper DOM tree
- Layout engine
- Interactive navigation
- Configuration
- Caching

## Milestones

### M1.1: Metal Pipeline Setup

**Goal:** Establish the Metal rendering foundation.

This is front-loaded because GPU text rendering requires infrastructure:
- Metal device and command queue
- Render pipeline state
- Vertex/fragment shaders for textured quads
- Basic coordinate system

```swift
// gui/macos/MetalRenderer.swift
class MetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState

    func render(to drawable: CAMetalDrawable) {
        // Clear and draw quads from glyph atlas
    }
}
```

**Estimated time:** 2-3 days (significant upfront investment)

### M1.2: Glyph Atlas Foundation

**Goal:** Render text using a texture atlas.

```zig
// src/render/atlas.zig
pub const GlyphAtlas = struct {
    texture_data: []u8,
    width: u32,
    height: u32,
    glyphs: std.AutoHashMap(GlyphKey, GlyphInfo),

    pub fn getOrRasterize(self: *GlyphAtlas, codepoint: u21, font_size: f32) GlyphInfo {
        // Use CoreText to rasterize glyph
        // Pack into atlas
        // Return UV coordinates
    }
};
```

Initial implementation:
- ASCII characters only (expand later)
- Single font size
- CoreText for rasterization

**Estimated time:** 2-3 days

### M1.3: Swift/AppKit Shell

**Goal:** Native macOS window hosting Metal view.

```swift
// gui/macos/VulpesApp.swift
import AppKit
import MetalKit

@main
struct VulpesApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class VulpesWindow: NSWindow {
    let metalView: MTKView
    let renderer: MetalRenderer

    // Bridge to libvulpes (Zig core)
    var vulpesContext: OpaquePointer?
}
```

**Estimated time:** 1-2 days

### M1.4: HTTP GET via std.http

**Goal:** Fetch a URL using Zig's standard library HTTP client.

```zig
// src/network/http.zig
const std = @import("std");

pub fn get(allocator: std.mem.Allocator, url: []const u8) !Response {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var request = try client.request(.GET, uri, .{}, .{});
    defer request.deinit();

    try request.wait();

    const body = try request.reader().readAllAlloc(allocator, 1024 * 1024);
    return Response{
        .status = request.response.status,
        .body = body,
    };
}
```

**Benefits of std.http:**
- Built-in TLS support
- Connection pooling
- Redirect handling
- No external dependencies

**Estimated lines:** ~100

### M1.5: URL Parsing

**Goal:** Parse URLs into components.

```zig
// Use std.Uri for parsing
const std = @import("std");

pub fn parseUrl(url: []const u8) !std.Uri {
    return std.Uri.parse(url);
}

// Or wrap for convenience
pub const Url = struct {
    scheme: []const u8,     // "https"
    host: []const u8,       // "example.com"
    port: u16,              // 443
    path: []const u8,       // "/page"
    query: ?[]const u8,     // "foo=bar"
    fragment: ?[]const u8,  // "section"

    pub fn fromStd(uri: std.Uri) Url { ... }
};
```

**Estimated lines:** ~100

### M1.6: Text Extraction

**Goal:** Extract readable text from HTML.

For Phase 1, this can be naive:
```zig
pub fn extractText(html: []const u8) []const u8 {
    // Strip tags (naive approach)
    // Decode basic entities (&amp; etc.)
    // Normalize whitespace
}
```

Handle:
- `<title>` -> display as heading
- `<p>`, `<div>`, `<br>` -> newlines
- `<h1>`-`<h6>` -> uppercase or prefixed
- `<a href="...">` -> collect links
- `<script>`, `<style>` -> skip entirely

**Estimated lines:** ~300

### M1.7: Zig-to-Swift Bridge

**Goal:** C ABI for calling Zig from Swift.

```zig
// src/lib.zig
export fn vulpes_init() ?*VulpesContext {
    // Initialize allocator, state
}

export fn vulpes_load(ctx: *VulpesContext, url: [*:0]const u8) LoadHandle {
    // Start async load
}

export fn vulpes_get_text(ctx: *VulpesContext, handle: LoadHandle) ?[*:0]const u8 {
    // Return extracted text
}
```

```swift
// Swift bridging header
func vulpes_init() -> OpaquePointer?
func vulpes_load(_ ctx: OpaquePointer, _ url: UnsafePointer<CChar>) -> Int32
func vulpes_get_text(_ ctx: OpaquePointer, _ handle: Int32) -> UnsafePointer<CChar>?
```

**Estimated lines:** ~200

## File Structure

```
vulpes-browser/
├── build.zig
├── src/
│   ├── main.zig           # CLI entry (optional, for testing)
│   ├── lib.zig            # C ABI exports
│   ├── network/
│   │   ├── http.zig       # std.http wrapper
│   │   └── url.zig        # URL parsing
│   ├── parse/
│   │   └── text.zig       # Naive text extraction
│   └── render/
│       └── atlas.zig      # Glyph atlas (Zig side)
├── gui/
│   └── macos/
│       ├── VulpesApp.swift
│       ├── VulpesWindow.swift
│       ├── MetalRenderer.swift
│       ├── Shaders.metal
│       └── Info.plist
└── docs/
    └── ...
```

## Testing Strategy

### Manual Testing

Sites that should work:
- https://example.com (canonical test)
- http://info.cern.ch (first website ever)
- Simple HTML pages

Sites that will fail (and that's okay):
- Anything JavaScript-dependent
- Complex layouts

### Unit Tests

```zig
test "url parsing" {
    const uri = try std.Uri.parse("https://example.com:8080/path?query=1#frag");
    try std.testing.expectEqualStrings("https", uri.scheme);
    try std.testing.expectEqualStrings("example.com", uri.host.?);
}

test "text extraction" {
    const html = "<p>Hello <b>world</b></p>";
    const text = extractText(html);
    try std.testing.expectEqualStrings("Hello world", text);
}
```

## Dependencies

### Required
- Zig 0.12+ (stable)
- Xcode / Swift toolchain
- macOS 13+ (for Metal 3 features)

### Frameworks (linked)
- Metal.framework
- MetalKit.framework
- AppKit.framework
- CoreText.framework (for glyph rasterization)

### No External Zig Dependencies
We're building from scratch using Zig's standard library.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Metal learning curve | Medium | Medium | Start simple, iterate |
| Glyph atlas complexity | Medium | High | Begin with ASCII only |
| Swift/Zig bridging issues | Low | Medium | Clean C ABI boundary |
| std.http edge cases | Low | Medium | Test with many sites |
| Scope creep | High | High | Strict phase boundaries |

## Timeline Adjustment

Because we're setting up Metal from day 1 (instead of terminal output), Phase 1 takes longer but sets us up for success:

| Milestone | Estimated Days |
|-----------|----------------|
| M1.1: Metal Pipeline | 2-3 |
| M1.2: Glyph Atlas | 2-3 |
| M1.3: AppKit Shell | 1-2 |
| M1.4: HTTP via std.http | 1 |
| M1.5: URL Parsing | 0.5 |
| M1.6: Text Extraction | 2 |
| M1.7: Zig-Swift Bridge | 1-2 |
| **Total** | **10-14 days** |

This is more than a terminal-based Phase 1 would be, but we avoid a rewrite later.

## Done Criteria

Phase 1 is complete when:

1. A macOS window opens and displays text from a URL
2. Text is rendered via Metal (not Core Graphics/NSTextView)
3. Links are listed with numbers
4. HTTPS works via std.http
5. Basic error messages for failures
6. Code is clean and documented
7. Unit tests pass

## What's Next

Phase 1 proves the concept with the final tech stack. Phase 2 makes it actually useful:
- Real HTML parser (DOM tree)
- Interactive navigation (follow links)
- Vim-style keyboard navigation via AppKit
- Metal glyph atlas refinement

See [phase-2-actually-useful.md](phase-2-actually-useful.md).
