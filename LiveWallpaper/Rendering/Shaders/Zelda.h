// Подборка «Зельда»: открытые поля, небесные острова, древние технологии, лес.

/// Кучевые облака: плотность с мягким освещением сверху.
float3 cumulus(float3 col, float2 p, float t, float3 lit, float3 shade, float coverage) {
    float2 q = p * float2(1.6, 3.0) + float2(t * 0.012, 0.0);
    float d = fbm(q);
    float mask = smoothstep(coverage, coverage + 0.18, d);
    float light = sat((d - fbm(q + float2(0.0, -0.06))) * 6.0 + 0.6);
    return mix(col, mix(shade, lit, light), mask);
}

// Поля Хайрула: холмы с волнами ветра по траве, облака, гора и замок вдали.
float3 scene_hyruleFields(float2 fc, float2 res, float t) {
    float aspect = res.x / res.y;
    float2 p = centered(fc, res);
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(0.70, 0.85, 0.95), float3(0.22, 0.48, 0.85), pow(sy, 0.8));
    col = cumulus(col, p + float2(0.0, -0.1), t, float3(1.0, 1.0, 0.98), float3(0.70, 0.76, 0.88), 0.52);

    // Гора с дымкой.
    float mx = p.x - 0.28 * min(aspect, 1.8);
    float mountain = -0.02 + 0.22 * exp(-mx * mx * 9.0) + 0.04 * ridge(p.x, 2.0, 1.0);
    col = mix(col, float3(0.50, 0.58, 0.72), (1.0 - smoothstep(mountain - 0.002, mountain + 0.002, p.y)) * 0.85);
    float peakGlow = exp(-length(float2(mx, p.y - 0.2) * float2(8.0, 20.0)));
    col += float3(1.0, 0.45, 0.2) * peakGlow * 0.15;

    // Замок на дальнем холме.
    float cx = p.x + 0.18 * min(aspect, 1.8);
    float castle = 0.0;
    castle = max(castle, step(abs(cx), 0.035) * step(p.y, 0.035));
    castle = max(castle, step(abs(cx), 0.008) * step(p.y, 0.085 - abs(cx) * 2.0));
    castle = max(castle, step(abs(cx - 0.025), 0.006) * step(p.y, 0.065 - abs(cx - 0.025) * 3.0));
    castle = max(castle, step(abs(cx + 0.025), 0.006) * step(p.y, 0.06 - abs(cx + 0.025) * 3.0));
    castle = max(castle, step(abs(cx - 0.045), 0.004) * step(p.y, 0.05));
    castle *= step(0.0, p.y + 0.02);
    col = mix(col, float3(0.42, 0.48, 0.62), castle);

    // Слои холмов; по траве бегут светлые полосы ветра.
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float y0 = 0.0 - fi * 0.13 + 0.08 * (ridge(p.x, 0.8 + fi * 0.4, 20.0 + fi * 3.0) - 0.5)
                 + 0.03 * sin(p.x * (1.2 + fi * 0.5) + fi);
        float mask = 1.0 - smoothstep(y0 - 0.0015, y0 + 0.0015, p.y);
        float3 grass = mix(float3(0.55, 0.70, 0.45), float3(0.12, 0.32, 0.10), fi / 3.0);
        float depth = y0 - p.y;
        float wind = sin((p.x * 6.0 + depth * 25.0) - t * 1.3 + fbm3(p * 4.0 + fi) * 4.0);
        grass *= 0.9 + 0.12 * smoothstep(0.6, 1.0, wind);
        grass *= 0.85 + 0.15 * fbm3(float2(p.x * 40.0, p.y * 80.0));
        grass += float3(0.25, 0.25, 0.1) * exp(-depth * 40.0) * 0.4;
        col = mix(col, grass, mask);
    }
    // Белые цветы в ближней траве.
    float2 fq = p * float2(60.0, 90.0) + float2(sin(t + p.y * 20.0) * 0.3, 0.0);
    float flower = step(0.92, hash21(floor(fq))) * (1.0 - smoothstep(0.1, 0.25, length(fract(fq) - 0.5)));
    col = mix(col, float3(0.95, 0.95, 0.85), flower * step(p.y, -0.3));
    return col;
}

// Небесные острова над морем облаков на закате.
float island(float2 p, float2 c, float w, float h, float seed) {
    float dx = (p.x - c.x) / w;
    float top = c.y + 0.015 * noise(float2(p.x * 30.0 / w * 0.1, seed)) ;
    float body = max(1.0 - dx * dx, 0.0);
    float jag = 0.6 + 0.4 * noise(float2(p.x / w * 6.0, seed + 3.0)) + 0.15 * noise(float2(p.x / w * 25.0, seed));
    float bottom = c.y - h * pow(body, 1.4) * jag;
    return step(abs(dx), 1.0) * step(p.y, top) * step(bottom, p.y);
}

