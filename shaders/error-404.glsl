// 404 - Lost in the Void
// Drifting, searching, existential shader for page not found
// Continuous loop - the eternal search for content that doesn't exist

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 center = uv - 0.5;

    float t = iTime;

    // Swirling void - like being lost in space
    float angle = atan(center.y, center.x);
    float dist = length(center);

    // Spiral distortion - searching, spinning
    float spiral = sin(angle * 3.0 + dist * 10.0 - t * 2.0) * 0.5 + 0.5;

    // Pulsing rings - radar searching for the page
    float rings = sin(dist * 30.0 - t * 4.0) * 0.5 + 0.5;
    rings *= smoothstep(0.5, 0.0, dist);

    // Drifting noise - static from the void
    float noise = fract(sin(dot(uv + t * 0.1, vec2(12.9898, 78.233))) * 43758.5453);
    float noise2 = fract(sin(dot(uv - t * 0.15, vec2(93.989, 67.345))) * 24876.123);

    // Sample the underlying content with drift
    vec2 drift = vec2(
        sin(t * 0.5 + uv.y * 3.0) * 0.02,
        cos(t * 0.7 + uv.x * 2.0) * 0.02
    );
    vec4 content = texture(iChannel0, uv + drift);

    // Dissolve effect - content fading into void
    float dissolve = noise * 0.5 + spiral * 0.3 + rings * 0.2;
    float fadeAmount = sin(t * 0.5) * 0.2 + 0.6;
    content.rgb = mix(content.rgb, vec3(0.0), dissolve * fadeAmount);

    // Add searching scan lines
    float scanline = sin(fragCoord.y * 0.5 + t * 10.0) * 0.5 + 0.5;
    scanline = pow(scanline, 8.0) * 0.3;

    // Purple/blue void colors - mysterious, lost
    vec3 voidColor = vec3(0.1, 0.05, 0.2);
    vec3 searchColor = vec3(0.3, 0.4, 0.8);
    vec3 highlight = mix(voidColor, searchColor, rings);

    // Blend content with void
    vec3 color = mix(content.rgb, highlight, 0.3 + dissolve * 0.2);
    color += scanline * searchColor;

    // Occasional "found something?" flash
    float flash = pow(sin(t * 0.3) * 0.5 + 0.5, 8.0);
    color += flash * 0.2 * searchColor;

    // Vignette - darkness at edges
    float vignette = 1.0 - smoothstep(0.3, 0.7, dist);
    color *= vignette * 0.7 + 0.3;

    fragColor = vec4(color, 1.0);
}
