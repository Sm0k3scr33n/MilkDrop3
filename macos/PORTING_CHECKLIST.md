# MilkDrop3 macOS Porting Checklist

Track progress file-by-file. Legend: ✅ Done | 🔧 In Progress | ⬜ Not Started | ⚠️ Blocked

---

## New macOS Files (macos/)

| File | Status | Notes |
|---|---|---|
| `CMakeLists.txt` | ✅ | Full build system |
| `platform/win32_compat.h` | ✅ | All core Windows types stubbed |
| `platform/d3d_compat.h` | ✅ | D3D9 types + GLM math aliases |
| `platform/ini_parser.h` | ✅ | Header |
| `platform/ini_parser.cpp` | ✅ | Full GetPrivateProfile* replacement |
| `render/MetalDevice.h` | ✅ | IDirect3DDevice9 interface |
| `render/MetalDevice.mm` | ✅ | Metal implementation |
| `render/HLSLToMSL.h` | ✅ | Transpiler interface |
| `render/HLSLToMSL.mm` | ✅ | Runtime HLSL→MSL transpiler |
| `render/shaders/milkdrop_base.metal` | ✅ | Base shaders (warp, comp, blur, waveform, sprite) |
| `audio/CoreAudioCapture.h` | ✅ | Interface |
| `audio/CoreAudioCapture.mm` | ✅ | SCKit + AudioUnit loopback |
| `app/main.mm` | ✅ | Entry point |
| `app/AppDelegate.h` | ✅ | NSWindow + MTKView |
| `app/AppDelegate.mm` | ✅ | Full render + event loop |
| `app/Info.plist.in` | ✅ | Bundle metadata |
| `README.md` | ✅ | Build instructions + status |

---

## Original Source File Edits (code/)

### vis_milk2/

| File | Status | What's needed |
|---|---|---|
| `shell_defines.h` | ✅ | Guard `<windows.h>` include |
| `utility.h` | ✅ | Guard Windows/D3D includes |
| `Milkdrop2PcmVisualizer.cpp` | ✅ | Guard entire file under `#ifndef MILKDROP_MACOS` |
| `dxcontext.h` | 🔧 | Replace D3D9 members with Metal equivalents |
| `dxcontext.cpp` | 🔧 | Replace with thin wrapper to MetalDevice |
| `pluginshell.h` | ⬜ | Guard Win32/D3D members; replace font types |
| `pluginshell.cpp` | ⬜ | Guard Win32 calls; replace GDI/DX init |
| `plugin.h` | ⬜ | Guard Win32 types (HWND, LRESULT etc.) |
| `plugin.cpp` | ⬜ | ~40 Win32 call sites to replace (see README) |
| `milkdropfs.cpp` | ⬜ | Shader compilation → HLSLToMSL; D3D calls → stubs |
| `texmgr.h` | ⬜ | Guard `<d3d9.h>`; replace `LPDIRECT3DTEXTURE9` |
| `texmgr.cpp` | ⬜ | Replace D3DX texture loading with stb_image |
| `textmgr.h` | ⬜ | Replace `LPD3DXFONT`; CoreText text renderer |
| `textmgr.cpp` | ⬜ | Implement CoreText-based text rendering |
| `support.h` | ⬜ | Guard `<d3dx9.h>`; `D3DXMATRIX` → glm types |
| `support.cpp` | ⬜ | Replace `PrepareFor3DDrawing` / `PrepareFor2DDrawing` |
| `state.h` | ⬜ | Guard `<d3dx9math.h>` |
| `state.cpp` | ⬜ | INI read/write already handled; check file I/O |
| `menu.h` | ⬜ | Minor Win32 type guards |
| `menu.cpp` | ⬜ | Minor Win32 type guards |
| `utility.cpp` | ⬜ | Replace PathFileExists, FindFirstFile, etc. |
| `wasabi.h` | ⬜ | Guard under `#ifndef MILKDROP_MACOS` |
| `wasabi.cpp` | ⬜ | Guard under `#ifndef MILKDROP_MACOS` |
| `fft.h` | ✅ | No Windows dependencies |
| `fft.cpp` | ✅ | Pure C++ math, no changes needed |

### audio/

| File | Status | Notes |
|---|---|---|
| `common.h` | ✅ | Guarded WASAPI includes |
| `loopback-capture.h` | ⬜ | Guard under `#ifndef MILKDROP_MACOS` |
| `loopback-capture.cpp` | ⬜ | Guard under `#ifndef MILKDROP_MACOS` |
| `audiobuf.h` | ⬜ | Check for Windows-only types |
| `audiobuf.cpp` | ⬜ | May be clean |
| `prefs.h/.cpp` | ⬜ | May use GetPrivateProfile → already handled |

### ns-eel2/

| File | Status | Notes |
|---|---|---|
| `ns-eel.h` | ⬜ | Check for Windows types |
| `nseel-compiler.c` | ⬜ | JIT: x64 works, ARM64 needs interpreter fallback |
| `asm-nseel-x64-macho.o` | ✅ | Pre-built x86_64 Mach-O, works on Intel Mac |
| ARM64 JIT | ⬜ | Write `asm-nseel-arm64-macho.s` OR enable interpreter |
| Other .c files | ⬜ | Likely clean — portable C |

---

## Known Remaining Issues

1. **Text rendering**: `textmgr.cpp` uses `ID3DXFont` (D3DX GDI-based font rendering).
   Need to implement CoreText or SDL_ttf based rendering. This affects all on-screen
   text (preset names, FPS counter, menus).

2. **File enumeration**: `plugin.cpp` uses `FindFirstFileW`/`FindNextFileW` to scan
   the presets directory. Replace with POSIX `opendir`/`readdir`.

3. **ns-eel2 ARM64 JIT**: Without the JIT, complex presets with heavy per-pixel
   expressions will be slower on Apple Silicon. The interpreter path is correct
   but ~15% slower. Target: write ARM64 backend.

4. **D3DX texture loading**: `D3DXCreateTextureFromFileW` used in `texmgr.cpp`.
   Replace with stb_image (header already in many open-source projects) +
   manual MTLTexture upload.

5. **Noise textures**: MilkDrop generates built-in LQ/MQ/HQ noise textures at
   startup. The generation code is in `milkdropfs.cpp` — it uses D3D to create
   and lock textures. Port to Metal buffer uploads.

6. **HLSL transpiler edge cases**: Some community presets use HLSL features the
   text-substitution transpiler doesn't handle (loops, user functions, etc.).
   For production quality, integrate DXC + SPIRV-Cross for full correctness.

---

## Next Session Priorities

1. `dxcontext.cpp` — replace with Metal wrapper (unblocks all other compile errors)
2. `pluginshell.cpp` — guard Win32 init code (the biggest remaining file)
3. `plugin.cpp` — file enumeration + Win32 call stubs
4. Text rendering proof-of-concept
5. First successful build + black window
6. Wire up preset loading
7. First visual output 🎉
