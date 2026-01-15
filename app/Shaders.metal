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

// MARK: - Particle and Glow Shaders

// Particle fragment shader with soft edges and color shifting
// Creates sparkly, chromatic particles that fade beautifully
fragment float4 fragmentShaderParticle(VertexOut in [[stage_in]]) {
    // Calculate distance from center of quad (texCoords are 0-1)
    float2 center = float2(0.5, 0.5);
    float2 offset = in.texCoord - center;
    float dist = length(offset) * 2.0; // 0 at center, 1 at edge

    // Multiple layers of glow for depth
    float innerGlow = exp(-dist * dist * 8.0);  // Bright hot core
    float midGlow = exp(-dist * dist * 3.0);    // Medium glow
    float outerGlow = exp(-dist * dist * 1.5);  // Soft outer halo

    // Combine layers
    float alpha = innerGlow * 0.9 + midGlow * 0.5 + outerGlow * 0.2;

    // Color shift based on distance - chromatic aberration effect
    // Shifts color slightly toward blue at edges, warm at center
    float3 color = in.color.rgb;
    color.r += innerGlow * 0.3;  // Extra warmth at center
    color.b += (1.0 - innerGlow) * 0.2;  // Blue tint at edges

    // Sparkle effect - slight color variation based on angle
    float angle = atan2(offset.y, offset.x);
    float sparkle = sin(angle * 6.0) * 0.5 + 0.5;
    color += sparkle * innerGlow * 0.15;

    return float4(color, in.color.a * alpha);
}

// Glow fragment shader - creates a soft dreamy halo around links
// Pure gaussian falloff - no hard edges
fragment float4 fragmentShaderGlow(VertexOut in [[stage_in]]) {
    // Map texCoords to -1 to 1 range
    float2 uv = in.texCoord * 2.0 - 1.0;

    // Pure gaussian falloff in both directions (no smoothstep = no hard edge)
    float distX = uv.x * uv.x;
    float distY = uv.y * uv.y;

    // Gaussian with different spreads for X and Y (wider horizontally)
    float gaussX = exp(-distX * 2.0);  // Wider spread
    float gaussY = exp(-distY * 3.5);  // Tighter vertically

    // Combine for soft pill shape
    float alpha = gaussX * gaussY;

    // Boost the center slightly
    float centerBoost = exp(-(distX + distY) * 4.0);
    alpha = alpha * 0.85 + centerBoost * 0.15;

    // Soft color - slightly warmer at center
    float3 color = in.color.rgb;
    color.r += centerBoost * 0.05;
    color.b += (1.0 - centerBoost) * 0.1;

    return float4(color, in.color.a * alpha);
}

// MARK: - Bloom Post-Processing (Vulpes Style)
//
// Two-pass bloom: render scene to texture, then apply bloom
// Based on Ghostty bloom-vulpes.glsl - glows bright pixels

