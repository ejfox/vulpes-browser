# Vulpes Browser

A minimalist, keyboard-first web browser for macOS. Built with Zig, Swift, and Metal.

> **Beta Release** - This is early software. Expect rough edges.

## Download

Download the latest release from [GitHub Releases](https://github.com/ejfox/vulpes-browser/releases).

**Requirements:** macOS 14 (Sonoma) or later, Apple Silicon or Intel Mac.

## What It Does

Vulpes renders web pages as clean, readable text with GPU-accelerated graphics. No ads, no tracking, no JavaScript.

- **Vim-style navigation** - `j`/`k` scroll, `d`/`u` half-page, `G`/`gg` top/bottom
- **Link navigation** - Numbers 1-9 follow links, `b`/`f` for back/forward
- **Metal rendering** - GPU-accelerated text with glyph atlas
- **GLSL shaders** - Ghostty/Shadertoy-compatible custom shaders
- **Page transitions** - Visual effects when navigating

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `j` / `k` | Scroll down / up |
| `d` / `u` | Half-page down / up |
| `G` / `gg` | Bottom / top |
| `b` / `f` | Back / forward |
| `/` or `Cmd+L` | Focus URL bar |
| `1-9` | Follow numbered link |
| `Tab` | Cycle through links |
| `Enter` | Activate focused link |

## Configuration

Config file at `~/.config/vulpes/config`:

```
shader = bloom-vulpes
bloom = true
scroll_speed = 40
home_page = https://example.com
```

Shaders load from `~/.config/ghostty/shaders/` for Ghostty compatibility.

## Building from Source

Requirements:
- macOS 14+
- Zig 0.15+
- Xcode 15+
- xcodegen (`brew install xcodegen`)

```bash
zig build
xcodegen generate
xcodebuild -project Vulpes.xcodeproj -scheme Vulpes -configuration Release build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/Vulpes-*/Build/Products/Release/Vulpes.app`

## Limitations

This is a text-focused browser. It does **not** support:
- JavaScript (SPAs will show minimal content)
- CSS layout (text extraction only)
- Images
- Forms

This is intentional. Vulpes is for reading, not web apps.

## License

MIT
