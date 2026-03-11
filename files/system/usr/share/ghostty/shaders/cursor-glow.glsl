float sdBox(vec2 p, vec2 center, vec2 half_size) {
    vec2 d = abs(p - center) - half_size;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 base = texture(iChannel0, uv);
    fragColor = base;

    if (iCursorVisible.x < 0.5 || iCurrentCursor.z <= 0.0 || iCurrentCursor.w <= 0.0) {
        return;
    }

    vec2 center = vec2(
        iCurrentCursor.x + iCurrentCursor.z * 0.5,
        iCurrentCursor.y - iCurrentCursor.w * 0.5
    );
    vec2 half_size = max(iCurrentCursor.zw * 0.5, vec2(1.0));

    float since_change = max(0.0, iTime - iTimeCursorChange);
    float pulse = 0.55 + 0.45 * exp(-since_change * 3.2) * cos(since_change * 10.0);

    float box_dist = sdBox(fragCoord, center, half_size + vec2(2.0));
    float glow = exp(-max(0.0, box_dist) * 0.08) * 0.25 * pulse;

    float ring_radius = 4.0 + min(12.0, since_change * 22.0);
    float ring = smoothstep(2.4, 0.0, abs(sdBox(fragCoord, center, half_size + vec2(ring_radius))));
    ring *= 0.12 * exp(-since_change * 2.4);

    vec3 accent = mix(iCursorColor.rgb, vec3(0.96, 0.77, 0.93), 0.35);
    fragColor.rgb = min(vec3(1.0), fragColor.rgb + accent * (glow + ring));
}
