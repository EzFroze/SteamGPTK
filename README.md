# SteamGPTK

Run Windows games from the **native macOS Steam client**, using **Sikarugir Wine 11** and your own **Apple Game Porting Toolkit 4** download. CrossOver is not required.

SteamGPTK is a community fork of [NotProton](https://github.com/NotProtonNot/NotProton). It is not affiliated with Apple, Valve, or CodeWeavers.

[Инструкция на русском](docs/INSTALL.ru.md) · [Half-Life 2: быстрый старт](docs/HL2_QUICKSTART.ru.md) · [Maintainer / release guide](docs/PUBLISHING.md) · [Changes](CHANGELOG.md)

## Requirements

- Apple Silicon Mac and macOS 26 or newer for the app.
- Native Steam installed at `/Applications/Steam.app`.
- Rosetta 2. If it is missing, install it with `softwareupdate --install-rosetta` and review Apple's prompt.
- A **GPTK 4 DMG downloaded by you from Apple**. GPTK 4.0 beta 3 was tested; compatibility with other versions is not established.
- Internet access for the initial Wine, bridge and support-library downloads.

The tested machine is an M1 Pro MacBook Pro running macOS 27.0.1. This is an experimental compatibility tool: support varies by game. DirectX 8/9 games use D9VK automatically, including 32-bit titles. Half-Life 2 was tested with this path. Compatibility with other games, anti-cheat and DRM varies. Ray tracing is disabled in the initial runtime defaults used for the tested M1 configuration.

## Installation

### 1. Obtain the app

Download `SteamGPTK.zip` from [this fork's Releases](https://github.com/EzFroze/SteamGPTK/releases), extract it, and open `SteamGPTK.app`. The `.sha256` asset lets you verify the download with `shasum -a 256 -c SteamGPTK.zip.sha256` in the folder containing both files.

You can also use the source build below. Builds from this repository use a local ad-hoc signature and are not notarized by Apple. Follow the app-specific instructions in macOS **System Settings → Privacy & Security** if Gatekeeper asks for approval; do not disable Gatekeeper globally.

### 2. Download your GPTK

Download **Game Porting Toolkit 4** or its **Evaluation environment for Windows games** DMG from [Apple Developer Downloads](https://developer.apple.com/download/all/?q=game%20porting%20toolkit), using your Apple account and reviewing Apple's terms.

Keep the DMG anywhere you like. It does not have to be placed in a particular Downloads folder, extracted, or copied into this repository. Both the outer GPTK DMG and the evaluation-environment DMG are accepted. An image already opened in Finder can be reused.

### 3. Import and install

1. Quit Steam, Windows games and Wine configuration tools.
2. Open **SteamGPTK**.
3. In **Apple GPTK / D3DMetal**, click **Choose DMG…**, then select your downloaded DMG.
4. Wait for Wine preparation and local GPTK import. The previous renderer is retained in a backup when replaced.
5. Click **Install / Repair**. The app stages the Steam bridge, applies the hash-checked Wine detour and installs the integration into Steam.
6. Verify **Wine 11**, **Rosetta 2**, **Apple GPTK / D3DMetal** and **Steam bridge** report ready.
7. Start your regular macOS Steam client and install or launch a Windows game.

Installation and import are disabled while Steam is running. Existing game prefixes and saves are kept during installation and runtime repair. Reinstalling the integration reuses the already imported GPTK; **Import Another…** changes it explicitly.

Windows-only titles use the compatibility tool. Games with a native macOS build keep their native route unless you explicitly select a Windows compatibility tool in that game's Steam settings.

## Graphics and upgrading to 0.2.0

DirectX 8/9 uses **D9VK → Vulkan → Metal** automatically. DirectX 11/12 keeps the selected D3DMetal, DXMT or DXVK backend. An explicit **WineD3D** choice disables the alternative renderers. No `WINEDLLPATH_D9VK` launch option is needed; remove a previously added override after upgrading.

For an existing installation, quit Steam and Wine games, open the new app and click **Install / Repair**. Your imported GPTK, Wine runtime, backups, prefixes and saves are retained. The installer creates a compatible path to existing support files, backs up Steam configuration before updating tool selections, and uses the internal tool identifier `steamgptk-proton` so Steam Cloud continues to map Windows save folders. Conflicting separate old and new support directories are preserved and reported instead of merged.

Vulkan driver paths are corrected during setup and repair. The first D9VK launch can take longer while graphics caches are created. Game performance must be checked during gameplay; menu FPS is not a benchmark.

## Automatic game profiles

Starting with version 0.2.2, SteamGPTK includes an automatic **Half-Life 2** profile (Steam AppID `220`): D9VK 3.1.1-async with KosmicKrisp, D3D9 VSync off, AVX advertisement off, and the verified 32-bit Steam bridge. The profile applies when the Windows game starts through SteamGPTK; no launch options or temporary configuration files are needed. Install / Repair reinstalls the profile and prepares the bridge without changing Valve's original downloaded DLLs.

Explicit launch options override profile settings. `DXVK_CONFIG_FILE` selects your own DXVK config instead of the profile's inline VSync setting. Use `STEAMGPTK_GAME_PROFILE=0` to disable the profile for one game. No profile is applied to other AppIDs, and native macOS launches keep their existing route.

Profiles leave resolution, game graphics settings, Steam Cloud and graphics caches alone. First-time shader compilation can still cause stutter. The HL2 configuration was tested on M1 Pro with Wine 11 and macOS 27.0.1; performance on other configurations is not established. See [profile details and adding another game](docs/GAME_PROFILES.ru.md).

## Steam Cloud

The launch script unifies Wine's account profile with `steamuser`, so Steam's Windows cloud-save roots and the game resolve to the same files. Conflicting existing saves are not silently overwritten; the launch stops and records the conflict for resolution.

Steam remains responsible for remote uploads and downloads, and each game must support Steam Cloud. The app's **Steam Cloud paths** row checks installation of profile support; it does not report a completed cloud sync. Exit the game and wait for Steam to finish syncing before continuing on Windows.

## Build from source

Install Apple's Command Line Tools (`xcode-select --install`) or Xcode with Swift 6.2 or newer, and install CMake. If you already use Homebrew, `brew install cmake` is sufficient. A full Xcode installation is another supported toolchain; this project does not install Homebrew for you.

```bash
git clone https://github.com/EzFroze/SteamGPTK.git
cd SteamGPTK
./scripts/build-free-ui.sh
open out/SteamGPTK.app
```

The default `main` branch contains SteamGPTK. Use a checkout path without spaces when building the native module.

The build pins Dobby and the bridge payload from SteamGPTK 0.1.2, verifies the archive checksum, compiles the module/UI and produces `out/SteamGPTK.app`. It packages license notices and rejects accidentally staged GPTK renderer binaries. No GPTK image, Wine runtime or patched `ntdll.dll` is packaged with the app. The Wine detour is applied locally to the verified downloaded engine.

`NP_UI_SDK=/path/to/MacOSX.sdk` overrides SDK selection. `NP_UI_BUILD_DIR=/path/to/cache` overrides the Swift build cache. The script uses the installed macOS 26.5 SDK when available, to support Command Line Tools installations without the SwiftUI macro plugin.

```bash
./scripts/test-free-ui.sh
make profilecheck gamecheck compatcheck webpatch-fixtures compatsvc-check
```

A separate, opt-in full installation test uses only a temporary runtime and your local GPTK image:

```bash
STEAMGPTK_INSTALL_SMOKE=1 \
STEAMGPTK_GPTK_DMG="/path/to/Game_Porting_Toolkit_4.dmg" \
./scripts/test-free-ui.sh --filter FreeInstallSmokeTests
```

Automatic updates are disabled. Obtain updates from this repository and run **Install / Repair** with Steam closed.

## Troubleshooting and removal

- If maintenance buttons are disabled, quit Steam and wait for prefix operations to finish.
- If the DMG is rejected, verify that it contains the GPTK 4 Windows evaluation environment, not only shader-conversion tools.
- Use **Install / Repair** to restore missing Wine or integration components. Imported GPTK is retained when Wine is rebuilt.
- Steam client updates can change the functions used by SteamGPTK. The app offers an update-block toggle; future Steam builds may require a fork update.
- UI log: `~/Library/Application Support/steamgptk/app.log`.
- Game launch log: `steamgptk-run.log` inside that game's `steamapps/compatdata/<AppID>/` directory in its Steam library.
- **Original Steam → Restore…** removes the Steam integration. **Remove SteamGPTK → Remove…** also removes the managed runtime and imported GPTK. Game prefixes and saves remain in the Steam library.

Include macOS version, Mac chip, Steam build, game name/AppID and the relevant log excerpt when reporting an issue. Redact account details and personal paths before posting logs publicly.

## Licenses and origin

See [LICENSE](LICENSE), [NOTICE](NOTICE), [lsteamclient license](LICENSE.lsteamclient) and [steam-shim license](LICENSE.steam-shim). The project is principally GPL-3.0, with existing third-party licenses retained. Dependency source references and notices are also included in built apps.

Apple GPTK/D3DMetal files are **not included in this repository or app archive**. Users obtain and import them under Apple's terms. Runtime downloads retain their own upstream licenses; this policy does not replace those terms.

This implementation starts from the tested standalone NotProton commit `5b8d18683b619b66390be8cbcffc1fbf47e45971`, with Wine 11, UI, Steam compatibility and Steam Cloud path fixes. Historical [NotProton documentation](docs/upstream/README-NotProton.md) and [Wine 8/GPTK beta 2 notes](docs/upstream/README-GPTK4-Wine8.md) are preserved for attribution and context, not as current installation instructions.
