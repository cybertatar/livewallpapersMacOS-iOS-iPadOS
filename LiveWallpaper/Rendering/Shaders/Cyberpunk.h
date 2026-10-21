// Подборка «Киберпанк»: неон, дождь, ночной город.

/// Слой небоскрёбов: возвращает маску здания и яркость окон.
float2 skyline(float2 p, float density, float baseY, float heightScale, float seed, float t) {
    float x = p.x * density + seed;
    float cell = floor(x);
    float local = fract(x);
    float h = hash11(cell * 1.31 + seed);
    float height = baseY + heightScale * (0.25 + 0.75 * h * h);
    float gap = 0.06 + 0.1 * hash11(cell * 7.7);
    float inside = step(gap, local) * step(local, 1.0 - gap) * step(p.y, height);
    // Антенна на части крыш.
    float antenna = step(0.75, hash11(cell * 3.3)) * step(abs(local - 0.5), 0.015) * step(height, p.y) * step(p.y, height + 0.05);
    // Окна: сетка, часть горит и иногда мигает.
    float2 w = float2((local - gap) / (1.0 - 2.0 * gap) * 6.0, (p.y - baseY) * density * 9.0);
    float2 wc = floor(w);
    float lit = step(0.6, hash21(wc + cell * 17.0 + floor(t * 0.05 + hash11(cell) * 10.0) * 3.0));
    float win = lit * step(0.25, fract(w.x)) * step(fract(w.x), 0.75) * step(0.3, fract(w.y)) * step(fract(w.y), 0.75);
    return float2(max(inside, antenna), win * inside);
}

// Неоновый город под дождём.
float3 scene_neonCity(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(0.45, 0.10, 0.35), float3(0.03, 0.02, 0.10), pow(sy, 0.7));
    // Облака, подсвеченные городом.
    float clouds = fbm(float2(p.x * 2.0 + t * 0.01, p.y * 4.0));
    col += float3(0.35, 0.08, 0.30) * smoothstep(0.4, 0.9, clouds) * (1.0 - sy) * 0.6;

    float3 magenta = float3(1.0, 0.15, 0.65);
    float3 cyan = float3(0.1, 0.9, 1.0);

    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 b = skyline(p, 6.0 - fi * 1.5, -0.25 - fi * 0.08, 0.45 + fi * 0.15, fi * 19.0, t);
        float3 wall = mix(float3(0.10, 0.05, 0.16), float3(0.015, 0.01, 0.03), fi / 2.0);
        float3 windowCol = mix(float3(1.0, 0.75, 0.45), mix(cyan, magenta, step(0.5, hash11(fi + 3.0))), 0.35);
        col = mix(col, wall, b.x);
        col += windowCol * b.y * (0.5 + 0.25 * fi);
        // Дымка между слоями.
        col = mix(col, float3(0.30, 0.08, 0.28), 0.10 * (2.0 - fi) * (1.0 - sy));
    }

    // Неоновые вывески: вертикальные полосы на ближних зданиях.
    float x = p.x * 3.0 + 38.0;
    float cell = floor(x);
    float h = hash11(cell * 5.1);
    float signX = abs(fract(x) - (0.2 + 0.6 * h));
    float signY = -0.05 - 0.25 * hash11(cell * 2.3);
    float sign = step(0.5, h) * step(signX, 0.012) * step(abs(p.y - signY), 0.09);
    float flicker = step(0.08, fract(sin(floor(t * 8.0) + cell) * 43.7)) ;
    float3 neon = mix(magenta, cyan, step(0.75, h));
    col += neon * sign * flicker * 1.2;
    col += neon * glow(max(signX - 0.012, 0.0) + max(abs(p.y - signY) - 0.09, 0.0), 0.01, 0.4) * step(0.5, h) * flicker;

    // Мокрая улица с отражениями.
    float street = -0.42;
    if (p.y < street) {
        float depth = street - p.y;
        float ripple = 0.004 * sin(p.y * 300.0 + t * 3.0) * fbm3(float2(p.x * 10.0, t));
        float2 rp = float2(p.x + ripple, street + depth * 1.5);
        float2 b = skyline(rp, 3.0, -0.41, 0.75, 38.0, t);
        float3 refl = mix(magenta, cyan, 0.5 + 0.5 * sin(p.x * 6.0)) * 0.15;
        col = mix(float3(0.02, 0.01, 0.04), refl, 0.6) + float3(1.0, 0.7, 0.5) * b.y * 0.25;
        col += neon * 0.08;
    }

    // Дождь.
    for (int i = 0; i < 2; i++) {
        float fi = float(i);
        float2 rq = float2(p.x * (80.0 + fi * 50.0) + p.y * 8.0, p.y * (4.0 + fi * 2.0) + t * (6.0 + fi * 3.0));
        float rc = hash21(floor(rq) + fi * 11.0);
        float drop = step(0.92, rc) * (1.0 - smoothstep(0.0, 0.08, abs(fract(rq.x) - 0.5))) * fract(rq.y);
        col += float3(0.6, 0.7, 0.9) * drop * (0.18 + 0.1 * fi);
    }
    return col;
}

