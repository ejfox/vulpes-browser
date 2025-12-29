# Ghostty: Design Inspiration

## Overview

[Ghostty](https://ghostty.org) is a terminal emulator created by Mitchell Hashimoto (founder of HashiCorp). It represents the gold standard for intentional, native software design that vulpes-browser aspires to follow.

## Key Takeaways for vulpes

### 1. The libghostty Architecture

Ghostty's most important architectural decision is separating the core into a standalone library (libghostty) that provides:
- Terminal emulation
- Font rendering
- Core rendering logic

The GUI applications (macOS, Linux) are thin shells that consume this library.

**vulpes equivalent:**
```
libvulpes (core)
├── HTML parsing
├── CSS parsing
├── Layout engine
├── Text rendering abstraction
└── C-ABI interface

vulpes-tui (terminal shell)
vulpes-gui (native GUI shell, future)
```

**Why this matters:**
- Test the core independently
- Multiple UIs without code duplication
- Embed in other applications
- Each platform gets truly native UI

### 2. "Fast, Features, Native Is Not Mutually Exclusive"

The conventional wisdom says you can pick two of:
- Fast
- Feature-rich
- Native feel

Ghostty rejects this. Mitchell's insight: the tradeoff is false if you're willing to do the work.

**How Ghostty achieves all three:**
- Custom GPU-accelerated rendering (fast)
- Full terminal emulation, ligatures, images, etc. (features)
- Swift/AppKit on macOS, GTK on Linux (native)

**vulpes application:**
- We won't compete with Chromium on features
- But within our scope, we can be fast AND native AND featureful
- The key is being intentional about scope

### 3. Comptime Interface Pattern

Ghostty uses Zig's compile-time execution heavily for zero-cost abstractions:

```zig
// Platform-specific code selected at compile time
pub const FontBackend = switch (builtin.os.tag) {
    .macos => @import("fonts/coretext.zig"),
    .linux => @import("fonts/fontconfig.zig"),
    else => @import("fonts/stb.zig"),
};
```

**Benefits:**
- No runtime dispatch overhead
- Dead code elimination (unused platforms not compiled)
- Type-safe platform abstraction

**vulpes application:**
```zig
pub const TlsBackend = switch (builtin.os.tag) {
    .macos => @import("tls/securetransport.zig"),
    .linux => @import("tls/openssl.zig"),
    else => @import("tls/bearssl.zig"),
};

pub const SimdOps = switch (builtin.cpu.arch) {
    .aarch64 => @import("simd/neon.zig"),
    .x86_64 => @import("simd/avx2.zig"),
    else => @import("simd/scalar.zig"),
};
```

### 4. Comptime Data Tables

Instead of runtime lookup tables, Ghostty defines data at comptime:

```zig
const KeyMappings = comptime blk: {
    var result: [256]KeyAction = undefined;
    // Build table at compile time
    for (raw_mappings) |mapping| {
        result[mapping.code] = mapping.action;
    }
    break :blk result;
};
```

**vulpes application:**
- HTML entity mappings (`&amp;` → `&`)
- CSS property lookup tables
- Character encoding tables

### 5. "70% Font Rendering"

Mitchell's joke that Ghostty is "70% a font rendering engine and 30% a terminal emulator" reveals a truth: text rendering is the hard part.

**Challenges:**
- Font discovery and fallback
- Glyph rasterization
- Subpixel positioning
- Unicode/emoji handling
- Performance with large text

**vulpes implication:**
- Don't underestimate text layout
- Budget significant time for fonts
- Use system font libraries (CoreText, Fontconfig)
- Test with real content early

### 6. Thread Architecture

Ghostty's runtime separates concerns:
- **IO Thread**: PTY read/write, escape sequence handling
- **Render Thread**: Drawing at framerate

**vulpes equivalent:**
- **Network Thread** (optional): HTTP fetching
- **Main Thread**: Parsing, layout, input
- **Render Thread** (GUI only): Drawing at framerate

For terminal UI, single-threaded is fine initially.

### 7. Starting as a Learning Project

From Mitchell:
> "I started the project in 2022 merely as a way to play with Zig, do some graphics programming, and deepen my understanding of terminals. I never intended to release it."

**Lesson:** The best projects often start as learning exercises. Build for yourself first.

### 8. Platform-Specific Optimizations

Ghostty doesn't just compile for multiple platforms—it *optimizes* for them:
- ARM NEON instructions on Apple Silicon
- x86 SIMD on Intel
- Metal on macOS, OpenGL on Linux

**vulpes approach:**
- Phase 1: Get it working (scalar code)
- Phase 2: Profile and identify hotspots
- Phase 3: Platform-specific optimizations where measured

### 9. Configuration Philosophy

Ghostty has configuration, but it's:
- Simple (single config file)
- Documented
- Reasonable defaults
- No GUI configurator

**vulpes config approach:**
```zig
pub const Config = struct {
    font_size: u16 = 16,
    dark_mode: bool = true,
    max_width: u32 = 80,
    allow_http: bool = false,
    // ...
};
```

Load from file, override from CLI, done.

## Ghostty Resources

### Primary Sources
- [Ghostty Official Docs](https://ghostty.org/docs/about)
- [Ghostty 1.0 Reflection](https://mitchellh.com/writing/ghostty-1-0-reflection)
- [Ghostty Zig Patterns](https://mitchellh.com/writing/ghostty-and-useful-zig-patterns)
- [libghostty Is Coming](https://mitchellh.com/writing/libghostty-is-coming)

### Talks
- [Terminal Trove Interview](https://terminaltrove.com/blog/terminal-trove-talks-with-mitchell-hashimoto-ghostty/)

### Code (when public)
- GitHub (check ghostty.org for current status)

## What We Adapt vs. Copy

### Adapt (principles)
- Core library architecture
- Comptime patterns
- Native-first philosophy
- Starting as learning project
- Intentional scope

### Don't Copy (specifics)
- Terminal emulation (we're not a terminal)
- PTY handling (we do HTTP)
- VT escape sequences (we parse HTML)
- Their exact thread model (ours is simpler)

## See Also

- [ladybird.md](ladybird.md) - Ladybird inspiration
- [prior-art.md](prior-art.md) - Other browser projects
- [../principles.md](../principles.md) - Our principles
