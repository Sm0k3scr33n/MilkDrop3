/**
 * HLSLToMSL.mm
 *
 * MilkDrop HLSL → Metal Shading Language transpiler.
 *
 * The translation is text-based (regex + string substitutions) because the
 * MilkDrop shader dialect is deliberately simple.  A full AST-based transpiler
 * (e.g. via DXC + SPIRV-Cross) would be more robust but adds a large dependency
 * and startup latency.  For the constrained MilkDrop dialect this approach is
 * pragmatic and fast.
 *
 * If a preset shader uses features that break text translation, the runtime
 * falls back to a no-op passthrough shader and logs the error.
 */

#import <Metal/Metal.h>
#include "HLSLToMSL.h"
#include <regex>
#include <sstream>
#include <algorithm>

// ──────────────────────────────────────────────────────────────────────────────
// MSL boilerplate templates
//
// The warp shader:
//   Input : warped UV coordinates for the current pixel
//   Output: sampled/modified colour (ret)
//   It reads from sampler_main (the previous frame) and blur textures.
//
// The comp shader:
//   Input : final UV coordinates
//   Output: final pixel colour
//
// Uniform layout mirrors MilkDropUniforms in MetalDevice.h (buffer(1)).
// Textures are bound at the indices defined in the base library.
// ──────────────────────────────────────────────────────────────────────────────

static const char* kMSLUniformStruct = R"msl(
#include <metal_stdlib>
using namespace metal;

// ── Uniform buffer (matches MilkDropUniforms in MetalDevice.h) ───────────────
struct MilkDropUniforms {
    float4 c[14];      // _c0 .. _c13
    float4 q[16];      // _qa .. _qh  (q1-q64)
    float4x4 rot_s[4];
    float4x4 rot_d[4];
    float4x4 rot_f[4];
    float4x4 rot_vf[4];
    float4x4 rot_uf[4];
    float4x4 rot_rand[4];
};

// ── Convenience macros matching include.fx defines ───────────────────────────
// (defined as inline functions for better MSL type safety)
)msl";

static const char* kMSLUniformAliases = R"msl(
#define time      uniforms.c[2].x
#define fps       uniforms.c[2].y
#define frame     uniforms.c[2].z
#define progress  uniforms.c[2].w
#define bass      uniforms.c[3].x
#define mid       uniforms.c[3].y
#define treb      uniforms.c[3].z
#define vol       uniforms.c[3].w
#define bass_att  uniforms.c[4].x
#define mid_att   uniforms.c[4].y
#define treb_att  uniforms.c[4].z
#define vol_att   uniforms.c[4].w
#define q1  uniforms.q[0].x
#define q2  uniforms.q[0].y
#define q3  uniforms.q[0].z
#define q4  uniforms.q[0].w
#define q5  uniforms.q[1].x
#define q6  uniforms.q[1].y
#define q7  uniforms.q[1].z
#define q8  uniforms.q[1].w
#define q9  uniforms.q[2].x
#define q10 uniforms.q[2].y
#define q11 uniforms.q[2].z
#define q12 uniforms.q[2].w
#define q13 uniforms.q[3].x
#define q14 uniforms.q[3].y
#define q15 uniforms.q[3].z
#define q16 uniforms.q[3].w
#define q17 uniforms.q[4].x
#define q18 uniforms.q[4].y
#define q19 uniforms.q[4].z
#define q20 uniforms.q[4].w
#define q21 uniforms.q[5].x
#define q22 uniforms.q[5].y
#define q23 uniforms.q[5].z
#define q24 uniforms.q[5].w
#define q25 uniforms.q[6].x
#define q26 uniforms.q[6].y
#define q27 uniforms.q[6].z
#define q28 uniforms.q[6].w
#define q29 uniforms.q[7].x
#define q30 uniforms.q[7].y
#define q31 uniforms.q[7].z
#define q32 uniforms.q[7].w
#define aspect    uniforms.c[0]
#define texsize   uniforms.c[7]
#define roam_cos  uniforms.c[8]
#define roam_sin  uniforms.c[9]
#define slow_roam_cos uniforms.c[10]
#define slow_roam_sin uniforms.c[11]
#define mip_x   uniforms.c[12].x
#define mip_y   uniforms.c[12].y
#define mip_xy  uniforms.c[12].xy
#define mip_avg uniforms.c[12].z
#define blur1_min uniforms.c[6].z
#define blur1_max uniforms.c[6].w
#define blur2_min uniforms.c[13].x
#define blur2_max uniforms.c[13].y
#define blur3_min uniforms.c[13].z
#define blur3_max uniforms.c[13].w
#define lum(x) (dot(x, float3(0.32,0.49,0.29)))
#define tex2d   tex2D
#define tex3d   tex3D
)msl";

