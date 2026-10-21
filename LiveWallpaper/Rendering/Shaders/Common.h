// Общие функции для сцен.
//
// Сцены пишутся на общем подмножестве Metal и GLSL, чтобы их можно было проверять
// и в Metal, и в WebGL (GLSL-прелюдия делает `#define float2 vec2` и т.п.). Правила:
// только float2/3/4 (без матриц и массивов), литералы всегда с точкой (1.0, а не 1),
// без scalar-перегрузок min/max/clamp для векторов, atan2 вместо atan(y, x),
// без глобальных переменных (константы — через #define).
//
// Каждая сцена — функция `float3 scene_<имя>(float2 fc, float2 res, float t)`:
// fc — координата пикселя с началом в левом нижнем углу, res — размер в пикселях, t — время.

#define PI 3.14159265
#define TAU 6.28318531

float sat(float x) { return clamp(x, 0.0, 1.0); }

float3 sat3(float3 c) { return clamp(c, float3(0.0), float3(1.0)); }

float wrap(float x, float y) { return x - y * floor(x / y); }

// Хэши без sin (Dave Hoskins): стабильны на любых GPU.
float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(float2 p) {
    float3 p3 = fract(p.xyx * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float2 hash22(float2 p) {
    float3 p3 = fract(p.xyx * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

float fbm3(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

float2 rot(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(TAU * (c * t + d));
}

/// Центрированные координаты: по вертикали -0.5…0.5, по горизонтали с учётом пропорций.
float2 centered(float2 fc, float2 res) {
    return (fc - 0.5 * res) / res.y;
}

/// Мягкое свечение вокруг расстояния d.
float glow(float d, float radius, float intensity) {
    return intensity * radius / (abs(d) + radius);
}

/// Звёздное небо: редкие мерцающие точки.
float stars(float2 p, float density, float t) {
    float2 cell = floor(p * density);
    float2 local = fract(p * density) - 0.5;
    float h = hash21(cell);
    float2 offset = (hash22(cell + 7.1) - 0.5) * 0.7;
    float d = length(local - offset);
    float size = 0.02 + 0.06 * hash11(h * 91.7);
    float twinkle = 0.6 + 0.4 * sin(t * (1.0 + 3.0 * h) + h * 40.0);
    return step(0.86, h) * (1.0 - smoothstep(0.0, size, d)) * twinkle;
}

/// Силуэт гор: высота хребта в точке x.
float ridge(float x, float scale, float seed) {
    return fbm3(float2(x * scale + seed, seed * 3.7));
}

/// Падающие частицы (лепестки, листья, снег) в сетке ячеек. Возвращает яркость.
/// density — доля ячеек с частицей (0…1).
float fallingParticles(float2 p, float t, float cellSize, float speed, float sway, float size, float density) {
    float2 q = p / cellSize;
    q.y += t * speed / cellSize;
    float2 cell = floor(q);
    float2 local = fract(q) - 0.5;
    float h = hash21(cell);
    if (h > density) { return 0.0; }
    h = h / density;
    float phase = h * TAU + t * (0.6 + h);
    float2 center = float2((hash11(h * 13.3) - 0.5) * 0.6 + sin(phase) * sway, (hash11(h * 7.7) - 0.5) * 0.6);
    float2 d = rot(local - center, phase * 0.7);
    d.x *= 1.0 + 0.8 * abs(sin(phase));          // «кувыркание» лепестка
    float r = length(d * float2(1.0, 1.6));
    return 1.0 - smoothstep(size * 0.6, size, r);
}

/// Светлячки / магические искры: мерцающие точки с ореолом.
float floatingMotes(float2 p, float t, float cellSize, float rise) {
    float2 q = p / cellSize;
    q.y -= t * rise;
    float2 cell = floor(q);
    float2 local = fract(q) - 0.5;
    float h = hash21(cell);
    float2 center = (hash22(cell) - 0.5) * 0.6;
    center += 0.15 * float2(sin(t * 0.7 + h * 20.0), cos(t * 0.5 + h * 11.0));
    float d = length(local - center);
    float blink = pow(0.5 + 0.5 * sin(t * (1.0 + 2.0 * h) + h * 30.0), 3.0);
    return step(0.55, h) * blink * (0.02 / (d + 0.02)) * (1.0 - smoothstep(0.2, 0.5, d));
}
