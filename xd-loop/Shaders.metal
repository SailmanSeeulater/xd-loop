#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Each function below runs once for every pixel on the screen, on the GPU.
// They use the same maths as the ASCII patterns in Patterns.swift, but return
// a smooth colour instead of picking a character.

// Same coordinates as the ASCII patterns: 32 units across, measured from the centre.
// y is halved because the ASCII formulas counted in text rows, which are about twice as tall as wide
struct Spot {
    float x, y;     // y grows downward
    float d, a;     // distance and angle from the centre
    float halfW, halfH;
};

static Spot spot(float2 pos, float2 size) {
    float k = 32.0 / size.x;
    Spot s;
    s.x = (pos.x - size.x * 0.5) * k;
    s.y = (pos.y - size.y * 0.5) * k * 0.5;
    s.d = length(float2(s.x, 2.0 * s.y));
    s.a = atan2(2.0 * s.y, s.x);
    s.halfW = 16.0;
    s.halfH = size.y * k * 0.25;
    return s;
}

// Smooth looping colours: a + b * cos(2π(c·v + d)). Change d to shift the hues
static float3 palette(float v, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * v + d));
}

static half4 rgb(float3 c) {
    return half4(half3(saturate(c)), 1.0);
}

// 1. Three overlapping sine waves, coloured like a rainbow that slowly shifts
[[ stitchable ]] half4 plasma(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float v = (sin(p.x * 0.15 + t) + sin(p.y * 0.3 - t) + sin((p.x + p.y) * 0.1 + t * 0.5) + 3.0) / 6.0;
    return rgb(palette(v + t * 0.05, float3(0.5), float3(0.5), float3(1.0), float3(0.0, 0.33, 0.67)));
}

// 2. Rings spreading out from the centre, with bright crests
[[ stitchable ]] half4 ripples(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float v = (sin(p.d * 0.6 - t * 3.0) + 1.0) / 2.0;
    return rgb(float3(0.02, 0.1, 0.25) + float3(0.1, 0.5, 1.0) * v + float3(0.7, 0.9, 1.0) * pow(v, 12.0));
}

// 3. Night sky, a foamy wavy surface, and water that gets darker the deeper it goes
[[ stitchable ]] half4 ocean(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float fromTop = p.y + p.halfH;
    float surface = p.halfH * 2.0 * 0.45 + sin(p.x * 0.2 + t * 2.0) * 2.0 + sin(p.x * 0.07 - t) * 1.5;
    float depth = fromTop - surface;
    float3 sky = mix(float3(0.01, 0.01, 0.06), float3(0.12, 0.18, 0.4), fromTop / (2.0 * p.halfH));
    float3 water = mix(float3(0.1, 0.55, 0.85), float3(0.0, 0.03, 0.15), saturate(depth / 6.0));
    float foam = 1.0 - smoothstep(0.0, 0.35, abs(depth));
    return rgb((depth < 0.0 ? sky : water) + foam * 0.9);
}

// 4. Rotating spiral arms with a soft purple glow
[[ stitchable ]] half4 spiral(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float v = (sin(p.a * 3.0 + p.d * 0.4 - t * 3.0) + 1.0) / 2.0;
    float3 c = mix(float3(0.05, 0.0, 0.12), float3(0.77, 0.55, 1.0), v) + float3(1.0, 0.8, 1.0) * pow(v, 16.0);
    return rgb(c * (1.0 - exp(-p.d * 0.5)));
}

// 5. Rotating, zooming tiles with smooth edges
[[ stitchable ]] half4 checkerboard(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float c = cos(t * 0.5), s = sin(t * 0.5);
    float tile = 3.0 + sin(t) * 1.5;
    float u = p.x * c - p.y * 2.0 * s;
    float v = p.x * s + p.y * 2.0 * c;
    float check = sin(u / tile * M_PI_F) * sin(v / tile * M_PI_F);
    return rgb(mix(float3(0.08, 0.05, 0.0), float3(1.0, 0.85, 0.29), smoothstep(-0.08, 0.08, check)));
}

