Historical Wine 8/GPTK beta 2 notes. This is not the supported SteamGPTK installation route.

# Running Steam Games on macOS with NotProton + GPTK 4 (Beta 2)

This branch adds standalone, reproducible support for running Windows Steam games on Apple Silicon macOS using **NotProton** paired with **Wine-Crossover** (with experimental 32-on-64 WOW64 support) and **Apple Game Porting Toolkit 4.0 (Beta 2)** without requiring a commercial CrossOver license or third-party launchers.

---

## Standalone Architecture (Launcher-Agnostic)

The setup is completely standalone:
- **No Commercial CrossOver Required**: Uses open-source Wine-Crossover or Game Porting Toolkit runtime with WOW64 memory support.
- **No Third-Party Launchers Required**: Does not rely on Heroic, Whisky, or Porting Kit. The setup script configures the Wine runtime and integrates Apple's GPTK directly into NotProton's native runner tree.
- **Native Steam Client Integration**: Injects seamlessly into `/Applications/Steam.app` and registers as a first-class compatibility tool (**"Game Porting Toolkit 4"**).

---

## Key Improvements & Bug Fixes

1. **Wine-Crossover + Apple GPTK 4 Integration**:
   - Uses Wine 8.0.1 (CrossOver 23.7.1 FOSS base) which fixes the `virtual.c` WOW64 memory assertion (`alloc_pages_vprot`) that causes 32-bit games to crash on Apple's standalone GPTK 1.x Wine 7.7 runner on macOS 15+.
   - Bundles Apple's `D3DMetal.framework` (GPTK 4.0b2) and `libd3dshared.dylib` in `lib/external/`.
   - Enables GPTK 4 runtime features by default:
     - `D3DM_MTL4=1` (Apple Metal 4 translation pipeline)
     - `D3DM_ENABLE_METALFX=1` (MetalFX spatial/temporal upscaling)
     - `D3DM_SUPPORT_DXR=1` (DirectX Raytracing support)
     - `ROSETTA_ADVERTISE_AVX=1` (Rosetta 2 AVX capability)
     - `WINEMSYNC=1` & `WINEESYNC=1` (Fast synchronization)
     - `WINEDLLOVERRIDES`: includes `d3dcompiler_47=n,b` and `nvapi64,nvngx=n,b`

2. **Experimental 32-bit Game Support (`tier0_s.dll` and `vstdlib_s.dll`)**:
   - Experimental 32-bit support (not proven to run): 32-bit Windows games initialize Steam via 32-bit `steamclient.dll`.
   - Valve's 32-bit `steamclient.dll` requires 32-bit `tier0_s.dll` and `vstdlib_s.dll`.
   - The setup extracts and verifies both DLLs from Valve client package `bins_win64.zip` and adds them to `valve-packages.manifest`, `bridge_files` in `compat_run.sh`, and the prefix DLL search path.

3. **`iscriptevaluator.exe` macOS Crash Bypass**:
   - Steam invokes Valve's `iscriptevaluator.exe` prior to launching games to evaluate DirectX/redistributable scripts.
   - On macOS, this binary crashes with a stack buffer overflow / page fault when paths contain spaces (`/Users/.../Application Support/...`), causing game launches to fail prematurely.
   - `compat_run.sh` intercepts `iscriptevaluator.exe` and exits `0` cleanly.

4. **`ntdll_compat.so` Export & ABI Adapter**:
   - `lsteamclient.so` is compiled against Proton's Wine tree and requires Proton-specific ntdll exports (`__wine_dbg_strdup`, `ntdll_get_dos_file_name`, etc.) as well as Microsoft x64 calling convention (`ms_abi`) for NT system calls (`NtClose`, `NtCreateKey`, `NtQueryInformationToken`, `NtSetValueKey`).
   - Wine-Crossover's macOS Mach-O `ntdll.so` uses the System V AMD64 ABI on the host. `setup-gptk4.sh` builds and stages `ntdll_compat.so` to transparently bridge these symbols and calling conventions, re-exporting Wine-Crossover's `ntdll.so`.

