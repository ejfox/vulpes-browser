# Phase 3: Beautiful

## Goal

Transform vulpes from a functional browser into a beautiful, polished experience. With Metal rendering already in place from Phase 1, this phase focuses on refinement, typography excellence, and delightful details rather than a rendering rewrite.

## Platform

**macOS only.** visionOS as a stretch goal.

## Success Criteria

A native macOS app that:
- Feels instant and responsive
- Has beautiful text rendering (subpixel antialiasing, proper kerning)
- Smooth scrolling at 60fps (already achieved, now polish)
- Dark/light themes that respect system preferences
- Feels like it belongs on macOS

## Key Insight

**Metal is already in place.** Unlike a traditional phased approach where Phase 3 would involve rewriting to GPU rendering, we did that work in Phase 1. This phase is about:
- Polish, not rewrite
- Typography refinement, not rendering migration
- UX details, not infrastructure

## Scope

### In Scope

- [ ] Typography refinement (kerning, ligatures, line height)
- [ ] Advanced glyph atlas (emoji, extended Unicode)
- [ ] Font fallback chains
- [ ] System theme integration (automatic dark/light)
- [ ] Smooth animations and transitions
- [ ] Reader mode refinements
- [ ] Image support (opt-in)
- [ ] Performance profiling and optimization
- [ ] Accessibility improvements
- [ ] visionOS port (stretch goal)

### Out of Scope (Still)

- JavaScript
- Complex CSS layouts
- Forms beyond basic search
- Extensions/plugins
- Sync features

## Milestones

### M3.1: Typography Refinement

**Goal:** Refined reading experience through better typography.

```zig
// src/render/typography.zig
const Typography = struct {
    // Base settings
    base_size: f32 = 18,
    line_height: f32 = 1.6,
    paragraph_spacing: f32 = 1.0,  // in em

    // Heading scale
    h1_scale: f32 = 2.0,
    h2_scale: f32 = 1.5,
    h3_scale: f32 = 1.25,

    // Measure (line length)
    max_width: f32 = 65,  // characters

    // Margins
    content_margin: f32 = 48,
};
```

**Enhancements:**
- Optimal line length (45-75 characters)
- Generous line height (1.5-1.7)
- Clear heading hierarchy
- Proper quote styling
- Code block formatting

**Estimated lines:** ~200

### M3.2: Advanced Glyph Atlas

**Goal:** Full Unicode support with emoji and ligatures.

```zig
// src/render/atlas.zig (enhanced)
pub const GlyphAtlas = struct {
    // Color emoji support (Apple Color Emoji)
    color_glyphs: std.AutoHashMap(GlyphKey, ColorGlyphInfo),

    // Ligature support (fi, fl, ffi, etc.)
    ligatures: std.AutoHashMap(LigatureKey, GlyphInfo),

    // Font fallback chain for missing glyphs
    fallback_fonts: []FontHandle,

    pub fn getGlyph(
        self: *GlyphAtlas,
        codepoint: u21,
        font: FontHandle,
        size: f32,
    ) GlyphResult {
        // 1. Try primary font
        // 2. Try ligature substitution
        // 3. Fall back through font chain
        // 4. Return tofu glyph if all else fails
    }
};
```

**Unicode coverage:**
- Full Latin Extended (accents, diacritics)
- Common symbols and punctuation
- Emoji (via Apple Color Emoji)
- Basic CJK (via system fonts)

**Estimated lines:** ~500

### M3.3: Font System

**Goal:** Proper font discovery, fallback, and metrics via CoreText.

```zig
// src/render/fonts.zig
const FontManager = struct {
    primary_font: FontHandle,
    fallback_chain: []FontHandle,

    pub fn init() FontManager {
        // Build fallback chain from system fonts
        // Primary -> Symbols -> Emoji -> Last Resort
    }

    pub fn getMetrics(self: *FontManager, font: FontHandle, size: f32) FontMetrics {
        // Ascent, descent, line gap, x-height
    }
};
```