// Fullscreen quad vertex shader for post-processing
// Input: vertex index 0-5 for two triangles covering screen
vertex VertexOut vertexShaderFullscreen(
    uint vertexID [[vertex_id]]
) {
    // Generate fullscreen quad from vertex ID
    // Triangle 1: (0,1,2) Triangle 2: (2,1,3)
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),  // Triangle 1
        float2(-1, 1), float2(1, -1), float2(1, 1)     // Triangle 2
    };
    float2 texCoords[6] = {
        float2(0, 1), float2(1, 1), float2(0, 0),  // Flip Y for Metal
        float2(0, 0), float2(1, 1), float2(1, 0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    out.color = float4(1.0);
    return out;
}

// Bloom sample offsets - spiral pattern for nice distribution
constant float3 bloomSamples[24] = {
    float3(0.169, 0.986, 1.0),
    float3(-1.333, 0.472, 0.707),
    float3(-0.846, -1.511, 0.577),
    float3(1.554, -1.259, 0.5),
    float3(1.681, 1.474, 0.447),
    float3(-1.280, 2.089, 0.408),
    float3(-2.458, -0.980, 0.378),
    float3(0.587, -2.767, 0.354),
    float3(2.998, 0.117, 0.333),
    float3(0.414, 3.135, 0.316),
    float3(-3.167, 0.984, 0.302),
    float3(-1.574, -3.086, 0.289),
    float3(2.888, -2.158, 0.277),
    float3(2.715, 2.575, 0.267),
    float3(-2.150, 3.221, 0.258),
    float3(-3.655, -1.625, 0.250),
    float3(1.013, -3.997, 0.243),
    float3(4.230, 0.331, 0.236),
    float3(0.401, 4.340, 0.229),
    float3(-4.319, 1.160, 0.224),
    float3(-1.921, -4.161, 0.218),
    float3(3.864, -2.659, 0.213),
    float3(3.349, 3.433, 0.209),
    float3(-2.877, 3.965, 0.204)
};

// Bloom tuning
constant float BLOOM_INTENSITY = 0.12;   // Glow strength
constant float LUM_THRESHOLD = 0.25;     // Min brightness to bloom
constant float BLOOM_RADIUS = 2.5;       // Sample spread

// Luminance calculation
float luminance(float4 c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
}

// Check if pixel should bloom (bright or has strong color)
bool shouldBloom(float4 c) {
    float brightness = max(max(c.r, c.g), c.b);
    // Bloom bright pixels and strong blues (links)
    bool veryBright = brightness > 0.5;
    bool isBlue = c.b > 0.6 && c.b > c.r * 1.1;
    bool isRed = c.r > 0.7 && c.r > c.g * 1.1;
    return veryBright || isBlue || isRed;
}

// Bloom fragment shader - samples surrounding pixels and adds glow
fragment float4 fragmentShaderBloom(
    VertexOut in [[stage_in]],
    texture2d<float> sceneTexture [[texture(0)]]
) {
    constexpr sampler texSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    float2 uv = in.texCoord;
    float4 color = sceneTexture.sample(texSampler, uv);

    // Get texture dimensions for proper scaling
    float2 texSize = float2(sceneTexture.get_width(), sceneTexture.get_height());
    float2 step = float2(BLOOM_RADIUS) / texSize;

    // Accumulate bloom from surrounding pixels
    for (int i = 0; i < 24; i++) {
        float3 s = bloomSamples[i];
        float4 c = sceneTexture.sample(texSampler, uv + s.xy * step);
        float l = luminance(c);

        // Only bloom bright/colored pixels
        if (l > LUM_THRESHOLD && shouldBloom(c)) {
            color += l * s.z * c * BLOOM_INTENSITY;
        }
    }

    // Subtle blue emphasis for link glow
    float4 original = sceneTexture.sample(texSampler, uv);
    float4 bloomOnly = color - original;
    bloomOnly.b *= 1.15;  // Slight blue boost
    color = original + bloomOnly;

    return color;
}

// Simple passthrough for when bloom is disabled
fragment float4 fragmentShaderPassthrough(
    VertexOut in [[stage_in]],
    texture2d<float> sceneTexture [[texture(0)]]
) {
    constexpr sampler texSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    return sceneTexture.sample(texSampler, in.texCoord);
}

// MARK: - Future: Subpixel Antialiasing
//
// For macOS text rendering quality, we could implement subpixel AA:
// - Atlas stores RGB channels with per-channel coverage
// - Fragment shader blends each channel separately against background
// - Requires knowing the background color (compositing challenge)
//
// For Phase 1, grayscale antialiasing is sufficient.

// MARK: - Image Rendering

// Image fragment shader - renders images from atlas with optional effects
// Used for: inline images, background images
fragment float4 fragmentShaderImage(
    VertexOut in [[stage_in]],
    texture2d<float> imageAtlas [[texture(0)]]
) {
    constexpr sampler imageSampler(
        mag_filter::linear,    // Smooth scaling
        min_filter::linear,
        address::clamp_to_edge
    );
    
    // Sample the image atlas
    float4 color = imageAtlas.sample(imageSampler, in.texCoord);
    
    // Apply vertex alpha for fade effects
    color.a *= in.color.a;
    
    // Optionally tint based on vertex color (useful for hover effects)
    // Preserve original color but allow alpha and brightness modulation
    color.rgb *= in.color.rgb;
    
    return color;
}

// Image fragment shader with grayscale effect (shader-based filter)
fragment float4 fragmentShaderImageGrayscale(
    VertexOut in [[stage_in]],
    texture2d<float> imageAtlas [[texture(0)]]
) {
    constexpr sampler imageSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    
    float4 color = imageAtlas.sample(imageSampler, in.texCoord);
    
    // Convert to grayscale using luminance
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    
    return float4(gray, gray, gray, color.a * in.color.a);
}

// Image fragment shader with sepia tone effect
fragment float4 fragmentShaderImageSepia(
    VertexOut in [[stage_in]],
    texture2d<float> imageAtlas [[texture(0)]]
) {
    constexpr sampler imageSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    
    float4 color = imageAtlas.sample(imageSampler, in.texCoord);
    
    // Sepia transformation matrix
    float3 sepia;
    sepia.r = dot(color.rgb, float3(0.393, 0.769, 0.189));
    sepia.g = dot(color.rgb, float3(0.349, 0.686, 0.168));
    sepia.b = dot(color.rgb, float3(0.272, 0.534, 0.131));
    
    return float4(sepia, color.a * in.color.a);
}

