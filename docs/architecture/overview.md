# Architecture Overview

## Design Goals

vulpes-browser is a macOS-native browser built with a clear, opinionated tech stack:

1. **Fast** - Sub-100ms page loads for target content
2. **Feature-rich** - Full support for our curated feature set
3. **Native** - macOS-native rendering via Metal, native text via Core Text

These are not mutually exclusive when you're intentional about scope.

## Tech Stack (Locked In)

| Component | Technology | Notes |
|-----------|------------|-------|
| Core Engine | **Zig** | Memory-safe, comptime, C-ABI compatible |
| GUI Framework | **Swift + AppKit** | Native macOS application shell |
| Rendering | **Metal** | GPU-accelerated, macOS-native graphics |
| Text | **Core Text** | Glyphs rasterized to Metal textures |
| Networking | **Zig std.http** | HTTP client from Zig standard library |
| TLS/Certs | **Security.framework** | System certificate trust, keychain integration |

**This is macOS-only, forever. No cross-platform considerations.**

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      macOS APPLICATION                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Swift + AppKit Shell                     │  │
│  │                                                            │  │
│  │  ┌─────────────────┐  ┌────────────────────────────────┐  │  │
│  │  │   AppDelegate   │  │         VulpesView            │  │  │
│  │  │   WindowGroup   │  │   (MTKView + Metal pipeline)  │  │  │
│  │  └─────────────────┘  └────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              │ C ABI                             │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                       libvulpes (Zig)                      │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │                    Public API                        │  │  │
│  │  │  vulpes_init() | vulpes_load() | vulpes_render()    │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                              │                             │  │
│  │  ┌───────────┬───────────┬───────────┬───────────────┐   │  │
│  │  │  Network  │   Parse   │  Layout   │    Render     │   │  │
│  │  │  Module   │  Module   │  Module   │    Module     │   │  │
│  │  │           │           │           │               │   │  │
│  │  │ std.http  │   HTML    │   Box     │   Metal       │   │  │
│  │  │ Security  │   CSS     │   Tree    │   Textures    │   │  │
│  │  └───────────┴───────────┴───────────┴───────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   macOS Frameworks                         │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │
│  │  │    Metal    │  │  Core Text  │  │    Security     │   │  │
│  │  │   (GPU)     │  │   (Fonts)   │  │  (TLS/Certs)    │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### Swift + AppKit Shell

The native macOS application layer. Handles:

- Window management via AppKit
- Input capture (keyboard, mouse, trackpad gestures)
- Metal rendering surface (MTKView)
- Menu bar and system integration
- User preferences via UserDefaults

```swift
// VulpesView.swift
import AppKit
import MetalKit

class VulpesView: MTKView {
    var vulpesContext: OpaquePointer?
    var textureCache: [GlyphKey: MTLTexture] = [:]

    override func draw(_ rect: CGRect) {
        guard let ctx = vulpesContext,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Get render commands from libvulpes
        var commands = [VulpesRenderCommand](repeating: .init(), count: 10000)
        let count = vulpes_get_render_commands(ctx, &commands, UInt32(commands.count))

        // Execute with Metal
        executeRenderCommands(commands[..<Int(count)], to: drawable, with: commandBuffer)
    }
}
```

### libvulpes Core (Zig)

The heart of the browser. C-ABI compatible library written in Zig.

```zig
// Public API (C-compatible)
pub export fn vulpes_init(config: *const Config) ?*Context;
pub export fn vulpes_load(ctx: *Context, url: [*:0]const u8) LoadResult;
pub export fn vulpes_render(ctx: *Context, surface: *Surface) void;
pub export fn vulpes_navigate(ctx: *Context, direction: Direction) void;
pub export fn vulpes_deinit(ctx: *Context) void;
```

### Internal Modules

#### Network Module (Zig std.http + Security.framework)
- HTTP/1.1 client via Zig's `std.http.Client`
- TLS certificate validation via Security.framework
- Connection pooling
- Caching layer
- Redirect handling

#### Parse Module
- HTML tokenizer (WHATWG-inspired)
- HTML tree builder
- CSS tokenizer and parser
- DOM construction

