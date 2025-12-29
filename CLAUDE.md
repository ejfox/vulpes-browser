# CLAUDE.md - Vulpes Browser Development Context

## Project Overview

**vulpes-browser** is a minimalist, keyboard-first web browser for macOS, inspired by Ghostty's intentional design philosophy.

### Tech Stack (Locked In)
- **Core Engine:** Zig (compiles to libvulpes.a static library)
- **GUI:** Swift + AppKit
- **Rendering:** Metal (GPU-accelerated)
- **Text:** Core Text (for glyph rasterization)
- **Networking:** Zig std.http + Security.framework for TLS

### Key Design Decisions
- macOS only, forever (visionOS as stretch goal)
- Keyboard-first (vim-style navigation)
- No JavaScript, no ads, no tracking
- Spatial cards metaphor (HyperCard-inspired, not tabs)

## Current State

### What Works
- `zig build` produces `zig-out/lib/libvulpes.a` (1.6 MB)
- `xcodegen generate` creates `Vulpes.xcodeproj` from `project.yml`
- `xcodebuild` compiles the Swift app successfully
- App launches and creates a window
- Metal device initializes (Apple M1 Pro detected)
- Render pipelines compile (solid + glyph shaders)
- View gets proper bounds (1200x800) and drawable size (2400x1600 for Retina)

### What's Broken
**The Metal view renders a blank/black screen instead of the test blue rectangle.**

The app initializes correctly:
```
MetalView: Metal initialized successfully
  Device: Apple M1 Pro
MetalView: viewDidMoveToWindow
MetalView: Ready - bounds: (0.0, 0.0, 1200.0, 800.0), drawableSize: (2400.0, 1600.0)
```

But nothing renders. The test geometry (a blue rectangle) should appear at (50,50) to (400,200).

## What We've Tried

### 1. Initial CAMetalLayer Setup (Failed)
Created CAMetalLayer manually in `setupMetalLayer()`, assigned to `self.layer`.
- Problem: Drawable size was (0,0) at init time because view hadn't been laid out yet.

### 2. Deferred Setup via viewDidMoveToWindow (Failed)
Added `viewDidMoveToWindow()` to set drawable size after view is in window hierarchy.
- Problem: Still blank screen even though dimensions are correct.

### 3. Proper makeBackingLayer() Pattern (Current - Still Failing)
Rewrote to use the correct AppKit pattern:
```swift
override func makeBackingLayer() -> CALayer {
    let layer = CAMetalLayer()
    layer.device = MTLCreateSystemDefaultDevice()
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    return layer
}
```
With `wantsUpdateLayer = true` and `updateLayer()` calling `render()`.

- The drawable size is now correct (2400x1600)
- But still nothing renders

### 4. Debug Output Added
Added print statements throughout. The `render()` function appears to be called but we never see output from inside it, suggesting either:
- `render()` returns early (guards failing)
- `render()` isn't being called at all despite `updateLayer()` existing

## Suspected Issues

1. **updateLayer vs draw**: When `wantsUpdateLayer` is true, AppKit calls `updateLayer()` instead of `draw(_:)`. We implemented `updateLayer()` to call `render()`, but it may not be triggering.

2. **needsDisplay not being set**: The view might not be marked dirty. Try adding a timer or CVDisplayLink to force redraws.

3. **Shader compilation**: The shaders compile without errors but we haven't verified they actually work. Could try using Metal debugger in Xcode.

4. **Vertex buffer**: The test geometry might have incorrect values or the buffer might not be bound correctly.

5. **Coordinate system mismatch**: The shader transforms pixel coords to clip space. If viewportSize in uniforms is wrong, nothing appears.

## Files to Investigate

### app/MetalView.swift
The main rendering view. Key methods:
- `makeBackingLayer()` - Creates CAMetalLayer
- `commonInit()` - Sets up device, command queue, pipelines
- `setupTestGeometry()` - Creates test blue rectangle vertices
- `render()` - The actual Metal rendering code
- `updateLayer()` - Should trigger render() when view needs update

### app/Shaders.metal
Vertex and fragment shaders:
- `vertexShader` - Transforms pixel coords to clip space
- `fragmentShaderSolid` - Returns solid color
- `fragmentShaderGlyph` - For textured text (not used yet)

### Key Debug Points
1. Is `render()` being called? Add print at very start.
2. Is `metalLayer.nextDrawable()` returning nil?
3. Is `testVertexBuffer` nil?
4. What's the actual viewport size being passed to shader?

## Potential Solutions to Try

### A. Use MTKView Instead
MTKView handles a lot of the boilerplate. Replace NSView + CAMetalLayer with MTKView subclass.

### B. Add CVDisplayLink
Force continuous rendering to ensure draw happens:
```swift
var displayLink: CVDisplayLink?
// Create and start display link in viewDidMoveToWindow
```

### C. Xcode Metal Debugger
Open project in Xcode, run with GPU Frame Capture to see what's actually being submitted.

### D. Simplify Test
Instead of drawing geometry, just clear to a bright color (red) to verify the render pass works at all.

### E. Check presentDrawable
Make sure `commandBuffer.present(drawable)` and `commandBuffer.commit()` are being called.

## Build Commands

