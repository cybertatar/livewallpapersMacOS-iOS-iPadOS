// Подборка «Фрирен»: спокойное фэнтези, сумерки, магия, звёзды.

// Поле голубых цветов в сумерках, луна и искры маны.
float3 scene_frierenFlowers(float2 fc, float2 res, float t) {
    float aspect = res.x / res.y;
    float2 p = centered(fc, res);
    float horizon = -0.06;

    // Небо: сумеречный градиент, луна, звёзды.
    float sy = sat((p.y - horizon) / (0.5 - horizon));
    float3 col = mix(float3(0.72, 0.62, 0.80), float3(0.10, 0.13, 0.32), pow(sy, 0.6));
    col = mix(col, float3(0.04, 0.05, 0.15), smoothstep(0.55, 1.0, sy));
    col += float3(stars(p + 3.0, 70.0, t)) * smoothstep(0.25, 0.8, sy) * 0.9;

    float2 moonPos = float2(0.22 * min(aspect, 1.8), 0.27);
    float md = length(p - moonPos);
    col += float3(0.85, 0.88, 1.0) * glow(md - 0.045, 0.02, 0.35);
    float moon = 1.0 - smoothstep(0.044, 0.047, md);
    float craters = fbm3((p - moonPos) * 40.0);
    col = mix(col, float3(0.95, 0.96, 1.0) - 0.12 * craters, moon);

    // Лёгкие облака у горизонта.
    float cloud = fbm(float2(p.x * 2.5 + t * 0.01, p.y * 8.0));
    col = mix(col, float3(0.80, 0.70, 0.85), smoothstep(0.55, 0.8, cloud) * smoothstep(0.35, 0.0, p.y - horizon) * 0.5);

    // Дальние горы в дымке.
    float far = horizon + 0.03 + 0.10 * ridge(p.x, 1.3, 4.0);
    col = mix(col, float3(0.42, 0.42, 0.62), (1.0 - smoothstep(far - 0.002, far + 0.002, p.y)) * 0.85);
    float near = horizon + 0.02 * ridge(p.x, 3.0, 9.0);
    float field = 1.0 - smoothstep(near - 0.002, near + 0.002, p.y);

    // Поле: трава темнеет к зрителю.
    float fy = sat((near - p.y) / (near + 0.5));
    float3 grass = mix(float3(0.26, 0.32, 0.52), float3(0.04, 0.08, 0.14), pow(fy, 0.7));
    grass *= 0.85 + 0.15 * fbm3(float2(p.x * 30.0 + sin(t * 0.6 + p.y * 10.0) * 0.5, p.y * 60.0));
    col = mix(col, grass, field);

    // Цветы: несколько слоёв от дальних мелких к ближним крупным.
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float scale = 120.0 / pow(fi + 1.0, 1.5);
        float wind = sin(t * 0.9 + p.x * 3.0 + fi) * 0.25 * (fi + 1.0) / 5.0;
        float2 q = float2(p.x * scale + wind, p.y * scale * 1.6);
        float2 cell = floor(q);
        float2 local = fract(q) - 0.5;
        float h = hash21(cell + fi * 17.0);
        float2 center = (hash22(cell + fi * 31.0) - 0.5) * 0.5;
        float cy = (cell.y + 0.5 + center.y) / (scale * 1.6);
        float limit = near - 0.01 - fi * 0.055;
        if (h > 0.40 + fi * 0.09 && cy < limit) {
            float d = length((local - center) * float2(1.0, 0.8));
            float size = 0.18 + 0.12 * hash11(h * 5.1);
            float petal = 1.0 - smoothstep(size * 0.7, size, d);
            float3 flower = mix(float3(0.45, 0.70, 1.0), float3(0.92, 0.95, 1.0), step(0.9, hash11(h * 77.0)));
            flower = mix(flower, float3(1.0, 0.95, 0.75), 1.0 - smoothstep(0.0, size * 0.35, d));
            float depthFade = mix(0.55, 1.0, fi / 4.0);
            col = mix(col, flower * depthFade, petal * field);
            col += float3(0.3, 0.5, 1.0) * glow(d - size, 0.08, 0.06) * field;
        }
    }

    // Искры маны поднимаются над полем.
    float motes = floatingMotes(p * float2(1.0, 1.0) + 10.0, t * 0.5, 0.09, 0.05);
    col += float3(0.55, 0.85, 1.0) * motes * smoothstep(0.25, -0.1, p.y) * 0.9;
    return col;
}

// Магический круг: вращающиеся кольца с рунами, звезда и поднимающиеся искры.
float sdEquilateral(float2 p, float r) {
    float k = 1.7320508;
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0) { p = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0; }
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

