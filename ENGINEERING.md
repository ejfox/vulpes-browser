# Vulpes Browser - Engineering Decisions

> **A living document recording all architectural, technical, and design decisions made during the creation of Vulpes Browser**

**Status:** Phase 1 Complete, Phase 2 In Progress  
**Last Updated:** January 2026  
**Total Lines of Code:** ~5,000

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Founding Principles](#founding-principles)
3. [Technology Stack](#technology-stack)
4. [Architecture](#architecture)
5. [Implementation Decisions](#implementation-decisions)
6. [What We Built](#what-we-built)
7. [What We Explicitly Rejected](#what-we-explicitly-rejected)
8. [Lessons Learned](#lessons-learned)
9. [Future Considerations](#future-considerations)

---

## Executive Summary

**Vulpes Browser** is a minimalist, keyboard-first web browser for macOS that renders web pages as GPU-accelerated text. Built from scratch in Zig and Swift, it demonstrates that you can create a fast, native, feature-rich browser by being intentional about scope.

**What makes it unique:**
- No JavaScript, no ads, no tracking
- Full Metal GPU rendering from day one
- Vim-style keyboard navigation
- GLSL shader support (Ghostty-compatible)
- Text-focused content extraction
- ~5,000 lines of code (vs millions in mainstream browsers)

**Core Philosophy:** Build a browser for *reading* content, not running web applications.

---

## Founding Principles

### 1. macOS Only, Forever

**Decision:** Target macOS exclusively. No cross-platform considerations.

**Rationale:**
- Leverage Apple's best-in-class frameworks (Metal, Core Text, AppKit)
- Eliminate abstraction layers that harm performance
- Focus energy on doing one platform perfectly
- Inspired by platform-native excellence (Ghostty, BBEdit)

**Trade-off:** Smaller potential user base. We accept this—quality over quantity.

### 2. Keyboard-First Navigation

**Decision:** Primary interface is keyboard, not mouse/trackpad.

**Rationale:**
- Vim-style navigation (`j`/`k`/`d`/`u`/`G`/`gg`) feels natural to target users
- Numbered link navigation (1-9) faster than clicking
- Tab key link cycling for precision
- Mouse support is additive, not primary

**Implementation:**
- `j`/`k` - Line-by-line scrolling
- `d`/`u` - Half-page scrolling
- `G`/`gg` - Jump to top/bottom
- `/` or `Cmd+L` - Focus URL bar
- `1-9` - Follow numbered links
- `b`/`f` - Back/forward history

### 3. No JavaScript

**Decision:** Explicitly do not support JavaScript execution.

**Rationale:**
- JavaScript engines are massive (V8 is millions of lines)
- 90% of JS is for ads, tracking, and analytics
- Text content is accessible via HTML alone
- Security: No JS = massive reduction in attack surface
- Simplicity: Focus on HTML/CSS rendering only

**Trade-off:** SPAs (React, Vue, Nuxt) show minimal content. This is acceptable—those sites aren't for us.

### 4. GPU-Accelerated From Day One

**Decision:** Use Metal for rendering from Phase 1, not as a later optimization.

**Rationale:**
- Learned from Ghostty: Setting up GPU rendering early prevents rewrites
- 60fps smooth scrolling is non-negotiable in 2024+
- Glyph atlas text rendering scales to large documents
- Enables shader effects (page transitions, error pages)
- visionOS compatibility (future consideration)

**Trade-off:** Steeper initial learning curve than Core Graphics. Worth it.

### 5. Zig + Swift Architecture

**Decision:** Zig core library (libvulpes) + Swift/AppKit shell.

**Rationale:**
- **Zig for core:** Fast compiles, comptime magic, C ABI native, explicit memory control
- **Swift for GUI:** AppKit integration, keyboard events, Metal views
- Clean separation: Zig handles browser logic, Swift handles macOS integration
- Inspired by Ghostty's libghostty architecture

**Why not Rust?**
- Borrow checker fights browser engine patterns (cyclic DOM references)
- Zig's arena allocators match browser memory models better
- Faster compile times matter for iteration speed

**Why not pure Swift?**
- Swift isn't designed for low-level engine work
- C++ interop would be painful
- Zig gives us metal-to-the-floor control where needed

---

## Technology Stack

### Locked-In Decisions

| Component | Technology | Version | Rationale |
|-----------|-----------|---------|-----------|
| **Core Engine** | Zig | 0.15+ | Comptime, C ABI, explicit memory |
| **GUI Framework** | Swift + AppKit | macOS 14+ | Keyboard control, Metal integration |
| **Rendering** | Metal | 3.0+ | GPU acceleration, native |
| **Text** | Core Text | System | Shaping, fonts, correctness |
| **Networking** | Zig std.http | stdlib | Built-in, no dependencies |
| **TLS/Certs** | Security.framework | System | System trust store |
| **Shaders** | GLSL → Metal | Custom | Ghostty compatibility |

### Build System

```bash
# Zig builds static library
zig build

# xcodegen generates Xcode project from YAML
xcodegen generate

# Xcode builds Swift app + links libvulpes.a
xcodebuild -project Vulpes.xcodeproj -scheme Vulpes build
```

**Why xcodegen?**
- Version control friendly (YAML config, not opaque .xcodeproj)
- Reproducible builds across team
- Easy CI/CD integration

---

## Architecture

### High-Level Structure

```
┌─────────────────────────────────────────────────────────┐
│              Swift + AppKit Application                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │  MainWindow.swift    - Window management          │  │
│  │  MetalView.swift     - Rendering + input          │  │
│  │  VulpesConfig.swift  - Config file parsing        │  │
│  │  VulpesBridge.swift  - C ABI wrapper              │  │
│  │  GLSLTranspiler.swift - Shader compatibility      │  │
│  └───────────────────────────────────────────────────┘  │
│                        ↓ C ABI                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │           libvulpes.a (Zig Static Library)        │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │  network/http.zig  - HTTP client            │  │  │
│  │  │  html/text_extractor.zig - HTML parsing     │  │  │
│  │  │  lib.zig - C API exports                    │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### C ABI Boundary

**Key exported functions:**
```c
// Initialization
int vulpes_init(void);
void vulpes_deinit(void);

// HTTP fetching
VulpesFetchResult* vulpes_fetch(const char* url);
void vulpes_fetch_free(VulpesFetchResult* result);

// Text extraction
VulpesTextResult* vulpes_extract_text(const uint8_t* html, size_t len);
void vulpes_text_free(VulpesTextResult* result);
```

**Why C ABI?**
- Swift imports C naturally (no FFI friction)
- Future-proof (any language can link libvulpes)
- Clear ownership boundaries for memory

### Memory Management

**Zig Side (libvulpes):**
- Page allocator for long-lived C API results
- Arena allocators (planned) for per-page DOM trees
- Explicit `free` functions for every `alloc`

**Swift Side:**
- ARC manages Swift objects
- Manual `free` calls for Zig-allocated memory
- `defer` ensures cleanup

### Rendering Pipeline

```
URL Request
    ↓
┌────────────────┐
│  HTTP Fetch    │  (Zig std.http + Security.framework)
│  (vulpes_fetch)│
└────────────────┘
    ↓
┌────────────────┐
│  HTML Parsing  │  (text_extractor.zig)
│  Text Extract  │  Strips tags, decodes entities
└────────────────┘
    ↓
┌────────────────┐
│  Swift Bridge  │  (VulpesBridge.swift)
│  String Conv.  │
└────────────────┘
    ↓
┌────────────────┐
│  Glyph Atlas   │  (GlyphAtlas.swift)
│  Core Text     │  Rasterize glyphs → MTLTexture
└────────────────┘
    ↓
┌────────────────┐
│  Metal Render  │  (MetalView.swift)
│  GPU Drawing   │  Textured quads at 60fps
└────────────────┘
```

### Shader System

**Innovation:** GLSL shader support (Ghostty/Shadertoy-compatible)

**Pipeline:**
1. User writes GLSL shader (mainImage signature)
2. GLSLTranspiler.swift auto-converts GLSL → Metal Shading Language
3. Metal compiles to GPU code
4. Shader runs as post-process or transition effect

**Supported shaders:**
- **Post-process:** bloom, CRT, custom filters
- **Transitions:** 70s wobble, cyberpunk glitch
- **Error pages:** 404 void, 500 fire (animated)

**Key insight:** Transpiler handles 80% of syntax differences, enabling Ghostty shader reuse.

---

## Implementation Decisions

### 1. Networking: Zig std.http + Security.framework

**Decision:** Use Zig's standard library HTTP client, delegate TLS to macOS.

**Why not URLSession?**
- Keeps libvulpes pure Zig
- URLSession requires Swift/ObjC (breaks clean C ABI)
- std.http is sufficient for our needs

**How TLS works:**
- Zig std.http handles HTTP protocol
- Security.framework provides TLS stream wrapper
- macOS system trust store used for cert validation
- Result: Proper HTTPS with zero bundled CA certs

### 2. Text Extraction: Regex + State Machine

**Decision:** Naive HTML parsing for Phase 1, good enough for text extraction.

**Current implementation:**
- Strip `<script>`, `<style>` entirely
- Extract text from remaining tags
- Decode HTML entities (`&amp;` → `&`)
- Extract links with text for numbered navigation
- No DOM tree construction (yet)

**Why this works:**
- 90% of web content is accessible via simple text extraction
- Full HTML parsing (WHATWG spec) is 50k+ lines
- We can add proper parser incrementally

**Trade-offs:**
- Nested elements sometimes mishandled
- Complex layouts ignored
- Good enough for reading articles, docs, blogs

### 3. Glyph Atlas: Core Text + Metal Texture

**Decision:** Pre-rasterize glyphs to GPU texture atlas.

**How it works:**
1. Core Text shapes text → glyph IDs + positions
2. First render of glyph: Core Text rasterizes to CGImage
3. Upload to shared MTLTexture (4096x4096)
4. Cache glyph → texture coordinate mapping
5. Draw text as instanced quads with atlas texture

**Why atlas vs. render-on-demand?**
- GPU texture bandwidth >> CPU rasterization
- Glyphs rarely change (cache friendly)
- Sub-pixel AA done once, reused forever
- Enables 60fps scrolling through long documents

### 4. Keyboard Navigation: NSResponder Chain

**Decision:** Intercept keyDown in NSView, handle before system.

**Implementation:**
```swift
override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers {
    case "j": scrollDown()
    case "k": scrollUp()
    case "d": scrollHalfPage(down: true)
    case "u": scrollHalfPage(down: false)
    case "1"..."9": followLink(Int(event.characters!)! - 1)
    default: super.keyDown(with: event)
    }
}
```

**Why this works:**
- First responder gets first chance at events
- `super.keyDown()` fallback preserves system shortcuts
- Direct metal-to-the-floor control

### 5. Page Transitions: Offscreen Texture + Shader

**Decision:** Two-pass rendering for transition effects.

**Pipeline:**
1. Render page to offscreen MTLTexture
2. Apply transition shader (e.g., 70s wobble)
3. Composite to screen

**Why two-pass?**
- Separates content rendering from effects
- Transition shaders operate on full-page texture
- Enables post-process bloom without touching text rendering

### 6. Configuration: Dotfile (nvim-style)

**Decision:** Simple text config at `~/.config/vulpes/config`.

**Format:**
```
shader = bloom-vulpes
bloom = true
scroll_speed = 40
home_page = https://example.com
```

**Why not JSON/TOML?**
- Simpler to parse (key = value)
- Feels Unix-y
- Matches Ghostty's approach
- Easy to edit by hand

**Ghostty compatibility:**
- Shaders load from `~/.config/ghostty/shaders/`
- Any Ghostty shader works in Vulpes
- Community shader library reusable

### 7. History: Simple Array

**Decision:** Back/forward history as Swift array of URLs.

**Implementation:**
```swift
class NavigationHistory {
    private var urls: [String] = []
    private var currentIndex: Int = -1
    
    func navigateTo(url: String) {
        // Truncate forward history
        urls = Array(urls.prefix(currentIndex + 1))
        urls.append(url)
        currentIndex = urls.count - 1
    }
    
    func canGoBack() -> Bool { currentIndex > 0 }
    func canGoForward() -> Bool { currentIndex < urls.count - 1 }
}
```

**Why not stack?**
- Need random access for forward navigation
- Array is simple, fast, built-in
- No database needed for 100-entry history

---

## What We Built

### Phase 1: Hello Web (Complete ✓)

**Milestone:** Basic browsing with Metal rendering

**Completed:**
- [x] Full HTTP/HTTPS with gzip, TLS validation
- [x] URL parsing and redirect handling
- [x] HTML text extraction with link parsing
- [x] Metal rendering pipeline
- [x] Core Text glyph atlas
- [x] Swift/AppKit window shell
- [x] Zig-to-Swift C ABI bridge
- [x] Basic error handling

**What works:**
- Load any URL
- Display readable text
- Follow numbered links (1-9)
- HTTPS with proper cert verification

### Phase 2: Actually Useful (In Progress)

**Milestone:** Daily-driveable browser

**Completed:**
- [x] GLSL shader support (Ghostty-compatible)
- [x] Page transition effects (70s wobble, glitch)
- [x] Error page shaders (404, 500)
- [x] Vim-style keyboard navigation (`j`/`k`/`d`/`u`/`G`/`gg`)
- [x] Back/forward history (`b`/`f`)
- [x] URL bar focus (`/`)
- [x] Link cycling (Tab key)
- [x] Smooth scrolling (keyboard + trackpad)
- [x] Config file support (~/.config/vulpes/config)
- [x] Tmux-style status bar with template config

**In Progress:**
- [ ] HTML form inputs
- [ ] Basic image rendering
- [ ] In-page search (`/` then pattern)
- [ ] Bookmark system

### Features We're Proud Of

**1. Shader System**
- Ghostty-compatible GLSL shaders
- Auto-transpiled to Metal
- `iResolution`, `iTime`, `iChannel0` uniforms supported
- Community shaders "just work"

**2. Page Transitions**
- 70s analog TV wobble effect
- Cyberpunk datamosh glitch
- Smooth, GPU-accelerated
- Configurable per-user

**3. Error Pages**
- 404: Animated void shader (particle system)
- 500: Fire effect (Shadertoy-style)
- Beautiful failures, not boring error text

**4. Numbered Link Navigation**
- Inspired by browser extensions (Vimium, Surfingkeys)
- Built-in from day one
- Works on any page, no extension needed

### Metrics

| Metric | Value |
|--------|-------|
| Total LOC | ~5,000 |
| Zig Code | ~1,500 lines |
| Swift Code | ~3,500 lines |
| GLSL Shaders | ~500 lines |
| Build Time (clean) | ~8 seconds |
| Binary Size | ~800 KB |
| Memory (idle) | ~15 MB |
| Memory (10 pages) | ~45 MB |

Compare to mainstream browsers:
- Chromium: 35+ million LOC
- Firefox: 21+ million LOC
- WebKit: 4+ million LOC

---

## What We Explicitly Rejected

### 1. Cross-Platform Support

**Rejected:** Windows, Linux, Web (WASM)

**Why:** Dilutes focus, adds abstraction layers, harms quality. We'd rather have one perfect platform than three mediocre ones.

### 2. JavaScript Engine

**Rejected:** V8, JavaScriptCore, SpiderMonkey

**Why:** 
- Engines are millions of lines (V8: 2M+)
- Most JS is ads/tracking/analytics
- Security nightmare (infinite attack surface)
- Out of scope for a reading browser

**Impact:** SPAs don't work. We accept this.

### 3. SwiftUI

**Rejected:** SwiftUI for GUI

**Why:**
- Keyboard-first demands low-level event control
- Metal views integrate better with AppKit
- SwiftUI's declarative model fights keyboard control
- AppKit is mature, stable, well-documented

### 4. Electron/Tauri

**Rejected:** Web-based GUI frameworks

**Why:** We're building a browser, not wrapping one. If we wanted Chromium, we'd just use Chrome.

### 5. CSS Layout Engine (for now)

**Rejected:** Full box model, flexbox, grid

**Why:**
- Text extraction is 80% of use case
- Full layout engine is 100k+ lines
- Can add incrementally if needed
- Focused scope = faster iteration

**Future consideration:** Simple block/inline layout might be added in Phase 3.

### 6. Bookmarks UI

**Rejected:** Visual bookmark manager, folders

**Why:**
- Plain text file (`~/.config/vulpes/bookmarks`) suffices
- `grep` is a great search tool
- Unix philosophy: Tools that do one thing well

### 7. Tabs

**Rejected:** Traditional tab bar

**Future consideration:** Spatial cards (HyperCard-inspired) might be explored, but not browser-style tabs.

---

## Lessons Learned

### What Worked Well

**1. GPU Rendering From Day One**
- No rewrite needed later
- Forces proper architecture early
- Performance is baked in, not bolted on

**2. Zig + Swift Split**
- Clean separation of concerns
- Each language used for what it's best at
- C ABI boundary is clear contract

**3. Ghostty Inspiration**
- Proven architecture for keyboard-driven apps
- Shader compatibility opened creative possibilities
- Standing on shoulders of giants

**4. Constrained Scope**
- No JavaScript = massive complexity avoided
- Text-focus = clear target
- Can always expand, hard to shrink

### What We'd Do Differently

**1. Start with Simpler Shaders**
- GLSL transpiler was ambitious for Phase 1
- Could've shipped with built-in bloom only
- Learned a lot, but delayed other features

**2. Config System Earlier**
- Added in Phase 2, should've been Phase 1
- Users want to tweak scroll speed immediately
- Easy win for UX

**3. More Unit Tests**
- Heavy on integration testing, light on unit tests
- Zig's test framework is great, should use more
- Especially for HTML parsing edge cases

### Surprises

**1. Core Text Complexity**
- "Just render text" is surprisingly deep
- Emoji, ligatures, RTL, complex scripts
- Core Text handles it all, but docs are sparse

**2. Metal Learning Curve**
- Steeper than expected (especially shaders)
- Great once you get it
- Worth the investment

**3. User Enthusiasm**
- Early users love keyboard navigation
- Shader support resonated with creative users
- "No JS" is a feature, not a bug

---

## Future Considerations

### Phase 3: Beautiful (Planned)

**Goals:**
- Refined visual design
- Animations and polish
- Image rendering (basic)
- Simple layout (block + inline)

### Stretch Goals

**visionOS Port**
- Metal rendering already compatible
- SwiftUI for spatial UI?
- "Cards in space" metaphor

**Plugin System**
- Custom content filters (Reader mode, etc.)
- User scripts (not full JS, think Userscripts)
- Community extensions

**Advanced Features**
- Reader mode (Readability-style)
- Dark mode (system-aware)
- Bookmarks sync (CloudKit?)
- RSS reader integration
- Link hover preview tooltip (thumbnail snapshot)

### Things We'll Probably Never Do

- Video playback (use dedicated apps)
- WebGL (conflicts with no-JS stance)
- Forms POST (read-only browser philosophy)
- WebSockets (no persistent connections)
- Service Workers (requires JS)

---

## Conclusion

**What we proved:**
- Small teams can build browsers from scratch
- Constrained scope enables excellence
- Native tools are worth mastering
- Keyboard-first is viable in 2024+

**What we learned:**
- Text rendering is 70% of a browser
- GPU acceleration is table stakes
- Users crave simplicity
- Platform-specific is powerful

**What's next:**
- Finish Phase 2 (forms, images, search)
- Refine Phase 3 (polish, beauty)
- Community shaders and themes
- Maybe visionOS

**Total time invested:** ~6 months part-time  
**Was it worth it?** Absolutely.

---

## Appendix: Key Files

| File | Purpose | LOC |
|------|---------|-----|
| `src/lib.zig` | C API exports | 291 |
| `src/network/http.zig` | HTTP client | 418 |
| `src/html/text_extractor.zig` | HTML parsing | 658 |
| `app/MetalView.swift` | Rendering engine | 1,242 |
| `app/VulpesBridge.swift` | Zig ↔ Swift bridge | 156 |
| `app/GLSLTranspiler.swift` | GLSL → Metal | 387 |
| `app/TransitionManager.swift` | Page effects | 243 |
| `build.zig` | Build system | 117 |
| `project.yml` | Xcode config | 68 |

**Grand total:** 3,580 core lines (excluding shaders, docs, tests)

---

**Document version:** 1.0  
**Maintained by:** EJ Fox (@ejfox)  
**License:** MIT (like the code)

*This document is a snapshot of decisions as of January 2026. The code is the source of truth.*