// Texture/sampler declarations for warp shader
static const char* kMSLWarpTextures = R"msl(
// Inline tex2D / tex3D helpers (replaces HLSL sampler state objects)
#define GetMain(uv)   (sampler_main.sample(samp_main, uv).xyz)
#define GetPixel(uv)  (sampler_main.sample(samp_main, uv).xyz)
#define GetBlur1(uv)  (sampler_blur1.sample(samp_linear, uv).xyz * uniforms.c[5].x + uniforms.c[5].y)
#define GetBlur2(uv)  (sampler_blur2.sample(samp_linear, uv).xyz * uniforms.c[5].z + uniforms.c[5].w)
#define GetBlur3(uv)  (sampler_blur3.sample(samp_linear, uv).xyz * uniforms.c[6].x + uniforms.c[6].y)
)msl";

// Vertex/fragment I/O for warp pass
static const char* kMSLWarpIO = R"msl(
struct WarpVertIn {
    float3 position  [[attribute(0)]];
    float4 diffuse   [[attribute(1)]];
    float4 uv        [[attribute(2)]];   // .xy = warped UV, .zw = orig UV
    float2 rad_ang   [[attribute(3)]];
};
struct WarpVertOut {
    float4 position [[position]];
    float4 diffuse;
    float4 uv;
    float2 rad_ang;
};
)msl";

static const char* kMSLWarpVert = R"msl(
vertex WarpVertOut warp_vert(WarpVertIn in [[stage_in]]) {
    WarpVertOut out;
    out.position = float4(in.position.xy, in.position.z, 1.0);
    out.diffuse  = in.diffuse;
    out.uv       = in.uv;
    out.rad_ang  = in.rad_ang;
    return out;
}
)msl";

// Fragment shader wrapper – the preset body is spliced between BEGIN/END marks.
static const char* kMSLWarpFragBegin = R"msl(
fragment float4 warp_frag(
    WarpVertOut in [[stage_in]],
    constant MilkDropUniforms& uniforms [[buffer(1)]],
    texture2d<float> sampler_main   [[texture(0)]],
    texture2d<float> sampler_blur1  [[texture(1)]],
    texture2d<float> sampler_blur2  [[texture(2)]],
    texture2d<float> sampler_blur3  [[texture(3)]],
    texture2d<float> sampler_noise_lq [[texture(4)]],
    texture2d<float> sampler_noise_mq [[texture(5)]],
    texture2d<float> sampler_noise_hq [[texture(6)]],
    texture3d<float> sampler_noisevol_lq [[texture(7)]],
    sampler samp_main   [[sampler(0)]],
    sampler samp_linear [[sampler(1)]]
) {
    // Alias input semantics to HLSL names
    float2 uv      = in.uv.xy;
    float2 uv_orig = in.uv.zw;
    float  rad     = in.rad_ang.x;
    float  ang     = in.rad_ang.y;
    float3 ret     = float3(0,0,0);

    // Inline tex2D helper for this scope
    auto tex2D = [&](texture2d<float> t, float2 coords) -> float4 {
        return t.sample(samp_linear, coords);
    };
    auto tex3D = [&](texture3d<float> t, float3 coords) -> float4 {
        return t.sample(samp_linear, coords);
    };

    // ── PRESET SHADER BODY BEGIN ──────────────────────────────────────────────
)msl";

