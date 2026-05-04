/**
 * d3d_compat.h
 *
 * Stubs for Direct3D 9 / D3DX types and enums.
 *
 * Strategy:
 *   - D3DX math types (D3DXVECTOR3, D3DXMATRIX, etc.) are aliased to GLM
 *     equivalents so existing arithmetic code compiles unchanged.
 *   - D3D device / resource types are forward-declared as opaque classes
 *     that are implemented by the Metal backend (MetalDevice.h).
 *   - Enums and flags are defined with the same numeric values as the
 *     original D3D9 headers wherever the values matter at runtime.
 */

#pragma once

#include "win32_compat.h"

// ── GLM math (replaces d3dx9math) ────────────────────────────────────────────
#define GLM_FORCE_RADIANS
#define GLM_FORCE_DEFAULT_ALIGNED_GENTYPES
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <glm/gtx/euler_angles.hpp>

// D3DX math type aliases
typedef glm::vec2   D3DXVECTOR2;
typedef glm::vec3   D3DXVECTOR3;
typedef glm::vec4   D3DXVECTOR4;
typedef glm::mat4   D3DXMATRIX;
typedef glm::mat4x3 D3DXMATRIX4X3; // used for rot_s1 etc. (float4x3 in HLSL)

// D3DCOLOR is packed ARGB (0xAARRGGBB)
typedef DWORD D3DCOLOR;

#define D3DCOLOR_ARGB(a,r,g,b) \
    ((D3DCOLOR)(((DWORD)(a)<<24)|((DWORD)(r)<<16)|((DWORD)(g)<<8)|(DWORD)(b)))
#define D3DCOLOR_RGBA(r,g,b,a) D3DCOLOR_ARGB(a,r,g,b)
#define D3DCOLOR_XRGB(r,g,b)   D3DCOLOR_ARGB(0xFF,r,g,b)

// ── D3DFORMAT ────────────────────────────────────────────────────────────────
typedef enum _D3DFORMAT {
    D3DFMT_UNKNOWN    = 0,
    D3DFMT_R8G8B8     = 20,
    D3DFMT_A8R8G8B8   = 21,
    D3DFMT_X8R8G8B8   = 22,
    D3DFMT_R5G6B5     = 23,
    D3DFMT_A1R5G5B5   = 25,
    D3DFMT_A4R4G4B4   = 26,
    D3DFMT_D16        = 80,
    D3DFMT_D24X8      = 77,
    D3DFMT_D24S8      = 75,
    D3DFMT_D32        = 71,
    D3DFMT_A32B32G32R32F = 116,
    D3DFMT_A16B16G16R16F = 113,
    D3DFMT_R32F       = 114,
    D3DFMT_G16R16F    = 112,
    D3DFMT_R16F       = 111,
} D3DFORMAT;

// ── D3DMULTISAMPLE_TYPE ───────────────────────────────────────────────────────
typedef enum _D3DMULTISAMPLE_TYPE {
    D3DMULTISAMPLE_NONE       = 0,
    D3DMULTISAMPLE_2_SAMPLES  = 2,
    D3DMULTISAMPLE_4_SAMPLES  = 4,
    D3DMULTISAMPLE_8_SAMPLES  = 8,
} D3DMULTISAMPLE_TYPE;

// ── D3DDISPLAYMODE ────────────────────────────────────────────────────────────
typedef struct _D3DDISPLAYMODE {
    UINT        Width;
    UINT        Height;
    UINT        RefreshRate;
    D3DFORMAT   Format;
} D3DDISPLAYMODE;

// ── D3DPRESENT_PARAMETERS ────────────────────────────────────────────────────
typedef struct _D3DPRESENT_PARAMETERS {
    UINT                BackBufferWidth;
    UINT                BackBufferHeight;
    D3DFORMAT           BackBufferFormat;
    UINT                BackBufferCount;
    D3DMULTISAMPLE_TYPE MultiSampleType;
    DWORD               MultiSampleQuality;
    UINT                SwapEffect;
    HWND                hDeviceWindow;
    BOOL                Windowed;
    BOOL                EnableAutoDepthStencil;
    D3DFORMAT           AutoDepthStencilFormat;
    DWORD               Flags;
    UINT                FullScreen_RefreshRateInHz;
    UINT                PresentationInterval;
} D3DPRESENT_PARAMETERS;

// Present interval flags
#define D3DPRESENT_INTERVAL_DEFAULT  0x00000000
#define D3DPRESENT_INTERVAL_ONE      0x00000001
#define D3DPRESENT_INTERVAL_IMMEDIATE 0x80000000

