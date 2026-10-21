// Подборка «Аниме»: небо, сакура, летние ночи, фонарики, море.

// Сакура: ветка в цвету, мягкие блики и падающие лепестки.
float3 scene_sakura(float2 fc, float2 res, float t) {
    float aspect = res.x / res.y;
    float2 p = centered(fc, res);
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(1.0, 0.86, 0.90), float3(0.55, 0.72, 0.95), pow(sy, 0.9));

    // Боке на фоне.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 q = p * (3.0 + fi * 2.0) + float2(t * 0.02 * (fi + 1.0), fi * 7.0);
        float2 cell = floor(q);
        float2 local = fract(q) - 0.5;
        float h = hash21(cell + fi * 9.0);
        float2 c = (hash22(cell) - 0.5) * 0.5;
        float d = length(local - c);
        float r = 0.15 + 0.15 * h;
        float bokeh = step(0.6, h) * (1.0 - smoothstep(r - 0.04, r, d)) * (0.6 + 0.4 * smoothstep(r - 0.06, r - 0.01, d));
        col = mix(col, float3(1.0, 0.80, 0.88), bokeh * 0.25);
    }

    // Ветка из правого верхнего угла, вокруг неё — облака цветов.
    float2 bp = p - float2(0.5 * min(aspect, 1.8), 0.5);
    float branchY = -0.08 - 0.22 * (bp.x * bp.x) + 0.015 * sin(bp.x * 10.0);
    float thick = 0.006 + 0.02 * sat(1.0 + bp.x * 1.2);
    float branchD = abs(bp.y - branchY) - thick;
    float onBranch = step(bp.x, 0.05) * step(-1.1, bp.x);
    col = mix(col, float3(0.32, 0.20, 0.20), (1.0 - smoothstep(0.0, 0.003, branchD)) * onBranch);
    // Веточки.
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float x0 = -0.15 - fi * 0.22;
        float y0 = -0.08 - 0.22 * x0 * x0;
        float2 d = bp - float2(x0, y0);
        float dir = (hash11(fi * 3.0) > 0.5) ? 1.0 : -1.0;
        float along = dot(d, normalize(float2(-0.5, dir)));
        float across = abs(dot(d, normalize(float2(dir, 0.5))));
        float twig = (1.0 - smoothstep(0.003, 0.005, across)) * step(0.0, along) * step(along, 0.12);
        col = mix(col, float3(0.32, 0.20, 0.20), twig);
    }

    // Цветы: круглые соцветия в 3×3 соседних ячейках, сгущаются возле ветки.
    float zone = exp(-pow(bp.y - branchY, 2.0) * 90.0) * onBranch;
    float2 fq = p * 22.0;
    float2 fcell = floor(fq);
    float3 flowerCol = col;
    float flowerMask = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 cell = fcell + float2(float(x), float(y));
            float h = hash21(cell);
            float2 cc = (cell + 0.5 + (hash22(cell) - 0.5) * 0.8) / 22.0;
            float2 cbp = cc - float2(0.5 * min(aspect, 1.8), 0.5);
            float cy = -0.08 - 0.22 * (cbp.x * cbp.x);
            float cz = exp(-pow(cbp.y - cy, 2.0) * 90.0) * step(cbp.x, 0.05) * step(-1.1, cbp.x);
            if (h < cz * 1.3) {
                float2 d = (p - cc) * 22.0;
                float a = atan2(d.y, d.x) + h * 6.0 + 0.1 * sin(t * 0.8 + h * 20.0);
                float rr = 0.42 + 0.08 * cos(a * 5.0);           // пять лепестков
                float dist = length(d);
                float m = 1.0 - smoothstep(rr - 0.06, rr, dist);
                float3 c = mix(float3(1.0, 0.70, 0.80), float3(1.0, 0.93, 0.95), hash11(h * 7.0));
                c = mix(float3(0.92, 0.42, 0.58), c, smoothstep(0.0, 0.18, dist));
                c *= 0.9 + 0.1 * smoothstep(0.0, rr, dist);
                if (m > flowerMask) { flowerCol = c; flowerMask = m; }
            }
        }
    }
    col = mix(col, flowerCol, flowerMask);
    col += float3(1.0, 0.85, 0.9) * zone * 0.08;

    // Падающие лепестки в три слоя глубины.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 q = p + float2(t * 0.03 * (fi + 1.0), 0.0);
        float petal = fallingParticles(q + fi * 5.3, t, 0.06 + fi * 0.04, 0.03 + fi * 0.02, 0.3, 0.22, 0.22);
        float3 pc = mix(float3(1.0, 0.75, 0.85), float3(1.0, 0.62, 0.75), fi / 2.0);
        col = mix(col, pc, petal * (0.55 + 0.2 * fi));
    }
    return col;
}

