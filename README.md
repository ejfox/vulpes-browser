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
- HTML text extraction
- Metal GPU rendering
- 60fps glyph atlas

NO
--
- JavaScript
- Ads
- Tracking

LICENSE
-------
MIT
