#include <metal_stdlib>
using namespace metal;

// Должна совпадать с ShaderUniforms в ShaderRenderer.swift.
struct Uniforms {
    float2 resolution;
    float time;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
};

// Один треугольник, перекрывающий весь экран.
vertex VertexOut wallpaper_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2(float((vid << 1) & 2), float(vid & 2));
    VertexOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// MARK: - Helpers

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

static float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * t + d));
}

/// Координаты с началом внизу слева, по вертикали 0…1, по горизонтали с учётом пропорций.
static float2 aspectUV(float4 position, constant Uniforms &u) {
    float2 p = position.xy / u.resolution.y;
    p.y = 1.0 - p.y;
    return p;
}

// MARK: - Северное сияние

fragment float4 fragment_aurora(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = aspectUV(in.position, u);
    float t = u.time * 0.06;

    float3 col = mix(float3(0.01, 0.02, 0.05), float3(0.02, 0.06, 0.14), uv.y);

    // Звёзды на фоне.
    float2 starGrid = uv * 220.0;
    float star = hash21(floor(starGrid));
    float twinkle = 0.5 + 0.5 * sin(u.time * 2.0 + star * 50.0);
    col += step(0.995, star) * twinkle * 0.6 * smoothstep(0.3, 1.0, uv.y);

    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float n = fbm(float2(uv.x * 1.6 + fi * 3.1, t + fi * 1.7));
        float center = 0.55 + fi * 0.08 + 0.25 * (n - 0.5);
        float d = uv.y - center;
        float curtain = exp(-d * d * (d > 0.0 ? 25.0 : 120.0));
        float rays = 0.55 + 0.45 * fbm(float2(uv.x * 9.0 + fi * 5.0, t * 4.0));
        float3 tint = mix(float3(0.10, 0.95, 0.55), float3(0.55, 0.30, 1.00), fi / 2.0);
        col += tint * curtain * rays * 0.55;
    }

    // Лёгкое свечение у горизонта.
    col += float3(0.05, 0.12, 0.10) * exp(-uv.y * 6.0);
    return float4(col, 1.0);
}

// MARK: - Плазма

fragment float4 fragment_plasma(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time * 0.25;

    float v = sin(p.x * 3.0 + t);
    v += sin((p.y * 3.0 + t) * 0.8);
    v += sin((p.x + p.y) * 2.5 + t * 1.3);
    v += sin(length(p * 4.0 + float2(sin(t * 0.7), cos(t * 0.5)) * 2.0) * 3.0 - t);

    float3 col = palette(v * 0.18 + t * 0.05,
                         float3(0.5, 0.5, 0.5),
                         float3(0.5, 0.5, 0.5),
                         float3(1.0, 1.0, 1.0),
                         float3(0.00, 0.33, 0.67));
    col = pow(col, float3(1.3)) * 0.9;
    return float4(col, 1.0);
}

// MARK: - Волны

fragment float4 fragment_waves(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.position.xy / u.resolution;
    uv.y = 1.0 - uv.y;
    float aspect = u.resolution.x / u.resolution.y;
    float x = uv.x * aspect;
    float t = u.time * 0.35;

    float3 col = mix(float3(1.00, 0.72, 0.55), float3(0.30, 0.28, 0.65), uv.y);

    // Слои рисуются от дальнего (верхнего) к ближнему.
    const int layers = 5;
    for (int i = layers - 1; i >= 0; i--) {
        float fi = float(i);
        float y0 = 0.15 + fi * 0.12
                 + 0.045 * sin(x * (1.2 + fi * 0.35) + t * (0.6 + fi * 0.12) + fi * 1.3)
                 + 0.020 * sin(x * (3.1 + fi) - t * 0.9 + fi * 2.1);
        float3 layerColor = mix(float3(0.10, 0.07, 0.30), float3(0.95, 0.45, 0.50), fi / float(layers - 1));
        // Тень над гребнем следующего слоя.
        float above = uv.y - y0;
        col *= 1.0 - 0.18 * exp(-max(above, 0.0) * 35.0) * step(0.0, above);
        float mask = 1.0 - smoothstep(-0.0025, 0.0025, above);
        col = mix(col, layerColor * (0.85 + 0.15 * uv.y), mask);
    }
    return float4(col, 1.0);
}

// MARK: - Звёзды

static float3 starLayer(float2 uv) {
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
            m *= (1.0 - smoothstep(0.2, 0.9, d));
            float3 tint = sin(float3(0.2, 0.3, 0.9) * fract(n * 2345.2) * 123.2) * 0.5 + 0.5;
            tint = tint * float3(1.0, 0.5, 1.0 + size) + float3(0.4, 0.4, 0.6);
            col += m * tint;
        }
    }
    return col;
}

fragment float4 fragment_starfield(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time * 0.03;

    float3 col = float3(0.005, 0.005, 0.02) + float3(0.04, 0.02, 0.08) * (1.0 - length(p));

    const int layers = 5;
    for (int i = 0; i < layers; i++) {
        float depth = fract(float(i) / float(layers) + t);
        float scale = mix(18.0, 0.6, depth);
        float fade = depth * (1.0 - smoothstep(0.85, 1.0, depth));
        col += starLayer(p * scale + float(i) * 453.2) * fade;
    }
    col = 1.0 - exp(-col * 1.4); // мягкий тонмаппинг
    return float4(col, 1.0);
}
