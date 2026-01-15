# CLAUDE.md - Vulpes Browser Development Context

## Project Overview

**vulpes-browser** is a minimalist, keyboard-first web browser for macOS, inspired by Ghostty's intentional design philosophy.

### Tech Stack (Locked In)
- **Core Engine:** Zig (compiles to libvulpes.a static library)
- **GUI:** Swift + AppKit
- **Rendering:** Metal (GPU-accelerated)
- **Text:** Core Text (for glyph rasterization)
- **Networking:** Zig std.http + Security.framework for TLS
- **Shaders:** GLSL (Ghostty-compatible) auto-transpiled to Metal

### Key Design Decisions
- macOS only, forever (visionOS as stretch goal)
- Keyboard-first (vim-style navigation)
- No JavaScript, no ads, no tracking
- Spatial cards metaphor (HyperCard-inspired, not tabs)

## Current State (Dec 2025)

### What Works
- Full end-to-end browsing: fetch URL → extract text → render with Metal
- GLSL shader support (Ghostty/Shadertoy compatible)
- Custom post-process shaders (bloom, CRT effects)
- Page transition effects (70s wobble, cyberpunk glitch)
- Error page shaders (404 void, 500 fire)
- Vim-style keyboard navigation
- Back/forward history navigation
- Link extraction and numbered navigation
- Glyph atlas with CoreText
- Two-pass rendering with offscreen texture

### Build & Run
```bash
zig build
xcodegen generate
xcodebuild -project Vulpes.xcodeproj -scheme Vulpes build
/Users/ejfox/Library/Developer/Xcode/DerivedData/Vulpes-*/Build/Products/Debug/Vulpes.app/Contents/MacOS/Vulpes
```

## Keyboard Navigation

| Key | Action |
|-----|--------|
| `j` | Scroll down one line |
| `k` | Scroll up one line |
| `d` | Scroll down half page |
| `u` | Scroll up half page |
| `G` | Jump to bottom |
| `gg` | Jump to top |
| `b` | Go back in history |
| `f` | Go forward in history |
| `/` | Focus URL bar |
| `Cmd+L` | Focus URL bar |
| `1-9` | Follow numbered link |
| `Tab` | Cycle through links |
| `Enter` | Activate focused link |
| Trackpad | Smooth scrolling |

## Architecture

### Shader Pipeline
1. Scene renders to offscreen texture
2. Post-process shader applied (custom GLSL or built-in bloom)
3. Transition shaders overlay during navigation
4. Error shaders loop continuously on error pages

### Key Files
- `app/MetalView.swift` - Main rendering view, keyboard handling, image rendering
- `app/GLSLTranspiler.swift` - GLSL → Metal shader conversion
- `app/TransitionManager.swift` - Page transition effects
- `app/NavigationHistory.swift` - Back/forward history
- `app/VulpesConfig.swift` - nvim-style dotfile config (~/.config/vulpes/config)
- `app/VulpesBridge.swift` - Swift wrapper for Zig C API
- `app/GlyphAtlas.swift` - Text glyph texture atlas
- `app/ImageAtlas.swift` - Image texture atlas with GPU acceleration
- `src/html/text_extractor.zig` - HTML text and image extraction with link parsing
- `shaders/` - GLSL shaders (transitions, errors)

### Config File (~/.config/vulpes/config)
```
shader = bloom-vulpes
bloom = true
scroll_speed = 40
home_page = https://ejfox.com
```

Shaders are loaded from `~/.config/ghostty/shaders/` for Ghostty compatibility.

## Shader System

### Supported GLSL Features
- Shadertoy/Ghostty `mainImage(out vec4, in vec2)` signature
- `iResolution`, `iTime`, `iChannel0` uniforms
- Auto-transpiled: vec2→float2, texture()→.sample(), etc.

### Available Shaders
- **Transitions:** `transition-70s.glsl` (wobble), `transition-glitch.glsl` (datamosh)
- **Errors:** `error-404.glsl` (void), `error-500.glsl` (fire)
- **Custom:** Any Ghostty shader via config

## Image Rendering System

### GPU-Accelerated Architecture
- **ImageAtlas**: Texture atlas with LRU caching (4K atlas, 100 image cache)
- **Metal Shaders**: `fragmentShaderImage`, `fragmentShaderImageGrayscale`, `fragmentShaderImageSepia`
- **Async Loading**: Background image download with progressive enhancement
- **Smart Packing**: Row-based atlas packing with automatic eviction

### Performance Features
- Zero-copy texture upload via blit encoder
- Private GPU memory for optimal rendering
- Batched draw calls via texture atlas
- Individual textures for large images (>2048px)
- Aspect ratio preservation with smart scaling

### Image Extraction
- Zig parser extracts `<img>` tags from HTML
- Control character markers (`0x1E`) for inline placement
- Relative URL resolution against page URL
- Image list appended to extracted text

### See Also
- `docs/IMAGE_RENDERING.md` - Detailed documentation
- `docs/test-images.html` - Test page for image rendering

## Known Limitations

1. **No JavaScript** - JS-heavy sites (SPAs, Nuxt, React) show empty/minimal content
2. **No CSS layout** - Text extraction only, no visual styling
3. **No forms** - Input elements not yet implemented
4. **Image rendering** - Basic inline image support with GPU acceleration

## Next Steps

1. **HTML Input Types** - Form elements, text inputs, buttons
2. **Image rendering** - Basic image support
3. **Better empty page handling** - Show title for JS-only sites
4. **In-page search** - Find text with highlighting
5. **History breadcrumbs** - Show navigation history as breadcrumbs at bottom of screen (page titles, fuzzy de-duping)

## Phase 1 Complete ✓

All Phase 1 milestones done:
- [x] M1.1: Metal Pipeline Setup
- [x] M1.2: Glyph Atlas Foundation
- [x] M1.3: Swift/AppKit Shell
- [x] M1.4: HTTP GET (gzip, TLS)
- [x] M1.5: URL Parsing
- [x] M1.6: Text Extraction
- [x] M1.7: Zig-Swift Bridge

## Phase 2 In Progress

- [x] Custom shader support (GLSL transpiler)
- [x] Page transitions (70s, glitch)
- [x] Error page effects (404, 500)
- [x] Back/forward navigation
- [x] URL bar focus (/)
- [x] Image rendering (GPU-accelerated with shader effects)
- [ ] HTML form inputs
- [ ] In-page search