// SwapEffect
#define D3DSWAPEFFECT_DISCARD 1
#define D3DSWAPEFFECT_FLIP    2
#define D3DSWAPEFFECT_COPY    3

// ── D3DCAPS9 ─────────────────────────────────────────────────────────────────
typedef struct _D3DCAPS9 {
    DWORD DeviceType;
    UINT  AdapterOrdinal;
    DWORD Caps;
    DWORD Caps2;
    DWORD MaxTextureWidth;
    DWORD MaxTextureHeight;
    DWORD MaxTextureAspectRatio;
    DWORD MaxAnisotropy;
    float MaxPixelShaderValue;
    DWORD PixelShaderVersion;
    DWORD VertexShaderVersion;
    // ... add more fields as needed
} D3DCAPS9;

// ── D3DVIEWPORT9 ──────────────────────────────────────────────────────────────
typedef struct _D3DVIEWPORT9 {
    DWORD X, Y, Width, Height;
    float MinZ, MaxZ;
} D3DVIEWPORT9;

// ── D3DXFONT: lightweight text rendering wrapper ──────────────────────────────
// We replace D3DX font rendering with CoreText / SDL_ttf.
// The interface is kept minimal; only DrawText is used.
struct ID3DXFont {
    virtual int DrawTextW(void* pSprite, const wchar_t* text, int count,
                          RECT* pRect, DWORD format, D3DCOLOR color) = 0;
    virtual void Release() = 0;
    virtual ~ID3DXFont() {}
};
typedef ID3DXFont* LPD3DXFONT;

// DrawText flags (subset)
#define DT_LEFT         0x00000000
#define DT_CENTER       0x00000001
#define DT_RIGHT        0x00000002
#define DT_TOP          0x00000000
#define DT_VCENTER      0x00000004
#define DT_BOTTOM       0x00000008
#define DT_WORDBREAK    0x00000010
#define DT_SINGLELINE   0x00000020
#define DT_NOCLIP       0x00000100
#define DT_CALCRECT     0x00000400

// ── D3DXSPRITE stub ─────────────────────────────────────────────────────────
struct ID3DXSprite { virtual void Release() = 0; virtual ~ID3DXSprite() {} };
typedef ID3DXSprite* LPD3DXSPRITE;

// ── IDirect3DTexture9 ─────────────────────────────────────────────────────────
// Implemented in MetalTexture.h/.mm
struct IDirect3DTexture9 {
    virtual void Release() = 0;
    virtual ~IDirect3DTexture9() {}
};
typedef IDirect3DTexture9* LPDIRECT3DTEXTURE9;

// ── IDirect3DVertexBuffer9 ────────────────────────────────────────────────────
struct IDirect3DVertexBuffer9 {
    virtual HRESULT Lock(UINT offsetBytes, UINT sizeBytes, void** ppData, DWORD flags) = 0;
    virtual HRESULT Unlock() = 0;
    virtual void    Release() = 0;
    virtual ~IDirect3DVertexBuffer9() {}
};
typedef IDirect3DVertexBuffer9* LPDIRECT3DVERTEXBUFFER9;

// ── IDirect3DIndexBuffer9 ────────────────────────────────────────────────────
struct IDirect3DIndexBuffer9 {
    virtual HRESULT Lock(UINT offsetBytes, UINT sizeBytes, void** ppData, DWORD flags) = 0;
    virtual HRESULT Unlock() = 0;
    virtual void    Release() = 0;
    virtual ~IDirect3DIndexBuffer9() {}
};
typedef IDirect3DIndexBuffer9* LPDIRECT3DINDEXBUFFER9;

// ── IDirect3DPixelShader9 / IDirect3DVertexShader9 ────────────────────────────
struct IDirect3DPixelShader9  { virtual void Release() = 0; virtual ~IDirect3DPixelShader9()  {} };
struct IDirect3DVertexShader9 { virtual void Release() = 0; virtual ~IDirect3DVertexShader9() {} };
typedef IDirect3DPixelShader9*  LPDIRECT3DPIXELSHADER9;
typedef IDirect3DVertexShader9* LPDIRECT3DVERTEXSHADER9;

// ── IDirect3DVertexDeclaration9 ───────────────────────────────────────────────
struct IDirect3DVertexDeclaration9 { virtual void Release() = 0; virtual ~IDirect3DVertexDeclaration9() {} };
typedef IDirect3DVertexDeclaration9* LPDIRECT3DVERTEXDECLARATION9;

// ── D3DVERTEXELEMENT9 ─────────────────────────────────────────────────────────
typedef struct _D3DVERTEXELEMENT9 {
    WORD Stream, Offset;
    BYTE Type, Method, Usage, UsageIndex;
} D3DVERTEXELEMENT9;
#define D3DDECL_END() {0xFF,0,0,0,0,0}