```swift
// gui/macos/FontBridge.swift
// Bridge to CoreText for font discovery and rasterization
func getSystemFont(size: CGFloat, weight: NSFont.Weight) -> CTFont {
    NSFont.systemFont(ofSize: size, weight: weight) as CTFont
}

func rasterizeGlyph(font: CTFont, glyph: CGGlyph) -> (data: Data, metrics: GlyphMetrics) {
    // Rasterize to bitmap for atlas
}
```

**Estimated lines:** ~400

### M3.4: Smooth Scrolling (Polish)

**Goal:** Perfect 60fps scrolling with momentum.

Metal rendering is already in place. This milestone focuses on:
- Scroll physics refinement
- Momentum curves that match iOS/macOS feel
- Overscroll bounce effect
- Page up/down animations

```zig
// src/ui/scroll.zig (enhanced)
const ScrollAnimator = struct {
    target: f32,
    current: f32,
    velocity: f32,
    deceleration: f32 = 0.998,  // Momentum decay

    pub fn update(self: *ScrollAnimator, dt: f32) bool {
        if (self.velocity != 0) {
            // Momentum scrolling
            self.current += self.velocity * dt;
            self.velocity *= std.math.pow(f32, self.deceleration, dt * 60);

            if (@abs(self.velocity) < 0.1) {
                self.velocity = 0;
            }
        } else {
            // Spring to target
            const diff = self.target - self.current;
            self.current += diff * 0.15;
        }

        return @abs(self.velocity) > 0.01 or @abs(self.target - self.current) > 0.01;
    }
};
```

**Estimated lines:** ~150

### M3.5: Theme System

**Goal:** Beautiful light and dark themes with system integration.

```zig
// src/render/theme.zig
const Theme = struct {
    // Background
    background: Color,
    surface: Color,

    // Text
    text_primary: Color,
    text_secondary: Color,
    text_muted: Color,

    // Links
    link: Color,
    link_visited: Color,
    link_hover: Color,

    // Accents
    accent: Color,
    selection: Color,

    // Semantic
    error_color: Color,
    warning: Color,
    success: Color,
};

const themes = struct {
    pub const dark = Theme{
        .background = Color.fromHex("#1a1a2e"),
        .surface = Color.fromHex("#16213e"),
        .text_primary = Color.fromHex("#eee"),
        // ...
    };

    pub const light = Theme{
        .background = Color.fromHex("#fafafa"),
        .surface = Color.fromHex("#fff"),
        .text_primary = Color.fromHex("#222"),
        // ...
    };
};
```

```swift
// gui/macos/ThemeObserver.swift
class ThemeObserver {
    func observeSystemTheme() {
        // Listen to NSApp.effectiveAppearance changes
        // Notify Zig core when theme changes
    }
}
```

**Features:**
- Respect system preference by default
- Manual override option
- Smooth theme transitions (fade)

**Estimated lines:** ~200

### M3.6: Optional Image Support

**Goal:** Load images on demand.

```zig
// src/content/images.zig
// Off by default, toggled with 'i' key or config
pub fn loadImages(document: *Document, allocator: Allocator) !void {
    for (document.images) |img| {
        const data = try fetchImage(img.src);
        img.decoded = try decodeImage(allocator, data);  // PNG/JPEG/WebP
    }
}
```

**Implementation:**
- Lazy loading (only visible images)
- Decode off main thread
- Reasonable size limits
- Placeholder during load
- Metal texture upload

**Estimated lines:** ~400

### M3.7: Reader Mode Enhancements

**Goal:** Distraction-free reading experience.

```zig
// src/reader/mode.zig
const ReaderMode = struct {
    // Content extraction
    article_content: []const u8,
    title: []const u8,
    byline: ?[]const u8,
    published_date: ?[]const u8,

    // Reader-specific styling
    font_family: FontFamily = .serif,
    font_size: f32 = 20,
    line_height: f32 = 1.8,
    max_width_chars: u32 = 60,

    pub fn extract(document: *Document) ?ReaderMode {
        // Readability-style content extraction
    }
};
```

**Features:**
- Article extraction (Readability-style)
- Serif font option
- Adjustable font size
- Progress indicator
- Estimated reading time

**Estimated lines:** ~500

### M3.8: Accessibility

**Goal:** VoiceOver and accessibility support.

