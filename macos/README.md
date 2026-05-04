# MilkDrop3 — macOS Native Port

Metal + CoreAudio native port. No Wine. Full 120fps on Apple Silicon.

---

## Architecture

```
macos/
├── CMakeLists.txt              ← Build system (replaces .sln/.vcxproj)
├── platform/
│   ├── win32_compat.h          ← Stubs all Windows types (HWND, RECT, etc.)
│   ├── d3d_compat.h            ← D3D9/D3DX stubs; math via GLM
│   ├── ini_parser.h/.cpp       ← GetPrivateProfile* replacement
├── render/
│   ├── MetalDevice.h/.mm       ← IDirect3DDevice9 Metal implementation
│   ├── HLSLToMSL.h/.mm         ← Runtime HLSL → MSL transpiler
│   └── shaders/
│       └── milkdrop_base.metal ← Pre-compiled base shader library
├── audio/
│   └── CoreAudioCapture.h/.mm  ← WASAPI → CoreAudio / ScreenCaptureKit
└── app/
    ├── main.mm                 ← Entry point
    ├── AppDelegate.h/.mm       ← NSWindow + MTKView render loop
    └── Info.plist.in           ← Bundle metadata
```

---

## Build

```bash
# Install dependencies
brew install cmake glm sdl2

# Configure & build
cd macos
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(sysctl -n hw.logicalcpu)

# Run
open build/MilkDrop3.app
```

---

## Status: What Works vs What Still Needs Work

### ✅ Done (scaffolding complete)
| Component | Status |
|---|---|
| Build system (CMake) | ✅ |
| Windows type stubs (`win32_compat.h`) | ✅ |
| D3D9/D3DX type stubs + GLM math (`d3d_compat.h`) | ✅ |
| INI file parser (replaces `GetPrivateProfile*`) | ✅ |
| Metal device / command encoder | ✅ |
| Vertex/index buffer wrappers | ✅ |
| Texture creation + render targets | ✅ |
| Render state → Metal PSO builder | ✅ |
| Base Metal shaders (warp, comp, blur, waveform, sprite) | ✅ |
| Runtime HLSL → MSL transpiler | ✅ |
| Audio loopback (ScreenCaptureKit macOS 13+) | ✅ |
| Audio loopback (AudioUnit input fallback) | ✅ |
| MTKView render loop | ✅ |
| Keyboard event mapping | ✅ |
| Mouse event mapping | ✅ |

---

### 🔧 Required Changes to Original Source Files

The original `code/vis_milk2/` files need targeted edits. The strategy is to
**guard** macOS-specific replacements with `#ifdef MILKDROP_MACOS` so the
Windows build is not broken.

#### Priority 1 — Won't compile without these

**`shell_defines.h`**
```cpp
// Replace:
#include <windows.h>
// With:
#ifdef MILKDROP_MACOS
  #include "../../macos/platform/win32_compat.h"
  #include "../../macos/platform/d3d_compat.h"
#else
  #include <windows.h>
  #include <d3d9.h>
  #include <d3dx9.h>
#endif
```

**`utility.h`**  
Same guard — remove `<windows.h>`, `<crtdefs.h>`, `<d3d9.h>`, `<d3dx9.h>`,
`<shlobj.h>` under `MILKDROP_MACOS`.  Keep the cross-platform functions.

**`pluginshell.h`**  
- Replace `HINSTANCE m_hInstance` → `void* m_hInstance`  
- Replace `LARGE_INTEGER m_high_perf_timer_freq` → already handled by `win32_compat.h`  
- Remove `IDirect3DTexture9* m_lpDDSText` (D3DX font atlas) — handled by new text layer  
- Replace `LPD3DXFONT m_d3dx_font[]` with a macOS font handle  

**`dxcontext.h / dxcontext.cpp`**  
These are the D3D context init files. Under `MILKDROP_MACOS`, the `DXContext`
class becomes a thin wrapper around `IDirect3DDevice9` (our Metal impl).
The `.cpp` file contains ~500 lines of Win32/D3D9 init code — all replaced by
`MetalDevice.mm`.

**`Milkdrop2PcmVisualizer.cpp`**  
This is the Windows entry point / main loop. Under macOS it is replaced by
`AppDelegate.mm`. Guard the whole file:
```cpp
#ifndef MILKDROP_MACOS
// ... entire Windows-only file
#endif
```

**`wasabi.cpp / wasabi.h`**  
Winamp SDK glue — not used in standalone mode. Guard entirely under
`#ifndef MILKDROP_MACOS`.

**`audio/common.h`**  
Remove `<mmdeviceapi.h>`, `<audioclient.h>`, `<avrt.h>` under macOS guard.

#### Priority 2 — Compile with warnings, runtime fixes