static const char* kMSLWarpFragEnd = R"msl(
    // ── PRESET SHADER BODY END ────────────────────────────────────────────────
    return float4(ret, 1.0);
}
)msl";

// Comp pass (similar structure)
static const char* kMSLCompFragBegin = R"msl(
fragment float4 comp_frag(
    WarpVertOut in [[stage_in]],
    constant MilkDropUniforms& uniforms [[buffer(1)]],
    texture2d<float> sampler_main   [[texture(0)]],
    texture2d<float> sampler_blur1  [[texture(1)]],
    texture2d<float> sampler_blur2  [[texture(2)]],
    texture2d<float> sampler_blur3  [[texture(3)]],
    texture2d<float> sampler_noise_lq [[texture(4)]],
    texture2d<float> sampler_noise_mq [[texture(5)]],
    texture2d<float> sampler_noise_hq [[texture(6)]],
    texture3d<float> sampler_noisevol_lq [[texture(7)]],
    sampler samp_main   [[sampler(0)]],
    sampler samp_linear [[sampler(1)]]
) {
    float2 uv      = in.uv.xy;
    float2 uv_orig = in.uv.zw;
    float  rad     = in.rad_ang.x;
    float  ang     = in.rad_ang.y;
    float3 ret     = float3(0,0,0);

    auto tex2D = [&](texture2d<float> t, float2 coords) -> float4 {
        return t.sample(samp_linear, coords);
    };
    auto tex3D = [&](texture3d<float> t, float3 coords) -> float4 {
        return t.sample(samp_linear, coords);
    };

    // ── PRESET SHADER BODY BEGIN ──────────────────────────────────────────────
)msl";

static const char* kMSLCompFragEnd = R"msl(
    // ── PRESET SHADER BODY END ────────────────────────────────────────────────
    return float4(ret, 1.0);
}
)msl";

// ──────────────────────────────────────────────────────────────────────────────
// Text-based HLSL → MSL transformations
// ──────────────────────────────────────────────────────────────────────────────

static std::string ApplyTextSubstitutions(std::string src) {
    // 1. Remove HLSL sampler declarations (sampler2D xxx = sampler_state {...})
    //    These are replaced by MSL texture/sampler arguments.
    src = std::regex_replace(src,
        std::regex(R"(\bsampler2D\s+\w+\s*=\s*sampler_state\s*\{[^}]*\}\s*;)"),
        "// [sampler removed]");
    src = std::regex_replace(src,
        std::regex(R"(\bsampler3D\s+\w+\s*=\s*sampler_state\s*\{[^}]*\}\s*;)"),
        "// [sampler removed]");
    src = std::regex_replace(src, std::regex(R"(\bsampler2D\s+(\w+)\s*;)"), "// sampler2D $1");
    src = std::regex_replace(src, std::regex(R"(\bsampler3D\s+(\w+)\s*;)"), "// sampler3D $1");

    // 2. Remove texture declarations
    src = std::regex_replace(src,
        std::regex(R"(\btexture\s+\w+\s*;)"), "// [texture decl removed]");

    // 3. HLSL type constructors that differ: none needed (float4(), etc. same in MSL)

    // 4. Remove : POSITION, : COLOR, : TEXCOORD semantics from local vars
    //    (they appear in function signatures; we've already handled those in wrappers)
    src = std::regex_replace(src,
        std::regex(R"(\s*:\s*(POSITION|COLOR\d*|TEXCOORD\d*|SV_\w+))"), "");

    // 5. 'static' keyword is valid in MSL; keep it.

    // 6. HLSL 'clip()' function → MSL 'discard_fragment()' if arg < 0
    src = std::regex_replace(src,
        std::regex(R"(\bclip\s*\(([^)]+)\))"),
        "({ if(($1) < 0) discard_fragment(); })");

    // 7. saturate() — same name in MSL, no change needed.
    // 8. lerp() — same in MSL.
    // 9. frac() → fract() in MSL
    src = std::regex_replace(src, std::regex(R"(\bfrac\s*\()"), "fract(");

    // 10. mul(matrix, vec) → (matrix * vec) in MSL
    //     MSL uses operator* for matrix multiplication.
    src = std::regex_replace(src,
        std::regex(R"(\bmul\s*\(\s*([^,]+),\s*([^)]+)\))"),
        "(($1) * ($2))");

    // 11. float4x3 → float4x3 (same in MSL — but needs transposed indexing)
    //     For now leave as-is; most presets don't use 4x3 directly.

    // 12. ddx/ddy → dfdx/dfdy in MSL
    src = std::regex_replace(src, std::regex(R"(\bddx\s*\()"), "dfdx(");
    src = std::regex_replace(src, std::regex(R"(\bddy\s*\()"), "dfdy(");

    // 13. #define M_PI / M_PI_2 already in our preamble; remove duplicates
    // (harmless to leave)

    // 14. 'ret' is already declared float3 in the wrapper; ensure 'return' isn't used
    //     in the body (the body sets ret directly and falls through to the wrapper return).
    //     Some presets may use early return for ret – transform to block assignment.
    // This is complex; skip for now and document as a known limitation.

    return src;
}