// Летнее небо: глубокая синева, огромные кучевые облака, солнце и провода.
float3 scene_summerSky(float2 fc, float2 res, float t) {
    float aspect = res.x / res.y;
    float2 p = centered(fc, res);
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(0.55, 0.80, 0.98), float3(0.05, 0.28, 0.75), pow(sy, 0.7));
    float2 sun = float2(-0.3 * min(aspect, 1.8), 0.36);
    float sd = length(p - sun);
    col += float3(1.0, 0.95, 0.8) * glow(sd, 0.03, 0.8);
    col = mix(col, float3(1.0), 1.0 - smoothstep(0.03, 0.04, sd));

    // Кучевые облака: крупные формы у горизонта, верхний край освещён.
    float2 q = float2(p.x * 1.1 + t * 0.006, p.y * 1.7);
    float2 warp = float2(fbm3(q * 1.3 + 4.0), fbm3(q * 1.3 + 9.0)) * 0.35;
    float heightBias = 0.5 * (1.0 - sat((p.y + 0.25) / 0.6));
    float dens = fbm3((q + warp) * 1.6) * 0.75 + fbm((q + warp) * 5.0) * 0.25 + heightBias - 0.35;
    float2 qu = q + float2(0.0, 0.035);
    float densUp = fbm3((qu + warp) * 1.6) * 0.75 + fbm((qu + warp) * 5.0) * 0.25 + 0.5 * (1.0 - sat((p.y + 0.27) / 0.6)) - 0.35;
    float cloud = smoothstep(0.30, 0.38, dens);
    float lit = sat((dens - densUp) * 9.0 + 0.45);
    float3 cloudCol = mix(float3(0.60, 0.68, 0.84), float3(1.0, 0.99, 0.96), lit);
    cloudCol = mix(cloudCol, float3(0.80, 0.86, 0.96), smoothstep(0.38, 0.30, dens) * 0.5);
    cloudCol = mix(cloudCol, float3(1.0, 0.97, 0.90), exp(-sd * 3.0) * 0.4);
    col = mix(col, cloudCol, cloud);

    // Блики от солнца.
    col += float3(0.5, 0.7, 1.0) * glow(length(p + sun * 0.4), 0.01, 0.15);
    col += float3(1.0, 0.8, 0.6) * glow(length(p + sun * 0.1), 0.015, 0.1);

    // Провода.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float sag = 0.10 + 0.03 * fi;
        float y = -0.20 + fi * 0.035 + sag * pow(p.x / max(aspect, 1.0) * 0.9, 2.0) * 1.8 - sag * 0.2;
        float d = abs(p.y - y);
        col = mix(col, float3(0.10, 0.12, 0.18), 1.0 - smoothstep(0.0008, 0.0022, d));
    }
    // Силуэт крыш у нижнего края.
    float roof = -0.42 + 0.04 * step(0.5, hash11(floor(p.x * 6.0))) + 0.02 * step(0.7, hash11(floor(p.x * 20.0)));
    col = mix(col, float3(0.10, 0.14, 0.22), 1.0 - smoothstep(roof - 0.001, roof + 0.001, p.y));
    return col;
}

// Летняя ночь: высокая трава, звёзды и светлячки.
float3 scene_fireflies(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(0.06, 0.12, 0.20), float3(0.01, 0.02, 0.06), pow(sy, 0.6));
    col += float3(stars(p, 80.0, t)) * smoothstep(0.3, 0.8, sy) * 0.8;
    col += float3(stars(p + 4.0, 160.0, t)) * smoothstep(0.4, 0.9, sy) * 0.4;

    // Трава: три слоя травинок, качающихся на ветру.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float density = 45.0 - fi * 12.0;
        float x = p.x * density + fi * 50.0;
        float cell = floor(x);
        float h = hash11(cell + fi * 11.0);
        float height = -0.18 - fi * 0.08 + 0.18 * h;
        float bend = (sin(t * 0.8 + cell * 0.1 + fi) * 0.5 + 0.3) * 0.6;
        float rel = sat((p.y + 0.5) / (height + 0.5));
        float bladeX = fract(x) - 0.5 - bend * rel * rel;
        float width = 0.30 * (1.0 - rel * 0.9);
        float blade = (1.0 - smoothstep(width, width + 0.08, abs(bladeX))) * step(p.y, height);
        float3 g = mix(float3(0.05, 0.10, 0.10), float3(0.0, 0.02, 0.02), fi / 2.0);
        col = mix(col, g, blade);
    }

    // Светлячки.
    float ff = floatingMotes(p + 3.0, t * 0.6, 0.09, 0.01) + floatingMotes(p * 1.5 + 9.0, t * 0.5, 0.08, 0.015) * 0.7;
    float3 fireCol = float3(0.85, 1.0, 0.35);
    col += fireCol * ff * 2.2 * smoothstep(0.3, -0.25, p.y);
    col += fireCol * 0.03 * smoothstep(0.0, -0.5, p.y);
    return col;
}

// Небесные фонарики над озером.
float lantern(float2 p, float2 c, float size) {
    float2 d = (p - c) / size;
    float w = 0.5 - 0.1 * d.y;
    float bx = 1.0 - smoothstep(w - 0.08, w, abs(d.x));
    float by = 1.0 - smoothstep(0.62, 0.7, abs(d.y));
    return bx * by;
}