float runeRing(float2 p, float radius, float width, float count, float spin, float seed) {
    float r = length(p);
    float a = atan2(p.y, p.x) + spin;
    float seg = floor(wrap(a, TAU) / TAU * count);
    float local = fract(wrap(a, TAU) / TAU * count);
    float h = hash11(seg + seed);
    float band = (1.0 - smoothstep(width * 0.5, width * 0.5 + 0.002, abs(r - radius)));
    // Каждая «руна» — набор штрихов разной длины.
    float rr = (r - radius) / width + 0.5;
    float stroke = step(0.25, local) * step(local, 0.75);
    float bars = step(abs(local - 0.5), 0.08 + 0.1 * h) * step(abs(rr - 0.5), 0.35);
    float dots = step(length(float2(local - 0.5, (rr - 0.5) * 0.5)), 0.12) * step(0.5, h);
    float hor = step(abs(rr - (0.2 + 0.6 * hash11(seg * 3.1 + seed))), 0.06) * stroke;
    return band * sat(bars + dots + hor);
}

float3 scene_frierenSpell(float2 fc, float2 res, float t) {
    float2 p = (fc - 0.5 * res) / min(res.x, res.y);
    float r = length(p);
    float3 col = mix(float3(0.03, 0.05, 0.12), float3(0.0, 0.01, 0.03), sat(r * 1.2));
    col += float3(0.05, 0.08, 0.18) * fbm(p * 3.0 + t * 0.03) * 0.8;

    float pulse = 0.85 + 0.15 * sin(t * 1.3);
    float3 magic = float3(0.55, 0.85, 1.0);
    float3 gold = float3(1.0, 0.82, 0.45);

    float lines = 0.0;
    lines += glow(r - 0.42, 0.0015, 1.0);
    lines += glow(r - 0.40, 0.0010, 0.7);
    lines += glow(r - 0.30, 0.0012, 0.9);
    lines += glow(r - 0.28, 0.0010, 0.6);
    lines += glow(r - 0.16, 0.0012, 0.8);
    col += magic * lines * pulse;

    col += magic * runeRing(p, 0.41, 0.012, 64.0, t * 0.05, 1.0) * 0.9;
    col += gold * runeRing(p, 0.29, 0.016, 40.0, -t * 0.08, 7.0) * 0.9;
    col += magic * runeRing(p, 0.17, 0.010, 24.0, t * 0.12, 13.0) * 0.8;

    // Гексаграмма из двух треугольников.
    float2 q = rot(p, t * 0.1);
    float tri1 = abs(sdEquilateral(q, 0.24));
    float tri2 = abs(sdEquilateral(float2(q.x, -q.y), 0.24));
    col += gold * (glow(tri1, 0.0012, 0.8) + glow(tri2, 0.0012, 0.8)) * pulse * step(r, 0.29);

    // Малые круги на вершинах.
    for (int i = 0; i < 6; i++) {
        float a = float(i) / 6.0 * TAU + t * 0.1 + PI / 6.0;
        float2 c = float2(cos(a), sin(a)) * 0.35;
        float d = length(p - c);
        col += magic * glow(d - 0.03, 0.001, 0.7) * pulse;
        col += magic * glow(d, 0.004, 0.25);
    }

    // Центральное свечение и искры.
    col += magic * glow(r, 0.02, 0.25) * pulse;
    col += float3(0.7, 0.9, 1.0) * floatingMotes(p + 5.0, t, 0.06, 0.06) * 0.8 * (1.0 - smoothstep(0.3, 0.6, r));
    return 1.0 - exp(-col * 1.3);
}

// Звездопад над холмами: Млечный путь, падающие звёзды, огни деревни.
float3 scene_frierenMeteor(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float horizon = -0.22;
    float sy = sat((p.y - horizon) / 0.72);
    float3 col = mix(float3(0.10, 0.22, 0.32), float3(0.02, 0.03, 0.10), pow(sy, 0.5));

    // Млечный путь — диагональная полоса.
    float2 mp = rot(p, 0.5);
    float band = exp(-mp.y * mp.y * 18.0);
    float dust = fbm(mp * float2(3.0, 9.0) + 2.0);
    col += float3(0.35, 0.40, 0.60) * band * smoothstep(0.3, 0.8, dust) * 0.7;
    col += float3(0.5, 0.45, 0.6) * exp(-mp.y * mp.y * 120.0) * dust * 0.25;
    col -= float3(0.025) * band * smoothstep(0.6, 0.8, fbm(mp * 12.0));
    col += float3(stars(p, 110.0, t)) * 0.9;
    col += float3(stars(p + 9.0, 45.0, t * 0.7)) * 0.7 * (0.5 + band);

    // Падающие звёзды.
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float period = 3.0 + 4.0 * hash11(fi * 3.3);
        float cycle = floor(t / period + hash11(fi));
        float phase = fract(t / period + hash11(fi));
        float h = hash11(cycle * 7.1 + fi * 13.0);
        float2 start = float2((h - 0.3) * 1.4, 0.15 + 0.35 * hash11(h * 31.0));
        float2 dir = normalize(float2(-0.8 - 0.4 * hash11(h * 3.0), -0.55));
        float travel = phase * 1.6;
        float2 head = start + dir * travel * 0.4;
        float2 rel = p - head;
        float along = dot(rel, -dir);
        float across = abs(dot(rel, float2(-dir.y, dir.x)));
        float len = 0.18;
        float tail = step(0.0, along) * (1.0 - smoothstep(0.0, len, along));
        float alive = smoothstep(0.0, 0.1, phase) * (1.0 - smoothstep(0.35, 0.5, phase));
        float streak = tail * (0.0012 / (across + 0.0012)) * alive;
        col += float3(0.85, 0.92, 1.0) * streak * 1.4;
        col += float3(1.0) * glow(length(rel), 0.002, 0.6) * alive * step(phase, 0.45);
    }

    // Холмы, деревья-силуэты и огни деревни.
    float hill = horizon + 0.05 * ridge(p.x, 2.0, 3.0) + 0.04 * sin(p.x * 2.0 + 1.0);
    float trees = hill + 0.025 * step(0.6, noise(float2(p.x * 40.0, 1.0))) * noise(float2(p.x * 120.0, 5.0));
    float ground = 1.0 - smoothstep(trees - 0.0015, trees + 0.0015, p.y);
    col = mix(col, float3(0.015, 0.02, 0.04), ground);
    float2 lp = float2(p.x * 60.0, (p.y - hill + 0.02) * 60.0);
    float2 lc = floor(lp);
    float lh = hash21(lc);
    float light = step(0.93, lh) * step(abs(lc.y), 1.0) * (1.0 - smoothstep(0.05, 0.25, length(fract(lp) - 0.5)));
    col += float3(1.0, 0.7, 0.35) * light * (0.7 + 0.3 * sin(t * 2.0 + lh * 40.0)) * ground;
    return col;
}

