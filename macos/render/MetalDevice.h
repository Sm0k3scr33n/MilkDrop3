/**
 * MetalDevice.h
 *
 * IDirect3DDevice9 — Metal implementation.
 *
 * This class is the heart of the port. It implements the subset of the D3D9
 * device interface that MilkDrop actually calls, backed by Metal.
 *
 * Key mappings:
 *   D3D concept               → Metal concept
 *   ─────────────────────────────────────────────────────
 *   IDirect3DDevice9          → id<MTLDevice> + MTLRenderCommandEncoder
 *   IDirect3DTexture9         → id<MTLTexture>
 *   IDirect3DVertexBuffer9    → id<MTLBuffer> (vertex)
 *   IDirect3DIndexBuffer9     → id<MTLBuffer> (index)
 *   IDirect3DPixelShader9     → id<MTLFunction>  (fragment)
 *   IDirect3DVertexShader9    → id<MTLFunction>  (vertex)
 *   D3DXMATRIX / uniform cbuf → MTLBuffer (per-frame constant buffer)
 *   RenderState               → MTLRenderPipelineState + MTLDepthStencilState
 *   SetTexture(stage, tex)    → encoder setFragmentTexture:atIndex:
 *
 * All Obj-C++ implementation is in MetalDevice.mm.
 */

#pragma once

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>
#endif

#include "platform/d3d_compat.h"
#include <vector>
#include <unordered_map>
#include <functional>
#include <string>

// ── Metal texture wrapper ─────────────────────────────────────────────────────
class MetalTexture : public IDirect3DTexture9 {
public:
#ifdef __OBJC__
    id<MTLTexture>  tex   = nil;
    id<MTLSamplerState> samp = nil;
#else
    void* tex  = nullptr;
    void* samp = nullptr;
#endif
    int img_w = 0, img_h = 0;

    void Release() override;
    ~MetalTexture() override;
};

// ── Metal buffer wrapper ──────────────────────────────────────────────────────
class MetalVertexBuffer : public IDirect3DVertexBuffer9 {
public:
#ifdef __OBJC__
    id<MTLBuffer> buf = nil;
#else
    void* buf = nullptr;
#endif
    size_t size = 0;
    void*  mapped = nullptr;   // points into buf.contents

    HRESULT Lock(UINT offsetBytes, UINT sizeBytes, void** ppData, DWORD flags) override;
    HRESULT Unlock() override;
    void    Release() override;
    ~MetalVertexBuffer() override;
};

class MetalIndexBuffer : public IDirect3DIndexBuffer9 {
public:
#ifdef __OBJC__
    id<MTLBuffer> buf = nil;
#else
    void* buf = nullptr;
#endif
    size_t size = 0;

    HRESULT Lock(UINT offsetBytes, UINT sizeBytes, void** ppData, DWORD flags) override;
    HRESULT Unlock() override;
    void    Release() override;
    ~MetalIndexBuffer() override;
};

// ── Metal shader wrapper ──────────────────────────────────────────────────────
class MetalPixelShader : public IDirect3DPixelShader9 {
public:
#ifdef __OBJC__
    id<MTLFunction> fn  = nil;
    id<MTLLibrary>  lib = nil;
#else
    void *fn = nullptr, *lib = nullptr;
#endif
    void Release() override;
    ~MetalPixelShader() override;
};

class MetalVertexShader : public IDirect3DVertexShader9 {
public:
#ifdef __OBJC__
    id<MTLFunction> fn  = nil;
    id<MTLLibrary>  lib = nil;
#else
    void *fn = nullptr, *lib = nullptr;
#endif
    void Release() override;
    ~MetalVertexShader() override;
};

// ── Render state cache ─────────────────────────────────────────────────────────
// Metal bakes render state into pipeline state objects (PSOs).
// We track the "dirty" state and rebuild the PSO lazily each draw call.
struct RenderStateCache {
    bool  alphaBlend  = false;
    DWORD srcBlend    = D3DBLEND_ONE;
    DWORD dstBlend    = D3DBLEND_ZERO;
    DWORD blendOp     = D3DBLENDOP_ADD;
    bool  zEnable     = false;
    bool  zWrite      = false;
    DWORD cullMode    = D3DCULL_NONE;
    DWORD fillMode    = D3DFILL_SOLID;
    bool  dirty       = true;
};

