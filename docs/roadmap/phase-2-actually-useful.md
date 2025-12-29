# Phase 2: Actually Useful

## Goal

Transform vulpes from a proof-of-concept into a daily-driver for reading content. Interactive navigation, proper HTML/CSS parsing in Zig, and vim-style keyboard navigation via AppKit.

## Platform

**macOS only.** Building on the Swift/AppKit shell and Metal rendering from Phase 1.

## Success Criteria

A macOS window displaying:
```
╔══════════════════════════════════════════════════════════════════╗
║                        Hacker News                                ║
╚══════════════════════════════════════════════════════════════════╝

[1] Show HN: I built a browser in Zig (github.com)
    142 points | 47 comments

[2] The rise of small language models (arxiv.org)
    89 points | 23 comments

[3] Why SQLite is so great (sqlite.org)
    234 points | 112 comments

───────────────────────────────────────────────────────────────────
Commands: [number] follow link | [b]ack | [q]uit | [/]search
URL: https://news.ycombinator.com
```

With vim-style navigation (j/k scrolling, gg/G jump, / search) handled natively in AppKit.

## Tech Stack

- **HTML/CSS Parsing:** Zig (pure, no dependencies)
- **Text Rendering:** Metal glyph atlas (refined from Phase 1)
- **Keyboard Handling:** AppKit (NSEvent, NSResponder chain)
- **Networking:** Zig std.http (from Phase 1)
- **Shell:** Swift/AppKit (from Phase 1)

## Scope

### In Scope

- [ ] Proper HTML tokenizer (Zig)
- [ ] DOM tree construction (Zig)
- [ ] CSS parsing - basic (Zig)
- [ ] Style computation - basic (Zig)
- [ ] Text layout with wrapping
- [ ] Metal glyph atlas refinement (multiple sizes, more characters)
- [ ] Interactive link following
- [ ] Navigation history (back/forward)
- [ ] In-page search
- [ ] Smooth scrolling (Metal + animation)
- [ ] Vim-style keyboard navigation (AppKit)
- [ ] Configuration file
- [ ] Redirect handling
- [ ] Better error messages

### Out of Scope

- Images
- JavaScript
- Forms (POST)
- Cookies
- Complex CSS (grid, flexbox)
- Multiple windows/tabs

## Milestones

### M2.1: HTML Tokenizer (Zig)

**Goal:** Spec-compliant HTML tokenization in pure Zig.

Following WHATWG HTML spec, implement tokenizer states:
- Data state
- Tag open/close states
- Attribute states
- Entity handling

```zig
// src/parse/html/tokenizer.zig
const Token = union(enum) {
    doctype: Doctype,
    start_tag: StartTag,
    end_tag: EndTag,
    character: u21,
    comment: []const u8,
    eof,
};

pub const Tokenizer = struct {
    input: []const u8,
    state: State,

    pub fn next(self: *Tokenizer) ?Token { ... }
};
```

