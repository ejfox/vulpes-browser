// Cyberpunk Glitch / Datamosh Transition Shader
// Digital corruption effect with block displacement and color channel splits

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;

    // Transition intensity - peaks in middle
    float t = iTime;
    float intensity = sin(t * 3.14159);

    // Block-based displacement (datamosh style)
    float blockSize = 32.0 + intensity * 64.0;
    vec2 block = floor(fragCoord / blockSize);

    // Pseudo-random per block
    float blockRand = fract(sin(dot(block, vec2(12.9898, 78.233)) + t * 0.1) * 43758.5453);
    float blockRand2 = fract(sin(dot(block, vec2(93.989, 17.345)) + t * 0.15) * 24876.123);

    // Horizontal block displacement (corruption)
    float displaceX = 0.0;
    if (blockRand > (1.0 - intensity * 0.4)) {
        displaceX = (blockRand2 - 0.5) * 0.15 * intensity;
    }

    // Vertical tear/jump
    float displaceY = 0.0;
    if (blockRand2 > (1.0 - intensity * 0.2)) {
        displaceY = (blockRand - 0.5) * 0.08 * intensity;
    }

    vec2 glitchUV = uv + vec2(displaceX, displaceY);

    // Scanline flicker
    float scanline = sin(fragCoord.y * 2.0 + t * 50.0) * 0.5 + 0.5;
    float flicker = 1.0 - intensity * 0.2 * scanline;

    // Aggressive chromatic aberration
    float chromaOffset = 0.02 * intensity;
    float r = texture(iChannel0, glitchUV + vec2(chromaOffset * (blockRand - 0.5), 0.0)).r;
    float g = texture(iChannel0, glitchUV).g;
    float b = texture(iChannel0, glitchUV - vec2(chromaOffset * (blockRand2 - 0.5), 0.0)).b;

    vec3 color = vec3(r, g, b);

    // Color bit-crush / posterization during peak intensity
    if (intensity > 0.5) {
        float crush = 4.0 + (1.0 - intensity) * 12.0;
        color = floor(color * crush) / crush;
    }

    // Random noise overlay
    float noise = fract(sin(dot(fragCoord, vec2(12.9898, 78.233)) + t * 1000.0) * 43758.5453);
    color = mix(color, vec3(noise), intensity * 0.1);

    // Occasional full-screen flash
    if (blockRand > 0.98 && intensity > 0.6) {
        color = mix(color, vec3(1.0), 0.5);
    }

    // RGB shift lines (like bad VHS tracking)
    if (mod(fragCoord.y + t * 500.0, 200.0) < 3.0 * intensity) {
        color.r = texture(iChannel0, uv + vec2(0.05, 0.0)).r;
    }

    fragColor = vec4(color * flicker, 1.0);
}