float3 scene_skyIslands(float2 fc, float2 res, float t) {
    float aspect = res.x / res.y;
    float2 p = centered(fc, res);
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(1.0, 0.66, 0.45), float3(0.22, 0.28, 0.60), pow(sy, 0.85));
    float2 sun = float2(-0.1 * min(aspect, 1.8), -0.12);
    col += float3(1.0, 0.7, 0.4) * glow(length(p - sun), 0.05, 0.6);
    col += float3(stars(p, 80.0, t)) * smoothstep(0.65, 1.0, sy) * 0.5;
    col = cumulus(col, p * 1.3 + float2(3.0, 0.4), t * 0.5, float3(1.0, 0.75, 0.65), float3(0.55, 0.45, 0.65), 0.6);

    float w = min(aspect, 1.8);
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float depth = fi / 4.0;
        float2 c = float2((hash11(fi * 7.3 + 2.0) - 0.5) * w * 0.85,
                          0.20 - depth * 0.18 + 0.12 * (hash11(fi * 3.1) - 0.5));
        c.y += 0.01 * sin(t * (0.3 + 0.1 * fi) + fi * 2.0);
        float size = mix(0.07, 0.22, depth * depth);
        float isl = island(p, c, size, size * 0.9, fi * 10.0);
        float3 rock = mix(float3(0.80, 0.55, 0.58), float3(0.16, 0.10, 0.16), depth);
        rock *= 0.8 + 0.25 * fbm3(p * 60.0 / (0.5 + depth));
        float3 grass = mix(float3(0.78, 0.68, 0.55), float3(0.22, 0.42, 0.18), depth);
        float topBand = 1.0 - smoothstep(0.0, 0.01 + 0.02 * depth, c.y - p.y);
        float3 islandCol = mix(rock, grass, topBand);
        // Подсветка закатом со стороны солнца.
        islandCol += float3(1.0, 0.55, 0.3) * 0.35 * (1.0 - depth * 0.6) * smoothstep(0.2, -0.6, (p.x - c.x) / size);
        col = mix(col, islandCol, isl);

        // Деревья на верхушке.
        float tx = (p.x - c.x) / size;
        float treeCell = floor(tx * 7.0);
        float tl = fract(tx * 7.0) - 0.5;
        float th = hash11(treeCell + fi * 9.0);
        float treeTop = c.y + size * (0.05 + 0.08 * th) * (1.0 - tl * tl * 4.0);
        float tree = step(abs(tx), 0.8) * step(0.45, th) * step(c.y, p.y) * step(p.y, treeTop);
        col = mix(col, grass * 0.6, tree);

        // Водопад с ближних островов.
        if (fi > 2.0) {
            float fx = p.x - (c.x + size * 0.45);
            float flow = fbm3(float2(fx * 200.0, p.y * 8.0 + t * 1.5));
            float fall = (1.0 - smoothstep(0.003, 0.008, abs(fx))) * step(p.y, c.y) * smoothstep(-0.5, c.y - 0.05, p.y);
            col = mix(col, float3(0.9, 0.92, 1.0) * (0.75 + 0.35 * flow), fall * 0.8);
        }
    }

    // Море облаков: несколько слоёв с объёмной подсветкой.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float level = -0.25 - fi * 0.08;
        float2 q = float2(p.x * (2.5 + fi) + t * (0.008 + fi * 0.006), fi * 4.0);
        float n = fbm(q);
        float surface = level + 0.07 * n + 0.02 * sin(p.x * 8.0 + fi);
        float mask = 1.0 - smoothstep(surface - 0.015, surface, p.y);
        float depthIn = sat((surface - p.y) * 8.0);
        float3 lit = mix(float3(1.0, 0.82, 0.72), float3(0.80, 0.62, 0.72), fi / 2.0);
        float3 shade = mix(float3(0.62, 0.50, 0.66), float3(0.35, 0.30, 0.52), fi / 2.0);
        float3 cloud = mix(lit, shade, depthIn * (0.7 + 0.3 * fbm3(q * 3.0)));
        col = mix(col, cloud, mask);
    }
    return col;
}

