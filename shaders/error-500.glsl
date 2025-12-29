// 500 - Server Meltdown
// Fire, chaos, digital destruction - the server is NOT okay
// Continuous loop of pure chaos energy

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    float t = iTime;

    // Rising fire effect
    vec2 fireUV = uv;
    fireUV.y += t * 0.3;

    // Multi-octave fire noise
    float fire = 0.0;
    float amp = 0.5;
    vec2 p = fireUV * 4.0;
    for (int i = 0; i < 4; i++) {
        fire += amp * fract(sin(dot(p + t, vec2(12.9898, 78.233))) * 43758.5453);
        p *= 2.0;
        amp *= 0.5;
    }

    // Fire intensity based on vertical position (hotter at bottom)
    float fireIntensity = (1.0 - uv.y) * 1.5;
    fire *= fireIntensity;

    // Glitch blocks - server corruption
    float blockSize = 16.0 + sin(t * 3.0) * 8.0;
    vec2 block = floor(fragCoord / blockSize);
    float blockRand = fract(sin(dot(block, vec2(12.9898, 78.233)) + floor(t * 5.0)) * 43758.5453);

    // Random block displacement
    vec2 glitchOffset = vec2(0.0);
    if (blockRand > 0.85) {
        glitchOffset.x = (blockRand - 0.5) * 0.1;
    }

    // Sample content with glitch
    vec4 content = texture(iChannel0, uv + glitchOffset);

    // Chromatic aberration - things are breaking
    float chromaAmt = 0.015 * (1.0 + sin(t * 5.0));
    float r = texture(iChannel0, uv + glitchOffset + vec2(chromaAmt, 0.0)).r;
    float g = content.g;
    float b = texture(iChannel0, uv + glitchOffset - vec2(chromaAmt, 0.0)).b;
    content.rgb = vec3(r, g, b);

    // Fire colors
    vec3 fireColorLow = vec3(0.8, 0.2, 0.0);
    vec3 fireColorMid = vec3(1.0, 0.5, 0.0);
    vec3 fireColorHigh = vec3(1.0, 0.9, 0.3);

    vec3 fireColor = mix(fireColorLow, fireColorMid, fire);
    fireColor = mix(fireColor, fireColorHigh, pow(fire, 3.0));

    // Blend fire with content
    vec3 color = mix(content.rgb, fireColor, fire * 0.6);

    // Add emergency red pulse
    float emergency = sin(t * 8.0) * 0.5 + 0.5;
    color += vec3(0.3, 0.0, 0.0) * emergency * 0.2;

    // Smoke at top
    float smoke = smoothstep(0.3, 0.0, 1.0 - uv.y);
    float smokeNoise = fract(sin(dot(uv + t * 0.2, vec2(12.9898, 78.233))) * 43758.5453);
    smoke *= smokeNoise;
    color = mix(color, vec3(0.2), smoke * 0.5);

    // Scanline flicker - failing display
    float scanline = sin(fragCoord.y * 2.0 + t * 20.0);
    color *= 0.95 + scanline * 0.05;

    fragColor = vec4(color, 1.0);
}