float3 lanternSky(float2 p, float t) {
    float sy = sat(p.y + 0.5);
    float3 col = mix(float3(0.35, 0.18, 0.35), float3(0.03, 0.03, 0.12), pow(sy, 0.6));
    col += float3(1.0, 0.45, 0.2) * exp(-(p.y + 0.18) * 7.0) * 0.12;
    col += float3(stars(p, 80.0, t)) * smoothstep(0.4, 0.9, sy) * 0.6;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float cellSize = 0.06 + fi * 0.06;
        float2 q = p / cellSize;
        q.y -= t * (0.02 + fi * 0.015) / cellSize;
        float2 cell = floor(q);
        float2 local = fract(q) - 0.5;
        float h = hash21(cell + fi * 13.0);
        if (h < 0.22) {
            float2 c = (hash22(cell + 3.0) - 0.5) * 0.5 + float2(0.08 * sin(t * 0.3 + h * 30.0), 0.0);
            float size = 0.20 + 0.08 * hash11(h * 9.0);
            float body = lantern(local, c, size);
            float flicker = 0.85 + 0.15 * sin(t * 6.0 + h * 50.0);
            float3 warm = mix(float3(1.0, 0.55, 0.20), float3(1.0, 0.80, 0.45), (local.y - c.y) / size + 0.5);
            col = mix(col, warm * flicker, body * (0.5 + 0.25 * fi));
            float halo = glow(length(local - c), 0.06, 0.2) * (1.0 - smoothstep(0.25, 0.5, length(local - c)));
            col += float3(1.0, 0.5, 0.2) * halo * flicker * (0.5 + 0.25 * fi);
        }
    }
    return col;
}

float3 scene_lanterns(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float shore = -0.18;
    if (p.y > shore) {
        float3 col = lanternSky(p, t);
        float hills = shore + 0.04 * ridge(p.x, 2.0, 7.0);
        col = mix(col, float3(0.02, 0.02, 0.05), 1.0 - smoothstep(hills - 0.002, hills + 0.002, p.y));
        return col;
    }
    // Отражение в воде с рябью.
    float depth = shore - p.y;
    float ripple = 0.006 * sin(p.y * 220.0 / (depth + 0.05) * 0.05 + t * 2.0) + 0.004 * fbm3(float2(p.x * 20.0, p.y * 60.0 + t));
    float2 rp = float2(p.x + ripple, shore + depth * 1.2 + 0.02);
    float3 col = lanternSky(rp, t) * 0.55;
    col = mix(col, float3(0.02, 0.03, 0.08), 0.25 + depth);
    return col;
}

// Закат у моря: солнце у горизонта, облака-полосы и солнечная дорожка.
float3 scene_oceanSunset(float2 fc, float2 res, float t) {
    float2 p = centered(fc, res);
    float horizon = -0.08;
    float3 col;
    float2 sun = float2(0.0, horizon + 0.07);
    if (p.y > horizon) {
        float sy = sat((p.y - horizon) / 0.58);
        col = mix(float3(1.0, 0.55, 0.30), float3(0.25, 0.20, 0.50), pow(sy, 0.7));
        col = mix(col, float3(0.06, 0.06, 0.20), smoothstep(0.6, 1.0, sy));
        float sd = length(p - sun);
        col += float3(1.0, 0.6, 0.3) * glow(sd, 0.05, 0.7);
        col = mix(col, float3(1.0, 0.92, 0.70), 1.0 - smoothstep(0.06, 0.063, sd));
        // Облака-полосы, подсвеченные снизу.
        float n = fbm(float2(p.x * 1.2 + t * 0.006, p.y * 9.0));
        float clouds = smoothstep(0.5, 0.75, n) * smoothstep(0.0, 0.1, p.y - horizon);
        float3 cloudCol = mix(float3(1.0, 0.55, 0.45), float3(0.45, 0.25, 0.45), sy);
        col = mix(col, cloudCol, clouds * 0.85);
    } else {
        float depth = horizon - p.y;
        float3 sea = mix(float3(0.55, 0.30, 0.35), float3(0.06, 0.07, 0.18), sat(depth * 2.5));
        // Волны: полосы, сжимающиеся к горизонту.
        float wave = sin(3.0 / (depth + 0.03) + t * 0.8 + fbm3(float2(p.x * 4.0 / (depth + 0.1), depth * 20.0)) * 5.0);
        sea *= 0.9 + 0.1 * wave;
        // Солнечная дорожка из бликов.
        float pathW = 0.03 + depth * 0.5;
        float path = exp(-pow(p.x / pathW, 2.0));
        float2 gq = float2(p.x * 260.0 / (depth * 6.0 + 0.2), depth * 900.0 / (depth * 6.0 + 0.2));
        float2 gl = fract(gq) - 0.5;
        float gh = hash21(floor(gq) + floor(t * 2.0 + hash21(floor(gq)) * 4.0) * 17.0);
        float sparkle = step(0.9, gh) * (1.0 - smoothstep(0.1, 0.4, length(gl * float2(1.0, 2.0))));
        sea += float3(1.0, 0.75, 0.45) * path * (0.25 + sparkle * 0.9);
        col = sea;
        col += float3(1.0, 0.6, 0.4) * exp(-depth * 60.0) * 0.4;
    }
    return col;
}
