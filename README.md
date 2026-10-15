# SteamGPTK

Run Windows games from the **native macOS Steam client**, using **Sikarugir Wine 11** and your own **Apple Game Porting Toolkit 4** download. CrossOver is not required.

SteamGPTK is a community fork of [NotProton](https://github.com/NotProtonNot/NotProton). It is not affiliated with Apple, Valve, or CodeWeavers.

[Инструкция на русском](docs/INSTALL.ru.md) · [Maintainer / release guide](docs/PUBLISHING.md) · [Changes](CHANGELOG.md)

## Requirements

- Apple Silicon Mac and macOS 26 or newer for the app.
- Native Steam installed at `/Applications/Steam.app`.
- Rosetta 2. If it is missing, install it with `softwareupdate --install-rosetta` and review Apple's prompt.
- A **GPTK 4 DMG downloaded by you from Apple**. GPTK 4.0 beta 3 was tested; compatibility with other versions is not established.
- Internet access for the initial Wine, bridge and support-library downloads.

The tested machine is an M1 Pro MacBook Pro running macOS 27.0.1. This is an experimental compatibility tool: support varies by game. The current Wine detour targets 64-bit Windows games; 32-bit games, anti-cheat and DRM compatibility are not guaranteed. Ray tracing is disabled in the initial runtime defaults used for the tested M1 configuration.

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

## Steam Cloud

The launch script unifies Wine's account profile with `steamuser`, so Steam's Windows cloud-save roots and the game resolve to the same files. Conflicting existing saves are not silently overwritten; the launch stops and records the conflict for resolution.

Steam remains responsible for remote uploads and downloads, and each game must support Steam Cloud. The app's **Steam Cloud paths** row checks installation of profile support; it does not report a completed cloud sync. Exit the game and wait for Steam to finish syncing before continuing on Windows.

## Build from source

Install Apple's Command Line Tools (`xcode-select --install`) or Xcode with Swift 6.2 or newer, and install CMake. If you already use Homebrew, `brew install cmake` is sufficient. A full Xcode installation is another supported toolchain; this project does not install Homebrew for you.

```bash
git clone --branch codex/wine-gptk-ui --single-branch https://github.com/EzFroze/SteamGPTK.git
cd SteamGPTK
./scripts/build-free-ui.sh
open out/SteamGPTK.app
```

The explicit branch selects this fork's Wine/GPTK implementation even before it is made the default branch on GitHub. Use a checkout path without spaces when building the native module.

The build pins Dobby and an upstream bridge archive, verifies the archive checksum, compiles the module/UI and produces `out/SteamGPTK.app`. It packages license notices and rejects accidentally staged GPTK renderer binaries. No GPTK image, Wine runtime or patched `ntdll.dll` is packaged with the app. The Wine detour is applied locally to the verified downloaded engine.

`NP_UI_SDK=/path/to/MacOSX.sdk` overrides SDK selection. `NP_UI_BUILD_DIR=/path/to/cache` overrides the Swift build cache. The script uses the installed macOS 26.5 SDK when available, to support Command Line Tools installations without the SwiftUI macro plugin.

```bash
./scripts/test-free-ui.sh
make profilecheck compatcheck webpatch-fixtures compatsvc-check
```

A separate, opt-in full installation test uses only a temporary runtime and your local GPTK image:

```bash
NOTPROTON_INSTALL_SMOKE=1 \
NOTPROTON_GPTK_DMG="/path/to/Game_Porting_Toolkit_4.dmg" \
./scripts/test-free-ui.sh --filter FreeInstallSmokeTests
```

The app does not install the upstream NotProton auto-updates. Obtain updates from this fork and run **Install / Repair** with Steam closed.

## Troubleshooting and removal

- If maintenance buttons are disabled, quit Steam and wait for prefix operations to finish.
- If the DMG is rejected, verify that it contains the GPTK 4 Windows evaluation environment, not only shader-conversion tools.
- Use **Install / Repair** to restore missing Wine or integration components. Imported GPTK is retained when Wine is rebuilt.
- Steam client updates can change the functions used by NotProton. The app offers an update-block toggle; future Steam builds may require a fork update.
- UI log: `~/Library/Application Support/notproton/app.log`.
- Game launch log: `notproton-run.log` inside that game's `steamapps/compatdata/<AppID>/` directory in its Steam library.
- **Original Steam → Restore…** removes the Steam integration. **Remove SteamGPTK → Remove…** also removes the managed runtime and imported GPTK. Game prefixes and saves remain in the Steam library.

Include macOS version, Mac chip, Steam build, game name/AppID and the relevant log excerpt when reporting an issue. Redact account details and personal paths before posting logs publicly.

## Licenses and origin

See [LICENSE](LICENSE), [NOTICE](NOTICE), [lsteamclient license](LICENSE.lsteamclient) and [steam-shim license](LICENSE.steam-shim). The project is principally GPL-3.0, with existing third-party licenses retained. Dependency source references and notices are also included in built apps.

Apple GPTK/D3DMetal files are **not included in this repository or app archive**. Users obtain and import them under Apple's terms. Runtime downloads retain their own upstream licenses; this policy does not replace those terms.

This implementation starts from the tested standalone NotProton commit `5b8d18683b619b66390be8cbcffc1fbf47e45971`, with Wine 11, UI, Steam compatibility and Steam Cloud path fixes. Historical [NotProton documentation](docs/upstream/README-NotProton.md) and [Wine 8/GPTK beta 2 notes](docs/upstream/README-GPTK4-Wine8.md) are preserved for attribution and context, not as current installation instructions.
