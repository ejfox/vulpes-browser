# Rendering

## Overview

Rendering transforms layout boxes into pixels (GUI) or characters (terminal). vulpes prioritizes speed and clarity—content should appear instantly and be effortlessly readable.

## Rendering Targets

### Terminal (Phase 1-2)
- ANSI escape sequences
- Character grid
- 256/truecolor support
- No GPU required

### Native macOS GUI (Phase 3)
- Metal for GPU acceleration
- Core Text for typography
- Native scrolling and input
- Retina support

## Terminal Rendering

### ANSI Escape Codes

```zig
const TerminalRenderer = struct {
    buffer: []u8,
    width: u32,
    height: u32,

    // Cursor positioning
    pub fn moveTo(self: *TerminalRenderer, x: u32, y: u32) void {
        self.write("\x1b[{};{}H", .{ y + 1, x + 1 });
    }

    // Colors (24-bit)
    pub fn setForeground(self: *TerminalRenderer, color: Color) void {
        self.write("\x1b[38;2;{};{};{}m", .{ color.r, color.g, color.b });
    }

    pub fn setBackground(self: *TerminalRenderer, color: Color) void {
        self.write("\x1b[48;2;{};{};{}m", .{ color.r, color.g, color.b });
    }

    // Styles
    pub fn setBold(self: *TerminalRenderer, on: bool) void {
        self.write(if (on) "\x1b[1m" else "\x1b[22m", .{});
    }

    pub fn setItalic(self: *TerminalRenderer, on: bool) void {
        self.write(if (on) "\x1b[3m" else "\x1b[23m", .{});
    }

    pub fn setUnderline(self: *TerminalRenderer, on: bool) void {
        self.write(if (on) "\x1b[4m" else "\x1b[24m", .{});
    }

    // Reset all attributes
    pub fn reset(self: *TerminalRenderer) void {
        self.write("\x1b[0m", .{});
    }

    // Clear screen
    pub fn clear(self: *TerminalRenderer) void {
        self.write("\x1b[2J\x1b[H", .{});
    }

    // Hide/show cursor
    pub fn setCursorVisible(self: *TerminalRenderer, visible: bool) void {
        self.write(if (visible) "\x1b[?25h" else "\x1b[?25l", .{});
    }
};
```

### Rendering Layout to Terminal

```zig
pub fn renderToTerminal(layout: *LayoutTree, terminal: *TerminalRenderer, scroll_y: u32) void {
    terminal.clear();
    terminal.setCursorVisible(false);

    var row: u32 = 0;
    for (layout.lines.items) |line| {
        if (row < scroll_y) {
            row += 1;
            continue;
        }

        if (row - scroll_y >= terminal.height) break;

        terminal.moveTo(0, row - scroll_y);
        renderLine(line, terminal);

        row += 1;
    }

    terminal.reset();
}

fn renderLine(line: *LayoutLine, terminal: *TerminalRenderer) void {
    for (line.runs.items) |run| {
        applyStyle(run.style, terminal);
        terminal.writeText(run.text);
    }
}

fn applyStyle(style: ComputedStyle, terminal: *TerminalRenderer) void {
    terminal.setForeground(style.color);
    if (style.background != .transparent) {
        terminal.setBackground(style.background);
    }
    terminal.setBold(style.font_weight == .bold);
    terminal.setItalic(style.font_style == .italic);
    terminal.setUnderline(style.text_decoration == .underline);
}
```

### Link Hints (nvim-style)

Display hint labels for keyboard navigation:

```zig
pub fn renderLinkHints(links: []Link, terminal: *TerminalRenderer) void {
    const hints = generateHints(links.len);  // "a", "s", "d", "f", "aa", "as"...

    for (links, hints) |link, hint| {
        // Position at link location
        terminal.moveTo(link.x, link.y);

        // Draw hint box
        terminal.setBackground(.{ .r = 255, .g = 200, .b = 0 });
        terminal.setForeground(.{ .r = 0, .g = 0, .b = 0 });
        terminal.writeText(hint);
        terminal.reset();
    }
}

fn generateHints(count: usize) [][]const u8 {
    // Home row keys for fast typing
    const chars = "asdfjkl;ghqwertyuiopzxcvbnm";
    var hints = ArrayList([]const u8).init(allocator);

    // Single char hints first
    for (chars[0..@min(count, chars.len)]) |c| {
        hints.append(&[_]u8{c});
    }

    // Two char hints if needed
    if (count > chars.len) {
        for (chars) |c1| {
            for (chars) |c2| {
                hints.append(&[_]u8{ c1, c2 });
                if (hints.items.len >= count) break;
            }
            if (hints.items.len >= count) break;
        }
    }

    return hints.items;
}
```

