# libvulpes Core Library

## Overview

libvulpes is the cross-platform core of vulpes-browser, inspired by Ghostty's libghostty architecture. It provides a C-ABI compatible interface that can be consumed by any language that can call C functions.

## Why a Core Library?

From Mitchell Hashimoto's Ghostty design:

> "This architecture allows for a clean separation between the terminal emulation and the GUI. It is the key architecture that allows Ghostty to achieve its goal of being native."

Benefits for vulpes:
1. **Multiple frontends** - Terminal UI now, native GUI later
2. **Embeddable** - Could be used in other applications
3. **Testable** - Core logic tested independently of UI
4. **Language flexibility** - Swift on macOS, Zig on Linux

## Public API Design

### Initialization

```zig
/// Initialize a vulpes context with the given configuration.
/// Returns null on failure (check vulpes_last_error for details).
pub export fn vulpes_init(config: *const VulpesConfig) ?*VulpesContext;

/// Clean up all resources associated with a context.
pub export fn vulpes_deinit(ctx: *VulpesContext) void;
```

### Page Loading

```zig
/// Load a URL. This is asynchronous - use vulpes_poll to check status.
pub export fn vulpes_load(
    ctx: *VulpesContext,
    url: [*:0]const u8,
) VulpesLoadHandle;

/// Poll for load completion. Returns current status.
pub export fn vulpes_poll(
    ctx: *VulpesContext,
    handle: VulpesLoadHandle,
) VulpesLoadStatus;

/// Cancel an in-progress load.
pub export fn vulpes_cancel(
    ctx: *VulpesContext,
    handle: VulpesLoadHandle,
) void;
```

### Navigation

```zig
/// Navigate to a link by index (0-indexed).
pub export fn vulpes_follow_link(
    ctx: *VulpesContext,
    link_index: u32,
) VulpesLoadHandle;

/// Navigate forward/back in history.
pub export fn vulpes_history_navigate(
    ctx: *VulpesContext,
    direction: VulpesHistoryDirection,
) VulpesLoadHandle;

/// Get information about links on the current page.
pub export fn vulpes_get_links(
    ctx: *VulpesContext,
    out_links: [*]VulpesLink,
    max_links: u32,
) u32;  // Returns actual count
```

### Rendering

```zig
/// Render the current page to a text buffer (for terminal UI).
pub export fn vulpes_render_text(
    ctx: *VulpesContext,
    buffer: [*]u8,
    width: u32,
    height: u32,
    scroll_offset: u32,
) VulpesRenderResult;

/// Render the current page to a pixel buffer (for GUI).
pub export fn vulpes_render_pixels(
    ctx: *VulpesContext,
    buffer: [*]u32,  // RGBA pixels
    width: u32,
    height: u32,
    stride: u32,
    scroll_offset: u32,
) VulpesRenderResult;

/// Get render commands for custom rendering backends.
pub export fn vulpes_get_render_commands(
    ctx: *VulpesContext,
    out_commands: [*]VulpesRenderCommand,
    max_commands: u32,
) u32;
```

### Scrolling

```zig
/// Scroll the viewport.
pub export fn vulpes_scroll(
    ctx: *VulpesContext,
    delta: i32,  // Positive = down, negative = up
) void;

/// Scroll to a specific position (0.0 = top, 1.0 = bottom).
pub export fn vulpes_scroll_to(
    ctx: *VulpesContext,
    position: f32,
) void;

/// Get current scroll information.
pub export fn vulpes_get_scroll_info(
    ctx: *VulpesContext,
) VulpesScrollInfo;
```

### Search

```zig
/// Search for text on the current page.
pub export fn vulpes_search(
    ctx: *VulpesContext,
    query: [*:0]const u8,
    flags: VulpesSearchFlags,
) VulpesSearchResult;

/// Navigate between search results.
pub export fn vulpes_search_next(ctx: *VulpesContext) bool;
pub export fn vulpes_search_prev(ctx: *VulpesContext) bool;

/// Clear search highlighting.
pub export fn vulpes_search_clear(ctx: *VulpesContext) void;
```

## Data Types

### Core Structures

```zig
pub const VulpesConfig = extern struct {
    /// Network timeout in milliseconds.
    timeout_ms: u32 = 10_000,

    /// Maximum number of redirects to follow.
    max_redirects: u8 = 10,

    /// User agent string (null-terminated).
    user_agent: [*:0]const u8 = "vulpes/0.1",

    /// Default font size in points.
    font_size: u16 = 16,

    /// Maximum content width in characters (0 = unlimited).
    max_width: u32 = 80,

    /// Enable CSS styling.
    enable_css: bool = true,

    /// Enable image loading.
    enable_images: bool = false,

    /// Dark mode.
    dark_mode: bool = true,

    /// Allow insecure HTTP connections.
    allow_insecure: bool = false,

    /// Memory limit in bytes (0 = unlimited).
    memory_limit: u64 = 0,
};

pub const VulpesContext = opaque {};

pub const VulpesLoadHandle = extern struct {
    id: u64,
};

pub const VulpesLoadStatus = extern struct {
    state: enum(u8) {
        pending,
        connecting,
        downloading,
        parsing,
        laying_out,
        complete,
        failed,
    },
    progress: f32,  // 0.0 to 1.0
    error_code: u32,  // 0 = no error
};

pub const VulpesLink = extern struct {
    /// Link text (display text).
    text: [*:0]const u8,
    text_len: u32,

    /// Link URL.
    url: [*:0]const u8,
    url_len: u32,

    /// Position in rendered output.
    line: u32,
    column: u32,

    /// Visual bounds (for GUI).
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

pub const VulpesScrollInfo = extern struct {
    /// Current scroll position (0.0 to 1.0).
    position: f32,

    /// Viewport height in lines (terminal) or pixels (GUI).
    viewport_height: u32,

    /// Total content height.
    content_height: u32,

    /// Whether there's more content above/below.
    can_scroll_up: bool,
    can_scroll_down: bool,
};
```