#### Layout Module
- Box model calculations
- Text measurement via Core Text metrics
- Flow layout (block/inline)
- Link hit-testing

#### Render Module (Metal)
- Glyph rasterization: Core Text -> Metal textures
- Texture atlas management
- GPU-accelerated drawing
- Viewport management

## Data Flow

```
URL Input
    │
    ▼
┌─────────────┐     ┌─────────┐     ┌─────────┐     ┌─────────────┐
│   Network   │────▶│  Parse  │────▶│ Layout  │────▶│   Render    │
│             │     │         │     │         │     │             │
│  std.http   │     │  HTML   │     │  Box    │     │  Core Text  │
│  Security   │     │  → DOM  │     │  tree   │     │  → Metal    │
└─────────────┘     └─────────┘     └─────────┘     └─────────────┘
    │                    │               │                │
    ▼                    ▼               ▼                ▼
  bytes              Document        LayoutTree       MTLTexture
                      Tree                            (glyphs)
```

## Text Rendering Pipeline

Core Text glyphs are rasterized and uploaded to Metal textures:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Core Text     │────▶│  Glyph Cache    │────▶│     Metal       │
│                 │     │                 │     │                 │
│ CTFontCreatePath│     │ [GlyphKey:      │     │ MTLTexture      │
│ CGContextDraw   │     │  CGImage]       │     │ drawPrimitives  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Memory Model

Following Zig's explicit memory management:

```
┌─────────────────────────────────────────┐
│              Global Arena               │
│  (Application lifetime allocations)     │
│  - Configuration                        │
│  - Glyph texture cache                  │
│  - Persistent state                     │
└─────────────────────────────────────────┘
                    │
    ┌───────────────┼───────────────┐
    ▼               ▼               ▼
┌─────────┐   ┌─────────┐   ┌─────────┐
│  Page   │   │  Page   │   │  Page   │
│  Arena  │   │  Arena  │   │  Arena  │
│         │   │         │   │         │
│ - DOM   │   │ - DOM   │   │ - DOM   │
│ - CSSOM │   │ - CSSOM │   │ - CSSOM │
│ - Layout│   │ - Layout│   │ - Layout│
└─────────┘   └─────────┘   └─────────┘
     │
     ▼
  (freed on navigation)
```

**Why arenas?**
- Browser engines notoriously fight Rust's borrow checker
- DOM trees have complex, cyclic references
- Per-page arenas allow bulk deallocation
- Matches how browsers actually manage memory

## Error Handling Strategy

```zig
// Errors are values, not exceptions
const LoadError = error{
    NetworkTimeout,
    DnsResolutionFailed,
    TlsHandshakeFailed,
    CertificateInvalid,  // Security.framework rejection
    InvalidHtml,
    OutOfMemory,
};

// Graceful degradation for rendering
const RenderResult = union(enum) {
    success: void,
    partial: PartialRenderInfo,  // Rendered what we could
    failed: RenderError,
};
```

**Philosophy**: A personal browser should never crash. Degrade gracefully, show what you can, clearly indicate problems.

## Configuration

```zig
pub const Config = struct {
    // Network
    timeout_ms: u32 = 10_000,
    max_redirects: u8 = 10,
    user_agent: []const u8 = "vulpes/0.1",

    // Rendering (Metal)
    preferred_color_space: ColorSpace = .display_p3,
    max_texture_atlas_size: u32 = 4096,

    // Text (Core Text)
    default_font_family: []const u8 = "system-ui",
    default_font_size: u16 = 16,
    line_height: f32 = 1.5,

    // Behavior
    enable_css: bool = true,
    enable_images: bool = false,  // off by default
    dark_mode: bool = true,

    // Security (Security.framework)
    allow_http: bool = false,  // HTTPS only by default
    allowed_hosts: ?[]const []const u8 = null,
};
```

## See Also

- [libvulpes-core.md](libvulpes-core.md) - Detailed core library design
- [threading-model.md](threading-model.md) - Concurrency architecture
- [platform-abstraction.md](platform-abstraction.md) - macOS framework integration