## GUI Rendering (Metal)

### Render Command Buffer

Abstract rendering for the GUI:

```zig
const RenderCommand = union(enum) {
    clear: Color,

    draw_text: struct {
        text: []const u8,
        x: f32,
        y: f32,
        font: FontHandle,
        size: f32,
        color: Color,
    },

    draw_rect: struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        color: Color,
        corner_radius: f32,
    },

    draw_line: struct {
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        color: Color,
        thickness: f32,
    },

    set_clip: struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    },

    clear_clip,
};

pub fn generateRenderCommands(layout: *LayoutTree, viewport: Viewport) []RenderCommand {
    var commands = ArrayList(RenderCommand).init(allocator);

    // Clear background
    commands.append(.{ .clear = theme.background });

    // Render visible boxes
    for (layout.visibleBoxes(viewport)) |box| {
        renderBox(box, &commands, viewport);
    }

    return commands.items;
}
```

### Metal Renderer (Swift)

```swift
// MetalRenderer.swift
import MetalKit

class MetalTextRenderer {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var glyphAtlas: MTLTexture
    var vertexBuffer: MTLBuffer

    func render(commands: [VulpesRenderCommand], to drawable: CAMetalDrawable) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        for command in commands {
            switch command.type {
            case .text:
                renderText(command.text, encoder: renderEncoder)
            case .rect:
                renderRect(command.rect, encoder: renderEncoder)
            case .clear:
                // Handled by clear color in render pass
                break
            }
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func renderText(_ text: TextCommand, encoder: MTLRenderCommandEncoder) {
        // 1. Shape text (get glyph positions)
        // 2. Upload vertices for glyph quads
        // 3. Bind glyph atlas texture
        // 4. Draw instanced quads
    }
}
```

### Text Rendering Pipeline

```
Text String
    │
    ▼
┌─────────────┐
│   Shaping   │  ← CoreText/HarfBuzz
│             │     Determine glyph IDs and positions
└─────────────┘
    │
    ▼
┌─────────────┐
│ Rasterize   │  ← CoreText/FreeType
│   Glyphs    │     Render to glyph atlas
└─────────────┘
    │
    ▼
┌─────────────┐
│  Generate   │  ← Create quad vertices
│   Quads     │     with texture coords
└─────────────┘
    │
    ▼
┌─────────────┐
│    GPU      │  ← Draw textured quads
│   Render    │     with subpixel AA
└─────────────┘
```

### Glyph Atlas

Cache rendered glyphs in a texture:

```zig
const GlyphAtlas = struct {
    texture: Texture,
    width: u32,
    height: u32,
    entries: std.HashMap(GlyphKey, AtlasEntry),
    packer: RectPacker,

    const GlyphKey = struct {
        codepoint: u21,
        font: FontHandle,
        size: u16,  // Fixed point for hashing
    };

    const AtlasEntry = struct {
        x: u16,
        y: u16,
        width: u16,
        height: u16,
        bearing_x: i16,
        bearing_y: i16,
        advance: u16,
    };

    pub fn getGlyph(self: *GlyphAtlas, key: GlyphKey) AtlasEntry {
        if (self.entries.get(key)) |entry| {
            return entry;
        }

        // Rasterize glyph
        const bitmap = rasterizeGlyph(key);

        // Pack into atlas
        const pos = self.packer.pack(bitmap.width, bitmap.height);

        // Upload to texture
        self.texture.upload(pos.x, pos.y, bitmap);

        // Cache entry
        const entry = AtlasEntry{
            .x = pos.x,
            .y = pos.y,
            .width = bitmap.width,
            .height = bitmap.height,
            .bearing_x = bitmap.bearing_x,
            .bearing_y = bitmap.bearing_y,
            .advance = bitmap.advance,
        };
        self.entries.put(key, entry);

        return entry;
    }
};
```

## Performance Optimization

### Double Buffering

Render to back buffer while displaying front:

```zig
const DoubleBuffer = struct {
    buffers: [2]RenderBuffer,
    current: u1,

    pub fn swap(self: *DoubleBuffer) void {
        self.current ^= 1;
    }

    pub fn front(self: *DoubleBuffer) *RenderBuffer {
        return &self.buffers[self.current];
    }

    pub fn back(self: *DoubleBuffer) *RenderBuffer {
        return &self.buffers[self.current ^ 1];
    }
};
```

### Dirty Rectangles

Only redraw what changed:

```zig
const DirtyRegion = struct {
    rects: ArrayList(Rect),

    pub fn add(self: *DirtyRegion, rect: Rect) void {
        // Merge overlapping rects
        for (self.rects.items) |*existing| {
            if (existing.intersects(rect)) {
                existing.* = existing.union(rect);
                return;
            }
        }
        self.rects.append(rect);
    }

    pub fn clear(self: *DirtyRegion) void {
        self.rects.clearRetainingCapacity();
    }
};
```

### Frame Pacing

Target 60fps, skip frames if behind:

```zig
const FramePacer = struct {
    target_frame_time: i64 = 16_666_667,  // 60fps in nanoseconds
    last_frame: i64,

    pub fn beginFrame(self: *FramePacer) void {
        self.last_frame = std.time.nanoTimestamp();
    }

    pub fn endFrame(self: *FramePacer) void {
        const elapsed = std.time.nanoTimestamp() - self.last_frame;
        const remaining = self.target_frame_time - elapsed;

        if (remaining > 0) {
            std.time.sleep(@intCast(remaining));
        }
    }
};
```

## Scrolling

### Smooth Scrolling

```zig
const SmoothScroller = struct {
    target_y: f32,
    current_y: f32,
    velocity: f32,

    pub fn scrollTo(self: *SmoothScroller, y: f32) void {
        self.target_y = y;
    }

    pub fn scrollBy(self: *SmoothScroller, delta: f32) void {
        self.target_y += delta;
    }

    pub fn update(self: *SmoothScroller, dt: f32) bool {
        const diff = self.target_y - self.current_y;

        if (@abs(diff) < 0.5) {
            self.current_y = self.target_y;
            self.velocity = 0;
            return false;  // Animation complete
        }

        // Spring physics
        const spring = 0.3;
        const damping = 0.8;

        self.velocity = self.velocity * damping + diff * spring;
        self.current_y += self.velocity * dt;

        return true;  // Still animating
    }
};
```

### Momentum Scrolling (Trackpad)

```zig
pub fn handleTrackpadScroll(delta: f32, phase: ScrollPhase) void {
    switch (phase) {
        .began, .changed => {
            // Direct scroll
            scroller.scrollBy(delta);
        },
        .ended => {
            // Apply momentum
            scroller.velocity = last_velocity;
        },
        .cancelled => {
            scroller.velocity = 0;
        },
    }
}
```

## Theme Support

```zig
const Theme = struct {
    background: Color,
    foreground: Color,
    link: Color,
    link_visited: Color,
    selection: Color,
    heading: Color,
    code_background: Color,
    code_foreground: Color,

    pub const dark = Theme{
        .background = Color.fromHex("#1a1a1a"),
        .foreground = Color.fromHex("#e0e0e0"),
        .link = Color.fromHex("#6cb6ff"),
        .link_visited = Color.fromHex("#a371f7"),
        .selection = Color.fromHex("#264f78"),
        .heading = Color.fromHex("#ffffff"),
        .code_background = Color.fromHex("#2d2d2d"),
        .code_foreground = Color.fromHex("#e6e6e6"),
    };

    pub const light = Theme{
        .background = Color.fromHex("#ffffff"),
        .foreground = Color.fromHex("#1a1a1a"),
        .link = Color.fromHex("#0066cc"),
        .link_visited = Color.fromHex("#551a8b"),
        .selection = Color.fromHex("#b4d7ff"),
        .heading = Color.fromHex("#000000"),
        .code_background = Color.fromHex("#f5f5f5"),
        .code_foreground = Color.fromHex("#1a1a1a"),
    };
};
```

## See Also

- [text-layout.md](text-layout.md) - Layout engine
- [../architecture/platform-abstraction.md](../architecture/platform-abstraction.md) - Platform-specific rendering