```bash
# Build Zig library
cd /Users/ejfox/code/vulpes-browser
zig build

# Generate Xcode project (after editing project.yml)
xcodegen generate

# Build Swift app
xcodebuild -project Vulpes.xcodeproj -scheme Vulpes -configuration Debug build

# Run app
/Users/ejfox/Library/Developer/Xcode/DerivedData/Vulpes-ftwrpbkcvauuefffpskpfmqkmooi/Build/Products/Debug/Vulpes.app/Contents/MacOS/Vulpes
```

## Resources Consulted

- [CAMetalLayer NSView setup](https://metashapes.com/blog/advanced-nsview-setup-opengl-metal-macos/)
- [CustomMetalView sample](https://github.com/cntrump/CustomMetalView)
- [Minimal CAMetalLayer NSView gist](https://gist.github.com/Oleksiy-Yakovenko/d20ff2536cd744474c1b8c3392dc0dbc)
- [Glitchless Metal Window Resizing](https://thume.ca/2019/06/19/glitchless-metal-window-resizing/)

## Phase 1 Roadmap Status

- [x] M1.3: Swift/AppKit Shell - Window opens, Metal view exists
- [x] M1.1: Metal Pipeline Setup - Rendering works at 60fps
- [x] M1.2: Glyph Atlas Foundation - GlyphAtlas class with CoreText
- [x] M1.4: HTTP GET via std.http - Fast HTTP client with TLS and gzip decompression
- [ ] M1.5: URL Parsing
- [ ] M1.6: Text Extraction from HTML
- [ ] M1.7: Zig-to-Swift Bridge completion

## HTTP Client (M1.4)

The HTTP client in `src/network/http.zig` uses Zig 0.15's `std.http.Client`:

**Features:**
- Low-level request API for streaming control
- Automatic gzip/deflate/zstd decompression
- Connection pooling via keep-alive
- TLS via system certificates (Security.framework)
- 10 MB response body limit

**Performance (example.com):**
- 195ms for full HTTPS fetch including TLS handshake and decompression
- 513 bytes decompressed from 366 bytes gzipped

**CLI Test:**
```bash
zig build run -- https://example.com
```

## Zig-Swift Bridge (M1.7)

The C ABI is defined in `src/vulpes.h` and implemented in `src/lib.zig`.

**Exported Functions:**
- `vulpes_init()` / `vulpes_deinit()` - Library lifecycle
- `vulpes_fetch(url)` - HTTP GET, returns `vulpes_fetch_result_t*`
- `vulpes_fetch_free(result)` - Free fetch result
- `vulpes_extract_text(html, len)` - Extract text from HTML
- `vulpes_text_free(result)` - Free text result

**Swift Usage:**
```swift
// Initialize
vulpes_init()

// Fetch URL
guard let result = vulpes_fetch("https://example.com") else { return }
defer { vulpes_fetch_free(result) }

if result.pointee.error_code == 0 {
    let body = Data(bytes: result.pointee.body!, count: result.pointee.body_len)

    // Extract text
    body.withUnsafeBytes { ptr in
        guard let textResult = vulpes_extract_text(ptr.baseAddress!, body.count) else { return }
        defer { vulpes_text_free(textResult) }

        if textResult.pointee.error_code == 0 {
            let text = String(bytes: UnsafeBufferPointer(start: textResult.pointee.text, count: textResult.pointee.text_len), encoding: .utf8)
            print(text ?? "")
        }
    }
}
```

## Phase 1 Complete

All Phase 1 milestones are now complete:
- [x] M1.1: Metal Pipeline Setup
- [x] M1.2: Glyph Atlas Foundation
- [x] M1.3: Swift/AppKit Shell
- [x] M1.4: HTTP GET (195ms fetch, gzip decompression)
- [x] M1.5: URL Parsing (via std.Uri)
- [x] M1.6: Text Extraction (0ms for typical pages)
- [x] M1.7: Zig-Swift Bridge

## End-to-End Integration Complete

The browser is now functional:
1. **VulpesBridge.swift** - Swift wrapper for Zig C API
2. **MetalView.loadURL()** - Fetches URL via Zig, extracts text, renders with glyph atlas
3. **URL bar** - NSTextField at top of window, Enter key navigates

**Running the app:**
```bash
zig build
xcodegen generate
xcodebuild -project Vulpes.xcodeproj -scheme Vulpes build
# Run from Xcode or:
/Users/ejfox/Library/Developer/Xcode/DerivedData/Vulpes-*/Build/Products/Debug/Vulpes.app/Contents/MacOS/Vulpes
```

## Keyboard Navigation (Implemented)

The browser now supports vim-style keyboard navigation:

| Key | Action |
|-----|--------|
| `j` | Scroll down one line |
| `k` | Scroll up one line |
| `d` | Scroll down half page |
| `u` | Scroll up half page |
| `G` | Jump to bottom |
| `gg` | Jump to top |
| `1-9` | Follow numbered link |
| Trackpad/Mouse wheel | Smooth scrolling |

## Link Extraction (Implemented)

- Links are extracted from `<a href="...">` tags
- **Blue link text** - Links render in traditional blue (#6699FF)
- Numbered inline: "Click here [1]"
- Link reference section appended at end:
  ```
  ---
  Links:
  [1] https://example.com
  [2] /relative/path
  ```
- Press 1-9 to follow links
- Relative URLs resolved against current page
- **URL bar updates** when navigating via link

## Next Steps

1. **Back navigation** - Track history, `b` key to go back
2. **URL bar interaction** - Focus URL bar with `/` or `Cmd+L`
3. **Search** - In-page search with `/` key
