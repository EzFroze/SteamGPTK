# SteamGPTK 0.2.2 — 2026-10-16

- Add the automatic Half-Life 2 profile (AppID 220): D9VK / KosmicKrisp, D3D9 VSync off, AVX advertisement off and the verified 32-bit Steam bridge.
- Preserve explicit profile overrides and pass either Vulkan driver variable to the Wine app loader.
- Recreate profiles during Install / Repair; keep original Valve files separate from the bridge selected for HL2.
- Validate and install the pinned i386 bridge, detect a missing or damaged runtime copy, and repair bridge corruption even when file sizes match.
- Cover automatic launch settings, user overrides, opt-out, unprofiled games and repeated setup followed by Valve installation with regression tests.

# SteamGPTK 0.2.1 — 2026-10-16

- Identify actual Wine game processes instead of matching renderer paths in launcher arguments.
- Let closed game sessions finish while other launcher scripts remain, preventing those scripts from keeping one another alive and consuming CPU.
- Use the same game-process selection for session lifetime and window activation.
- Cover Windows executable paths, Wine helpers, wrapper exclusion and session completion with regression checks.

# SteamGPTK 0.2.0 — 2026-10-15

- Enable D9VK automatically for DirectX 8/9, including 32-bit games.
- Correct relocated Vulkan driver manifests during installation and repair.
- Respect an explicit WineD3D selection.
- Rename the app, Swift target, native module, logs and build artifacts to SteamGPTK.
- Preserve existing runtime/GPTK, backups, game profiles and Steam tool selections during upgrade.
- Retain upstream attribution and component licenses.

# SteamGPTK changes

## 0.1.2 — 2026-10-15

- Fix startup crashes in downloaded apps: resources are resolved inside the app instead of the GitHub runner's SwiftPM build directory.
- Check resource loading for both native SwiftPM and Swift Build bundle layouts.
- Gate releases on a headless resource check after relocation and ZIP extraction. This does not open windows or inspect/change an installed Steam runtime.

## 0.1.1 — 2026-10-15

- Fix release verification for annotated Git tags checked out by GitHub Actions.
- First downloadable app release; the 0.1.0 tag passed build/tests but was not published because release verification stopped.

## 0.1.0 — 2026-10-15

Based on standalone SteamGPTK commit `5b8d18683b619b66390be8cbcffc1fbf47e45971`.

- Use Sikarugir Wine 11 without a commercial CrossOver installation or license.
- Import GPTK 4 from a user-selected Apple DMG; include no Apple renderer in source or app archives.
- Detect Wine, Rosetta, imported D3DMetal and the 64-bit Steam bridge correctly in the app.
- Install and repair the runtime/integration while preserving imported GPTK and game prefixes.
- Apply the Wine detour from a hash-checked patch recipe instead of bundling a manually prepared Wine DLL.
- Unify Wine account profiles with `steamuser` for Steam Cloud paths; preserve backups and refuse conflicting save merges.
- Match current native Steam JavaScript bundles and retain the working Wine 11 overlay implementation.
- Preserve explicit AVX settings and map Steam's graphics choices to the free runtime.
- Keep native macOS game launches native unless the user selects a compatibility tool.
- Provide reproducible build/test scripts, installation guides and fork-specific build/release workflows.
- Disable upstream application updates in this fork and retain GPL/third-party notices.
- Publish versioned app archives and SHA-256 checksums from GitHub Actions after build, test and lint checks.

Compatibility is experimental. Local validation covered 372 Swift tests, including a disposable full Wine installation, GPTK 4.0 beta 3 import, repair and prefix creation. GitHub Actions results are reported separately after publication.