// D3DDECLTYPE values
#define D3DDECLTYPE_FLOAT1   0
#define D3DDECLTYPE_FLOAT2   1
#define D3DDECLTYPE_FLOAT3   2
#define D3DDECLTYPE_FLOAT4   3
#define D3DDECLTYPE_D3DCOLOR 4
#define D3DDECLTYPE_UBYTE4   5

// D3DDECLUSAGE values
#define D3DDECLUSAGE_POSITION   0
#define D3DDECLUSAGE_BLENDWEIGHT 1
#define D3DDECLUSAGE_COLOR      3
#define D3DDECLUSAGE_TEXCOORD   5

// ── IDirect3DDevice9 ─────────────────────────────────────────────────────────
// Forward-declared; full definition in MetalDevice.h.
// The existing code uses this through GetDevice() which returns a pointer.
class  IDirect3DDevice9;
typedef IDirect3DDevice9* LPDIRECT3DDEVICE9;
class  IDirect3D9;
typedef IDirect3D9* LPDIRECT3D9;

// ── Render state constants (used in SetRenderState calls) ────────────────────
typedef enum _D3DRENDERSTATETYPE {
    D3DRS_ZENABLE           = 7,
    D3DRS_FILLMODE          = 8,
    D3DRS_SHADEMODE         = 9,
    D3DRS_ZWRITEENABLE      = 14,
    D3DRS_ALPHATESTENABLE   = 15,
    D3DRS_LASTPIXEL         = 16,
    D3DRS_SRCBLEND          = 19,
    D3DRS_DESTBLEND         = 20,
    D3DRS_CULLMODE          = 22,
    D3DRS_ZFUNC             = 23,
    D3DRS_ALPHAREF          = 24,
    D3DRS_ALPHAFUNC         = 25,
    D3DRS_DITHERENABLE      = 26,
    D3DRS_ALPHABLENDENABLE  = 27,
    D3DRS_FOGENABLE         = 28,
    D3DRS_SPECULARENABLE    = 29,
    D3DRS_STENCILENABLE     = 52,
    D3DRS_COLORWRITEENABLE  = 168,
    D3DRS_BLENDOP           = 171,
} D3DRENDERSTATETYPE;

// D3DBLEND
typedef enum _D3DBLEND {
    D3DBLEND_ZERO            = 1,
    D3DBLEND_ONE             = 2,
    D3DBLEND_SRCALPHA        = 5,
    D3DBLEND_INVSRCALPHA     = 6,
    D3DBLEND_DESTALPHA       = 7,
    D3DBLEND_INVDESTALPHA    = 8,
    D3DBLEND_DESTCOLOR       = 9,
    D3DBLEND_INVDESTCOLOR    = 10,
    D3DBLEND_SRCALPHASAT     = 11,
} D3DBLEND;

// D3DCULL
#define D3DCULL_NONE  1
#define D3DCULL_CW    2
#define D3DCULL_CCW   3

// D3DFILL
#define D3DFILL_POINT     1
#define D3DFILL_WIREFRAME 2
#define D3DFILL_SOLID     3

// D3DBLENDOP
#define D3DBLENDOP_ADD         1
#define D3DBLENDOP_SUBTRACT    2
#define D3DBLENDOP_REVSUBTRACT 3
#define D3DBLENDOP_MIN         4
#define D3DBLENDOP_MAX         5

// D3DPRIMITIVETYPE
typedef enum _D3DPRIMITIVETYPE {
    D3DPT_POINTLIST     = 1,
    D3DPT_LINELIST      = 2,
    D3DPT_LINESTRIP     = 3,
    D3DPT_TRIANGLELIST  = 4,
    D3DPT_TRIANGLESTRIP = 5,
    D3DPT_TRIANGLEFAN   = 6,
} D3DPRIMITIVETYPE;

// ── Texture stage state (for fixed-function; largely no-op in our port) ───────
typedef enum _D3DTEXTURESTAGESTATETYPE {
    D3DTSS_COLOROP   = 1,
    D3DTSS_COLORARG1 = 2,
    D3DTSS_COLORARG2 = 3,
    D3DTSS_ALPHAOP   = 4,
    D3DTSS_ALPHAARG1 = 5,
    D3DTSS_ALPHAARG2 = 6,
} D3DTEXTURESTAGESTATETYPE;
#define D3DTOP_DISABLE         1
#define D3DTOP_MODULATE        4
#define D3DTA_TEXTURE          0x00000000
#define D3DTA_DIFFUSE          0x00000002