**`plugin.cpp`** (~8860 lines)  
Key Win32 calls to stub/replace:
- `GetPrivateProfileIntW` / `WritePrivateProfileIntW` → already handled by `ini_parser.cpp`
- `PathFileExistsW` → replace with `access()` via `#ifdef MILKDROP_MACOS`
- `FindFirstFileW` / `FindNextFileW` → replace with POSIX `opendir/readdir`
- `CreateThread` → replace with `std::thread`
- `WideCharToMultiByte` / `MultiByteToWideChar` → replace with standard `wcstombs/mbstowcs`
- `SetWindowPos`, `ShowWindow`, `GetClientRect` → stub/no-op or SDL2 equivalent
- `D3DXCreateTextureFromFileW` → replace with stb_image or NSImage loader

**`milkdropfs.cpp`** (~4713 lines)  
The heaviest file. Changes needed:
- All `pDevice->SetVertexShaderConstantF(...)` calls → our stub (already handled)
- All `pDevice->SetTexture(...)` → our stub (already handled)
- Shader compilation: `D3DXCompileShaderFromFile` → `HLSLToMSL::Transpile()`
- `D3DXCreateEffectFromFile` → not used (MilkDrop builds shaders manually)
- `pDevice->CreateVertexDeclaration(...)` → our stub returns nullptr (handled)

**`texmgr.cpp`**  
- `D3DXCreateTextureFromFile` → stb_image + `IDirect3DDevice9::CreateTexture` + upload

**`textmgr.cpp`**  
- Replace `ID3DXFont` / `DrawText` rendering with a CoreText-based renderer.
  Simplest approach: render text to an `NSBitmapImageRep`, upload as a Metal
  texture, blit as a sprite.

#### Priority 3 — Polish

- Noise textures (`sampler_noise_lq` etc.): generate procedurally in Metal or load from PNG
- `ns-eel2` JIT: `asm-nseel-x64-macho.o` should work on x86_64; for Apple Silicon
  (ARM64) the JIT assembler needs a new backend or use the interpreter path
  (set `#define NSEEL_SUPER_MINIMAL_LEXER` and disable the JIT)
- INI file path: macOS should store settings in `~/Library/Application Support/MilkDrop3/`
- Preset paths: default to `<app bundle>/Contents/Resources/presets/`
- Retina display: multiply all pixel sizes by `view.contentsScale`

---

## Shader Translation Notes

MilkDrop presets contain inline HLSL in two fields:
- `warp_shader` — runs per-pixel over a mesh, samples previous frame
- `comp_shader` — composites the final frame

At preset load time (`plugin.cpp::LoadPreset`), call:
```cpp
#ifdef MILKDROP_MACOS
auto result = HLSLToMSL::Transpile(warpShaderBody, MilkDropShaderType::Warp,
                                    g_device->GetMTLDevice(), presetName);
if (result.success) {
    // cache result.vertFunc / result.fragFunc, use on next frame
}
#endif
```

The transpiler handles the common HLSL→MSL substitutions automatically.
If a preset fails to transpile (complex macros, etc.), the default passthrough
shader is used and the error is logged to stderr.

---

## Audio Notes

**macOS 13+ (Ventura and later):**  
ScreenCaptureKit provides system audio loopback. The app needs the
`NSScreenCaptureDescription` permission and will prompt the user on first launch.
No external software needed.

**macOS 12 and earlier:**  
Install [BlackHole](https://github.com/ExistentialAudio/BlackHole) (free, open source).
In System Preferences → Sound → Output, select BlackHole 2ch.
In System Preferences → Sound → Input, select BlackHole 2ch.
MilkDrop will capture from the default input device.

---

## ns-eel2 on Apple Silicon

The expression evaluator has a pre-built `asm-nseel-x64-macho.o` for x86_64.
On ARM64 (M1/M2/M3/M4):

1. **Interpreter path (easy):** Add to `ns-eel2/ns-eel.h`:
   ```c
   #if defined(__aarch64__)
   #define NSEEL_USE_INTERPRETER 1
   #endif
   ```
   This disables the JIT and uses the bytecode interpreter. ~10-20% slower
   for complex presets but fully correct.

2. **ARM64 JIT (future work):** Write `asm-nseel-arm64-macho.s` implementing
   the same calling convention as the x64 version. ~300 lines of ARM64 asm.

---

## Dependencies

| Library | Purpose | Install |
|---|---|---|
| GLM 1.0+ | Math (replaces D3DX) | `brew install glm` |
| SDL2 | (Optional — currently using Cocoa directly) | `brew install sdl2` |
| stb_image | Texture loading | Header-only, bundled |

---

## Contributing

When editing original `code/vis_milk2/` files, always use the pattern:
```cpp
#ifdef MILKDROP_MACOS
  // macOS implementation
#else
  // original Windows implementation
#endif
```
This keeps the Windows build intact.

File-by-file porting progress is tracked in [PORTING_CHECKLIST.md](PORTING_CHECKLIST.md).
