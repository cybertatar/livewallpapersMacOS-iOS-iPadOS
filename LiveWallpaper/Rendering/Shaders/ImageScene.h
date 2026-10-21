// «Живая картинка»: изображение пользователя (и вырезанный с него персонаж) с эффектами.
//
// Доступ к текстурам — через макросы, которые по-разному определены в Metal и GLSL:
// TEX_PARAMS / TEX_ARGS — дописываются к параметрам функции, SAMPLE_BG / SAMPLE_CUT(uv, lod) — выборка.
// Текстуры: bg — исходная картинка или кадр живой сцены-фона, cut — персонаж с альфой (premultiplied).
// UV текстур — от левого верхнего угла.

// Флаги (битовая маска во float).
#define IMG_KEN_BURNS 1.0
#define IMG_FLOAT 2.0
#define IMG_RAYS 4.0
#define IMG_HAS_CUTOUT 8.0
#define IMG_BG_SHADER 16.0
#define IMG_AURA 32.0

float flagBit(float flags, float bit) { return wrap(floor(flags / bit + 0.001), 2.0); }

// Частицы: 0 нет, 1 лепестки, 2 листья, 3 снег, 4 светлячки, 5 магические искры, 6 дождь, 7 звёзды.
// Возвращает premultiplied цвет и альфу; layer 0 — позади персонажа, 1 — впереди.
float4 particleLayer(float2 p, float t, float type, float layer) {
    float L = layer;
    if (type < 0.5) { return float4(0.0); }
    if (type < 1.5) {
        float m = fallingParticles(p + L * 7.3, t, mix(0.05, 0.11, L), mix(0.03, 0.06, L), 0.3, 0.2, mix(0.22, 0.10, L));
        float a = m * mix(0.65, 0.95, L);
        return float4(float3(1.0, 0.74, 0.84) * a, a);
    }
    if (type < 2.5) {
        float m = fallingParticles(p + L * 4.1, t, mix(0.06, 0.12, L), mix(0.03, 0.06, L), 0.35, 0.22, mix(0.16, 0.08, L));
        float3 c = mix(float3(0.95, 0.45, 0.15), float3(0.85, 0.22, 0.10), hash11(floor(t * 0.1) + L));
        float a = m * mix(0.7, 0.95, L);
        return float4(c * a, a);
    }
    if (type < 3.5) {
        float m = fallingParticles(p + L * 3.1, t * 0.6, mix(0.025, 0.07, L), mix(0.015, 0.035, L), 0.5, mix(0.14, 0.2, L), mix(0.55, 0.25, L));
        float a = m * mix(0.55, 0.9, L);
        return float4(float3(a), a);
    }
    if (type < 4.5) {
        float m = floatingMotes(p + L * 5.0, t * 0.5, mix(0.07, 0.11, L), 0.015) * 1.8;
        float a = sat(m) * 0.6;
        return float4(float3(0.85, 1.0, 0.4) * m, a);
    }
    if (type < 5.5) {
        float m = floatingMotes(p * 1.3 + L * 9.0, t * 0.7, mix(0.05, 0.09, L), 0.05) * 1.6;
        float2 q = p * mix(14.0, 8.0, L) + float2(0.0, -t * 0.05);
        float2 cell = floor(q);
        float2 f = fract(q) - 0.5 - (hash22(cell) - 0.5) * 0.6;
        float tw = pow(0.5 + 0.5 * sin(t * 2.0 + hash21(cell) * 40.0), 6.0) * step(0.85, hash21(cell + 3.0));
        float twinkleCross = (0.004 / (abs(f.x) + 0.004)) * (0.004 / (abs(f.y) + 0.004)) * 60.0 * (1.0 - smoothstep(0.0, 0.4, length(f)));
        float3 c = float3(0.6, 0.85, 1.0) * m + float3(0.9, 0.95, 1.0) * twinkleCross * tw;
        return float4(c, sat(m + twinkleCross * tw) * 0.5);
    }
    if (type < 6.5) {
        float2 rq = float2(p.x * mix(70.0, 40.0, L) + p.y * 6.0, p.y * mix(4.0, 2.5, L) + t * mix(5.0, 8.0, L));
        float rc = hash21(floor(rq) + L * 11.0);
        float drop = step(0.9, rc) * (1.0 - smoothstep(0.0, 0.1, abs(fract(rq.x) - 0.5))) * fract(rq.y);
        float a = drop * mix(0.25, 0.4, L);
        return float4(float3(0.8, 0.85, 1.0) * a, a);
    }
    if (L > 0.5) { return float4(0.0); }
    float s = stars(p, 70.0, t) + stars(p + 5.0, 140.0, t * 1.3) * 0.6;
    return float4(float3(s), sat(s) * 0.6);
}