// ── Uniform / constant buffer layout ─────────────────────────────────────────
// Matches the binding layout in milkdrop_base.metal (buffer index 0).
struct alignas(16) MilkDropUniforms {
    // _c0 – _c13 from include.fx
    float c[14][4];
    // q vars: _qa – _qh (q1–q32, extended to q64 for MilkDrop3)
    float q[16][4];
    // Rotation matrices (as 4x4 padded from 4x3)
    float rot_s[4][16];
    float rot_d[4][16];
    float rot_f[4][16];
    float rot_vf[4][16];
    float rot_uf[4][16];
    float rot_rand[4][16];
};

// ── IDirect3DDevice9 — Metal implementation ───────────────────────────────────
class IDirect3DDevice9 {
public:
    IDirect3DDevice9();
    ~IDirect3DDevice9();

    // ── Called from the app's Metal render loop ─────────────────────────────
    // Call BeginFrame before any draw calls, EndFrame to commit.
#ifdef __OBJC__
    void BeginFrame(id<CAMetalDrawable> drawable, MTKView* view);
#endif
    void EndFrame();
    // Reset is used by the original codebase; on macOS this will reconfigure
    // internal state (viewport, backbuffer size) to match a new present params.
    HRESULT Reset(D3DPRESENT_PARAMETERS* pParams);

    // ── D3D9 surface ─────────────────────────────────────────────────────────
    HRESULT Clear(DWORD count, const void* rects, DWORD flags,
                  D3DCOLOR color, float z, DWORD stencil);
    HRESULT BeginScene();
    HRESULT EndScene();
    HRESULT Present(const RECT* src, const RECT* dst, HWND wnd, const void* dirty);

    // ── State management ─────────────────────────────────────────────────────
    HRESULT SetRenderState(D3DRENDERSTATETYPE state, DWORD value);
    HRESULT GetRenderState(D3DRENDERSTATETYPE state, DWORD* value);
    HRESULT SetTextureStageState(DWORD stage, D3DTEXTURESTAGESTATETYPE type, DWORD value);
    HRESULT SetSamplerState(DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD value);

    // ── Texture / RT ─────────────────────────────────────────────────────────
    HRESULT SetTexture(DWORD stage, IDirect3DTexture9* tex);
    HRESULT CreateTexture(UINT w, UINT h, UINT levels, DWORD usage,
                          D3DFORMAT fmt, DWORD pool, IDirect3DTexture9** ppTex,
                          HANDLE* handle);
    HRESULT CreateRenderTarget(UINT w, UINT h, D3DFORMAT fmt,
                               D3DMULTISAMPLE_TYPE ms, DWORD msQ, BOOL lockable,
                               IDirect3DTexture9** ppSurface, HANDLE* handle);

    // ── Shaders ──────────────────────────────────────────────────────────────
    HRESULT SetVertexShader(IDirect3DVertexShader9* vs);
    HRESULT SetPixelShader(IDirect3DPixelShader9* ps);
    HRESULT SetVertexShaderConstantF(UINT start, const float* data, UINT count);
    HRESULT SetPixelShaderConstantF(UINT start, const float* data, UINT count);

    // ── Geometry ─────────────────────────────────────────────────────────────
    HRESULT CreateVertexBuffer(UINT bytes, DWORD usage, DWORD fvf, DWORD pool,
                               IDirect3DVertexBuffer9** ppVB, HANDLE* handle);
    HRESULT CreateIndexBuffer(UINT bytes, DWORD usage, D3DFORMAT fmt, DWORD pool,
                              IDirect3DIndexBuffer9** ppIB, HANDLE* handle);
    HRESULT SetVertexDeclaration(IDirect3DVertexDeclaration9* decl);
    HRESULT CreateVertexDeclaration(const D3DVERTEXELEMENT9* elems,
                                    IDirect3DVertexDeclaration9** ppDecl);
    HRESULT SetStreamSource(UINT stream, IDirect3DVertexBuffer9* vb,
                            UINT offset, UINT stride);
    HRESULT SetIndices(IDirect3DIndexBuffer9* ib);
    HRESULT DrawPrimitive(D3DPRIMITIVETYPE type, UINT startVertex, UINT primCount);
    HRESULT DrawIndexedPrimitive(D3DPRIMITIVETYPE type, INT baseVertex,
                                 UINT minIndex, UINT numVerts,
                                 UINT startIndex, UINT primCount);
    HRESULT DrawPrimitiveUP(D3DPRIMITIVETYPE type, UINT primCount,
                            const void* data, UINT stride);