// Синтвейв: ретро-солнце, горы и бегущая сетка.
float3 scene_synthwave(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float horizon = -0.08;
    float3 col;
    if (p.y > horizon) {
        float sy = sat((p.y - horizon) / 0.6);
        col = mix(float3(0.95, 0.35, 0.55), float3(0.08, 0.02, 0.20), pow(sy, 0.6));
        col += float3(stars(p, 90.0, t)) * smoothstep(0.3, 0.9, sy) * 0.8;

        // Солнце с вырезанными полосами.
        float2 sp = p - float2(0.0, horizon + 0.17);
        float sd = length(sp);
        float3 sunCol = mix(float3(1.0, 0.85, 0.30), float3(1.0, 0.20, 0.55), sat(-sp.y / 0.2 + 0.5));
        float stripes = step(0.0, sp.y) + step(0.35 + 0.5 * sat(-sp.y / 0.18), fract(sp.y * 40.0 - t * 0.3));
        float sun = (1.0 - smoothstep(0.19, 0.192, sd)) * sat(stripes);
        col += float3(1.0, 0.3, 0.5) * glow(sd - 0.19, 0.03, 0.4);
        col = mix(col, sunCol, sun);

        // Горы-силуэты с неоновым контуром.
        float m = horizon + 0.12 * pow(abs(sin(p.x * 3.0 + 1.0)), 2.0) * (0.5 + 0.5 * fbm3(float2(p.x * 2.0, 1.0)))
                + 0.04 * fbm3(float2(p.x * 10.0, 3.0));
        float mountain = 1.0 - smoothstep(m - 0.0015, m + 0.0015, p.y);
        col = mix(col, float3(0.05, 0.02, 0.12), mountain);
        col += float3(0.9, 0.3, 1.0) * glow(p.y - m, 0.0015, 0.5) * step(0.0, p.y - horizon);
    } else {
        // Сетка в перспективе.
        float depth = 0.08 / (horizon - p.y + 0.0001);
        float2 g = float2(p.x * depth * 6.0, depth + t * 0.8);
        float2 gd = 0.5 - abs(fract(g) - 0.5);         // расстояние до ближайшей линии
        // Размер пикселя в координатах сетки — для сглаживания и гашения мелких линий.
        float fwy = depth * depth / 0.08 / res.y;
        float fwx = (depth * 6.0 + abs(p.x) * 6.0 * depth * depth / 0.08) / res.y;
        float lx = sat(1.0 - gd.x / (fwx * 1.5 + 0.015)) * sat(1.0 - fwx * 3.0);
        float ly = sat(1.0 - gd.y / (fwy * 1.5 + 0.015)) * sat(1.0 - fwy * 3.0);
        col = float3(0.06, 0.01, 0.12) + float3(1.0, 0.2, 0.8) * sat(lx + ly);
        col += float3(1.0, 0.3, 0.6) * exp(-(horizon - p.y) * 18.0) * 0.6;
    }
    return col;
}

