// Shaders.metal
// vulpes-browser
//
// Metal shaders for 2D rendering. Simple and focused:
// - Colored rectangles (selections, cursors, backgrounds)
// - Textured quads (glyphs from atlas)
//
// Coordinate System:
// - Input: Pixel coordinates (0,0 at top-left, like web/AppKit)
// - Output: Metal clip space (-1 to 1, Y-up)
// - Transformation done in vertex shader using viewport size uniform

#include <metal_stdlib>
using namespace metal;

// MARK: - Data Structures

// Per-vertex data passed from CPU to vertex shader
struct Vertex {
    float2 position [[attribute(0)]];  // Pixel coordinates
    float2 texCoord [[attribute(1)]];  // UV for glyph atlas (0-1)
    float4 color    [[attribute(2)]];  // RGBA color
};

// Uniform data shared by all vertices in a draw call
struct Uniforms {
    float2 viewportSize;  // Width and height in pixels
};

// Data passed from vertex shader to fragment shader
struct VertexOut {
    float4 position [[position]];  // Clip space position (Metal requirement)
    float2 texCoord;               // UV for texture sampling
    float4 color;                  // Vertex color
};

// MARK: - Vertex Shader

vertex VertexOut vertexShader(
    Vertex in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;

    // Transform from pixel coordinates to clip space
    // Pixel: (0,0) top-left, (width, height) bottom-right
    // Clip:  (-1,-1) bottom-left, (1,1) top-right
    //
    // Formula:
    //   clipX = (pixelX / width) * 2.0 - 1.0
    //   clipY = 1.0 - (pixelY / height) * 2.0  (flip Y for top-left origin)

    float2 clipPosition;
    clipPosition.x = (in.position.x / uniforms.viewportSize.x) * 2.0 - 1.0;
    clipPosition.y = 1.0 - (in.position.y / uniforms.viewportSize.y) * 2.0;

    out.position = float4(clipPosition, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = in.color;

    return out;
}

// MARK: - Fragment Shaders

// Solid color fragment shader
// Used for: rectangles, selections, cursors, backgrounds
fragment float4 fragmentShaderSolid(VertexOut in [[stage_in]]) {
    return in.color;
}

// Textured fragment shader for glyph rendering
// Used for: text glyphs from atlas
//
// The glyph atlas is grayscale (alpha only).
// We use the alpha from the texture and RGB from the vertex color.
// This allows colored text with a single-channel atlas.
fragment float4 fragmentShaderGlyph(
    VertexOut in [[stage_in]],
    texture2d<float> glyphAtlas [[texture(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    // Sample the glyph atlas - we only care about alpha
    float alpha = glyphAtlas.sample(textureSampler, in.texCoord).r;

    // Output: vertex color with atlas alpha
    return float4(in.color.rgb, in.color.a * alpha);
}

// MARK: - Future: Subpixel Antialiasing
//
// For macOS text rendering quality, we could implement subpixel AA:
// - Atlas stores RGB channels with per-channel coverage
// - Fragment shader blends each channel separately against background
// - Requires knowing the background color (compositing challenge)
//
// For Phase 1, grayscale antialiasing is sufficient.
