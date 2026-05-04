/*
 * milkdrop_base.metal
 *
 * Pre-compiled Metal shader library for MilkDrop3.
 *
 * This file contains:
 *   1. The default warp and comp shaders (used when a preset has no shader body).
 *   2. The blur pass shaders (two-pass separable Gaussian).
 *   3. Shared vertex shader for both warp and comp passes.
 *
 * Preset-specific warp_shader / comp_shader bodies are compiled at runtime by
 * HLSLToMSL.mm and override the functions here.
 */

#include <metal_stdlib>
using namespace metal;

// ── Uniform buffer layout (matches MilkDropUniforms in MetalDevice.h) ─────────
struct MilkDropUniforms {
    float4   c[14];
    float4   q[16];
    float4x4 rot_s[4];
    float4x4 rot_d[4];
    float4x4 rot_f[4];
    float4x4 rot_vf[4];
    float4x4 rot_uf[4];
    float4x4 rot_rand[4];
};

// ── Vertex I/O ─────────────────────────────────────────────────────────────────
struct WarpVertIn {
    float3 position [[attribute(0)]];
    float4 diffuse  [[attribute(1)]];
    float4 uv       [[attribute(2)]];   // .xy = warped, .zw = original
    float2 rad_ang  [[attribute(3)]];
};

struct WarpVertOut {
    float4 position [[position]];
    float4 diffuse;
    float4 uv;
    float2 rad_ang;
};

// ── Shared vertex shader (used for both warp and comp passes) ──────────────────
vertex WarpVertOut warp_vert(WarpVertIn in [[stage_in]]) {
    WarpVertOut out;
    out.position = float4(in.position.xy, in.position.z, 1.0);
    out.diffuse  = in.diffuse;
    out.uv       = in.uv;
    out.rad_ang  = in.rad_ang;
    return out;
}

// ── Default warp fragment shader ───────────────────────────────────────────────
fragment float4 warp_frag(
    WarpVertOut            in          [[stage_in]],
    constant MilkDropUniforms& uniforms [[buffer(1)]],
    texture2d<float>       sampler_main [[texture(0)]],
    sampler                samp_main    [[sampler(0)]])
{
    float2 uv  = in.uv.xy;
    float3 ret = sampler_main.sample(samp_main, uv).rgb;
    // Default: sample previous frame and darken slightly
    ret = max(ret - 0.004, float3(0));
    return float4(ret, 1.0);
}

// ── Default comp fragment shader ───────────────────────────────────────────────
fragment float4 comp_frag(
    WarpVertOut            in          [[stage_in]],
    constant MilkDropUniforms& uniforms [[buffer(1)]],
    texture2d<float>       sampler_main [[texture(0)]],
    sampler                samp_main    [[sampler(0)]])
{
    float2 uv  = in.uv.xy;
    float3 ret = sampler_main.sample(samp_main, uv).rgb;
    return float4(ret, 1.0);
}

// ── Blur pass ─────────────────────────────────────────────────────────────────
// Two-pass separable Gaussian blur (5-tap, σ≈1).
// Pass 1 = horizontal, Pass 2 = vertical.
// These match the D3D blur1_ps.fx / blur2_ps.fx shaders.

struct BlurVertIn {
    float4 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};
struct BlurVertOut {
    float4 position [[position]];
    float2 uv;
};

vertex BlurVertOut blur_vert(BlurVertIn in [[stage_in]]) {
    BlurVertOut out;
    out.position = in.position;
    out.uv       = in.uv;
    return out;
}

// Gaussian weights for 9-tap kernel (σ≈1.5)
constant float kWeights[5] = { 0.0625, 0.25, 0.375, 0.25, 0.0625 };

fragment float4 blur_frag_h(
    BlurVertOut            in      [[stage_in]],
    texture2d<float>       src     [[texture(0)]],
    constant MilkDropUniforms& uniforms [[buffer(1)]],
    sampler                smp     [[sampler(0)]])
{
    float2 texel = float2(1.0 / uniforms.c[7].x, 0.0);
    float4 col = float4(0);
    for (int i = -2; i <= 2; ++i)
        col += kWeights[i + 2] * src.sample(smp, in.uv + float2(i, 0) * texel);
    return col;
}

fragment float4 blur_frag_v(
    BlurVertOut            in      [[stage_in]],
    texture2d<float>       src     [[texture(0)]],
    constant MilkDropUniforms& uniforms [[buffer(1)]],
    sampler                smp     [[sampler(0)]])
{
    float2 texel = float2(0.0, 1.0 / uniforms.c[7].y);
    float4 col = float4(0);
    for (int i = -2; i <= 2; ++i)
        col += kWeights[i + 2] * src.sample(smp, in.uv + float2(0, i) * texel);
    return col;
}

// ── Waveform / geometry vertex shader ─────────────────────────────────────────
// Simple untextured coloured geometry (oscilloscope waveforms, shapes).
struct WFVertIn {
    float3 position [[attribute(0)]];
    float4 diffuse  [[attribute(1)]];
};
struct WFVertOut {
    float4 position [[position]];
    float4 diffuse;
};

vertex WFVertOut waveform_vert(WFVertIn in [[stage_in]]) {
    WFVertOut out;
    out.position = float4(in.position.xy, in.position.z, 1.0);
    out.diffuse  = in.diffuse;
    return out;
}

fragment float4 waveform_frag(WFVertOut in [[stage_in]]) {
    return in.diffuse;
}

// ── Sprite vertex shader (for texture sprites) ─────────────────────────────────
struct SpriteVertIn {
    float3 position [[attribute(0)]];
    float4 diffuse  [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};
struct SpriteVertOut {
    float4 position [[position]];
    float4 diffuse;
    float2 uv;
};

vertex SpriteVertOut sprite_vert(SpriteVertIn in [[stage_in]]) {
    SpriteVertOut out;
    out.position = float4(in.position.xy, in.position.z, 1.0);
    out.diffuse  = in.diffuse;
    out.uv       = in.uv;
    return out;
}

fragment float4 sprite_frag(
    SpriteVertOut      in  [[stage_in]],
    texture2d<float>   tex [[texture(0)]],
    sampler            smp [[sampler(0)]])
{
    float4 c = tex.sample(smp, in.uv);
    return c * in.diffuse;
}