// Древняя технология: светящиеся схемы на тёмном камне, по линиям бегут импульсы.
float3 scene_ancientTech(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float stone = fbm(p * 5.0) * 0.6 + fbm(p * 25.0) * 0.4;
    float3 col = mix(float3(0.05, 0.06, 0.08), float3(0.15, 0.16, 0.18), stone);
    // Крупные каменные плиты.
    float2 slab = fract(p * float2(3.0, 4.0)) - 0.5;
    col *= 0.85 + 0.15 * smoothstep(0.5, 0.47, max(abs(slab.x), abs(slab.y)));
    col *= 1.0 - 0.5 * length(p);

    float3 cyan = float3(0.25, 0.85, 1.0);
    float3 orange = float3(1.0, 0.55, 0.15);

    // Схемы: горизонтальные дорожки со ступеньками, только в части плит.
    float scale = 14.0;
    float2 q = p * scale;
    float row = floor(q.y);
    float rh = hash11(row * 3.7);
    float lane = abs(fract(q.y) - 0.5);
    float segment = floor(q.x / 3.0 + rh * 10.0);
    float segH = hash11(segment * 1.3 + row);
    float onLane = step(0.55, segH) * step(0.4, rh);
    float hLine = lane + (1.0 - onLane) * 10.0;
    float vx = abs(fract(q.x / 3.0 + rh * 10.0) - 0.05) * 3.0;
    float vLine = vx + (1.0 - step(0.8, segH)) * 10.0 + step(0.5, fract(q.y)) * 10.0;
    float nodeD = length(float2(fract(q.x / 3.0 + rh * 10.0) * 3.0 - 0.15, fract(q.y) - 0.5));
    float d = min(min(hLine, vLine), abs(nodeD - 0.15) + (1.0 - onLane) * 10.0) / scale;

    float3 tint = mix(cyan, orange, step(0.9, hash11(segment * 7.0 + row)));
    float travel = fract(q.x / 12.0 - t * 0.15 + rh);
    float pulse = 0.3 + 0.7 * smoothstep(0.85, 1.0, travel);
    col += tint * glow(d, 0.0012, 0.9) * pulse;
    col += tint * glow(d, 0.008, 0.06) * pulse;

    // Центральная руна из колец и делений.
    float2 cp = (fc - 0.5 * res) / min(res.x, res.y);
    float r = length(cp);
    float a = atan2(cp.y, cp.x);
    float breathe = 0.6 + 0.4 * sin(t * 0.8);
    float ring = min(min(abs(r - 0.16), abs(r - 0.22)), abs(r - 0.10));
    float ticks = step(0.6, fract(a / TAU * 36.0 + t * 0.03)) * step(abs(r - 0.19), 0.018);
    float spokes = step(0.97, fract(a / TAU * 6.0 - t * 0.02)) * step(0.10, r) * step(r, 0.16);
    col = mix(col, col * 0.3, 1.0 - smoothstep(0.23, 0.26, r));
    col += cyan * (glow(ring, 0.0015, 1.0) + (ticks + spokes) * 0.7) * breathe;
    col += cyan * glow(r, 0.025, 0.2) * breathe;
    col += orange * glow(r - 0.04, 0.003, 0.5) * (0.5 + 0.5 * sin(t * 1.7));
    return 1.0 - exp(-col * 1.4);
}

// Затерянный лес: стволы в тумане, лучи света, парящие споры.
float3 scene_lostWoods(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float sy = sat(p.y + 0.5);
    float3 fog = mix(float3(0.16, 0.30, 0.24), float3(0.62, 0.80, 0.62), pow(sy, 1.2));
    float3 col = fog;

    // Стволы: от дальних (бледных) к ближним (тёмным), у земли расширяются корнями.
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float density = 3.4 - fi * 0.6;
        float x = p.x * density + fi * 13.7;
        float cell = floor(x);
        float local = fract(x) - 0.5;
        float h = hash11(cell + fi * 5.0);
        float ground = -0.36 - fi * 0.03;
        float flare = 1.0 + 1.2 * exp(-(p.y - ground) * 25.0);
        float width = (0.05 + 0.06 * h) * flare;
        float sway = 0.02 * sin(p.y * 2.5 + h * 10.0);
        float dx = abs(local - (h - 0.5) * 0.5 + sway);
        float trunk = step(0.35, h) * (1.0 - smoothstep(width - 0.008, width, dx)) * step(ground, p.y);
        float shade = mix(0.55, 0.12, (fi + 1.0) / 4.0);
        float3 bark = fog * shade * (0.85 + 0.2 * noise(float2(local * 25.0, p.y * 50.0)));
        bark += fog * 0.25 * (1.0 - smoothstep(0.0, width, dx + width * 0.6));
        col = mix(col, bark, trunk);
    }

    // Крона сверху.
    float canopy = fbm(float2(p.x * 4.0, p.y * 3.0) + float2(t * 0.01, 0.0));
    float canopyMask = smoothstep(0.40, 0.52, p.y + canopy * 0.18);
    col = mix(col, float3(0.05, 0.12, 0.08), canopyMask * 0.9);

    // Лучи света сквозь крону.
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float x0 = (hash11(fi * 3.7) - 0.5) * 1.8;
        float dx = p.x - x0 - (p.y - 0.4) * 0.3;
        float beam = exp(-dx * dx * 400.0) * (0.5 + 0.5 * sin(t * 0.25 + fi * 2.0));
        col += float3(0.9, 1.0, 0.75) * beam * 0.22 * smoothstep(-0.5, 0.4, p.y);
    }

    // Земля и папоротники.
    float groundY = -0.40 + 0.03 * fbm3(float2(p.x * 6.0, 1.0));
    float fern = groundY + 0.05 * pow(abs(sin(p.x * 40.0 + sin(t * 0.8 + p.x * 3.0) * 0.3)), 3.0) * fbm3(float2(p.x * 5.0, 2.0));
    col = mix(col, float3(0.05, 0.12, 0.07), 1.0 - smoothstep(fern - 0.002, fern + 0.002, p.y));

    // Споры.
    col += float3(0.75, 1.0, 0.55) * floatingMotes(p + 2.0, t * 0.4, 0.08, 0.03) * 0.9;
    col += float3(0.9, 1.0, 0.7) * floatingMotes(p * 1.7 + 8.0, t * 0.3, 0.09, 0.02) * 0.5;
    return col;
}