// Осенняя дорога на закате: тёплый свет, холмы, падающие листья.
float3 scene_frierenAutumn(float2 fc, float2 res, float t) {
    float aspect = res.x / res.y;
    float2 p = centered(fc, res);
    float2 sun = float2(-0.15 * min(aspect, 1.8), 0.02);
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(1.0, 0.70, 0.40), float3(0.45, 0.35, 0.60), pow(sy, 1.2));

    float sd = length(p - sun);
    col += float3(1.0, 0.65, 0.30) * glow(sd, 0.05, 0.6);
    col = mix(col, float3(1.0, 0.95, 0.80), 1.0 - smoothstep(0.05, 0.055, sd));

    // Лучи от солнца.
    float2 dir = p - sun;
    float ang = atan2(dir.y, dir.x);
    float rays = fbm3(float2(ang * 6.0, t * 0.05)) * exp(-length(dir) * 2.0);
    col += float3(1.0, 0.8, 0.5) * rays * 0.35;

    // Облака-полосы, подсвеченные снизу.
    float clouds = fbm(float2(p.x * 1.5 + t * 0.008, p.y * 7.0 + 3.0));
    col = mix(col, float3(1.0, 0.60, 0.50), smoothstep(0.55, 0.75, clouds) * smoothstep(-0.1, 0.3, p.y) * 0.5);

    // Слои холмов от дальнего к ближнему, с деревьями на гребнях.
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float y0 = 0.0 - fi * 0.12 + 0.16 * (ridge(p.x, 1.0 + fi * 0.5, fi * 5.0) - 0.5)
                 + 0.04 * sin(p.x * (1.5 + fi) + fi * 2.0);
        float treeCell = floor(p.x * (25.0 - fi * 4.0) + fi * 11.0);
        float treeLocal = fract(p.x * (25.0 - fi * 4.0) + fi * 11.0) - 0.5;
        float treeH = step(0.55, hash11(treeCell * 1.7 + fi)) * (0.02 + 0.02 * hash11(treeCell)) * (0.6 + fi * 0.25);
        float tree = treeH * sat(1.0 - abs(treeLocal) * 2.2) * (1.0 + 0.3 * sin(treeLocal * 40.0));
        float top = y0 + tree;
        float3 layer = mix(float3(0.88, 0.60, 0.55), float3(0.16, 0.06, 0.09), fi / 3.0);
        layer += float3(0.20, 0.10, 0.0) * fbm3(float2(p.x * 20.0, p.y * 20.0 + fi)) * (fi / 3.0);
        layer += float3(1.0, 0.6, 0.3) * 0.25 * exp(-(top - p.y) * 60.0) * (1.0 - fi / 4.0);
        float mask = 1.0 - smoothstep(top - 0.0015, top + 0.0015, p.y);
        col = mix(col, layer, mask);
    }

    // Листья.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float leaf = fallingParticles(p + fi * 3.7, t, 0.07 + fi * 0.05, 0.02 + fi * 0.015, 0.25, 0.2, 0.14);
        float3 lc = mix(float3(0.95, 0.45, 0.15), float3(0.85, 0.20, 0.10), hash11(fi + 2.0));
        col = mix(col, lc * (0.7 + 0.3 * fi / 2.0), leaf * (0.6 + 0.2 * fi));
    }
    return col;
}
