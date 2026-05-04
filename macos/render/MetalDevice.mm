/**
 * MetalDevice.mm
 *
 * IDirect3DDevice9 implementation using Metal.
 */

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

#include "MetalDevice.h"
#include <cassert>
#include <cstring>
#include <cstdio>

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────
static MTLPixelFormat D3DFormatToMTL(D3DFORMAT fmt) {
    switch (fmt) {
        case D3DFMT_A8R8G8B8:
        case D3DFMT_X8R8G8B8:  return MTLPixelFormatBGRA8Unorm;
        case D3DFMT_A16B16G16R16F: return MTLPixelFormatRGBA16Float;
        case D3DFMT_A32B32G32R32F: return MTLPixelFormatRGBA32Float;
        case D3DFMT_R16F:       return MTLPixelFormatR16Float;
        case D3DFMT_G16R16F:    return MTLPixelFormatRG16Float;
        case D3DFMT_R32F:       return MTLPixelFormatR32Float;
        default:                return MTLPixelFormatBGRA8Unorm;
    }
}

static MTLBlendFactor D3DBlendToMTL(DWORD d) {
    switch (d) {
        case D3DBLEND_ZERO:        return MTLBlendFactorZero;
        case D3DBLEND_ONE:         return MTLBlendFactorOne;
        case D3DBLEND_SRCALPHA:    return MTLBlendFactorSourceAlpha;
        case D3DBLEND_INVSRCALPHA: return MTLBlendFactorOneMinusSourceAlpha;
        case D3DBLEND_DESTALPHA:   return MTLBlendFactorDestinationAlpha;
        case D3DBLEND_INVDESTALPHA:return MTLBlendFactorOneMinusDestinationAlpha;
        case D3DBLEND_DESTCOLOR:   return MTLBlendFactorDestinationColor;
        case D3DBLEND_INVDESTCOLOR:return MTLBlendFactorOneMinusDestinationColor;
        case D3DBLEND_SRCALPHASAT: return MTLBlendFactorSourceAlphaSaturated;
        default:                   return MTLBlendFactorOne;
    }
}

static MTLBlendOperation D3DBlendOpToMTL(DWORD d) {
    switch (d) {
        case D3DBLENDOP_ADD:         return MTLBlendOperationAdd;
        case D3DBLENDOP_SUBTRACT:    return MTLBlendOperationSubtract;
        case D3DBLENDOP_REVSUBTRACT: return MTLBlendOperationReverseSubtract;
        case D3DBLENDOP_MIN:         return MTLBlendOperationMin;
        case D3DBLENDOP_MAX:         return MTLBlendOperationMax;
        default:                     return MTLBlendOperationAdd;
    }
}

static MTLPrimitiveType D3DPrimToMTL(D3DPRIMITIVETYPE t) {
    switch (t) {
        case D3DPT_POINTLIST:     return MTLPrimitiveTypePoint;
        case D3DPT_LINELIST:      return MTLPrimitiveTypeLine;
        case D3DPT_LINESTRIP:     return MTLPrimitiveTypeLineStrip;
        case D3DPT_TRIANGLELIST:  return MTLPrimitiveTypeTriangle;
        case D3DPT_TRIANGLESTRIP: return MTLPrimitiveTypeTriangleStrip;
        default:                  return MTLPrimitiveTypeTriangle;
    }
}