**Reference:** [WHATWG HTML Tokenization](https://html.spec.whatwg.org/multipage/parsing.html#tokenization)

**Estimated lines:** ~800

### M2.2: DOM Tree Builder (Zig)

**Goal:** Construct DOM tree from tokens in pure Zig.

```zig
// src/parse/dom.zig
const Node = union(enum) {
    element: Element,
    text: []const u8,
    comment: []const u8,
    document: Document,
};

const Element = struct {
    tag_name: []const u8,
    attributes: []Attribute,
    children: []Node,
    parent: ?*Element,
};

pub fn buildTree(tokenizer: *Tokenizer) !*Document { ... }
```

Implement tree construction algorithm:
- Stack of open elements
- Adoption agency algorithm (for misnested tags)
- Implicit tag closing

**Estimated lines:** ~600

### M2.3: CSS Tokenizer & Parser (Zig)

**Goal:** Parse inline styles and `<style>` blocks in pure Zig.

```zig
// src/parse/css/parser.zig
const CssRule = struct {
    selector: Selector,
    declarations: []Declaration,
};

const Declaration = struct {
    property: []const u8,
    value: CssValue,
};

// Supported properties (Phase 2)
const supported_properties = .{
    "color",
    "background-color",
    "font-weight",
    "font-style",
    "text-decoration",
    "display",  // block, inline, none
    "margin",
    "padding",
    "text-align",
};
```

**Reference:** [CSS Syntax Module](https://www.w3.org/TR/css-syntax-3/)

**Estimated lines:** ~500

### M2.4: Style Computation (Zig)

**Goal:** Compute final styles for each element.

```zig
// src/style/compute.zig
const ComputedStyle = struct {
    color: Color,
    background: Color,
    font_weight: enum { normal, bold },
    font_style: enum { normal, italic },
    display: enum { block, inline, none },
    // ...
};

pub fn computeStyle(element: *Element, parent_style: *ComputedStyle) ComputedStyle {
    // 1. Inherit from parent
    // 2. Apply element defaults (e.g., <b> is bold)
    // 3. Apply CSS rules (specificity order)
    // 4. Apply inline style attribute
}
```

**Estimated lines:** ~400

### M2.5: Text Layout Engine

**Goal:** Lay out text with proper line breaking.

```zig
// src/layout/text.zig
const LayoutBox = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    content: LayoutContent,
};

const LayoutContent = union(enum) {
    text: TextRun,
    block: []LayoutBox,
};

const TextRun = struct {
    text: []const u8,
    style: ComputedStyle,
};

pub fn layout(document: *Document, viewport_width: f32) []LayoutBox {
    // Block layout (vertical stacking)
    // Inline layout (horizontal flow with wrapping)
    // Line breaking
}
```

**Estimated lines:** ~600

### M2.6: Metal Glyph Atlas Refinement

**Goal:** Expand glyph atlas for real-world use.

```zig
// src/render/atlas.zig
pub const GlyphAtlas = struct {
    // Multiple texture pages for larger character sets
    pages: []AtlasPage,

    // Support multiple font sizes
    size_variants: []f32,

    // Extended character coverage
    pub fn getOrRasterize(
        self: *GlyphAtlas,
        codepoint: u21,
        font_size: f32,
        style: FontStyle,
    ) GlyphInfo {
        // CoreText rasterization
        // Subpixel positioning
        // Cache management
    }
};
```

Improvements over Phase 1:
- Full Latin-1 + common symbols
- Multiple font sizes (heading scale)
- Bold/italic variants
- Better texture packing

**Estimated lines:** ~400

### M2.7: AppKit Keyboard Handling

**Goal:** Vim-style navigation via native AppKit event handling.

```swift
// gui/macos/VulpesView.swift
class VulpesView: MTKView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { return }

        switch chars {
        case "j":
            scrollDown()
        case "k":
            scrollUp()
        case "g":
            if lastKeyWas("g") {
                scrollToTop()
            }
        case "G":
            scrollToBottom()
        case "/":
            beginSearch()
        case "n":
            nextSearchResult()
        case "N":
            previousSearchResult()
        case "b":
            goBack()
        case "f":
            goForward()
        case "q":
            confirmQuit()
        default:
            if let num = Int(chars), num >= 1 && num <= 9 {
                followLink(num)
            }
        }
    }
}
```

**Benefits of AppKit handling:**
- Native key repeat behavior
- Respects system keyboard preferences
- Proper modifier key handling (Cmd, Ctrl, Option)
- Accessibility support

**Estimated lines:** ~300 (Swift)

### M2.8: Navigation History

**Goal:** Back/forward navigation.

```zig
// src/ui/history.zig
const History = struct {
    entries: ArrayList(HistoryEntry),
    current: usize,

    pub fn push(self: *History, url: []const u8) void { ... }
    pub fn back(self: *History) ?[]const u8 { ... }
    pub fn forward(self: *History) ?[]const u8 { ... }
};
```

```swift
// Swift side - integrate with AppKit
class VulpesWindow: NSWindow {
    // Cmd+[ and Cmd+] for back/forward (standard macOS)
    @objc func goBack(_ sender: Any?) {
        vulpes_go_back(context)
    }
}
```

**Estimated lines:** ~150

### M2.9: Search

**Goal:** Find text on the current page.

```zig
// src/ui/search.zig
pub fn search(document: *Document, query: []const u8) []SearchResult {
    // Case-insensitive search
    // Return positions in document
}

pub fn highlightResults(layout: []LayoutBox, results: []SearchResult) void {
    // Add highlight styling to matches
}
```

```swift
// Swift - search UI
class SearchBar: NSTextField {
    // Appears at bottom of window when / is pressed
    // Esc to dismiss
    // Enter to confirm and jump to first result
}
```

**Estimated lines:** ~200

### M2.10: Configuration

**Goal:** User-configurable settings.

```zig
// ~/.config/vulpes/config.zig or config.toml
const Config = struct {
    // Display
    color_scheme: enum { dark, light, system } = .system,
    max_width: u32 = 80,

    // Behavior
    vim_keys: bool = true,
    confirm_quit: bool = false,
    smooth_scroll: bool = true,

    // Network
    timeout_seconds: u32 = 30,
    user_agent: []const u8 = "vulpes/0.2",

    // Security
    allow_http: bool = false,
};
```

**Estimated lines:** ~200

## File Structure

```
vulpes-browser/
├── build.zig
├── src/
│   ├── main.zig
│   ├── lib.zig
│   ├── config.zig
│   ├── network/
│   │   ├── http.zig
│   │   └── url.zig
│   ├── parse/
│   │   ├── html/
│   │   │   ├── tokenizer.zig
│   │   │   ├── tree_builder.zig
│   │   │   └── entities.zig
│   │   ├── css/
│   │   │   ├── tokenizer.zig
│   │   │   ├── parser.zig
│   │   │   └── selectors.zig
│   │   └── dom.zig
│   ├── style/
│   │   ├── compute.zig
│   │   └── properties.zig
│   ├── layout/
│   │   ├── box.zig
│   │   ├── text.zig
│   │   └── flow.zig
│   ├── render/
│   │   ├── atlas.zig
│   │   ├── commands.zig
│   │   └── theme.zig
│   └── ui/
│       ├── history.zig
│       └── search.zig
├── gui/
│   └── macos/
│       ├── VulpesApp.swift
│       ├── VulpesWindow.swift
│       ├── VulpesView.swift
│       ├── MetalRenderer.swift
│       ├── SearchBar.swift
│       ├── Shaders.metal
│       └── Info.plist
└── docs/
```

## Testing Strategy

### Target Sites

Sites that MUST work:
- https://news.ycombinator.com (our benchmark)
- https://lobste.rs
- https://lite.cnn.com
- https://text.npr.org
- https://en.wikipedia.org (basic reading)
- https://github.com (repo pages, not JS features)
- Blog posts (various)
- Documentation sites (MDN, man pages)

### Automated Tests

```zig
test "html tokenizer - basic" {
    const html = "<p>Hello</p>";
    var tokenizer = Tokenizer.init(html);

    const t1 = tokenizer.next().?;
    try std.testing.expect(t1 == .start_tag);
    try std.testing.expectEqualStrings("p", t1.start_tag.name);

    const t2 = tokenizer.next().?;
    try std.testing.expect(t2 == .character);
    // ...
}

test "css parsing - declaration" {
    const css = "color: red; font-weight: bold";
    const decls = try parseCss(css);
    try std.testing.expectEqual(2, decls.len);
}

test "layout - word wrap" {
    const text = "The quick brown fox jumps over the lazy dog";
    const lines = layout(text, 20);  // 20 char width
    try std.testing.expectEqual(3, lines.len);
}
```

### Visual Regression

Screenshot comparison for Metal rendering:
```bash
# Capture current output
vulpes https://example.com --screenshot test_output.png
# Compare with expected
compare expected/example.png test_output.png diff.png
```

## Performance Targets

| Operation | Target |
|-----------|--------|
| Page load (cached) | < 100ms |
| Page load (network) | < 2s |
| Scroll response | < 16ms (60fps) |
| Search (1000 words) | < 50ms |
| Memory per page | < 10MB |

## Done Criteria

Phase 2 is complete when:

1. Hacker News renders readably
2. Can navigate via numbered links
3. Back/forward history works
4. Vim-style keys work (j/k/gg/G//)
5. Search finds text
6. Scrolling is smooth (60fps Metal)
7. Configuration file is loaded
8. HTTPS-only by default
9. Code coverage > 70%

## What's Next

Phase 3 adds polish:
- Typography refinement
- Advanced glyph atlas (emoji, ligatures)
- Reader mode enhancements
- Performance optimization
- visionOS as stretch goal

See [phase-3-beautiful.md](phase-3-beautiful.md).
