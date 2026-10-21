// «Живая картинка»: изображение пользователя с аккуратными эффектами.
//
// Доступ к текстурам — через макросы, которые по-разному определены в Metal и GLSL:
// TEX_PARAMS / TEX_ARGS — дописываются к параметрам функции, SAMPLE_BG / SAMPLE_CUT(uv, lod) — выборка.
// Текстуры: bg — исходная картинка или кадр живой сцены-фона, cut — персонаж с альфой (premultiplied).
// UV текстур — от левого верхнего угла.
//
// Принципы: картинка не искажается и не двигается относительно персонажа (никаких двойных контуров),
// движение очень медленное и плавное, эффекты по умолчанию выключены.

#define IMG_KEN_BURNS 1.0
#define IMG_RAYS 4.0
#define IMG_SEPARATE 8.0      // персонаж отделён: частицы проходят между ним и фоном
#define IMG_BG_SHADER 16.0
#define IMG_AURA 32.0
#define IMG_FIT_WHOLE 64.0
#define IMG_FIT_FILL 128.0

float flagBit(float flags, float bit) { return wrap(floor(flags / bit + 0.001), 2.0); }

/// Мягкая круглая частица (боке) с центром в ячейке.
float softDot(float2 local, float2 center, float radius) {
    return 1.0 - smoothstep(radius * 0.35, radius, length(local - center));
}

// Частицы: 0 нет, 1 лепестки, 2 листья, 3 снег, 4 светлячки, 5 искры, 6 дождь, 7 звёзды.
// amount — плотность (0…1). layer 0 — дальний слой (мельче, медленнее), 1 — ближний.
// Возвращает premultiplied цвет и альфу.
float4 particleLayer(float2 p, float t, float type, float layer, float amount) {
    float L = layer;
    if (type < 0.5 || amount <= 0.0) { return float4(0.0); }
    float dens = amount * mix(1.0, 0.45, L);
    if (type < 1.5) {
        float m = fallingParticles(p + L * 7.3, t, mix(0.065, 0.11, L), mix(0.012, 0.022, L), 0.25, 0.17, 0.12 * dens);
        float a = m * mix(0.55, 0.8, L);
        return float4(float3(1.0, 0.80, 0.87) * a, a);
    }
    if (type < 2.5) {
        float m = fallingParticles(p + L * 4.1, t, mix(0.07, 0.12, L), mix(0.015, 0.025, L), 0.3, 0.18, 0.08 * dens);
        float a = m * mix(0.6, 0.85, L);
        return float4(float3(0.92, 0.50, 0.22) * a, a);
    }
    if (type < 3.5) {
        float2 q = (p + L * 3.1) / mix(0.022, 0.045, L);
        q.y += t * mix(0.5, 0.8, L);
        q.x += sin(q.y * 0.35 + t * 0.4) * 0.3;
        float2 cell = floor(q);
        float h = hash21(cell);
        float m = step(h, 0.35 * dens) * softDot(fract(q) - 0.5, (hash22(cell) - 0.5) * 0.5, mix(0.12, 0.2, L));
        float a = m * mix(0.45, 0.75, L);
        return float4(float3(a), a);
    }
    if (type < 4.5) {
        float m = floatingMotes(p + L * 5.0, t * 0.35, mix(0.09, 0.14, L), 0.01) * step(L, 0.5 + dens);
        m *= amount;
        return float4(float3(1.0, 0.92, 0.55) * m, sat(m) * 0.4);
    }
    if (type < 5.5) {
        float m = floatingMotes(p * 1.2 + L * 9.0, t * 0.4, mix(0.07, 0.12, L), 0.03) * amount;
        return float4(float3(0.70, 0.88, 1.0) * m, sat(m) * 0.4);
    }
    if (type < 6.5) {
        // Короткие наклонные капли: ячейки вытянуты по вертикали, в каждой — один короткий штрих.
        float2 rp = float2(p.x + p.y * 0.12, p.y);
        float2 q = rp / float2(mix(0.012, 0.02, L), mix(0.09, 0.14, L));
        q.y += t * mix(9.0, 12.0, L);
        float2 cell = floor(q);
        float h = hash21(cell + L * 11.0);
        float2 f = fract(q);
        float x0 = 0.2 + 0.6 * hash11(h * 13.0);
        float y0 = 0.15 + 0.5 * hash11(h * 7.0);
        float streak = (1.0 - smoothstep(0.0, 0.12, abs(f.x - x0)))
                     * smoothstep(y0, y0 + 0.05, f.y) * (1.0 - smoothstep(y0 + 0.2, y0 + 0.3, f.y));
        float a = step(h, 0.25 * dens) * streak * mix(0.10, 0.16, L);
        return float4(float3(0.85, 0.9, 1.0) * a, a);
    }
    if (L > 0.5) { return float4(0.0); }
    float s = (stars(p, 80.0, t) * 0.7 + stars(p + 5.0, 150.0, t * 1.3) * 0.4) * amount;
    s *= smoothstep(-0.1, 0.3, p.y);
    return float4(float3(s), sat(s) * 0.5);
}