```swift
// gui/macos/Accessibility.swift
class VulpesAccessibility: NSObject, NSAccessibilityProtocol {
    // Expose content to VoiceOver
    override func accessibilityRole() -> NSAccessibility.Role {
        .webArea
    }

    override func accessibilityChildren() -> [Any]? {
        // Return accessible elements for current page
    }
}
```

**Features:**
- VoiceOver navigation
- Keyboard-only operation (already done with vim keys)
- High contrast support
- Reduce motion preference

**Estimated lines:** ~300

### M3.9: Performance Optimization

**Goal:** Profile and optimize for smooth experience.

Focus areas:
- Frame time analysis (Metal GPU profiler)
- Memory usage per page
- Glyph atlas efficiency
- Layout caching

```zig
// src/debug/profiler.zig
const Profiler = struct {
    frame_times: RingBuffer(f64, 120),  // 2 seconds at 60fps
    layout_times: RingBuffer(f64, 100),
    network_times: RingBuffer(f64, 100),

    pub fn getAverageFrameTime(self: *Profiler) f64 {
        // Return average, highlight if > 16ms
    }
};
```

**Targets:**
| Operation | Target | Metric |
|-----------|--------|--------|
| Frame time | < 16ms | 60fps |
| Scroll latency | < 8ms | Responsive |
| Page render | < 100ms | Time to first paint |
| Memory (idle) | < 50MB | Low footprint |
| Memory (per page) | < 20MB | Reasonable |

**Estimated lines:** ~200

### M3.10: visionOS Port (Stretch Goal)

**Goal:** Run vulpes on Apple Vision Pro.

```swift
// gui/visionos/VulpesVisionApp.swift
import SwiftUI
import RealityKit

@main
struct VulpesVisionApp: App {
    var body: some Scene {
        WindowGroup {
            VulpesVisionView()
        }
        .windowStyle(.plain)
    }
}

struct VulpesVisionView: View {
    var body: some View {
        // SwiftUI wrapper around Metal content
        MetalView(renderer: renderer)
            .frame(width: 1200, height: 800)
    }
}
```

**Considerations:**
- Same libvulpes core
- SwiftUI shell instead of AppKit
- Spatial input (gaze + pinch) for navigation
- Window placement in space
- Same Metal rendering pipeline

**Estimated lines:** ~500 (Swift, new shell)

## File Structure

```
vulpes-browser/
├── build.zig
├── src/
│   ├── lib.zig
│   ├── main.zig
│   ├── ... (existing)
│   ├── render/
│   │   ├── atlas.zig        # Enhanced glyph atlas
│   │   ├── commands.zig
│   │   ├── fonts.zig        # Font system
│   │   ├── theme.zig
│   │   └── typography.zig   # Typography settings
│   ├── reader/
│   │   └── mode.zig         # Reader mode
│   ├── content/
│   │   └── images.zig       # Image loading
│   └── debug/
│       └── profiler.zig     # Performance profiling
├── gui/
│   ├── macos/
│   │   ├── VulpesApp.swift
│   │   ├── VulpesWindow.swift
│   │   ├── VulpesView.swift
│   │   ├── MetalRenderer.swift
│   │   ├── FontBridge.swift
│   │   ├── ThemeObserver.swift
│   │   ├── Accessibility.swift
│   │   ├── Shaders.metal
│   │   └── Info.plist
│   └── visionos/            # Stretch goal
│       ├── VulpesVisionApp.swift
│       └── Info.plist
└── docs/
```

## Done Criteria

Phase 3 is complete when:

1. Text rendering is beautiful (subjective, but we'll know)
2. Dark/light themes work with system preference
3. Performance targets met (60fps scrolling)
4. Reader mode extracts and displays articles cleanly
5. Accessibility basics work (VoiceOver navigation)
6. Images can be optionally loaded
7. Memory usage is reasonable (< 50MB idle)

**Stretch:**
8. visionOS app runs and is usable

## Beyond Phase 3

With a beautiful, functional macOS browser complete, future possibilities include:

- **Phase 4:** Advanced features (tabs, bookmarks, sync)
- **iPadOS port:** Touch-optimized interface
- **Gemini protocol support:** Alternative web
- **Reader database:** Save articles locally

See [future-ideas.md](future-ideas.md) for the full wishlist.