    // ── Viewport ─────────────────────────────────────────────────────────────
    HRESULT SetViewport(const D3DVIEWPORT9* vp);
    HRESULT GetViewport(D3DVIEWPORT9* vp);

    // ── Caps ─────────────────────────────────────────────────────────────────
    HRESULT GetDeviceCaps(D3DCAPS9* caps);
    HRESULT GetDisplayMode(UINT adapter, D3DDISPLAYMODE* mode);
    HRESULT GetBackBuffer(UINT swap, UINT idx, DWORD type, IDirect3DTexture9** ppSurf);

    // ── Uniform buffer helpers (called by MilkDropUniforms uploading code) ───
    MilkDropUniforms& GetUniforms() { return m_uniforms; }
    void              MarkUniformsDirty() { m_uniformsDirty = true; }

    // ── Accessors for the Metal objects ──────────────────────────────────────
#ifdef __OBJC__
    id<MTLDevice>             GetMTLDevice()  const { return m_device; }
    id<MTLCommandQueue>       GetCmdQueue()   const { return m_queue; }
    id<MTLRenderCommandEncoder> GetEncoder()  const { return m_encoder; }
    id<MTLLibrary>            GetBaseLib()    const { return m_baseLib; }
#endif

    int  GetWidth()  const { return m_width; }
    int  GetHeight() const { return m_height; }

private:
#ifdef __OBJC__
    id<MTLDevice>               m_device       = nil;
    id<MTLCommandQueue>         m_queue        = nil;
    id<MTLCommandBuffer>        m_cmdBuf       = nil;
    id<MTLRenderCommandEncoder> m_encoder      = nil;
    id<MTLLibrary>              m_baseLib      = nil;   // pre-compiled milkdrop_base.metallib
    MTLRenderPassDescriptor*    m_passDesc     = nil;
    id<MTLTexture>              m_depthTex     = nil;

    // Active textures per stage
    id<MTLTexture>              m_textures[16] = {};
    id<MTLSamplerState>         m_samplers[16] = {};

    // Current PSO cache
    id<MTLRenderPipelineState>  m_pso          = nil;
    id<MTLDepthStencilState>    m_dss          = nil;

    // Active shaders
    id<MTLFunction>             m_vertFn       = nil;
    id<MTLFunction>             m_fragFn       = nil;

    // Streams
    id<MTLBuffer>               m_streamBuf    = nil;
    UINT                        m_streamOffset = 0;
    UINT                        m_streamStride = 0;
    id<MTLBuffer>               m_indexBuf     = nil;

    // Constant / uniform buffer
    id<MTLBuffer>               m_uniformBuf   = nil;
#endif

    MilkDropUniforms m_uniforms     = {};
    bool             m_uniformsDirty = true;
    RenderStateCache m_rs;
    D3DVIEWPORT9     m_viewport     = {};
    int              m_width        = 0;
    int              m_height       = 0;

    void RebuildPipelineIfNeeded();
    void UploadUniforms();

#ifdef __OBJC__
    id<MTLRenderPipelineState> BuildPSO();
    id<MTLDepthStencilState>   BuildDSS();
    id<MTLSamplerState>        BuildSampler(D3DTEXTUREADDRESS addr,
                                            D3DTEXTUREFILTERTYPE min,
                                            D3DTEXTUREFILTERTYPE mag);
#endif

    // Sampler state per-stage
    struct SamplerDesc {
        DWORD addressU  = D3DTADDRESS_WRAP;
        DWORD addressV  = D3DTADDRESS_WRAP;
        DWORD minFilter = D3DTEXF_LINEAR;
        DWORD magFilter = D3DTEXF_LINEAR;
    } m_samplerDesc[16];
};