static NSUInteger PrimCountToVertexCount(D3DPRIMITIVETYPE t, UINT prims) {
    switch (t) {
        case D3DPT_POINTLIST:     return prims;
        case D3DPT_LINELIST:      return prims * 2;
        case D3DPT_LINESTRIP:     return prims + 1;
        case D3DPT_TRIANGLELIST:  return prims * 3;
        case D3DPT_TRIANGLESTRIP: return prims + 2;
        case D3DPT_TRIANGLEFAN:   return prims + 2;
        default:                  return prims * 3;
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MetalTexture
// ──────────────────────────────────────────────────────────────────────────────
void MetalTexture::Release() { delete this; }
MetalTexture::~MetalTexture() { tex = nil; samp = nil; }

// ──────────────────────────────────────────────────────────────────────────────
// MetalVertexBuffer
// ──────────────────────────────────────────────────────────────────────────────
HRESULT MetalVertexBuffer::Lock(UINT offsetBytes, UINT, void** ppData, DWORD) {
    mapped = (uint8_t*)buf.contents + offsetBytes;
    *ppData = mapped;
    return S_OK;
}
HRESULT MetalVertexBuffer::Unlock() { return S_OK; }
void    MetalVertexBuffer::Release() { delete this; }
MetalVertexBuffer::~MetalVertexBuffer() { buf = nil; }

// ──────────────────────────────────────────────────────────────────────────────
// MetalIndexBuffer
// ──────────────────────────────────────────────────────────────────────────────
HRESULT MetalIndexBuffer::Lock(UINT offsetBytes, UINT, void** ppData, DWORD) {
    *ppData = (uint8_t*)buf.contents + offsetBytes;
    return S_OK;
}
HRESULT MetalIndexBuffer::Unlock() { return S_OK; }
void    MetalIndexBuffer::Release() { delete this; }
MetalIndexBuffer::~MetalIndexBuffer() { buf = nil; }

// ──────────────────────────────────────────────────────────────────────────────
// MetalPixelShader / MetalVertexShader
// ──────────────────────────────────────────────────────────────────────────────
void MetalPixelShader::Release()  { delete this; }
MetalPixelShader::~MetalPixelShader()  { fn = nil; lib = nil; }
void MetalVertexShader::Release() { delete this; }
MetalVertexShader::~MetalVertexShader() { fn = nil; lib = nil; }

// ──────────────────────────────────────────────────────────────────────────────
// IDirect3DDevice9
// ──────────────────────────────────────────────────────────────────────────────
IDirect3DDevice9::IDirect3DDevice9() {
    m_device = MTLCreateSystemDefaultDevice();
    assert(m_device && "Metal device creation failed – GPU not available?");
    m_queue = [m_device newCommandQueue];

    // Load the pre-compiled base Metal library
    NSString* libPath = [[NSBundle mainBundle]
                          pathForResource:@"milkdrop_base" ofType:@"metallib"];
    if (libPath) {
        NSError* err = nil;
        m_baseLib = [m_device newLibraryWithFile:libPath error:&err];
        if (err) NSLog(@"[MetalDevice] Failed to load metallib: %@", err);
    }
    if (!m_baseLib) {
        // Fallback: compile from source at runtime (slower, dev mode only)
        NSLog(@"[MetalDevice] WARNING: milkdrop_base.metallib not found; "
               "shaders will be compiled at runtime.");
    }

    // Allocate a persistent uniform buffer (triple-buffered in production;
    // single for simplicity here).
    m_uniformBuf = [m_device newBufferWithLength:sizeof(MilkDropUniforms) * 3
                                         options:MTLResourceStorageModeShared];
    m_uniformBuf.label = @"MilkDropUniforms";
}

IDirect3DDevice9::~IDirect3DDevice9() {}

void IDirect3DDevice9::BeginFrame(id<CAMetalDrawable> drawable, MTKView* view) {
    m_width  = (int)view.drawableSize.width;
    m_height = (int)view.drawableSize.height;

    // Recreate depth texture if resolution changed
    if (!m_depthTex ||
        (int)m_depthTex.width  != m_width ||
        (int)m_depthTex.height != m_height)
    {
        MTLTextureDescriptor* dd = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
            width:m_width height:m_height mipmapped:NO];
        dd.usage = MTLTextureUsageRenderTarget;
        dd.storageMode = MTLStorageModePrivate;
        m_depthTex = [m_device newTextureWithDescriptor:dd];
    }

    m_cmdBuf = [m_queue commandBuffer];

    m_passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    m_passDesc.colorAttachments[0].texture     = drawable.texture;
    m_passDesc.colorAttachments[0].loadAction  = MTLLoadActionClear;
    m_passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    m_passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(0,0,0,1);
    m_passDesc.depthAttachment.texture         = m_depthTex;
    m_passDesc.depthAttachment.loadAction      = MTLLoadActionClear;
    m_passDesc.depthAttachment.storeAction     = MTLStoreActionDontCare;
    m_passDesc.depthAttachment.clearDepth      = 1.0;

    m_encoder = [m_cmdBuf renderCommandEncoderWithDescriptor:m_passDesc];
    m_encoder.label = @"MilkDropFrame";

    // Set default viewport
    m_viewport = { 0, 0, (DWORD)m_width, (DWORD)m_height, 0.0f, 1.0f };
    MTLViewport vp = { 0, 0, (double)m_width, (double)m_height, 0.0, 1.0 };
    [m_encoder setViewport:vp];
}

void IDirect3DDevice9::EndFrame() {
    [m_encoder endEncoding];
    m_encoder = nil;
}

// ── Clear ─────────────────────────────────────────────────────────────────────
HRESULT IDirect3DDevice9::Clear(DWORD, const void*, DWORD, D3DCOLOR color,
                                  float z, DWORD) {
    // Clear is handled via render pass load action – update the clear color.
    float a = ((color >> 24) & 0xFF) / 255.0f;
    float r = ((color >> 16) & 0xFF) / 255.0f;
    float g = ((color >>  8) & 0xFF) / 255.0f;
    float b = ((color      ) & 0xFF) / 255.0f;
    if (m_passDesc)
        m_passDesc.colorAttachments[0].clearColor = MTLClearColorMake(r,g,b,a);
    return S_OK;
}

HRESULT IDirect3DDevice9::BeginScene() { return S_OK; }
HRESULT IDirect3DDevice9::EndScene()   { return S_OK; }
HRESULT IDirect3DDevice9::Present(const RECT*, const RECT*, HWND, const void*) {
    // Actual present is driven by the MTKView delegate in AppDelegate.mm
    return S_OK;
}

// ── Render state ──────────────────────────────────────────────────────────────
HRESULT IDirect3DDevice9::SetRenderState(D3DRENDERSTATETYPE state, DWORD value) {
    switch (state) {
        case D3DRS_ALPHABLENDENABLE: m_rs.alphaBlend = (value != 0); m_rs.dirty = true; break;
        case D3DRS_SRCBLEND:         m_rs.srcBlend   = value; m_rs.dirty = true; break;
        case D3DRS_DESTBLEND:        m_rs.dstBlend   = value; m_rs.dirty = true; break;
        case D3DRS_BLENDOP:          m_rs.blendOp    = value; m_rs.dirty = true; break;
        case D3DRS_ZENABLE:          m_rs.zEnable    = (value != 0); m_rs.dirty = true; break;
        case D3DRS_ZWRITEENABLE:     m_rs.zWrite     = (value != 0); m_rs.dirty = true; break;
        case D3DRS_CULLMODE:         m_rs.cullMode   = value; m_rs.dirty = true;
            [m_encoder setCullMode:(value == D3DCULL_CW  ? MTLCullModeFront :
                                    value == D3DCULL_CCW ? MTLCullModeBack  :
                                                           MTLCullModeNone)];
            break;
        case D3DRS_FILLMODE:
            [m_encoder setTriangleFillMode:
                (value == D3DFILL_WIREFRAME ? MTLTriangleFillModeLines
                                            : MTLTriangleFillModeFill)];
            break;
        default: break; // silently ignore unused states
    }
    return S_OK;
}

HRESULT IDirect3DDevice9::GetRenderState(D3DRENDERSTATETYPE state, DWORD* out) {
    if (!out) return E_POINTER;
    switch (state) {
        case D3DRS_ALPHABLENDENABLE: *out = m_rs.alphaBlend; break;
        case D3DRS_SRCBLEND:         *out = m_rs.srcBlend;   break;
        case D3DRS_DESTBLEND:        *out = m_rs.dstBlend;   break;
        default: *out = 0; break;
    }
    return S_OK;
}

HRESULT IDirect3DDevice9::SetTextureStageState(DWORD, D3DTEXTURESTAGESTATETYPE, DWORD) {
    return S_OK; // fixed-function pipeline not used with shaders
}

HRESULT IDirect3DDevice9::SetSamplerState(DWORD stage, D3DSAMPLERSTATETYPE type, DWORD value) {
    if (stage >= 16) return E_FAIL;
    auto& sd = m_samplerDesc[stage];
    switch (type) {
        case D3DSAMP_ADDRESSU:  sd.addressU  = value; break;
        case D3DSAMP_ADDRESSV:  sd.addressV  = value; break;
        case D3DSAMP_MINFILTER: sd.minFilter = value; break;
        case D3DSAMP_MAGFILTER: sd.magFilter = value; break;
        default: break;
    }
    // Rebuild sampler
    m_samplers[stage] = BuildSampler((D3DTEXTUREADDRESS)sd.addressU,
                                     (D3DTEXTUREFILTERTYPE)sd.minFilter,
                                     (D3DTEXTUREFILTERTYPE)sd.magFilter);
    return S_OK;
}

// ── Textures ──────────────────────────────────────────────────────────────────
HRESULT IDirect3DDevice9::SetTexture(DWORD stage, IDirect3DTexture9* tex) {
    if (stage >= 16) return E_FAIL;
    auto* mt = static_cast<MetalTexture*>(tex);
    m_textures[stage] = mt ? mt->tex  : nil;
    m_samplers[stage] = mt ? mt->samp : nil;
    if (m_encoder) {
        [m_encoder setFragmentTexture:m_textures[stage] atIndex:stage];
        [m_encoder setFragmentSamplerState:m_samplers[stage] atIndex:stage];
    }
    return S_OK;
}

HRESULT IDirect3DDevice9::CreateTexture(UINT w, UINT h, UINT levels, DWORD usage,
                                          D3DFORMAT fmt, DWORD, IDirect3DTexture9** ppTex,
                                          HANDLE*)
{
    auto* mt = new MetalTexture();
    MTLTextureDescriptor* td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:D3DFormatToMTL(fmt)
        width:w height:h mipmapped:(levels != 1)];

    // Determine usage flags
    bool isRT = (usage & 1); // D3DUSAGE_RENDERTARGET = 1
    if (isRT) {
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModePrivate;
    } else {
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        td.storageMode = MTLStorageModeShared;
    }
    mt->tex   = [m_device newTextureWithDescriptor:td];
    mt->img_w = w;
    mt->img_h = h;
    mt->samp  = BuildSampler(D3DTADDRESS_WRAP, D3DTEXF_LINEAR, D3DTEXF_LINEAR);
    *ppTex = mt;
    return S_OK;
}

