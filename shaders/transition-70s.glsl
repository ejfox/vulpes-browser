// 70s Dream Sequence / VHS Transition Shader
// Wobbly wave distortion with chromatic aberration
// Use iTransition (0.0 to 1.0) to control progress

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;

    // Transition progress - peaks at 0.5, fades at edges
    float t = iTime;  // Controlled externally during transition
    float intensity = sin(t * 3.14159);  // Smooth in-out

    // 70s wobbly wave parameters
    float waveFreqX = 8.0 + intensity * 12.0;
    float waveFreqY = 6.0 + intensity * 8.0;
    float waveAmpX = 0.02 * intensity;
    float waveAmpY = 0.015 * intensity;

    // Time-based phase for animation
    float phase = t * 15.0;

    // Apply horizontal wobble (like VHS tracking issues)
    float wobbleX = sin(uv.y * waveFreqY + phase) * waveAmpX;
    float wobbleY = sin(uv.x * waveFreqX + phase * 0.7) * waveAmpY;

    // Add scanline jitter (that 70s CRT feel)
    float jitter = sin(fragCoord.y * 0.5 + phase * 3.0) * 0.002 * intensity;

    vec2 distortedUV = uv + vec2(wobbleX + jitter, wobbleY);

    // Chromatic aberration - split RGB channels
    float chromaOffset = 0.008 * intensity;
    float r = texture(iChannel0, distortedUV + vec2(chromaOffset, 0.0)).r;
    float g = texture(iChannel0, distortedUV).g;
    float b = texture(iChannel0, distortedUV - vec2(chromaOffset, 0.0)).b;

    // Color tint - warm 70s tones
    vec3 warmTint = vec3(1.05, 0.98, 0.9);
    vec3 color = vec3(r, g, b) * mix(vec3(1.0), warmTint, intensity * 0.5);

    // Vignette that pulses with the transition
    float vignette = 1.0 - smoothstep(0.4, 1.0, length(uv - 0.5) * (1.0 + intensity * 0.3));

    // Slight bloom/glow effect
    color = mix(color, color * 1.2, intensity * 0.3);

    fragColor = vec4(color * vignette, 1.0);
}
