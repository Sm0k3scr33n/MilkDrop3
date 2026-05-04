## MilkDrop3 — Porting Roadmap & Feature Tracker

This document tracks the porting effort, cross-platform goals, and new features you requested (screensavers, plugins, networked multi-node, Raspberry Pi support, command center). Use this file as the single source of truth for prioritization, acceptance criteria, and next actionable tasks.

### Mission
- Port MilkDrop3 natively to macOS, Linux, and Windows while keeping a single shared codebase where possible.
- Add modern integration points: screensaver builds for each platform, plugins for OBS and VLC, a network multi-node mode for synchronized visuals, and a lightweight command center to control multiple instances.
- Optimize for low-power devices (Raspberry Pi 4 & 5) and provide extensibility via a plugin API for third-party integrations.

### High-level Goals (short bullets)
- Native macOS port (Metal) — priority: high (chosen by user).
- Native Linux port (Vulkan or OpenGL) — priority: high.
- Native Windows port (Direct3D9 compatibility / DXVK optional) — priority: medium (maintain original behavior).
- Screensaver targets for macOS, Linux (xscreensaver/gnome-screensaver), and Windows (.scr) — priority: medium.
- Plugins: OBS source plugin and VLC visual plugin — priority: medium-high.
- Networked multi-node rendering (synchronization, master/clients) — priority: medium.
- Raspberry Pi 4/5 optimizations (OpenGL ES/Metal-like via MoltenVK or native Vulkan/GBM) — priority: medium.
- Command center (desktop/web UI) to orchestrate multiple MilkDrop instances — priority: low-medium.

### Non-functional requirements
- Clean cross-platform build: CMake as primary build system; minimal #ifdefs in core renderer.
- Reusable compatibility layer that maps platform APIs (D3D/OpenGL/Metal) to a single internal renderer interface.
- Low-latency audio capture for visuals (support platform-specific loopback APIs and virtual-device fallback).
- Extensibility: plugin API (simple C ABI) for external integrations.

### Proposed Architecture (brief)
- Core cross-platform engine: audio processing, preset parser, math, and preset VM (ns-eel2 interpreter fallback).
- Platform layer: windowing/input, audio capture, GPU backend (Metal/Vulkan/OpenGL/Direct3D). Provide a thin abstraction (Device, Texture, Shader, Buffer, DrawCall).
- Plugins / Integrations: dynamic libraries implementing a small C API for rendering frames or acting as an input source.
- Network sync: small UDP/TCP protocol for sync messages (beat, time, preset, uniform updates). Master node broadcasts timeline and state; clients follow.

### Feature Ideas & Implementation Notes

- Screensaver (per-OS):
  - macOS: implement as `.saver` bundle or ScreenSaver.framework-based app; reuse Metal rendering path.
  - Linux: build as an xscreensaver module and a GNOME screensaver integration; use OpenGL or Vulkan depending on target.
  - Windows: build an `.scr` (screensaver) wrapper that hosts the visualizer and handles standard screensaver messages.
  - Acceptance: Smooth animation at native refresh, respects system suspend/resume and input to exit.

- OBS / VLC Plugins:
  - OBS: implement a source plugin that either renders into an OBS texture (preferred) or shares frames via shared memory. Use OBS plugin API (C/C++). Provide options: audio-reactive, network sync client.
  - VLC: implement a visualization plugin module; follow VLC module conventions (C API). Aim for lightweight dependency set.
  - Acceptance: Plugin can be added in OBS/VLC and renders MilkDrop visuals with audio from host.

- Networked Multi-node / Sync:
  - Design a small protocol (binary, protobuf optional) that carries: timeline position, beat events, preset id, uniform diffs, and optionally per-node transform/viewport.
  - Provide master/slave mode; support multicast for LAN convenience and TCP failover for reliability.
  - Acceptance: Two machines on the same LAN show visually synchronized presets within 50ms jitter under normal conditions.

