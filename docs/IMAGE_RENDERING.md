# Image Rendering System

## Overview

Vulpes Browser uses a high-performance, shader-based image rendering system that leverages Metal's GPU acceleration for efficient image display.

## Architecture

### Components

1. **HTML Image Extraction (Zig)**
   - `src/html/text_extractor.zig` parses `<img>` tags
   - Extracts `src` attributes and creates image placeholders
   - Uses control character markers (`0x1E`) for inline placement

2. **ImageAtlas (Swift)**
   - `app/ImageAtlas.swift` manages GPU texture atlas
   - Async image downloading and decoding
   - LRU cache with smart eviction
   - Texture packing for memory efficiency

3. **Metal Shaders**
   - `app/Shaders.metal` contains image fragment shaders
   - `fragmentShaderImage`: Standard image rendering
   - `fragmentShaderImageGrayscale`: Grayscale filter
   - `fragmentShaderImageSepia`: Sepia tone effect

4. **Rendering Pipeline**
   - `app/MetalView.swift` integrates image rendering
   - Images rendered after text, before particles
   - Preserves aspect ratio and scales to fit layout

## Performance Features

### GPU Acceleration
- All images rendered via Metal shaders
- Zero-copy texture upload using blit encoder
- Private GPU memory for optimal performance

### Texture Atlas
- Multiple images packed into 4K atlas texture
- Reduces draw calls and texture binds
- Automatic eviction for memory management

### Async Loading
- Images download in background
- Non-blocking UI rendering
- Progressive enhancement (text first, then images)

### Smart Caching
- LRU eviction strategy
- Configurable cache size (default: 100 images)
- Individual textures for large images (>2048px)

## Usage

### HTML Support
Images are automatically extracted from HTML:

```html
<img src="https://example.com/image.jpg" alt="Example">
<img src="/relative/path.png">
```

### Image Placement
- Images are placed inline in the text flow
- Numbered placeholders (e.g., `[IMG:1]`) mark positions
- Images scale to fit readable line width

### Relative URLs
Image URLs are resolved relative to the current page URL:
```swift
// /image.png becomes https://example.com/image.png
```

## Shader Effects

### Built-in Filters
- **Normal**: Full-color rendering
- **Grayscale**: Luminance-based conversion
- **Sepia**: Vintage photo effect

### Custom Shaders
To add custom image effects:

1. Add fragment shader to `Shaders.metal`:
```metal
fragment float4 fragmentShaderImageCustom(
    VertexOut in [[stage_in]],
    texture2d<float> imageAtlas [[texture(0)]]
) {
    // Your custom effect here
}
```

2. Create pipeline state in `MetalView.swift`
3. Apply during image rendering

## Configuration

### Atlas Settings
```swift
// ImageAtlas.swift
private let maxAtlasSize: Int = 4096  // 4K atlas
private let maxIndividualSize: Int = 2048  // Individual texture threshold
private let maxCacheSize: Int = 100  // Max cached images
```

### Image Size
```swift
// MetalView.swift - updateTextDisplay()
let desiredWidth: Float = min(400.0 * Float(scale), maxImageWidth)
```

## Memory Management

### Atlas Packing
- Simple row-based packing algorithm
- 2px padding between images
- Automatic overflow to next row

### Eviction Strategy
- LRU (Least Recently Used)
- Evicts 25% or 10 images when full
- Atlas is rebuilt after eviction

### Large Images
- Images >2048px get individual textures
- Bypasses atlas packing
- Still uses GPU memory efficiently

## Debugging

### Logging
```
ImageAtlas: Initialized with 4096x4096 atlas
ImageAtlas: Downloading https://...
ImageAtlas: Added image 800x600 at (0, 0)
MetalView: Parsed 5 links, 3 images
```

### Common Issues

**Images not showing:**
- Check that URLs are accessible
- Verify image format (PNG, JPEG, WebP supported)
- Look for download errors in console

**Performance issues:**
- Reduce `maxCacheSize` if memory constrained
- Lower `maxAtlasSize` for older GPUs
- Check that images aren't excessively large

## Future Enhancements

### Planned Features
- [ ] Progressive JPEG rendering
- [ ] WebP animation support
- [ ] Image lazy loading (viewport culling)
- [ ] Blur/sharpen filters
- [ ] Color adjustment shaders
- [ ] Image click-to-zoom

### Performance Optimizations
- [ ] Mipmapping for scaled images
- [ ] Compressed texture formats (ASTC, BC7)
- [ ] Better atlas packing (Skyline algorithm)
- [ ] Image preloading hints

## Technical Details

### Texture Formats
- **Atlas**: `rgba8Unorm` - 8-bit per channel, premultiplied alpha
- **Storage**: `.private` - GPU-only memory
- **Sampling**: Linear filtering for smooth scaling

### Coordinate Systems
- **Atlas UV**: (0,0) top-left, (1,1) bottom-right
- **Screen**: Pixel coordinates, Y-down
- **Metal Clip**: NDC coordinates, Y-up

### Rendering Order
1. Glow effects (behind text)
2. Text glyphs
3. **Images (inline with text)**
4. Particles (overlay)

## Example Integration

### Simple Page with Image
```html
<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body>
  <h1>My Page</h1>
  <p>Some text before image.</p>
  <img src="https://via.placeholder.com/400x300.png" alt="Demo">
  <p>Text after image.</p>
</body>
</html>
```

### Expected Output
```
My Page

Some text before image.

[IMG:1]

Text after image.

---
Images:
[1] https://via.placeholder.com/400x300.png
```

## License

Same as Vulpes Browser - see main LICENSE file.