5. **macOS Process Detection in `compat_run.sh`**:
   - Upstream Proton scripts checked if game processes were alive by filtering `ps -o args=` for Windows drive letters (`grep -E '^[A-Za-z]:\\'`).
   - On macOS, Wine processes report Unix paths (`/Users/.../wine ... Game.exe`), causing the watchdog to prematurely assume the game terminated and kill the Wine prefix after 10–35 seconds.
   - Fixed `prefix_game_running()` to match both `.exe` names and Windows paths while excluding helper utilities.

6. **Experimental 32-bit `lsteamclient.dll` Memory Corruption Fix**:
   - In 32-bit Windows games (experimental 32-bit support, not proven to run), Valve's legacy Proton code contained an old workaround that attempted to carve vtable memory directly from offset `0` of the module's `.data` section via `get_mem_from_steamclient_dll`.
   - In standalone NotProton, `lsteamclient.dll` is deployed as `steamclient.dll`. Carving memory from offset `0` of its own `.data` section overwrote internal globals (`steamclient_cs` critical section and `steamclient_interfaces` linked list), causing an immediate access violation inside `create_win_interface` during `SteamAPI_Init()`.
   - Patched `get_mem_from_steamclient_dll` to return `NULL`, falling back directly to static vtables and `HeapAlloc`, identically matching 64-bit Proton behavior.

7. **64-bit D3DMetal Bridge (`macdrv_functions` in `overlay-shim.dylib`)**:
   - In Wine 8.0+ WOW64, `winemac.so` does not export `macdrv_functions`, which causes Apple's `libd3dshared.dylib` (GPTK 4 D3DMetal) to crash at `shared.mm:605` on 64-bit DirectX 11/12 games.
   - Injected the complete `macdrv_functions` Cocoa and Metal view bridge in `overlay-shim.dylib`, resolving the crash and allowing D3DMetal to present directly to CAMetalLayer.

8. **Experimental 32-bit D3D9 / OpenGL Presentation Support**:
   - Under experimental 32-bit support (not proven to run), Valve's `gameoverlayrenderer.dylib` installs a `CGLFlushDrawable` replacement that dereferences internal state which is NULL for Wine CGL contexts, causing an access violation (`0xc0000005`) on every `wglSwapBuffers` call in 32-bit games and dropping all frames.
   - Removed `adopt_overlay_gl_present` hook in `overlay-shim.m` and configured `OpenGLSurfaceMode=behind` in the Wine Mac Driver registry, enabling Cocoa window transparency so Direct3D 9 and OpenGL drawing surfaces are not occluded by opaque window backgrounds.

9. **Native Frontmost Window Activation & Prompt SIGTERM Exit**:
   - Replaced AppleScript System Events calls with Cocoa's `NSRunningApplication.activate()`, eliminating macOS `-1743` Apple Events permission errors.
   - Ensured runner exits immediately on `SIGTERM` when stopping games in Steam without residual idle watchdog delays.

10. **Automated Window Presentation Validator**:
    - Included `scripts/test-window-presentation.sh` to verify on-screen compositor visibility (`kCGWindowIsOnscreen`) and swapchain health via CoreGraphics metadata and Wine logs without screen captures.

---

## Prerequisites

1. **Apple Silicon Mac** (M1/M2/M3/M4/M5) running macOS 14 Sonoma or macOS 15+ Sequoia.
2. **Xcode Command Line Tools**:
   ```bash
   xcode-select --install
   ```
3. **Steam for macOS**: Installed at `/Applications/Steam.app`.
4. **Wine Runtime (Game Porting Toolkit or Wine-Crossover)**:
   - Recommended via Homebrew (official Apple Game Porting Toolkit recommendation):
     ```bash
     brew tap gcenx/wine
     brew install --cask --no-quarantine game-porting-toolkit
     ```
     *(or `brew install --cask --no-quarantine wine-crossover`)*
   - Or provide any custom Wine 8+ WOW64 runtime directory via `WINE_CROSSOVER_PATH=/path/to/wine`.
