# Vulpes Browser Technology Stack

> **Platform: macOS only.** No cross-platform. This is intentional.

This document records the locked-in technology decisions for Vulpes Browser. These choices are final and form the foundation of the architecture.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        macOS Application                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    Swift / AppKit Layer                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │  │
│  │  │   AppKit    │  │   Metal     │  │    Core Text        │   │  │
│  │  │  Windows    │  │   Views     │  │   (text shaping)    │   │  │
│  │  │  + Events   │  │  (rendering)│  │                     │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘   │  │
│  │                                                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐ │  │
│  │  │              Keyboard-First Event Handling              │ │  │
│  │  │                 (vim-style navigation)                  │ │  │
│  │  └─────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                               │                                     │
│                               │ C ABI                               │
│                               ▼                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                      libvulpes (Zig Core)                     │  │
│  │                                                               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │  │
│  │  │   HTML      │  │    CSS      │  │    Layout           │   │  │
│  │  │   Parser    │  │   Parser    │  │    Engine           │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘   │  │
│  │                                                               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │  │
│  │  │   DOM       │  │   Style     │  │    Render           │   │  │
│  │  │   Tree      │  │   Resolver  │  │    Tree             │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘   │  │
│  │                                                               │  │
│  │  ┌───────────────────────────────────────────────────────┐   │  │
│  │  │                    Zig std.http                        │   │  │
│  │  │              + Security.framework (TLS)                │   │  │
│  │  └───────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │       Network         │
                    │    (HTTP/HTTPS)       │
                    └───────────────────────┘
```

---

## Technology Decisions

### 1. Core Engine: Zig

**Status:** LOCKED

**Choice:** Zig for all browser engine internals (libvulpes)

**Why:**
- **Comptime magic** - Like Ghostty demonstrates, Zig's compile-time evaluation enables zero-cost abstractions and eliminates runtime overhead for parsing, layout calculations, and rendering pipelines
- **C ABI native** - Seamless interop with Swift; no wrapper code needed, functions export directly
- **Explicit memory management** - No GC pauses, predictable performance, full control over allocations
- **Fast compiles** - Iteration speed matters; Zig compiles quickly even for large codebases

**Trade-off:** Smaller ecosystem compared to Rust or C++. But we're building from scratch anyway - we don't need a massive package ecosystem.

---

### 2. GUI Framework: AppKit (Swift)

**Status:** LOCKED

**Choice:** AppKit with Swift, not SwiftUI

**Why:**
- **Full keyboard control** - Critical for vim-style navigation. AppKit gives direct access to key events, responder chain, and input handling
- **Ghostty precedent** - Proven architecture for high-performance keyboard-driven apps
- **Metal integration** - Custom Metal views (`MTKView`) integrate cleanly into AppKit windows
- **Mature and stable** - 20+ years of refinement, excellent documentation, predictable behavior

**Trade-off:** More boilerplate than SwiftUI. But keyboard-first demands it. SwiftUI's declarative model fights against fine-grained keyboard control.

---

### 3. Rendering: Metal

**Status:** LOCKED

**Choice:** Metal for all rendering

**Why:**
- **60fps smooth scrolling** - GPU-accelerated rendering is non-negotiable for a browser in 2024+
- **Glyph atlases** - GPU-accelerated text rendering using texture atlases for maximum performance
- **visionOS compatible** - Future-proofs for spatial computing
- **Apple's direction** - Metal is where Apple invests; OpenGL is deprecated

**Trade-off:** Steeper learning curve than Core Graphics. Worth it to do it right from the start rather than rewrite later.

---

### 4. Text Rendering: Core Text + Metal

**Status:** LOCKED

**Choice:** Core Text for shaping, Metal for rasterization

**Why:**
- **Apple handles the hard parts** - Shaping, kerning, ligatures, emoji, RTL, complex scripts - Core Text solves all of this
- **We just rasterize** - Render glyphs to textures, upload to GPU, draw quads
- **System font support** - Automatic access to SF Pro and all installed fonts
- **Correct rendering** - Users expect text to look like every other macOS app

**Trade-off:** None. This is simply the right choice for macOS. Fighting Core Text would be foolish.

**Pipeline:**
```
Text String
    │
    ▼
┌──────────────────┐
│    Core Text     │  ← Shaping, font selection, glyph IDs
└──────────────────┘
    │
    ▼
┌──────────────────┐
│  Glyph Rasterizer│  ← Render to bitmaps (cached in atlas)
└──────────────────┘
    │
    ▼
┌──────────────────┐
│   Metal Texture  │  ← Upload to GPU
└──────────────────┘
    │
    ▼
┌──────────────────┐
│   Draw Quads     │  ← Render text as textured quads
└──────────────────┘
```

---

### 5. Networking: Zig std.http + Security.framework

**Status:** LOCKED

**Choice:** Zig's standard library HTTP client with macOS Security.framework for TLS

**Why:**
- **Pure Zig core** - libvulpes stays in Zig; no Swift dependencies bleeding into the engine
- **macOS cert store** - Security.framework handles certificate validation, trust chains, and keychain integration
- **Clean architecture** - Network code lives in the Zig layer where it belongs
- **HTTP/2 ready** - Zig std.http supports modern protocols

**Trade-off:** More work than just using URLSession. But this keeps the architecture clean - the Zig core can theoretically work on other platforms later (even if we don't plan to).

**Bridge:**
```
┌─────────────────────────────────────────────┐
│              libvulpes (Zig)                │
│                                             │
│  std.http.Client ──────┐                    │
│                        │                    │
│                        ▼                    │
│  ┌─────────────────────────────────────┐   │
│  │  TLS callback → C ABI → Swift       │   │
│  │                    │                │   │
│  │                    ▼                │   │
│  │           Security.framework        │   │
│  │         (certificate validation)    │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

## What This Means

### We ARE building:
- A macOS-native browser that feels like a first-class citizen
- A keyboard-first interface for power users
- A fast, GPU-accelerated rendering engine
- Clean separation between engine (Zig) and UI (Swift)

### We are NOT building:
- A cross-platform browser
- A WebKit/Blink/Gecko wrapper
- An Electron app
- Something that works on Windows or Linux

---

## Reference Implementations

These projects informed our decisions:

| Project | Relevance |
|---------|-----------|
| **Ghostty** | Zig + Swift + AppKit + Metal architecture |
| **Ladybird** | Modern browser engine from scratch |
| **Servo** | GPU-accelerated rendering, parallel layout |
| **WebKit** | How Apple does text rendering |

---

*Last updated: December 2024*
*These decisions are final. Build on them, don't question them.*
