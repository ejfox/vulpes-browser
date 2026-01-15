# Image Rendering Pipeline

## Overview Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    VULPES IMAGE PIPELINE                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────┐
│   HTML      │
│  <img src>  │
└──────┬──────┘
       │
       │ Parse (Zig)
       ▼
┌─────────────┐      ┌──────────────┐
│ Control     │      │  Image URLs  │
│ Markers     │      │    [1], [2]  │
│ 0x1E...0x1E │◄────►│              │
└──────┬──────┘      └──────┬───────┘
       │                    │
       │ Display            │ Download (Async)
       ▼                    ▼
┌─────────────┐      ┌──────────────┐
│  Text       │      │   NSImage    │
│  Layout     │      │   Decode     │
│  Engine     │      └──────┬───────┘
└──────┬──────┘             │
       │                    │ Convert
       │                    ▼
       │             ┌──────────────┐
       │             │   CGImage    │
       │             │  (RGBA)      │
       │             └──────┬───────┘
       │                    │
       │                    │ Upload (GPU)
       │                    ▼
       │             ┌──────────────────┐
       │             │  Staging Texture │
       │             │   (Shared)       │
       │             └──────┬───────────┘
       │                    │
       │                    │ Blit Encoder
       │                    ▼
       │             ┌──────────────────┐
       │             │   Image Atlas    │
       │             │   4096x4096      │
       │             │   (Private GPU)  │
       │             └──────┬───────────┘
       │                    │
       │                    │
       ▼                    ▼
┌────────────────────────────────────┐
│        METAL RENDER PASS           │
│  ┌──────────────────────────────┐  │
│  │ 1. Glow (Behind)             │  │
│  │ 2. Text Glyphs               │  │
│  │ 3. Images (Inline)    ◄──────┼──┘
│  │ 4. Particles (Overlay)       │
│  └──────────────────────────────┘  │
│             │                       │
│             ▼                       │
│  ┌──────────────────────────────┐  │
│  │  Offscreen Texture           │  │
│  └──────────────────────────────┘  │
│             │                       │
│             ▼                       │
│  ┌──────────────────────────────┐  │
│  │  Bloom/Custom Shader         │  │
│  └──────────────────────────────┘  │
│             │                       │
│             ▼                       │
│  ┌──────────────────────────────┐  │
│  │  Final Display               │  │
│  └──────────────────────────────┘  │
└────────────────────────────────────┘
```

## Component Details

### 1. HTML Parsing (Zig)

```zig
// src/html/text_extractor.zig
if (tag_name == "img") {
    src = extractImgSrc(tag);
    append(IMAGE_MARKER);
    append(image_number);
    append(IMAGE_MARKER);
}
```

Output format:
```
Some text [IMAGE_MARKER]1[IMAGE_MARKER] more text

---
Images:
[1] https://example.com/image.jpg
```

### 2. Image Download (Swift - Async)

```swift
// app/ImageAtlas.swift
downloadQueue.async {
    let data = try Data(contentsOf: url)
    let nsImage = NSImage(data: data)
    let cgImage = nsImage.cgImage(...)
    
    DispatchQueue.main.async {
        addToAtlas(url: url, image: cgImage)
    }
}
```

### 3. GPU Upload (Zero-Copy Blit)

```swift
// Create staging texture (CPU-accessible)
let stagingTexture = device.makeTexture(
    descriptor: .shared  // CPU can write
)

// Upload data to staging
stagingTexture.replace(region: region, 
                      withBytes: rawData)

// GPU-side copy to atlas
blitEncoder.copy(
    from: stagingTexture,
    to: atlasTexture  // .private storage
)
```

### 4. Atlas Packing

```
┌────────────────────────────────────────┐
│ 4096 x 4096 Atlas Texture              │
│                                        │
│ ┌────┐┌────┐┌──────┐                  │
│ │Img1││Img2││ Img3 │                  │
│ └────┘└────┘└──────┘                  │
│                                        │
│ ┌─────────┐┌───┐┌───┐                 │
│ │  Img4   ││I5 ││I6 │                 │
│ └─────────┘└───┘└───┘                 │
│                                        │
│ ┌──┐┌──────────┐                      │
│ │I7││  Img8    │                      │
│ └──┘└──────────┘                      │
│                                        │
│          (Free space)                 │
│                                        │
└────────────────────────────────────────┘

Next position: (x, y)
Current row height: max(img heights)
```

### 5. Rendering (Metal)

```metal
// Vertex shader (same as text)
vertex VertexOut vertexShader(
    Vertex in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    // Convert pixel coords to clip space
    out.position = pixelToClip(in.position, uniforms.viewportSize);
    out.texCoord = in.texCoord;  // UV in atlas
    return out;
}

// Fragment shader
fragment float4 fragmentShaderImage(
    VertexOut in [[stage_in]],
    texture2d<float> imageAtlas [[texture(0)]]
) {
    sampler s(filter::linear);
    float4 color = imageAtlas.sample(s, in.texCoord);
    return color * in.color;  // Apply tint/alpha
}
```

### 6. Effect Shaders

```metal
// Grayscale
float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
return float4(gray, gray, gray, color.a);

