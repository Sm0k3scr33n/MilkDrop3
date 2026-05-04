# Port & Issues

This document lists the top-priority issues/tasks for the native port and contains short instructions for forking/branching on GitHub.

## Top issues (suggested PR order)

1. dxcontext wrapper (macOS) — implemented as `code/vis_milk2/dxcontext_mac.mm` (guarded by `MILKDROP_MACOS`). Unblocks other macOS compile errors.
2. texmgr port — replace D3DXCreateTextureFromFile with cross-platform loader and Metal upload.
3. textmgr port — replace D3DX font/text rendering with CoreText (macOS) / FreeType (Linux) / GDI (Windows) or render-to-texture.
4. plugin shell guards — audit `pluginshell.cpp`/`plugin.cpp` for Windows-only APIs and guard or port them.
5. ns-eel2 interpreter on ARM64 — add interpreter fallback or ARM64 JIT for Apple Silicon & Raspberry Pi.
6. build CI — add GitHub Actions macOS, Ubuntu, and Windows jobs for cross-platform builds.

## Forking & Branching (how-to)

1. Fork the upstream repository (the one you cloned) into your GitHub account.
2. Clone your fork locally:

```bash
# replace <your-username> and repo name
git clone git@github.com:<your-username>/MilkDrop3.git
cd MilkDrop3
git remote add upstream git@github.com:milkdrop2077/MilkDrop3.git
git fetch upstream
git checkout -b macos/metal-port
```

3. Make commits on `macos/metal-port` and push to your fork:

```bash
git push -u origin macos/metal-port
```

4. Open a Pull Request from your fork/branch to the upstream `main` when ready.

## Notes
- Use small, focused PRs: one for dxcontext wrapper, one for texture manager, one for text manager, etc.
- Add `platform/macos` CI job first to ensure the macOS code builds early.

If you want, I can create a branch locally with the dxcontext changes and prepare a patch you can apply to your fork, or (if you give me your fork info) I can create a PR. Note: I can't push to GitHub from here without your credentials or by using your fork URL.