// ──────────────────────────────────────────────────────────────────────────────
// Public API
// ──────────────────────────────────────────────────────────────────────────────

std::string HLSLToMSL::GenerateMSL(const std::string& hlslBody,
                                    MilkDropShaderType type)
{
    std::string body = ApplyTextSubstitutions(hlslBody);

    std::ostringstream msl;
    msl << kMSLUniformStruct;
    msl << kMSLUniformAliases;
    msl << kMSLWarpTextures;
    msl << kMSLWarpIO;
    msl << kMSLWarpVert;     // vertex shader is the same for both passes

    if (type == MilkDropShaderType::Warp) {
        msl << kMSLWarpFragBegin;
        msl << "\n" << body << "\n";
        msl << kMSLWarpFragEnd;
    } else {
        // Comp – reuse warp vertex shader, different fragment entry
        msl << kMSLCompFragBegin;
        msl << "\n" << body << "\n";
        msl << kMSLCompFragEnd;
    }

    return msl.str();
}

TranspileResult HLSLToMSL::Transpile(const std::string& hlslBody,
                                      MilkDropShaderType type,
                                      id<MTLDevice> device,
                                      const std::string& presetName)
{
    TranspileResult result;
    result.msl = GenerateMSL(hlslBody, type);

    NSString* src = [NSString stringWithUTF8String:result.msl.c_str()];
    MTLCompileOptions* opts = [MTLCompileOptions new];
    opts.languageVersion = MTLLanguageVersion3_0;
    opts.fastMathEnabled = YES;

    NSError* err = nil;
    id<MTLLibrary> lib = [device newLibraryWithSource:src options:opts error:&err];

    if (!lib) {
        result.success = false;
        result.error   = err ? err.localizedDescription.UTF8String : "Unknown compile error";
        NSLog(@"[HLSLToMSL] Shader compile failed for '%s':\n%s",
              presetName.c_str(), result.error.c_str());
        return result;
    }

    result.library  = lib;
    result.vertFunc = [lib newFunctionWithName:@"warp_vert"];
    result.fragFunc = [lib newFunctionWithName:
        (type == MilkDropShaderType::Warp ? @"warp_frag" : @"comp_frag")];
    result.success  = (result.vertFunc != nil && result.fragFunc != nil);

    if (!result.success)
        result.error = "Missing vertex or fragment function in compiled library";

    return result;
}