// ── Sampler state ─────────────────────────────────────────────────────────────
typedef enum _D3DSAMPLERSTATETYPE {
    D3DSAMP_ADDRESSU       = 1,
    D3DSAMP_ADDRESSV       = 2,
    D3DSAMP_ADDRESSW       = 3,
    D3DSAMP_MAGFILTER      = 5,
    D3DSAMP_MINFILTER      = 6,
    D3DSAMP_MIPFILTER      = 7,
    D3DSAMP_MAXANISOTROPY  = 10,
} D3DSAMPLERSTATETYPE;
typedef enum _D3DTEXTUREADDRESS {
    D3DTADDRESS_WRAP   = 1,
    D3DTADDRESS_MIRROR = 2,
    D3DTADDRESS_CLAMP  = 3,
    D3DTADDRESS_BORDER = 4,
} D3DTEXTUREADDRESS;
typedef enum _D3DTEXTUREFILTERTYPE {
    D3DTEXF_NONE        = 0,
    D3DTEXF_POINT       = 1,
    D3DTEXF_LINEAR      = 2,
    D3DTEXF_ANISOTROPIC = 3,
} D3DTEXTUREFILTERTYPE;

// ── Lock flags ────────────────────────────────────────────────────────────────
#define D3DLOCK_DISCARD   0x2000
#define D3DLOCK_NOOVERWRITE 0x1000
#define D3DLOCK_READONLY  0x0010

// ── FVF vertex format flags (legacy fixed-function; used in vertex declarations) ─
#define D3DFVF_XYZ      0x002
#define D3DFVF_DIFFUSE  0x040
#define D3DFVF_TEX1     0x100
#define D3DFVF_TEX2     0x200
#define D3DFVF_TEX3     0x300
#define D3DFVF_TEXCOORDSIZE2(n) 0
#define D3DFVF_TEXCOORDSIZE4(n) 0

// ── D3DX utility functions (implemented in d3d_compat.mm) ────────────────────
#ifdef __cplusplus
#include <glm/glm.hpp>
inline D3DXMATRIX* D3DXMatrixIdentity(D3DXMATRIX* m) {
    *m = glm::mat4(1.0f); return m;
}
inline D3DXMATRIX* D3DXMatrixMultiply(D3DXMATRIX* out, const D3DXMATRIX* a, const D3DXMATRIX* b) {
    *out = (*a) * (*b); return out;
}
inline D3DXMATRIX* D3DXMatrixTranspose(D3DXMATRIX* out, const D3DXMATRIX* m) {
    *out = glm::transpose(*m); return out;
}
inline D3DXMATRIX* D3DXMatrixOrthoOffCenterLH(D3DXMATRIX* out,
    float l, float r, float b, float t, float zn, float zf)
{
    *out = glm::orthoLH_ZO(l, r, b, t, zn, zf); return out;
}
inline D3DXMATRIX* D3DXMatrixPerspectiveFovLH(D3DXMATRIX* out,
    float fov, float aspect, float zn, float zf)
{
    *out = glm::perspectiveFovLH_ZO(fov, aspect, 1.0f, zn, zf); return out;
}
inline D3DXMATRIX* D3DXMatrixTranslation(D3DXMATRIX* out, float x, float y, float z) {
    *out = glm::translate(glm::mat4(1.0f), glm::vec3(x,y,z)); return out;
}
inline D3DXMATRIX* D3DXMatrixScaling(D3DXMATRIX* out, float x, float y, float z) {
    *out = glm::scale(glm::mat4(1.0f), glm::vec3(x,y,z)); return out;
}
inline D3DXMATRIX* D3DXMatrixRotationYawPitchRoll(D3DXMATRIX* out, float y, float p, float r) {
    *out = glm::eulerAngleYXZ(y, p, r); return out;
}
inline D3DXMATRIX* D3DXMatrixLookAtLH(D3DXMATRIX* out,
    const D3DXVECTOR3* eye, const D3DXVECTOR3* at, const D3DXVECTOR3* up)
{
    *out = glm::lookAtLH(*eye, *at, *up); return out;
}
inline float D3DXVec3Length(const D3DXVECTOR3* v) { return glm::length(*v); }
inline D3DXVECTOR3* D3DXVec3Normalize(D3DXVECTOR3* out, const D3DXVECTOR3* v) {
    *out = glm::normalize(*v); return out;
}
inline D3DXVECTOR3* D3DXVec3TransformCoord(D3DXVECTOR3* out,
    const D3DXVECTOR3* v, const D3DXMATRIX* m)
{
    glm::vec4 r = (*m) * glm::vec4(*v, 1.0f);
    *out = glm::vec3(r) / r.w; return out;
}
#endif // __cplusplus