HRESULT IDirect3DDevice9::CreateRenderTarget(UINT w, UINT h, D3DFORMAT fmt,
                                               D3DMULTISAMPLE_TYPE, DWORD, BOOL,
                                               IDirect3DTexture9** ppSurf, HANDLE*)
{
    return CreateTexture(w, h, 1, 1 /*D3DUSAGE_RENDERTARGET*/, fmt, 0, ppSurf, nullptr);
}

// ── Shaders ───────────────────────────────────────────────────────────────────
HRESULT IDirect3DDevice9::SetVertexShader(IDirect3DVertexShader9* vs) {
    m_vertFn = vs ? static_cast<MetalVertexShader*>(vs)->fn : nil;
    m_rs.dirty = true;
    return S_OK;
}
HRESULT IDirect3DDevice9::SetPixelShader(IDirect3DPixelShader9* ps) {
    m_fragFn = ps ? static_cast<MetalPixelShader*>(ps)->fn : nil;
    m_rs.dirty = true;
    return S_OK;
}

HRESULT IDirect3DDevice9::SetVertexShaderConstantF(UINT start, const float* data, UINT count) {
    // Copy into uniform buffer: maps to constant registers c[start]..c[start+count-1]
    // We reuse the MilkDropUniforms.c[] array for the _c0-_c13 range.
    for (UINT i = 0; i < count && (start + i) < 14; ++i)
        memcpy(m_uniforms.c[start + i], data + i * 4, 16);
    m_uniformsDirty = true;
    return S_OK;
}