- Raspberry Pi 4 & 5 support:
  - Use Vulkan (if available) or OpenGL ES path optimized for Pi GPU; for Pi OS, build with GCC/Clang and link lightweight windowing (SDL2 with EGL/GBM).
  - Reduce shader complexity or provide quality presets for low-power mode; optimize audio resampling and buffer sizes.
  - Acceptance: Stable 30–60 FPS for simple presets on Pi 4, and 60+ for Pi 5 on medium presets (target depends on preset complexity).

- Command Center (control & orchestration):
  - Small controller app (desktop or web-based) that can discover instances via mDNS and issue commands (load preset, pause, timeline seek, group control).
  - Optional web UI with websockets to push state to instances.
  - Acceptance: Can discover and send a preset to 5 running instances and trigger a synchronized start within 200ms.

### Prioritized Milestones (MVP → v1 → v2)

MVP (get visuals running natively on one platform):
- Finish macOS Metal device and build (CMake). (In progress)
- Replace Direct3D-specific dxcontext and texmgr integration to use platform device API. (next)
- Ensure audio capture on macOS is working and feed PCM snapshots to the visual engine. (done: scaffold)
- Acceptance: Ability to build and render a basic preset on macOS with local audio.

v1 (cross-platform single-machine):
- Implement Vulkan/OpenGL backend for Linux and Windows (or reuse existing D3D path on Windows).
- Implement text rendering and texture loading cross-platform.
- Add screensaver mode for macOS and basic build for at least one Linux distro.
- Acceptance: Build & run on macOS and Ubuntu; screensaver loads on macOS.

v2 (integrations & scaling):
- OBS & VLC plugins; network multi-node sync; Raspberry Pi optimized builds.
- Command center (discovery + control UI).

### Concrete Next Actions (short checklist)
1. Implement dxcontext wrapper to route the original DX calls to the platform device (MetalDevice) — unblock compilation. (high)
2. Port `texmgr.cpp` to use cross-platform image loader and upload into backend textures. (high)
3. Port `textmgr.cpp` to use CoreText (macOS) / Pango/FreeType (Linux) / GDI (Windows) or render-to-texture fallback. (high)
4. Try a first CMake configure & build for macOS (CI or local) and resolve compiler errors. (high)
5. Draft a small network sync protocol and a simple master/server prototype (UDP for time/beat messages). (medium)
6. Create a simple OBS source prototype that can host the engine in-process or accept frames from a running MilkDrop instance. (medium)

### Risks & Unknowns
- ns-eel2 JIT is only provided for x86_64 in repo; need interpreter fallback or an ARM64 JIT for Apple Silicon and Raspberry Pi.
- HLSL preset dialect corner cases may break with simple text-based HLSL→MSL transpiler; may need DXC→SPIRV→MSL pipeline for full fidelity.
- System audio loopback has API and permission differences per OS; macOS screen-capture APIs require user consent.

### Acceptance Criteria (how we know it's 'done')
- Port: Builds and runs on each target OS with native GPU backend, passes a simple smoke test that renders the default preset and reacts to audio.
- Screensaver: Integrates with each desktop environment's screensaver system and exits cleanly on input.
- Plugins: OBS and VLC plugins load and display visuals with host audio input.
- Network: Multi-node sync maintains visual timeline within acceptable jitter on LAN.

### How to contribute / process
- Create feature branches off `main` and open PRs with one feature/fix per PR.
- Use the following labels: platform/macos, platform/linux, platform/windows, feature/screensaver, feature/obs, feature/vlc, feature/network, perf/pi.
- For major changes (renderer/ABI), open a design doc PR first.

---

Archived references & links:
- See `macos/PORTING_CHECKLIST.md` for current port tasks and file-level notes.

If you'd like, I can create a matching GitHub Project board or issues from the entries above and open the highest-priority task (dxcontext wrapper) as an issue/branch and start implementing it.
