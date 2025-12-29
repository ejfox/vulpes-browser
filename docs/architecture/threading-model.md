# Threading Model

## Overview

vulpes-browser's threading model is inspired by Ghostty's clean separation of IO and rendering. However, as a personal browser with intentionally limited scope, we can start simpler and add complexity only when needed.

## Ghostty's Model (Reference)

```
┌─────────────────────────────────────────┐
│              Application                │
│  (Creates surfaces, handles input)      │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│               Surface                   │
│  ┌─────────────┐    ┌─────────────┐    │
│  │  IO Thread  │    │Render Thread│    │
│  │             │    │             │    │
│  │ pty r/w     │    │ draw pixels │    │
│  │ escape seq  │    │ @framerate  │    │
│  └─────────────┘    └─────────────┘    │
└─────────────────────────────────────────┘
```

## vulpes Model

### Phase 1: Single-Threaded (Initial Implementation)

For the terminal UI, single-threaded is fine:

```
┌─────────────────────────────────────────┐
│            Main Thread                  │
│                                         │
│  Event Loop:                            │
│  1. Handle input                        │
│  2. Check network (non-blocking)        │
│  3. Parse (if data available)           │
│  4. Render (if needed)                  │
│  5. Sleep until next event              │
│                                         │
└─────────────────────────────────────────┘
```

**Why this works:**
- Terminal rendering is fast (just text)
- Network can be non-blocking
- Parsing small pages is quick
- Simpler to implement and debug

### Phase 2: Async IO (When Needed)

When network becomes a bottleneck:

```
┌─────────────────────────────────────────┐
│              Main Thread                │
│  (Input handling, rendering)            │
└─────────────────┬───────────────────────┘
                  │ channel
                  ▼
┌─────────────────────────────────────────┐
│             Network Thread              │
│  (HTTP requests, TLS, caching)          │
└─────────────────────────────────────────┘
```

### Phase 3: Full Pipeline (GUI Mode)

For GPU-accelerated GUI with smooth scrolling:

```
┌─────────────────────────────────────────┐
│              Main Thread                │
│  (Event loop, input handling)           │
└─────────────────┬───────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    ▼             ▼             ▼
┌────────┐  ┌──────────┐  ┌──────────┐
│Network │  │  Parse/  │  │  Render  │
│ Thread │  │  Layout  │  │  Thread  │
│        │  │  Thread  │  │          │
│ HTTP   │  │  DOM     │  │  @60fps  │
│ TLS    │  │  CSS     │  │  GPU     │
│ Cache  │  │  Layout  │  │          │
└────────┘  └──────────┘  └──────────┘
```

## Communication Patterns

### Channel-Based (Recommended)

Using Zig's `std.Thread.Channel` for type-safe message passing:

```zig
const NetworkMessage = union(enum) {
    request: struct {
        url: []const u8,
        callback_id: u64,
    },
    response: struct {
        callback_id: u64,
        data: []const u8,
        status: u16,
    },
    error: struct {
        callback_id: u64,
        code: NetworkError,
    },
};

const RenderMessage = union(enum) {
    invalidate: void,
    scroll: i32,
    resize: struct { width: u32, height: u32 },
    render_complete: void,
};
```

### Shared State (Careful)

Some state needs to be shared:
- Current DOM (read by render thread)
- Scroll position (written by input, read by render)
- Abort flag (written by main, read by network)

```zig
const SharedState = struct {
    // Atomic for simple flags
    abort_requested: std.atomic.Atomic(bool),

    // Mutex for complex state
    dom_mutex: std.Thread.Mutex,
    dom: ?*Document,

    // Lock-free scroll (single writer, single reader)
    scroll_position: std.atomic.Atomic(u32),
};
```

## Event Loop Design

### Terminal UI Event Loop

```zig
pub fn run(self: *App) !void {
    while (!self.should_quit) {
        // 1. Process input (non-blocking)
        while (self.input.poll()) |event| {
            try self.handleInput(event);
        }

        // 2. Check network status
        if (self.pending_load) |handle| {
            switch (self.ctx.poll(handle)) {
                .complete => {
                    self.pending_load = null;
                    self.needs_render = true;
                },
                .failed => |err| {
                    self.showError(err);
                    self.pending_load = null;
                },
                else => {},
            }
        }

        // 3. Render if needed
        if (self.needs_render) {
            try self.render();
            self.needs_render = false;
        }

        // 4. Sleep until next event (saves CPU)
        std.time.sleep(16 * std.time.ns_per_ms);  // ~60fps max
    }
}
```

### GUI Event Loop (Future)

```zig
pub fn run(self: *App) !void {
    // Platform event loop
    self.platform.runEventLoop(.{
        .on_input = handleInput,
        .on_resize = handleResize,
        .on_quit = handleQuit,
        .on_idle = handleIdle,
    });
}

fn handleIdle(self: *App) void {
    // Called when no events pending
    // Good time to do incremental work
    if (self.layout_dirty) {
        self.doIncrementalLayout();
    }
}
```

## Render Scheduling

### Terminal (Simple)

Render on demand, no frame pacing needed:
- After page load completes
- After scroll
- After window resize

### GUI (Frame-Paced)

Target 60fps with vsync:

```zig
const FramePacer = struct {
    last_frame: i64,
    frame_time_ns: i64 = 16_666_667,  // 60fps

    pub fn shouldRender(self: *FramePacer) bool {
        const now = std.time.nanoTimestamp();
        if (now - self.last_frame >= self.frame_time_ns) {
            self.last_frame = now;
            return true;
        }
        return false;
    }
};
```

## Cancellation

Important for responsive UI:

```zig
pub fn loadUrl(self: *Context, url: []const u8) !LoadHandle {
    // Cancel any existing load
    if (self.current_load) |existing| {
        self.cancel(existing);
    }

    return self.startLoad(url);
}

fn networkLoop(self: *NetworkThread) void {
    while (true) {
        const msg = self.channel.receive();

        // Check abort before expensive operations
        if (self.abort_flag.load(.Acquire)) {
            continue;
        }

        // Do network work...
        const response = try self.fetch(msg.url);

        // Check abort again before sending response
        if (!self.abort_flag.load(.Acquire)) {
            self.response_channel.send(.{ .response = response });
        }
    }
}
```

## Debugging Considerations

### Thread Naming

```zig
fn spawnNetworkThread(self: *App) !void {
    self.network_thread = try std.Thread.spawn(.{
        .name = "vulpes-network",
    }, networkThreadMain, .{self});
}
```

### Deadlock Prevention

1. Always acquire locks in the same order
2. Prefer message passing over shared state
3. Use timeouts on blocking operations
4. Log lock acquisitions in debug builds

```zig
fn acquireDomLock(self: *Context) void {
    if (builtin.mode == .Debug) {
        log.debug("Acquiring DOM lock from thread {}", .{std.Thread.getCurrentId()});
    }
    self.dom_mutex.lock();
}
```

## Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Input → Render | < 16ms | Responsive feel |
| Page load (network) | < 1s | Local/cached |
| Parse (simple HTML) | < 10ms | Most pages |
| Layout | < 5ms | Incremental |
| Render (terminal) | < 1ms | Just text |
| Render (GUI) | < 8ms | 60fps budget |

## See Also

- [overview.md](overview.md) - High-level architecture
- [libvulpes-core.md](libvulpes-core.md) - Core library API
- [../technical/rendering.md](../technical/rendering.md) - Render pipeline details