HRESULT IDirect3DDevice9::SetPixelShaderConstantF(UINT start, const float* data, UINT count) {
    for (UINT i = 0; i < count && (start + i) < 14; ++i)
        memcpy(m_uniforms.c[start + i], data + i * 4, 16);
    m_uniformsDirty = true;
    return S_OK;
}

// ── Buffers ───────────────────────────────────────────────────────────────────
HRESULT IDirect3DDevice9::CreateVertexBuffer(UINT bytes, DWORD, DWORD, DWORD,
                                               IDirect3DVertexBuffer9** ppVB, HANDLE*)
{
    auto* vb = new MetalVertexBuffer();
    vb->buf  = [m_device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    vb->size = bytes;
    *ppVB = vb;
    return S_OK;
}

HRESULT IDirect3DDevice9::CreateIndexBuffer(UINT bytes, DWORD, D3DFORMAT, DWORD,
                                              IDirect3DIndexBuffer9** ppIB, HANDLE*)
{
    auto* ib = new MetalIndexBuffer();
    ib->buf  = [m_device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    ib->size = bytes;
    *ppIB = ib;
    return S_OK;
}

HRESULT IDirect3DDevice9::SetVertexDeclaration(IDirect3DVertexDeclaration9*) { return S_OK; }
HRESULT IDirect3DDevice9::CreateVertexDeclaration(const D3DVERTEXELEMENT9*,
                                                    IDirect3DVertexDeclaration9** ppDecl)
{
    *ppDecl = nullptr; // handled via Metal vertex descriptors in the PSO
    return S_OK;
}

HRESULT IDirect3DDevice9::SetStreamSource(UINT stream, IDirect3DVertexBuffer9* vb,
                                           UINT offset, UINT stride)
{
    if (stream != 0) return S_OK;
    m_streamBuf    = vb ? static_cast<MetalVertexBuffer*>(vb)->buf : nil;
    m_streamOffset = offset;
    m_streamStride = stride;
    return S_OK;
}

HRESULT IDirect3DDevice9::SetIndices(IDirect3DIndexBuffer9* ib) {
    m_indexBuf = ib ? static_cast<MetalIndexBuffer*>(ib)->buf : nil;
    return S_OK;
}

// ── Draw calls ────────────────────────────────────────────────────────────────
void IDirect3DDevice9::RebuildPipelineIfNeeded() {
    if (!m_rs.dirty) return;
    m_pso = BuildPSO();
    m_dss = BuildDSS();
    [m_encoder setRenderPipelineState:m_pso];
    [m_encoder setDepthStencilState:m_dss];
    m_rs.dirty = false;
}

void IDirect3DDevice9::UploadUniforms() {
    if (!m_uniformsDirty) return;
    memcpy(m_uniformBuf.contents, &m_uniforms, sizeof(MilkDropUniforms));
    [m_encoder setVertexBuffer:m_uniformBuf   offset:0 atIndex:1];
    [m_encoder setFragmentBuffer:m_uniformBuf offset:0 atIndex:1];
    m_uniformsDirty = false;
}

HRESULT IDirect3DDevice9::DrawPrimitive(D3DPRIMITIVETYPE type, UINT startVertex, UINT primCount) {
    RebuildPipelineIfNeeded();
    UploadUniforms();
    [m_encoder setVertexBuffer:m_streamBuf offset:m_streamOffset atIndex:0];
    [m_encoder drawPrimitives:D3DPrimToMTL(type)
                  vertexStart:startVertex
                  vertexCount:PrimCountToVertexCount(type, primCount)];
    return S_OK;
}

HRESULT IDirect3DDevice9::DrawIndexedPrimitive(D3DPRIMITIVETYPE type, INT baseVertex,
                                                 UINT, UINT, UINT startIndex, UINT primCount)
{
    RebuildPipelineIfNeeded();
    UploadUniforms();
    [m_encoder setVertexBuffer:m_streamBuf offset:m_streamOffset atIndex:0];
    [m_encoder drawIndexedPrimitives:D3DPrimToMTL(type)
                          indexCount:PrimCountToVertexCount(type, primCount)
                           indexType:MTLIndexTypeUInt16
                         indexBuffer:m_indexBuf
                   indexBufferOffset:startIndex * 2
                       instanceCount:1
                          baseVertex:baseVertex
                        baseInstance:0];
    return S_OK;
}

HRESULT IDirect3DDevice9::DrawPrimitiveUP(D3DPRIMITIVETYPE type, UINT primCount,
                                           const void* data, UINT stride)
{
    NSUInteger vcount = PrimCountToVertexCount(type, primCount);
    NSUInteger bytes  = vcount * stride;
    id<MTLBuffer> tmp = [m_device newBufferWithBytes:data
                                              length:bytes
                                             options:MTLResourceStorageModeShared];
    RebuildPipelineIfNeeded();
    UploadUniforms();
    [m_encoder setVertexBuffer:tmp offset:0 atIndex:0];
    [m_encoder drawPrimitives:D3DPrimToMTL(type) vertexStart:0 vertexCount:vcount];
    return S_OK;
}

// ── Viewport ──────────────────────────────────────────────────────────────────
HRESULT IDirect3DDevice9::SetViewport(const D3DVIEWPORT9* vp) {
    if (!vp) return E_POINTER;
    m_viewport = *vp;
    MTLViewport mv = {
        (double)vp->X, (double)vp->Y,
        (double)vp->Width, (double)vp->Height,
        (double)vp->MinZ, (double)vp->MaxZ
    };
    [m_encoder setViewport:mv];
    return S_OK;
}
HRESULT IDirect3DDevice9::GetViewport(D3DVIEWPORT9* vp) {
    if (!vp) return E_POINTER;
    *vp = m_viewport;
    return S_OK;
}

// ── Caps ──────────────────────────────────────────────────────────────────────
HRESULT IDirect3DDevice9::GetDeviceCaps(D3DCAPS9* caps) {
    memset(caps, 0, sizeof(*caps));
    caps->MaxTextureWidth  = 16384;
    caps->MaxTextureHeight = 16384;
    caps->PixelShaderVersion  = 0x0300; // ps_3_0
    caps->VertexShaderVersion = 0x0300; // vs_3_0
    return S_OK;
}

HRESULT IDirect3DDevice9::GetDisplayMode(UINT, D3DDISPLAYMODE* mode) {
    if (!mode) return E_POINTER;
    mode->Width       = m_width;
    mode->Height      = m_height;
    mode->RefreshRate = 60;
    mode->Format      = D3DFMT_A8R8G8B8;
    return S_OK;
}

HRESULT IDirect3DDevice9::GetBackBuffer(UINT, UINT, DWORD, IDirect3DTexture9** ppSurf) {
    // Return a placeholder; the back buffer is managed by the CAMetalLayer.
    *ppSurf = nullptr;
    return S_OK;
}

// ── Pipeline state builder ────────────────────────────────────────────────────
id<MTLRenderPipelineState> IDirect3DDevice9::BuildPSO() {
    MTLRenderPipelineDescriptor* pd = [MTLRenderPipelineDescriptor new];

    // Use warp_vert / warp_frag from the base library as defaults
    // (preset-specific shaders override these via SetVertexShader / SetPixelShader)
    pd.vertexFunction   = m_vertFn ?: [m_baseLib newFunctionWithName:@"warp_vert"];
    pd.fragmentFunction = m_fragFn ?: [m_baseLib newFunctionWithName:@"warp_frag"];

    auto* ca = pd.colorAttachments[0];
    ca.pixelFormat           = MTLPixelFormatBGRA8Unorm;
    ca.blendingEnabled       = m_rs.alphaBlend;
    ca.sourceRGBBlendFactor      = D3DBlendToMTL(m_rs.srcBlend);
    ca.destinationRGBBlendFactor  = D3DBlendToMTL(m_rs.dstBlend);
    ca.rgbBlendOperation         = D3DBlendOpToMTL(m_rs.blendOp);
    ca.sourceAlphaBlendFactor    = D3DBlendToMTL(m_rs.srcBlend);
    ca.destinationAlphaBlendFactor= D3DBlendToMTL(m_rs.dstBlend);
    ca.alphaBlendOperation       = D3DBlendOpToMTL(m_rs.blendOp);

    pd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    NSError* err = nil;
    id<MTLRenderPipelineState> pso = [m_device newRenderPipelineStateWithDescriptor:pd
                                                                              error:&err];
    if (err) NSLog(@"[MetalDevice] PSO build error: %@", err);
    return pso;
}

id<MTLDepthStencilState> IDirect3DDevice9::BuildDSS() {
    MTLDepthStencilDescriptor* dd = [MTLDepthStencilDescriptor new];
    dd.depthCompareFunction = m_rs.zEnable  ? MTLCompareFunctionLess
                                            : MTLCompareFunctionAlways;
    dd.depthWriteEnabled    = m_rs.zWrite;
    return [m_device newDepthStencilStateWithDescriptor:dd];
}

id<MTLSamplerState> IDirect3DDevice9::BuildSampler(D3DTEXTUREADDRESS addr,
                                                     D3DTEXTUREFILTERTYPE minF,
                                                     D3DTEXTUREFILTERTYPE magF)
{
    auto addrMode = [](D3DTEXTUREADDRESS a) -> MTLSamplerAddressMode {
        switch (a) {
            case D3DTADDRESS_CLAMP:  return MTLSamplerAddressModeClampToEdge;
            case D3DTADDRESS_MIRROR: return MTLSamplerAddressModeMirrorRepeat;
            default:                 return MTLSamplerAddressModeRepeat;
        }
    };
    auto filterMode = [](D3DTEXTUREFILTERTYPE f) -> MTLSamplerMinMagFilter {
        return (f == D3DTEXF_POINT) ? MTLSamplerMinMagFilterNearest
                                    : MTLSamplerMinMagFilterLinear;
    };
    MTLSamplerDescriptor* sd = [MTLSamplerDescriptor new];
    sd.sAddressMode = addrMode(addr);
    sd.tAddressMode = addrMode(addr);
    sd.minFilter    = filterMode(minF);
    sd.magFilter    = filterMode(magF);
    sd.mipFilter    = MTLSamplerMipFilterLinear;
    return [m_device newSamplerStateWithDescriptor:sd];
}
