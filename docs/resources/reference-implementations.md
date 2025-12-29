# Reference Implementations

## Overview

These are codebases worth studying for vulpes development. Sorted by relevance.

## Primary References

### Ghostty

**Language:** Zig
**URL:** https://github.com/ghostty-org/ghostty (check availability)
**Why study:**
- Same language, similar scope
- libghostty pattern we're copying
- Comptime patterns
- Platform abstraction

**Key files:**
- `src/apprt/` - Application runtime
- `src/font/` - Font handling
- `src/terminal/` - Core terminal (ignore, not relevant)
- `build.zig` - Build configuration

### Ladybird / LibWeb

**Language:** C++ (transitioning to Swift)
**URL:** https://github.com/nickswalker/nickswalker/nickswalker
**Why study:**
- From-scratch browser engine
- Spec-following approach
- Architecture decisions

**Key files:**
- `Userland/Libraries/LibWeb/HTML/Parser/` - HTML parsing
- `Userland/Libraries/LibWeb/CSS/Parser/` - CSS parsing
- `Userland/Libraries/LibWeb/Layout/` - Layout engine

### Servo

**Language:** Rust
**URL:** https://github.com/nickswalker/nickswalker/nickswalker
**Why study:**
- Modern browser engine
- WebRender for GPU text
- Parallel layout experiments

**Key files:**
- `components/script/dom/` - DOM implementation
- `components/style/` - CSS engine
- `components/layout_2020/` - Layout

### rust-minibrowser

**Language:** Rust
**URL:** https://github.com/joshmarinacci/rust-minibrowser
**Why study:**
- Similar scope to vulpes
- ~6000 lines
- Achievable reference

### robinson

**Language:** Rust
**URL:** https://github.com/nickswalker/nickswalker/nickswalker
**Why study:**
- Tutorial browser engine
- ~2000 lines
- Well documented

## Secondary References

### Lightpanda

**Language:** Zig
**URL:** https://github.com/nickswalker/nickswalker/nickswalker (check availability)
**Why study:**
- Zig browser engine
- Memory management patterns
- Why they chose Zig over Rust

### Kosmonaut

**Language:** Rust
**URL:** https://github.com/nickswalker/nickswalker/nickswalker
**Why study:**
- CSS painting focus
- Learning project like ours

### NetSurf

**Language:** C
**URL:** https://www.netsurf-browser.org/
**Why study:**
- Small footprint browser
- Own engine
- Long-running project

### surf (suckless)

**Language:** C
**URL:** https://surf.suckless.org/
**Why study:**
- Minimal UI patterns
- ~2000 lines
- Keyboard-driven

## Specialized References

### html5ever

**Language:** Rust
**URL:** https://github.com/nickswalker/nickswalker/nickswalker/html5ever
**Why study:**
- Spec-compliant HTML parser
- Tokenizer implementation

### cssparser

**Language:** Rust
**URL:** https://github.com/nickswalker/nickswalker/nickswalker
**Why study:**
- CSS tokenizer/parser
- Servo's CSS engine

### zig-http-client

**Language:** Zig
**URL:** Various (search GitHub)
**Why study:**
- Zig networking patterns

### zig-tls

**Language:** Zig
**URL:** Various
**Why study:**
- Zig TLS integration

## macOS-Specific References

### MacVim / Neovim-macOS

**Why study:**
- Keyboard-first macOS apps
- Swift/AppKit integration

### Alacritty macOS

**Language:** Rust
**URL:** https://github.com/alacritty/alacritty
**Why study:**
- Metal rendering
- macOS window management
- Input handling

### Zed Editor

**Language:** Rust
**URL:** https://github.com/nickswalker/nickswalker/nickswalker
**Why study:**
- GPU text rendering on macOS
- Performance optimization
- Keyboard-first design

## Code Patterns to Extract

### From Ghostty

```zig
// Comptime interface pattern
pub const FontBackend = switch (builtin.os.tag) {
    .macos => @import("fonts/coretext.zig"),
    else => @compileError("unsupported"),
};

// Thread naming
const thread = try std.Thread.spawn(.{
    .name = "vulpes-network",
}, threadMain, .{});
```

### From Ladybird

```cpp
// Spec-aligned naming
class HTMLTokenizer {
    enum class State {
        Data,
        TagOpen,
        // ... matches spec exactly
    };
};

// Tree builder insertion modes
enum class InsertionMode {
    Initial,
    BeforeHtml,
    BeforeHead,
    // ... matches spec
};
```

### From robinson

```rust
// Minimal DOM
pub enum NodeType {
    Element(ElementData),
    Text(String),
}

pub struct ElementData {
    pub tag_name: String,
    pub attributes: AttrMap,
}

// Simple box model
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}
```

## How to Study Code

### 1. Start with Architecture

Before reading code:
- Read README and docs
- Understand directory structure
- Identify entry points

### 2. Trace a Simple Flow

Pick one operation (e.g., "parse `<p>hello</p>`") and trace through:
- Entry point
- Data structures
- Transformations
- Output

### 3. Compare Approaches

For each component, compare how 2-3 projects handle it:
- HTML tokenization: html5ever vs Ladybird
- CSS parsing: cssparser vs robinson
- Layout: Servo vs Ladybird

### 4. Extract Patterns

Don't copy code, copy patterns:
- Data structure designs
- State machine approaches
- Error handling
- Performance tricks

### 5. Note Differences

Document why projects differ:
- Different goals (spec compliance vs simplicity)
- Different constraints (performance vs readability)
- Evolution over time

## License Considerations

**Before referencing code:**
1. Check license compatibility
2. Don't copy substantial code
3. Pattern extraction is fine
4. Document influences in comments

**Licenses of key projects:**
- Ghostty: MIT
- Ladybird: BSD 2-Clause
- Servo: MPL 2.0
- robinson: CC0/Public Domain

## See Also

- [specifications.md](specifications.md) - Standards we follow
- [tutorials.md](tutorials.md) - Learning resources