/// UV картинки, вписанной в прямоугольник экрана (fit) или заполняющей его (cover).
/// Возвращает uv; inside — 1, если пиксель попал в саму картинку.
float2 placeImage(float2 fc, float2 res, float2 img, float cover, float focusX) {
    float s = cover > 0.5 ? max(res.x / img.x, res.y / img.y) : min(res.x / img.x, res.y / img.y);
    float2 shown = img * s;
    float2 offset = (res - shown) * 0.5;
    if (cover > 0.5) {
        // Сдвигаем кадр к персонажу, но не дальше края картинки.
        float excess = shown.x - res.x;
        offset.x = -clamp(focusX * shown.x - res.x * 0.5, 0.0, excess);
    }
    float2 local = (fc - offset) / shown;
    return float2(local.x, 1.0 - local.y);
}

float3 imageScene(float2 fc, float2 res, float t, float2 img, float flags, float particles,
                  float charScale, float3 glowCol, float focusX, float amount TEX_PARAMS) {
    float kenBurns = flagBit(flags, IMG_KEN_BURNS);
    float rays = flagBit(flags, IMG_RAYS);
    float separate = flagBit(flags, IMG_SEPARATE);
    float bgShader = flagBit(flags, IMG_BG_SHADER);
    float aura = flagBit(flags, IMG_AURA);

    // Очень медленный «вдох» камеры: приближение на 3% за минуту и обратно.
    float zoom = 1.0 + kenBurns * 0.03 * (0.5 - 0.5 * cos(t * TAU / 60.0));
    float2 zfc = (fc - 0.5 * res) / zoom + 0.5 * res;
    float2 p = centered(fc, res);

    float3 col;
    float2 charUV;
    float charIn;
    if (bgShader > 0.5) {
        // Фон — живая сцена, персонаж стоит внизу по центру.
        col = SAMPLE_BG(float2(fc.x / res.x, 1.0 - fc.y / res.y), 0.0).rgb;
        float hd = res.y * charScale;
        float wd = hd * img.x / img.y;
        float2 px = zfc - float2(res.x * 0.5 - focusX * wd, 0.0);
        charUV = float2(px.x / wd, 1.0 - px.y / hd);
        charIn = 1.0;
    } else {
        // Авто: если пропорции близки к экрану — на весь экран, иначе картинка целиком.
        float ratio = (img.x / img.y) / (res.x / res.y);
        float autoCover = step(0.7, ratio) * step(ratio, 1.45);
        float cover = flagBit(flags, IMG_FIT_FILL) + (1.0 - flagBit(flags, IMG_FIT_WHOLE)) * (1.0 - flagBit(flags, IMG_FIT_FILL)) * autoCover;
        float2 uv = placeImage(zfc, res, img, cover, focusX);
        float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);

        // Поля вокруг картинки: сама картинка, сильно размытая и притемнённая (как в iOS).
        float2 fillUV = placeImage(zfc, res, img, 1.0, 0.5);
        fillUV = (fillUV - 0.5) / 1.1 + 0.5;
        // Гладкое размытие: несколько выборок с грубого мип-уровня вокруг точки.
        float3 fill = float3(0.0);
        for (int i = 0; i < 8; i++) {
            float a = float(i) / 8.0 * TAU;
            fill += SAMPLE_BG(fillUV + float2(cos(a), sin(a)) * 0.05, 6.0).rgb;
        }
        fill = (fill / 8.0) * 0.6 + SAMPLE_BG(fillUV, 7.5).rgb * 0.4;
        float lum = dot(fill, float3(0.299, 0.587, 0.114));
        fill = mix(float3(lum), fill, 0.8) * 0.72;

        col = mix(fill, SAMPLE_BG(uv, 0.0).rgb, inside);
        charUV = uv;
        charIn = inside;
    }

    float hasChar = max(separate, bgShader);
    float4 back = particleLayer(p, t, particles, 0.0, amount);
    float4 front = particleLayer(p, t, particles, 1.0, amount);

    if (hasChar > 0.5) {
        float inRect = step(0.0, charUV.x) * step(charUV.x, 1.0) * step(0.0, charUV.y) * step(charUV.y, 1.0) * charIn;
        float4 ch = SAMPLE_CUT(charUV, 0.0) * inRect;
        // Дальние частицы — за персонажем.
        col = col * (1.0 - back.a) + back.rgb;
        if (aura > 0.5) {
            // Тонкий мягкий контровой свет по контуру.
            float soft = SAMPLE_CUT(charUV, 2.5).a * inRect;
            float rim = sat(soft - ch.a) * 2.0;
            col += glowCol * rim * 0.35 * (0.85 + 0.15 * sin(t * 0.8));
        }
        col = col * (1.0 - ch.a) + ch.rgb;
    } else {
        col = col * (1.0 - back.a) + back.rgb;
    }

    if (rays > 0.5) {
        float2 src = float2(-0.5 * res.x / res.y, 0.55);
        float2 dir = p - src;
        float ang = atan2(dir.y, dir.x);
        float beam = smoothstep(0.4, 0.8, fbm3(float2(ang * 4.0, t * 0.015)));
        float falloff = exp(-length(dir) * 1.6) * smoothstep(0.0, 0.25, length(dir));
        col += float3(1.0, 0.94, 0.85) * beam * falloff * 0.08;
    }

    col = col * (1.0 - front.a) + front.rgb;
    return col;
}
