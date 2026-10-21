// Абстрактные сцены.

float3 scene_aurora(float2 fc, float2 res, float t) {
    float2 uv = fc / res.y;
    float ty = fc.y / res.y;
    float tt = t * 0.06;

    float3 col = mix(float3(0.01, 0.02, 0.05), float3(0.02, 0.06, 0.14), ty);
    col += float3(stars(uv, 90.0, t)) * smoothstep(0.3, 1.0, ty) * 0.8;

    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float n = fbm(float2(uv.x * 1.6 + fi * 3.1, tt + fi * 1.7));
        float center = 0.55 + fi * 0.08 + 0.25 * (n - 0.5);
        float d = ty - center;
        float curtain = exp(-d * d * (d > 0.0 ? 25.0 : 120.0));
        float rays = 0.55 + 0.45 * fbm(float2(uv.x * 9.0 + fi * 5.0, tt * 4.0));
        float3 tint = mix(float3(0.10, 0.95, 0.55), float3(0.55, 0.30, 1.00), fi / 2.0);
        col += tint * curtain * rays * 0.55;
    }
    col += float3(0.05, 0.12, 0.10) * exp(-ty * 6.0);
    return col;
}

float3 scene_plasma(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float tt = t * 0.25;
    float v = sin(p.x * 3.0 + tt);
    v += sin((p.y * 3.0 + tt) * 0.8);
    v += sin((p.x + p.y) * 2.5 + tt * 1.3);
    v += sin(length(p * 4.0 + float2(sin(tt * 0.7), cos(tt * 0.5)) * 2.0) * 3.0 - tt);
    float3 col = palette(v * 0.18 + tt * 0.05, float3(0.5), float3(0.5), float3(1.0), float3(0.0, 0.33, 0.67));
    return pow(col, float3(1.3)) * 0.9;
}

float3 scene_waves(float2 fc, float2 res, float t) {
    float2 uv = fc / res;
    float x = fc.x / res.y;
    float tt = t * 0.35;
    float3 col = mix(float3(1.00, 0.72, 0.55), float3(0.30, 0.28, 0.65), uv.y);
    for (int i = 4; i >= 0; i--) {
        float fi = float(i);
        float y0 = 0.15 + fi * 0.12
                 + 0.045 * sin(x * (1.2 + fi * 0.35) + tt * (0.6 + fi * 0.12) + fi * 1.3)
                 + 0.020 * sin(x * (3.1 + fi) - tt * 0.9 + fi * 2.1);
        float3 layerColor = mix(float3(0.10, 0.07, 0.30), float3(0.95, 0.45, 0.50), fi / 4.0);
        float above = uv.y - y0;
        col *= 1.0 - 0.18 * exp(-max(above, 0.0) * 35.0) * step(0.0, above);
        float mask = 1.0 - smoothstep(-0.0025, 0.0025, above);
        col = mix(col, layerColor * (0.85 + 0.15 * uv.y), mask);
    }
    return col;
}

float3 starLayer(float2 uv) {
    float3 col = float3(0.0);
    float2 gv = fract(uv) - 0.5;
    float2 id = floor(uv);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 offs = float2(float(x), float(y));
            float n = hash21(id + offs);
            float size = fract(n * 345.32);
            float2 p = gv - offs - float2(n, fract(n * 34.0)) + 0.5;
            float d = length(p);
            float m = 0.02 * size / max(d, 0.001);
            m *= 1.0 - smoothstep(0.2, 0.9, d);
            float3 tint = sin(float3(0.2, 0.3, 0.9) * fract(n * 2345.2) * 123.2) * 0.5 + 0.5;
            tint = tint * float3(1.0, 0.5, 1.0 + size) + float3(0.4, 0.4, 0.6);
            col += m * tint;
        }
    }
    return col;
}

float3 scene_starfield(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float tt = t * 0.03;
    float3 col = float3(0.005, 0.005, 0.02) + float3(0.04, 0.02, 0.08) * (1.0 - length(p));
    for (int i = 0; i < 5; i++) {
        float depth = fract(float(i) / 5.0 + tt);
        float scale = mix(18.0, 0.6, depth);
        float fade = depth * (1.0 - smoothstep(0.85, 1.0, depth));
        col += starLayer(p * scale + float(i) * 453.2) * fade;
    }
    return 1.0 - exp(-col * 1.4);
}