5. **Apple Game Porting Toolkit 4 (Beta 2)**:
   - Download the official DMG from [Apple Developer Downloads](https://developer.apple.com/download/all/) (search for *Game Porting Toolkit 4* or *Evaluation environment for Windows games 4.0 beta 2*).
   - Place the `.dmg` in `~/Downloads` (the setup script will automatically locate and mount it), or mount it manually.

---

## Automated Setup

Run the setup script from the repository root:

```bash
./scripts/setup-gptk4.sh
```

### What the Script Does Automatically:
1. **Verifies Prerequisites**: Checks architecture (`arm64`), development tools, and Steam installation.
2. **Resolves Wine Runtime**: Detects existing runner, Homebrew (`game-porting-toolkit` / `wine-crossover`), or user-specified path, and syncs the runtime into `~/Library/Application Support/notproton/runners/gptk-4-beta2`.
3. **Integrates GPTK 4 (Beta 2)**: Detects mounted GPTK volumes or locates the DMG in `~/Downloads` / local folders, mounts it, and installs `D3DMetal.framework` and `libd3dshared.dylib`.
4. **Builds NotProton**: Compiles `notproton.dylib`, `overlay-shim.dylib`, and helper binaries (`iconmaker`, `appinfo`).
5. **Stages Valve Bridge**: Downloads and hashes Valve binaries from the Akamai CDN (including 64-bit and 32-bit `steamclient`, `tier0_s`, `vstdlib_s`, and `legacycompat` tools).
6. **Patches Steam**: Backs up `Info.plist`, configures `DYLD_INSERT_LIBRARIES`, re-signs Steam binaries with ad-hoc signatures, and updates LaunchServices.
7. **Registers Compatibility Tool**: Installs `compatibilitytool.vdf` in Steam's `compatibilitytools.d` directory as **Game Porting Toolkit 4**.

### Optional Overrides

You can optionally specify custom paths using environment variables:

```bash
# Custom Wine-Crossover runtime
WINE_CROSSOVER_PATH=/path/to/custom/wine ./scripts/setup-gptk4.sh

# Custom GPTK DMG file
GPTK4_DMG=/path/to/Game_Porting_Toolkit_4.0_beta_2.dmg ./scripts/setup-gptk4.sh

# Force clean reinstall of runner
./scripts/setup-gptk4.sh --force
```

---

## Running Games

### Method 1: Directly in Steam (Recommended)

1. Restart Steam to ensure the injected dylib is loaded:
   ```bash
   pkill steam_osx && open -a /Applications/Steam.app
   ```
2. Enable the tool in Steam:
   - **For all Windows titles**: Open **Steam → Settings → Compatibility** → check *Enable Steam Play for all other titles* → select **Game Porting Toolkit 4**.
   - **For a specific game**: Right-click the game → **Properties → Compatibility** → check *Force the use of a specific Steam Play compatibility tool* → select **Game Porting Toolkit 4**.
3. Click **Play** on any game!

### Method 2: From the Terminal

Use the included helper script:

```bash
# Launch a game by AppID
./scripts/launch-game.sh <AppID>

# Launch and follow the execution log in real time
./scripts/launch-game.sh <AppID> --tail

# Launch with the Apple Metal Performance HUD enabled
./scripts/launch-game.sh <AppID> --hud --tail
```

---

## Enabling the Metal Performance & Version HUD

To display the Apple Metal HUD (displaying Metal version, frame times, FPS, and GPTK translation stats):
- In Steam: Right-click game → **Properties → General → Launch Options**, and enter:
  ```bash
  MTL_HUD_ENABLED=1 %command%
  ```

---

## Troubleshooting & Logs

- **Runner Script Log**:
  `~/Library/Application Support/Steam/steamapps/compatdata/<AppID>/notproton-run.log`
- **Wine / Game Log**:
  `~/Library/Application Support/notproton/launchers/<AppID>/notproton-wine.log`
- **Prefix Location**:
  `~/Library/Application Support/Steam/steamapps/compatdata/<AppID>/pfx/`
