/**
 * HLSLToMSL.h
 *
 * Runtime HLSL → Metal Shading Language transpiler for MilkDrop preset shaders.
 *
 * MilkDrop preset shaders (warp_shader / comp_shader sections in .milk files)
 * are HLSL pixel shader bodies that get wrapped in a fixed boilerplate defined
 * in include.fx.  The dialect is a constrained subset of HLSL ps_2_x / ps_3_0:
 *
 *   - tex2D / tex3D sampling
 *   - float/float2/float3/float4 arithmetic
 *   - dot, length, sin, cos, atan2, etc.
 *   - No loops with non-constant bounds (in practice some presets do have loops)
 *   - No user-defined functions (in include.fx; preset bodies can define them)
 *
 * Translation approach:
 *   1. Text-substitute known HLSL-isms to MSL equivalents.
 *   2. Wrap in the MSL boilerplate that binds the correct texture/sampler/
 *      uniform arguments.
 *   3. Compile the resulting MSL string to a MTLLibrary at load time.
 *
 * This is fast enough: a typical preset shader is < 100 lines and MTLDevice
 * compiles it in < 5 ms on Apple Silicon.
 */

#pragma once

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

#include <string>

// Shader type: warp (per-pixel UV distortion) or comp (final composite)
enum class MilkDropShaderType { Warp, Comp };

struct TranspileResult {
    bool        success   = false;
    std::string msl;          // generated MSL source (useful for debugging)
    std::string error;        // error message if success == false
#ifdef __OBJC__
    id<MTLLibrary>  library  = nil;
    id<MTLFunction> vertFunc = nil;
    id<MTLFunction> fragFunc = nil;
#endif
};

class HLSLToMSL {
public:
    /**
     * Transpile a MilkDrop preset shader body (the contents of warp_shader {}
     * or comp_shader {} in a .milk file) into a compiled MTLLibrary.
     *
     * @param hlslBody     The raw HLSL body string from the preset.
     * @param type         Warp or Comp.
     * @param device       The Metal device to compile against.
     * @param presetName   Used for labelling the MTLLibrary (debug).
     */
#ifdef __OBJC__
    static TranspileResult Transpile(const std::string& hlslBody,
                                     MilkDropShaderType type,
                                     id<MTLDevice> device,
                                     const std::string& presetName = "");
#endif

    /**
     * Generate MSL source from HLSL body without compiling.
     * Useful for debugging / saving transpiled shaders to disk.
     */
    static std::string GenerateMSL(const std::string& hlslBody,
                                   MilkDropShaderType type);
};
