VULPES
======

Minimalist web browser. Zig + Swift + Metal.

BUILD
-----
    zig build
    xcodegen generate
    xcodebuild -project Vulpes.xcodeproj -scheme Vulpes build

RUN
---
    open Vulpes.xcodeproj  # run from Xcode
    # or directly:
    ./zig-out/bin/vulpes-cli https://example.com

REQUIREMENTS
------------
- macOS 14+
- Zig 0.15+
- Xcode 15+
- xcodegen

FEATURES
--------
- HTTP/HTTPS with TLS
- gzip/deflate decompression
- HTML text extraction with link parsing
- Metal GPU rendering with glyph atlas
- Vim keys: j/k scroll, d/u half-page, G/gg top/bottom
- Back/forward history with b/f
- Numbered link navigation (1-9)
- GLSL shaders (Ghostty/Shadertoy compatible)
- Page transition effects
- Error shaders for 404/500
- Config file at ~/.config/vulpes/config

NOT YET
-------
- JavaScript
- CSS layout
- Images
- Forms

NO
--
- Ads
- Tracking

LICENSE
-------
MIT