// Sepia
sepia.r = dot(color.rgb, float3(0.393, 0.769, 0.189));
sepia.g = dot(color.rgb, float3(0.349, 0.686, 0.168));
sepia.b = dot(color.rgb, float3(0.272, 0.534, 0.131));
```

## Data Flow Timeline

```
Time →

[0ms]    HTML parsed, images extracted
         └─► IMAGE_MARKER positions noted
         
[10ms]   Text layout begins
         └─► Image placeholders created
         
[50ms]   First frame rendered (text only)
         └─► Images downloading in background
         
[150ms]  First image downloaded
         └─► Decoded to CGImage
         └─► Uploaded to atlas
         └─► Frame invalidated
         
[160ms]  Second frame rendered (text + 1 image)
         
[250ms]  More images loaded
         └─► Atlas fills up
         
[350ms]  All images rendered
         └─► Final frame at 60 FPS
```

## Memory Layout

```
CPU Memory (~50 MB):
┌─────────────────────┐
│ HTML Text           │  5 MB
│ Swift Objects       │  10 MB
│ Image URLs/Metadata │  5 MB
│ Vertex Buffers      │  10 MB
│ Staging Buffers     │  20 MB (temporary)
└─────────────────────┘

GPU Memory (~100 MB):
┌─────────────────────┐
│ Image Atlas (4K)    │  64 MB
│ Glyph Atlas (1K)    │  1 MB
│ Offscreen Texture   │  16 MB
│ Vertex Buffers      │  10 MB
│ Individual Textures │  9 MB (large images)
└─────────────────────┘

Total: ~150 MB (vs ~250 MB CPU-only)
```

## Cache Management

```
LRU Cache:
┌────────────────────────────────────┐
│  Most Recent                       │
│  ┌──────────────┐                  │
│  │ image_10.jpg │  used: now       │
│  ├──────────────┤                  │
│  │ image_05.jpg │  used: -2s       │
│  ├──────────────┤                  │
│  │ image_03.jpg │  used: -5s       │
│  ├──────────────┤                  │
│  │ image_08.jpg │  used: -10s      │
│  ├──────────────┤                  │
│  │     ...      │                  │
│  ├──────────────┤                  │
│  │ image_01.jpg │  used: -120s ◄── Evict first
│  └──────────────┘                  │
│  Least Recent                      │
└────────────────────────────────────┘

On cache full:
1. Sort by timestamp
2. Remove oldest 25%
3. Clear atlas
4. Reload remaining
```

## Performance Characteristics

```
Operation               CPU Time    GPU Time    Total
────────────────────────────────────────────────────
Download image          50ms        0ms         50ms
Decode (NSImage)        20ms        0ms         20ms
Convert to CGImage      5ms         0ms         5ms
Upload to staging       2ms         0ms         2ms
Blit to atlas          0ms         1ms         1ms
Render (first frame)    0ms         0.5ms       0.5ms
Render (subsequent)     0ms         0.1ms       0.1ms
────────────────────────────────────────────────────
Total (first image)     77ms        1.5ms       78.5ms
Per-frame overhead      0ms         0.1ms       0.1ms

FPS with 100 images: 60 (render time: 10ms)
```

## Comparison to Traditional Approach

```
Traditional (CPU-based):
┌────────────────────────────────────┐
│ HTML → Parse → Download → Decode   │
│   ↓      ↓       ↓         ↓       │
│ CPU    CPU     CPU       CPU       │
│                ↓                    │
│             Scale (CPU)             │
│                ↓                    │
│             Blend (CPU)             │
│                ↓                    │
│          Upload to GPU              │
│                ↓                    │
│           Display (GPU)             │
└────────────────────────────────────┘
Time: ~200ms per image
Memory: 2x (CPU + GPU copies)

Vulpes (GPU-first):
┌────────────────────────────────────┐
│ HTML → Parse → Download → Decode   │
│   ↓      ↓       ↓         ↓       │
│  Zig    Zig    Swift     Swift     │
│                ↓                    │
│          Upload (Blit)              │
│                ↓                    │
│    Scale + Blend + Display (GPU)   │
└────────────────────────────────────┘
Time: ~80ms per image (2.5x faster)
Memory: 1x (GPU only)
```

## Key Innovations

1. **Zero-Copy Upload**
   - Staging texture → Blit encoder → Atlas
   - GPU performs copy asynchronously
   - CPU thread never blocks

2. **Unified Atlas**
   - Text glyphs + images in related atlases
   - Single bind for multiple images
   - Efficient GPU state management

3. **Shader Effects**
   - Filter applied during render
   - No separate pass needed
   - Cost: ~0.01ms per image

4. **Smart Eviction**
   - LRU tracks actual usage
   - Batch eviction (25% at once)
   - Minimal fragmentation

5. **Async Pipeline**
   - Download, decode, upload all parallel
   - UI never blocks
   - Progressive enhancement