// 6. Four moving blobs that melt together, glowing yellow where they're thickest
[[ stitchable ]] half4 lavaLamp(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float sum = 0.0;
    for (int i = 0; i < 4; i++) {
        float f = float(i);
        float bx = sin(t * (0.5 + f * 0.2) + f * 2.0) * p.halfW * 0.7;
        float by = cos(t * (0.4 + f * 0.15) + f) * p.halfH * 0.7;
        float dx = p.x - bx, dy = (p.y - by) * 2.0;
        sum += 12.0 / (dx * dx + dy * dy + 0.1);
    }
    float3 glow = float3(0.08, 0.0, 0.04) + float3(1.0, 0.3, 0.4) * smoothstep(0.3, 1.0, sum) * 0.35;
    float3 blob = mix(float3(1.0, 0.35, 0.48), float3(1.0, 0.85, 0.4), smoothstep(1.0, 4.0, sum));
    return rgb(mix(glow, blob, smoothstep(0.95, 1.05, sum)));
}

// 7. 1/distance gives depth, angle gives the walls; neon colours change as you fly in
[[ stitchable ]] half4 tunnel(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float depth = 8.0 / (p.d + 0.01) + t * 2.0;
    float around = p.a / M_PI_F * 4.0 + t * 0.5;
    float check = smoothstep(-0.2, 0.2, sin(depth * M_PI_F) * sin(around * M_PI_F));
    float fade = saturate(p.d / p.halfW);
    float3 c = palette(depth * 0.05, float3(0.5), float3(0.5), float3(1.0), float3(0.3, 0.2, 0.2));
    return rgb(c * check * fade * 1.4);
}

// 8. A swirl that twists harder near the centre, a black void, and a glowing ring around it
[[ stitchable ]] half4 blackHole(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float swirl = p.a + 6.0 / (p.d + 1.0) + t * 2.0;
    float v = (sin(swirl * 3.0 + p.d * 0.3) + 1.0) / 2.0 * saturate(p.d / 6.0);
    float3 disk = mix(float3(0.2, 0.05, 0.4), float3(0.72, 0.55, 1.0), v) * v;
    float ring = exp(-pow((p.d - 3.5) * 2.5, 2.0));
    float3 c = disk * smoothstep(3.0, 3.6, p.d) + float3(1.0, 0.75, 0.45) * ring * 1.5;
    return rgb(c);
}

// 9. The angle folded into 8 mirrored slices, with rainbow plasma inside them
[[ stitchable ]] half4 kaleidoscope(float2 pos, half4 color, float t, float2 size) {
    Spot p = spot(pos, size);
    float seg = M_PI_F / 4.0;
    float m = fmod(fmod(p.a, 2.0 * seg) + 2.0 * seg, 2.0 * seg);
    float a = abs(m - seg) + t * 0.3;
    float x = cos(a) * p.d * 0.3, y = sin(a) * p.d * 0.3;
    float v = (sin(x + t) + sin(y * 1.3 - t) + sin((x + y) * 0.7 + t * 0.7) + 3.0) / 6.0;
    return rgb(palette(v * 1.5 + p.d * 0.02, float3(0.5), float3(0.5), float3(1.0), float3(0.8, 0.9, 0.3)));
}

// Applied on top of every shader above: recolours it with the colour wheel's pick. It also brightens on loud music when audio reaction is on.
// It keeps the brightness of each pixel but swaps its colour; amount 0 = original, 1 = fully recoloured
[[ stitchable ]] half4 tint(float2 pos, half4 color, half4 target, float amount, float pulse) {
    // pulse is the microphone beat level: loud moments flash brighter
    float3 base = float3(color.rgb) * (1.0 + pulse * 0.7);
    float lum = dot(base, float3(0.299, 0.587, 0.114));
    float3 recoloured = float3(target.rgb) * lum * 1.6 + pow(lum, 4.0) * 0.4;
    return half4(half3(saturate(mix(base, recoloured, amount))), 1.0);
}