float3 imageScene(float2 fc, float2 res, float t, float2 img, float flags, float particles,
                  float charScale, float3 glowCol, float focusX TEX_PARAMS) {
    float kenBurns = flagBit(flags, IMG_KEN_BURNS);
    float floatOn = flagBit(flags, IMG_FLOAT);
    float rays = flagBit(flags, IMG_RAYS);
    float hasCut = flagBit(flags, IMG_HAS_CUTOUT);
    float bgShader = flagBit(flags, IMG_BG_SHADER);
    float aura = flagBit(flags, IMG_AURA);

    float2 su = fc / res;
    float2 p = centered(fc, res);
    float bob = floatOn * 0.006 * sin(t * 0.7);
    float breath = 1.0 + floatOn * 0.006 * sin(t * 0.9 + 1.0);

    float3 col;
    float2 charUV;
    if (bgShader > 0.5) {
        // Фон — живая сцена; персонаж стоит внизу по центру.
        col = SAMPLE_BG(float2(su.x, 1.0 - su.y), 0.0).rgb;
        float hd = res.y * charScale;
        float wd = hd * img.x / img.y;
        float2 anchor = float2(focusX * wd, 0.0);
        float2 px = fc - float2(res.x * 0.5 - focusX * wd, bob * res.y);
        px = anchor + (px - anchor) / breath;
        charUV = float2(px.x / wd, 1.0 - px.y / hd);
    } else {
        // Фон — сама картинка «по заполнению», с упором на персонажа по горизонтали.
        float s = max(res.x / img.x, res.y / img.y);
        float2 vis = res / (img * s);
        float2 off = float2(clamp(focusX - vis.x * 0.5, 0.0, 1.0 - vis.x), (1.0 - vis.y) * 0.4);
        float2 uv = off + float2(su.x, 1.0 - su.y) * vis;
        float2 focus = float2(focusX, 0.45);
        float z = 1.0 + kenBurns * (0.05 + 0.03 * sin(t * 0.05));
        float2 pan = kenBurns * 0.01 * float2(sin(t * 0.031), cos(t * 0.023));
        float2 bgUV = focus + (uv - focus) / z + pan;
        col = SAMPLE_BG(bgUV, 0.0).rgb;
        if (hasCut > 0.5) {
            // Под персонажем — размытый фон: при сдвиге слоёв не будет двойного контура.
            float m = SAMPLE_CUT(bgUV, 3.0).a;
            col = mix(col, SAMPLE_BG(bgUV, 6.0).rgb, smoothstep(0.05, 0.5, m));
        }
        // Персонаж «ближе» к зрителю: двигается иначе, чем фон (параллакс).
        float zc = 1.0 + (z - 1.0) * 0.5;
        charUV = focus + (uv - focus) / (zc * breath) + pan * 0.4 + float2(0.0, bob);
    }

    float4 back = particleLayer(p, t, particles, 0.0);
    col = col * (1.0 - back.a) + back.rgb;

    if (rays > 0.5) {
        float2 src = float2(-0.6, 0.6);
        float2 dir = p - src;
        float ang = atan2(dir.y, dir.x);
        float beam = fbm3(float2(ang * 7.0, t * 0.04)) * exp(-length(dir) * 1.1);
        col += float3(1.0, 0.92, 0.75) * smoothstep(0.35, 0.8, beam) * 0.35;
    }

    if (hasCut > 0.5) {
        float inside = step(0.0, charUV.x) * step(charUV.x, 1.0) * step(0.0, charUV.y) * step(charUV.y, 1.0);
        float4 ch = SAMPLE_CUT(charUV, 0.0) * inside;
        if (aura > 0.5) {
            float soft = SAMPLE_CUT(charUV, 4.0).a * inside;
            float halo = max(soft - ch.a, 0.0);
            col += glowCol * halo * (1.2 + 0.4 * sin(t * 1.3));
        }
        col = col * (1.0 - ch.a) + ch.rgb;
    }

    float4 front = particleLayer(p, t, particles, 1.0);
    col = col * (1.0 - front.a) + front.rgb;

    col *= 1.0 - 0.22 * dot(p, p);
    return col;
}