### Render Commands

For custom rendering backends (GPU, etc.):

```zig
pub const VulpesRenderCommand = extern struct {
    type: enum(u8) {
        text,
        rect,
        line,
        image,
        clear,
    },
    data: extern union {
        text: TextCommand,
        rect: RectCommand,
        line: LineCommand,
        image: ImageCommand,
        clear: ClearCommand,
    },
};

pub const TextCommand = extern struct {
    x: i32,
    y: i32,
    text: [*:0]const u8,
    text_len: u32,
    font_size: u16,
    color: u32,  // RGBA
    flags: TextFlags,
};

pub const TextFlags = packed struct {
    bold: bool,
    italic: bool,
    underline: bool,
    strikethrough: bool,
    _padding: u4,
};
```

## Internal Architecture

```
libvulpes/
├── src/
│   ├── lib.zig              # Public API exports
│   ├── context.zig          # VulpesContext implementation
│   ├── network/
│   │   ├── http.zig         # HTTP client
│   │   ├── tls.zig          # TLS wrapper
│   │   ├── dns.zig          # DNS resolution
│   │   └── cache.zig        # Response caching
│   ├── parse/
│   │   ├── html/
│   │   │   ├── tokenizer.zig
│   │   │   ├── tree_builder.zig
│   │   │   └── entities.zig
│   │   ├── css/
│   │   │   ├── tokenizer.zig
│   │   │   ├── parser.zig
│   │   │   └── selectors.zig
│   │   └── dom.zig          # DOM tree structures
│   ├── layout/
│   │   ├── box.zig          # Box model
│   │   ├── flow.zig         # Block/inline flow
│   │   ├── text.zig         # Text measurement
│   │   └── tree.zig         # Layout tree
│   ├── render/
│   │   ├── commands.zig     # Render command generation
│   │   ├── text.zig         # Text rendering
│   │   └── software.zig     # Software renderer
│   └── platform/
│       ├── fonts.zig        # Font abstraction
│       ├── allocator.zig    # Memory management
│       └── time.zig         # Time abstraction
└── build.zig
```

## Memory Management

libvulpes uses arena allocators for page-scoped memory:

```zig
const Context = struct {
    // Long-lived allocator (application lifetime)
    global_allocator: Allocator,

    // Per-page arena (freed on navigation)
    page_arena: std.heap.ArenaAllocator,

    // Current page data
    dom: ?*Document,
    layout: ?*LayoutTree,

    pub fn loadPage(self: *Context, url: []const u8) !void {
        // Reset arena for new page
        self.page_arena.deinit();
        self.page_arena = std.heap.ArenaAllocator.init(self.global_allocator);

        // All page allocations use the arena
        const allocator = self.page_arena.allocator();
        self.dom = try self.parseHtml(allocator, ...);
        self.layout = try self.layoutDom(allocator, ...);
    }
};
```

## Thread Safety

libvulpes is **not** thread-safe by default. Each `VulpesContext` must be used from a single thread. For multi-threaded applications, create one context per thread or implement external synchronization.

However, the API is designed to support async patterns:
- `vulpes_load` returns immediately with a handle
- `vulpes_poll` checks status without blocking
- Frontends can use their own async patterns (event loops, etc.)

## Error Handling

```zig
/// Get the last error message for the given context.
pub export fn vulpes_last_error(ctx: *VulpesContext) [*:0]const u8;

/// Get the last error code.
pub export fn vulpes_last_error_code(ctx: *VulpesContext) u32;

/// Error codes
pub const VULPES_OK = 0;
pub const VULPES_ERR_NETWORK = 1;
pub const VULPES_ERR_DNS = 2;
pub const VULPES_ERR_TLS = 3;
pub const VULPES_ERR_TIMEOUT = 4;
pub const VULPES_ERR_PARSE = 5;
pub const VULPES_ERR_MEMORY = 6;
pub const VULPES_ERR_INVALID_URL = 7;
```

## Comptime Configuration

Following Ghostty's pattern, libvulpes uses comptime for build-time decisions:

```zig
const builtin = @import("builtin");

pub const FontBackend = switch (builtin.os.tag) {
    .macos => @import("fonts/coretext.zig"),
    .linux => @import("fonts/fontconfig.zig"),
    else => @import("fonts/stb.zig"),  // Fallback
};

// Only compiled code for the target platform is included
pub const font_backend = FontBackend.init();
```

## See Also

- [threading-model.md](threading-model.md) - Detailed threading architecture
- [platform-abstraction.md](platform-abstraction.md) - Platform-specific implementation
- [../technical/html-parsing.md](../technical/html-parsing.md) - HTML parser design