// Цифровой дождь: падающие столбцы символов в неоновых цветах.
float glyph(float2 uv, float seed) {
    // Символ 5×7 точек из хэша.
    float2 g = floor(uv * float2(5.0, 7.0));
    float on = step(0.45, hash21(g + seed * 13.0));
    float2 f = fract(uv * float2(5.0, 7.0)) - 0.5;
    return on * step(max(abs(f.x), abs(f.y)), 0.38);
}

float3 scene_digitalRain(float2 fc, float2 res, float t) {
    float2 p = fc / res.y;
    float3 col = float3(0.01, 0.0, 0.03);
    for (int li = 0; li < 2; li++) {
        float fl = float(li);
        float size = 0.028 + fl * 0.02;
        float2 q = p / float2(size * 0.7, size);
        float column = floor(q.x);
        float ch = hash11(column * 3.1 + fl * 7.0);
        float speed = 4.0 + 8.0 * ch;
        float y = q.y + t * speed;
        float row = floor(y);
        float2 cellUV = float2(fract(q.x), fract(y));
        float headPos = fract(t * speed / 40.0 + ch);
        float trail = fract(-row / 40.0 + headPos);
        float columnOn = step(0.35, hash11(column * 9.7 + fl));
        float bright = pow(trail, 9.0) * columnOn;
        float seed = row + column * 31.0 + floor(t * (2.0 + 6.0 * hash11(row + column)));
        float g = glyph(cellUV * float2(1.0, 1.0) * 0.9 + 0.05, seed);
        float3 tint = mix(float3(0.1, 0.9, 1.0), float3(1.0, 0.2, 0.7), step(0.7, ch));
        float head = step(0.985, trail) * columnOn;
        col += g * (tint * bright + float3(0.9, 1.0, 1.0) * head) * (0.5 + 0.5 * fl);
    }
    // Сканлайны и виньетка.
    col *= 0.9 + 0.1 * sin(fc.y * 1.5);
    col *= 1.0 - 0.35 * length(centered(fc, res));
    return col;
}

// Неоновый тоннель: полёт сквозь светящиеся кольца.
float3 scene_neonTunnel(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    p += 0.06 * float2(sin(t * 0.3), cos(t * 0.23));
    float r = length(p);
    float a = atan2(p.y, p.x) + 0.15 * sin(t * 0.2);
    float z = 0.3 / max(r, 0.001) + t * 0.5;
    float u = a / TAU * 16.0;
    float ringD = abs(fract(z * 2.0) - 0.5) / 2.0;
    float panelD = abs(fract(u) - 0.5) / 16.0 * TAU / 0.3 * r * 0.0 + abs(fract(u) - 0.5) * 0.12;
    float ringLine = 0.003 / (ringD * r * 4.0 + 0.003);
    float panelLine = 0.002 / (panelD * r * 2.0 + 0.002);
    float3 c1 = float3(1.0, 0.15, 0.65);
    float3 c2 = float3(0.15, 0.85, 1.0);
    float3 tint = mix(c1, c2, 0.5 + 0.5 * sin(floor(z * 2.0) * 0.7));
    float fog = smoothstep(0.02, 0.3, r);
    float3 col = (tint * ringLine * 0.8 + mix(c2, c1, 0.5) * panelLine * 0.35) * fog;
    // Бегущие огни на кольцах.
    float runner = pow(0.5 + 0.5 * sin(a * 3.0 - t * 2.0 + floor(z * 2.0)), 20.0);
    col += float3(1.0) * ringLine * runner * 0.6 * fog;
    col += float3(0.5, 0.3, 1.0) * glow(r, 0.04, 0.35);
    return 1.0 - exp(-col * 1.4);
}
