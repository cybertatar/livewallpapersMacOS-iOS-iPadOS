#include <metal_stdlib>
using namespace metal;

// Сцены лежат в Shaders/*.h и написаны на общем подмножестве Metal/GLSL (см. Common.h).
#include "Shaders/Common.h"
#include "Shaders/Abstract.h"
#include "Shaders/Frieren.h"
#include "Shaders/Zelda.h"
#include "Shaders/Cyberpunk.h"
#include "Shaders/Anime.h"

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

// Обёртка сцены: переводит координаты в «начало снизу слева» и добавляет дизеринг против полос на градиентах.
#define SCENE(name) \
fragment float4 fragment_##name(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) { \
    float2 fc = float2(in.position.x, u.resolution.y - in.position.y); \
    float3 c = scene_##name(fc, u.resolution, u.time); \
    c += (hash21(fc + fract(u.time) * 100.0) - 0.5) / 255.0; \
    return float4(c, 1.0); \
}

SCENE(aurora)
SCENE(plasma)
SCENE(waves)
SCENE(starfield)

SCENE(frierenFlowers)
SCENE(frierenSpell)
SCENE(frierenMeteor)
SCENE(frierenAutumn)

SCENE(hyruleFields)
SCENE(skyIslands)
SCENE(ancientTech)
SCENE(lostWoods)

SCENE(neonCity)
SCENE(synthwave)
SCENE(digitalRain)
SCENE(neonTunnel)

SCENE(sakura)
SCENE(summerSky)
SCENE(fireflies)
SCENE(lanterns)
SCENE(oceanSunset)
