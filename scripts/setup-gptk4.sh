#!/bin/bash
# SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
# ==============================================================================
# setup-gptk4.sh
# 
# Standalone, reproducible setup script for running Windows Steam games via
# SteamGPTK using Wine-Crossover (WOW64) and Apple Game Porting Toolkit 4 (Beta 2).
#
# This script is completely standalone and agnostic to third-party launchers
# (Heroic, Whisky, etc.). It resolves the Wine runtime and integrates
# Apple's Game Porting Toolkit 4 directly into SteamGPTK.
#
# Requirements:
#   - macOS Sonoma 14+ / Sequoia 15+ on Apple Silicon (arm64)
#   - Xcode Command Line Tools (`xcode-select --install`)
#   - Native Steam.app installed in /Applications/Steam.app
#   - Apple Game Porting Toolkit 4 (Beta 2) DMG or extracted folder
#     (Download from https://developer.apple.com/games/)
#
# Optional Environment Overrides:
#   WINE_CROSSOVER_URL  - Custom URL to Wine tar archive
#   WINE_CROSSOVER_PATH - Custom directory containing Wine runtime
#   GPTK4_PATH          - Custom directory containing D3DMetal.framework
#   GPTK4_DMG           - Path to Apple's Game Porting Toolkit 4 DMG file
# ==============================================================================

set -euo pipefail

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${BLUE}${BOLD}==>${NC} ${BOLD}%s${NC}\n" "$*"; }
ok()    { printf "${GREEN}  ✓ %s${NC}\n" "$*"; }
warn()  { printf "${YELLOW}  ! %s${NC}\n" "$*"; }
error() { printf "${RED}${BOLD}  ✗ %s${NC}\n" "$*"; }
fatal() { error "$*"; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/steamgptk"
RUNNERS_DIR="$SUPPORT_DIR/runners"
BRIDGE_DIR="$SUPPORT_DIR/bridge"
DOWNLOADS_DIR="$SUPPORT_DIR/downloads"
RUNNER_TARGET="$RUNNERS_DIR/gptk-4-beta2"
STEAM_APP="/Applications/Steam.app"
STEAM_COMPAT_DIR="$HOME/Library/Application Support/Steam/compatibilitytools.d/steamgptk-proton"

FORCE_REINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE_REINSTALL=1
            ;;
        --help|-h)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Options:"
            echo "  --force, -f    Force re-fetching and re-assembling the runner"
            exit 0
            ;;
    esac
done

info "Setting up SteamGPTK with Wine-Crossover-Latest and GPTK 4 (Beta 2)..."

# ------------------------------------------------------------------------------
# 1. System & Prerequisite Checks
# ------------------------------------------------------------------------------
info "Checking prerequisites..."

ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
    fatal "SteamGPTK with GPTK 4 requires an Apple Silicon Mac (arm64). Detected: $ARCH"
fi
ok "Architecture: Apple Silicon ($ARCH)"

if [ ! -d "$STEAM_APP" ]; then
    fatal "Steam.app not found at $STEAM_APP. Please install Steam for macOS first."
fi
ok "Found Steam.app at $STEAM_APP"

for tool in clang git make python3 unzip curl tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fatal "Required command '$tool' not found. Please install Xcode CLI tools or Homebrew."
    fi
done
ok "Core development tools present"

mkdir -p "$RUNNERS_DIR" "$DOWNLOADS_DIR" "$SUPPORT_DIR/backups"

# ------------------------------------------------------------------------------
# 2. Acquire Wine-Crossover Runtime (Standalone)
# ------------------------------------------------------------------------------
info "Resolving Wine-Crossover runtime (Wine 8.0.1 / CX 23.7.1 WOW64)..."

WINE_RUNTIME=""

# Check if already present in target runner and valid
if [ "$FORCE_REINSTALL" -eq 0 ] && [ -x "$RUNNER_TARGET/bin/wine" ] && [ -x "$RUNNER_TARGET/bin/wineserver" ]; then
    WINE_RUNTIME="$RUNNER_TARGET"
    ok "Found existing Wine-Crossover runtime in $RUNNER_TARGET"
fi

# Check user-specified custom path
if [ -z "$WINE_RUNTIME" ] && [ -n "${WINE_CROSSOVER_PATH:-}" ]; then
    if [ -d "$WINE_CROSSOVER_PATH/Contents/Resources/wine" ]; then
        WINE_RUNTIME="$WINE_CROSSOVER_PATH/Contents/Resources/wine"
    elif [ -d "$WINE_CROSSOVER_PATH/bin" ]; then
        WINE_RUNTIME="$WINE_CROSSOVER_PATH"
    fi
fi

# Check common system locations (e.g. Homebrew or existing installs)
if [ -z "$WINE_RUNTIME" ]; then
    CANDIDATE_WINE_PATHS=(
        "/Applications/Game Porting Toolkit.app/Contents/Resources/wine"
        "/Applications/Wine Crossover.app/Contents/Resources/wine"
        "/Applications/Wine Staging.app/Contents/Resources/wine"
        "/opt/homebrew/opt/game-porting-toolkit/Contents/Resources/wine"
        "/opt/homebrew/opt/wine-crossover/Contents/Resources/wine"
        "/opt/homebrew/opt/wine-crossover"
        "/opt/homebrew/opt/game-porting-toolkit"
        "$HOME/Library/Application Support/heroic/tools/wine/Wine-Crossover-latest/Contents/Resources/wine"
    )
    for p in "${CANDIDATE_WINE_PATHS[@]}"; do
        if [ -x "$p/bin/wine" ] && [ -x "$p/bin/wineserver" ]; then
            WINE_RUNTIME="$p"
            ok "Found Wine-Crossover at: $p"
            break
        fi
    done
fi

# If still not found, check if a custom download URL was provided via WINE_CROSSOVER_URL
if [ -z "$WINE_RUNTIME" ]; then
    if [ -n "${WINE_CROSSOVER_URL:-}" ]; then
        ARCHIVE_NAME="$(basename "$WINE_CROSSOVER_URL")"
        ARCHIVE_PATH="$DOWNLOADS_DIR/$ARCHIVE_NAME"

        info "Downloading Wine runtime from $WINE_CROSSOVER_URL..."
        if [ ! -f "$ARCHIVE_PATH" ]; then
            curl -fSL --progress-bar -o "$ARCHIVE_PATH.part" "$WINE_CROSSOVER_URL"
            mv "$ARCHIVE_PATH.part" "$ARCHIVE_PATH"
        fi

        info "Extracting Wine runtime into runner directory..."
        mkdir -p "$RUNNER_TARGET"
        tar -xf "$ARCHIVE_PATH" -C "$DOWNLOADS_DIR"

        # Locate extracted runtime
        EXTRACTED_WINE="$(find "$DOWNLOADS_DIR" -type d -name "wine" -path "*/Contents/Resources/wine" | head -1)"
        if [ -z "$EXTRACTED_WINE" ]; then
            EXTRACTED_WINE="$(find "$DOWNLOADS_DIR" -type d -path "*/bin" -exec dirname {} \; | grep -v "$RUNNERS_DIR" | head -1)"
        fi
        if [ -n "$EXTRACTED_WINE" ] && [ -d "$EXTRACTED_WINE" ]; then
            rsync -a "$EXTRACTED_WINE/" "$RUNNER_TARGET/"
            WINE_RUNTIME="$RUNNER_TARGET"
            ok "Extracted Wine runtime to $RUNNER_TARGET"
        else
            fatal "Could not locate Wine binaries inside extracted archive."
        fi
    else
        echo ""
        error "Could not find a compatible Wine runtime (Game Porting Toolkit, Wine-Crossover, or Wine-Staging)."
        echo ""
        warn "How to install a compatible Wine runtime on macOS:"
        echo "  1. Via Homebrew (recommended by Apple Game Porting Toolkit):"
        echo "     brew tap gcenx/wine"
        echo "     brew install --cask --no-quarantine game-porting-toolkit"
        echo "     (or brew install --cask --no-quarantine wine-crossover)"
        echo ""
        echo "  2. Or specify an existing Wine directory path via environment variable:"
        echo "     WINE_CROSSOVER_PATH=/path/to/wine ./scripts/setup-gptk4.sh"
        echo ""
        echo "  3. Or specify a custom download URL via environment variable:"
        echo "     WINE_CROSSOVER_URL=https://... ./scripts/setup-gptk4.sh"
        echo ""
        fatal "Wine runtime missing."
    fi
elif [ "$WINE_RUNTIME" != "$RUNNER_TARGET" ]; then
    info "Syncing Wine-Crossover runtime into $RUNNER_TARGET..."
    mkdir -p "$RUNNER_TARGET"
    rsync -a --delete \
        --exclude "lib/external" \
        --exclude "lib/wine/x86_64-unix/D3DMetal.framework" \
        "$WINE_RUNTIME/" "$RUNNER_TARGET/"
    ok "Wine-Crossover synced to runner directory"
fi

# ------------------------------------------------------------------------------
# 3. Locate & Integrate Apple Game Porting Toolkit 4 (Beta 2)
# ------------------------------------------------------------------------------
info "Resolving Apple Game Porting Toolkit 4 (D3DMetal.framework)..."

D3DM_FRAMEWORK=""
D3D_SHARED=""
DMG_TO_UNMOUNT=""

cleanup_mount() {
    if [ -n "$DMG_TO_UNMOUNT" ] && [ -d "$DMG_TO_UNMOUNT" ]; then
        info "Detaching temporary GPTK mount: $DMG_TO_UNMOUNT"
        hdiutil detach "$DMG_TO_UNMOUNT" -force >/dev/null 2>&1 || true
    fi
}
trap cleanup_mount EXIT INT TERM

# Check if target runner already has D3DMetal installed
if [ "$FORCE_REINSTALL" -eq 0 ] && [ -d "$RUNNER_TARGET/lib/external/D3DMetal.framework" ]; then
    D3DM_FRAMEWORK="$RUNNER_TARGET/lib/external/D3DMetal.framework"
    D3D_SHARED="$RUNNER_TARGET/lib/external/libd3dshared.dylib"
    ok "Found existing GPTK 4 D3DMetal in $RUNNER_TARGET"
fi

# Check custom GPTK4_PATH
if [ -z "$D3DM_FRAMEWORK" ] && [ -n "${GPTK4_PATH:-}" ]; then
    for sub in "$GPTK4_PATH" "$GPTK4_PATH/Contents/Resources/wine" "$GPTK4_PATH/redist"; do
        if [ -d "$sub/lib/external/D3DMetal.framework" ]; then
            D3DM_FRAMEWORK="$sub/lib/external/D3DMetal.framework"
            D3D_SHARED="$sub/lib/external/libd3dshared.dylib"
            break
        fi
    done
fi

# Check if GPTK is currently mounted under /Volumes/
if [ -z "$D3DM_FRAMEWORK" ]; then
    for vol in /Volumes/*Evaluation* /Volumes/*Game*Porting* /Volumes/*GPTK*; do
        if [ -d "$vol/redist/lib/external/D3DMetal.framework" ]; then
            D3DM_FRAMEWORK="$vol/redist/lib/external/D3DMetal.framework"
            D3D_SHARED="$vol/redist/lib/external/libd3dshared.dylib"
            ok "Found mounted GPTK at $vol"
            break
        fi
    done
fi

# Check for local extracted directories or DMGs
if [ -z "$D3DM_FRAMEWORK" ]; then
    SEARCH_DIRS=(
        "$HOME/Downloads"
        "$HOME/Desktop"
        "$REPO_ROOT"
        "$HOME"
    )

    # Search for an already extracted directory
    for dir in "${SEARCH_DIRS[@]}"; do
        CANDIDATES=$(find "$dir" -maxdepth 3 -type d \( -iname "*Evaluation environment*" -o -iname "*Game_Porting_Toolkit*" \) 2>/dev/null || true)
        while IFS= read -r cand; do
            [ -n "$cand" ] || continue
            for sub in "$cand/redist/lib/external" "$cand/lib/external" "$cand/Contents/Resources/wine/lib/external"; do
                if [ -d "$sub/D3DMetal.framework" ]; then
                    D3DM_FRAMEWORK="$sub/D3DMetal.framework"
                    D3D_SHARED="$sub/libd3dshared.dylib"
                    ok "Found extracted GPTK at $cand"
                    break 2
                fi
            done
        done <<< "$CANDIDATES"
    done
fi

# Search for a DMG file to automatically mount
if [ -z "$D3DM_FRAMEWORK" ]; then
    CANDIDATE_DMG="${GPTK4_DMG:-}"
    if [ -z "$CANDIDATE_DMG" ]; then
        for dir in "${SEARCH_DIRS[@]}"; do
            FOUND_DMG=$(find "$dir" -maxdepth 2 -type f \( -iname "*Evaluation*4*.dmg" -o -iname "*Game_Porting_Toolkit*4*.dmg" -o -iname "*GPTK*4*.dmg" \) 2>/dev/null | head -1 || true)
            if [ -n "$FOUND_DMG" ] && [ -f "$FOUND_DMG" ]; then
                CANDIDATE_DMG="$FOUND_DMG"
                break
            fi
        done
    fi

    if [ -n "$CANDIDATE_DMG" ] && [ -f "$CANDIDATE_DMG" ]; then
        info "Mounting GPTK DMG: $CANDIDATE_DMG..."
        MOUNT_OUT="$(hdiutil attach -nobrowse -readonly "$CANDIDATE_DMG" 2>&1)"
        MOUNT_PT="$(echo "$MOUNT_OUT" | grep -o '/Volumes/.*' | head -1)"
        if [ -n "$MOUNT_PT" ] && [ -d "$MOUNT_PT" ]; then
            DMG_TO_UNMOUNT="$MOUNT_PT"
            for sub in "$MOUNT_PT/redist/lib/external" "$MOUNT_PT/lib/external"; do
                if [ -d "$sub/D3DMetal.framework" ]; then
                    D3DM_FRAMEWORK="$sub/D3DMetal.framework"
                    D3D_SHARED="$sub/libd3dshared.dylib"
                    ok "Mounted and located D3DMetal in $MOUNT_PT"
                    break
                fi
            done
        fi
    fi
fi

# Check other existing local installations (e.g. Heroic if previously installed)
if [ -z "$D3DM_FRAMEWORK" ]; then
    for heroic_cand in \
        "$HOME/Library/Application Support/heroic/tools/game-porting-toolkit/gptk-4-test" \
        "$HOME/Library/Application Support/heroic/tools/game-porting-toolkit/Game-Porting-Toolkit-4.0"; do
        if [ -d "$heroic_cand/Contents/Resources/wine/lib/external/D3DMetal.framework" ]; then
            D3DM_FRAMEWORK="$heroic_cand/Contents/Resources/wine/lib/external/D3DMetal.framework"
            D3D_SHARED="$heroic_cand/Contents/Resources/wine/lib/external/libd3dshared.dylib"
            ok "Found GPTK 4 in $heroic_cand"
            break
        fi
    done
fi

if [ -z "$D3DM_FRAMEWORK" ] || [ ! -d "$D3DM_FRAMEWORK" ]; then
    echo ""
    error "Could not find Apple Game Porting Toolkit 4 (D3DMetal.framework)."
    echo ""
    warn "How to obtain Game Porting Toolkit 4 (Beta 2):"
    echo "  1. Sign in to https://developer.apple.com/download/all/ (free Apple Developer account)"
    echo "  2. Download 'Game Porting Toolkit 4' or 'Evaluation environment for Windows games 4.0 beta 2.dmg'"
    echo "  3. Place the .dmg file in ~/Downloads (or open/mount it)"
    echo "  4. Re-run this script: ./scripts/setup-gptk4.sh"
    echo "     (Or specify path: GPTK4_DMG=/path/to/dmg $0)"
    echo ""
    fatal "GPTK 4 components missing."
fi

# Copy D3DMetal.framework and libd3dshared.dylib into runner target
if [ "$D3DM_FRAMEWORK" != "$RUNNER_TARGET/lib/external/D3DMetal.framework" ]; then
    info "Installing D3DMetal.framework and libd3dshared.dylib into runner..."
    mkdir -p "$RUNNER_TARGET/lib/external"
    cp -R -f "$D3DM_FRAMEWORK" "$RUNNER_TARGET/lib/external/"
    if [ -f "$D3D_SHARED" ]; then
        cp -f "$D3D_SHARED" "$RUNNER_TARGET/lib/external/"
    fi
fi

# Symlink D3DMetal into x86_64-unix
mkdir -p "$RUNNER_TARGET/lib/wine/x86_64-unix"
ln -sfn "../../external/D3DMetal.framework" "$RUNNER_TARGET/lib/wine/x86_64-unix/D3DMetal.framework"
ln -sfn "gptk-4-beta2" "$RUNNERS_DIR/current"
ok "Runner assembled: $RUNNERS_DIR/current -> gptk-4-beta2"

# ------------------------------------------------------------------------------
# 4. Build SteamGPTK Dylib & Helpers
# ------------------------------------------------------------------------------
info "Building SteamGPTK core binaries..."

cd "$REPO_ROOT"

if [ ! -f "build/dobby/libdobby.a" ]; then
    info "Building Dobby inline hook library..."
    make dobby
fi

make all overlay-shim helpers-install
ok "Built steamgptk.dylib, overlay-shim.dylib, and helpers"

# ------------------------------------------------------------------------------
# 5. Fetch and Stage Valve Bridge Components (64-bit and 32-bit)
# ------------------------------------------------------------------------------
info "Fetching and staging Valve client bridge files..."

./bridge/fetch-valve.sh --install

# Configure steamclient redirection to lsteamclient
if [ -f "$BRIDGE_DIR/x86_64-windows/lsteamclient.dll" ]; then
    mkdir -p "$RUNNER_TARGET/lib/wine/x86_64-windows"
    cp -f "$BRIDGE_DIR/x86_64-windows/lsteamclient.dll" "$RUNNER_TARGET/lib/wine/x86_64-windows/lsteamclient.dll"
    # Stage lsteamclient as 64-bit steamclient64.dll in bridge
    [ -f "$BRIDGE_DIR/steamclient64.dll.valve" ] || cp -p "$BRIDGE_DIR/steamclient64.dll" "$BRIDGE_DIR/steamclient64.dll.valve" 2>/dev/null || true
    cp -f "$BRIDGE_DIR/x86_64-windows/lsteamclient.dll" "$BRIDGE_DIR/steamclient64.dll"
fi
if [ -f "$BRIDGE_DIR/i386-windows/lsteamclient.dll" ]; then
    # Patch lsteamclient.dll to return NULL in get_mem_from_steamclient_dll.
    # When lsteamclient is loaded as steamclient.dll (SteamGPTK standalone),
    # carving memory from .data overwrites internal globals (steamclient_cs, interfaces list),
    # causing an access violation in create_win_interface. Returning NULL safely falls
    # back to direct vtables, matching 64-bit Proton behavior.
    python3 -c "
p = '$BRIDGE_DIR/i386-windows/lsteamclient.dll'
with open(p, 'r+b') as f:
    f.seek(0xbc40)
    cur = f.read(3)
    if cur == b'\x55\x89\xe5':
        f.seek(0xbc40)
        f.write(b'\x31\xc0\xc3')
" 2>/dev/null || true
    mkdir -p "$RUNNER_TARGET/lib/wine/i386-windows"
    cp -f "$BRIDGE_DIR/i386-windows/lsteamclient.dll" "$RUNNER_TARGET/lib/wine/i386-windows/lsteamclient.dll"
    # Stage lsteamclient as 32-bit steamclient.dll in bridge so 32-bit games route Steamworks via lsteamclient
    [ -f "$BRIDGE_DIR/steamclient.dll.valve" ] || cp -p "$BRIDGE_DIR/steamclient.dll" "$BRIDGE_DIR/steamclient.dll.valve" 2>/dev/null || true
    cp -f "$BRIDGE_DIR/i386-windows/lsteamclient.dll" "$BRIDGE_DIR/steamclient.dll"
fi
if [ -f "$BRIDGE_DIR/x86_64-unix/lsteamclient.so" ]; then
    mkdir -p "$RUNNER_TARGET/lib/wine/x86_64-unix"
    cp -f "$BRIDGE_DIR/x86_64-unix/lsteamclient.so" "$RUNNER_TARGET/lib/wine/x86_64-unix/lsteamclient.so"
    ln -sf "lsteamclient.so" "$RUNNER_TARGET/lib/wine/x86_64-unix/steamclient.so"
    ln -sf "lsteamclient.so" "$RUNNER_TARGET/lib/wine/x86_64-unix/steamclient64.so"
    ln -sf "lsteamclient.so" "$BRIDGE_DIR/x86_64-unix/steamclient.so"
    ln -sf "lsteamclient.so" "$BRIDGE_DIR/x86_64-unix/steamclient64.so"
    ln -sf "x86_64-unix/lsteamclient.so" "$BRIDGE_DIR/steamclient.so"
    ln -sf "x86_64-unix/lsteamclient.so" "$BRIDGE_DIR/steamclient64.so"


    # Build and stage ntdll_compat.so for Wine-Crossover to provide missing Proton-specific ntdll exports and ABI wrappers
    cat << 'EOF' > "$BRIDGE_DIR/x86_64-unix/ntdll_compat.c"
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>

static void *get_wine_ntdll(void) {
    static void *h = NULL;
    if (!h) {
        h = dlopen("@rpath/ntdll.so", RTLD_NOLOAD | RTLD_NOW);
        if (!h) h = dlopen("ntdll.so", RTLD_NOW);
    }
    return h;
}

const char *__wine_dbg_strdup(const char *str) {
    static __thread char bufs[32][1024];
    static __thread int idx = 0;
    if (!str) return "(null)";
    char *b = bufs[idx++ % 32];
    strncpy(b, str, 1023);
    b[1023] = '\0';
    return b;
}

int __wine_dbg_header(int cls, void *ch, const char *fn) {
    return 0;
}

int __wine_dbg_output(const char *str) {
    if (str) fputs(str, stderr);
    return 0;
}

int ntdll_get_dos_file_name(const char *src, void **dst, uint32_t disp) {
    if (dst) *dst = 0;
    return 0xc0000002;
}

int ntdll_get_unix_file_name(const void *src, char **dst, uint32_t disp) {
    if (dst) *dst = 0;
    return 0xc0000002;
}

int ntdll_umbstowcs(const char *src, size_t srclen, void *dst, size_t dstlen) {
    return 0;
}

int ntdll_wcstoumbs(const void *src, size_t srclen, char *dst, size_t dstlen, int strict) {
    return 0;
}

typedef __attribute__((ms_abi)) int (*nt_close_fn)(void *h);
int NtClose(void *h) {
    static nt_close_fn fn = NULL;
    if (!fn) fn = (nt_close_fn)dlsym(get_wine_ntdll(), "NtClose");
    return fn ? fn(h) : 0xc0000002;
}

typedef __attribute__((ms_abi)) int (*nt_create_key_fn)(void **key, uint32_t access, void *attr, uint32_t title_index, void *class_name, uint32_t options, void *disposition);
int NtCreateKey(void **key, uint32_t access, void *attr, uint32_t title_index, void *class_name, uint32_t options, void *disposition) {
    static nt_create_key_fn fn = NULL;
    if (!fn) fn = (nt_create_key_fn)dlsym(get_wine_ntdll(), "NtCreateKey");
    return fn ? fn(key, access, attr, title_index, class_name, options, disposition) : 0xc0000002;
}

typedef __attribute__((ms_abi)) int (*nt_query_token_fn)(void *token, int info_class, void *info, uint32_t length, uint32_t *ret_length);
int NtQueryInformationToken(void *token, int info_class, void *info, uint32_t length, uint32_t *ret_length) {
    static nt_query_token_fn fn = NULL;
    if (!fn) fn = (nt_query_token_fn)dlsym(get_wine_ntdll(), "NtQueryInformationToken");
    return fn ? fn(token, info_class, info, length, ret_length) : 0xc0000002;
}

typedef __attribute__((ms_abi)) int (*nt_set_value_key_fn)(void *key, void *value_name, uint32_t title_index, uint32_t type, const void *data, uint32_t data_size);
int NtSetValueKey(void *key, void *value_name, uint32_t title_index, uint32_t type, const void *data, uint32_t data_size) {
    static nt_set_value_key_fn fn = NULL;
    if (!fn) fn = (nt_set_value_key_fn)dlsym(get_wine_ntdll(), "NtSetValueKey");
    return fn ? fn(key, value_name, title_index, type, data, data_size) : 0xc0000002;
}
EOF

    clang -arch x86_64 -dynamiclib -o "$BRIDGE_DIR/x86_64-unix/ntdll_compat.so" \
      -install_name @rpath/ntdll_compat.so \
      -Wl,-rpath,"$RUNNER_TARGET/lib/wine/x86_64-unix" \
      -Wl,-reexport_library,"$RUNNER_TARGET/lib/wine/x86_64-unix/ntdll.so" \
      -headerpad_max_install_names \
      "$BRIDGE_DIR/x86_64-unix/ntdll_compat.c"
    codesign --remove-signature "$BRIDGE_DIR/x86_64-unix/ntdll_compat.so" 2>/dev/null || true
    cp -f "$BRIDGE_DIR/x86_64-unix/ntdll_compat.so" "$RUNNER_TARGET/lib/wine/x86_64-unix/ntdll_compat.so"

    for p in "$BRIDGE_DIR/x86_64-unix/lsteamclient.so" "$RUNNER_TARGET/lib/wine/x86_64-unix/lsteamclient.so"; do
        install_name_tool -change @rpath/ntdll.so @rpath/ntdll_compat.so "$p" 2>/dev/null || true
        codesign --remove-signature "$p" 2>/dev/null || true
    done
fi
if [ -f "$BRIDGE_DIR/aarch64-unix/lsteamclient.so" ] && [ -d "$RUNNER_TARGET/lib/wine/aarch64-unix" ]; then
    ln -sf "lsteamclient.so" "$RUNNER_TARGET/lib/wine/aarch64-unix/steamclient.so"
    ln -sf "lsteamclient.so" "$RUNNER_TARGET/lib/wine/aarch64-unix/steamclient64.so"
fi
ok "Valve bridge libraries staged (with lsteamclient routing and compatibility patches for Steamworks)"

# ------------------------------------------------------------------------------
# 6. Patch Steam Client & Install Tool Manifest
# ------------------------------------------------------------------------------
info "Patching native Steam client..."

PLIST="$STEAM_APP/Contents/Info.plist"
BACKUP_DIR="$SUPPORT_DIR/backups"
STEAM_DYLIB="$STEAM_APP/Contents/MacOS/steamgptk.dylib"

if [ ! -f "$BACKUP_DIR/Info.plist.before-steamgptk" ]; then
    cp -p "$PLIST" "$BACKUP_DIR/Info.plist.before-steamgptk"
    ok "Backed up original Info.plist to $BACKUP_DIR/Info.plist.before-steamgptk"
fi

# Deploy dylib into Steam bundle
cp -f "$REPO_ROOT/out/steamgptk.dylib" "$STEAM_DYLIB"

# Configure DYLD_INSERT_LIBRARIES in Steam Info.plist
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $STEAM_DYLIB" "$PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :LSEnvironment:DYLD_INSERT_LIBRARIES $STEAM_DYLIB" "$PLIST"

# Re-sign modified binaries
info "Re-signing Steam binaries with ad-hoc signature..."
codesign -f -s - "$STEAM_DYLIB"
codesign -f -s - "$STEAM_APP/Contents/MacOS/steam_osx"
codesign -f -s - "$STEAM_APP"

# Update LaunchServices
info "Refreshing LaunchServices registration..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$STEAM_APP"
ok "Steam.app signed and registered"

# Install Compatibility Tool Manifest
info "Installing Steam compatibility tool manifest..."
mkdir -p "$STEAM_COMPAT_DIR"

cat > "$STEAM_COMPAT_DIR/compatibilitytool.vdf" << 'EOF'
"compatibilitytools"
{
  "compat_tools"
  {
    "steamgptk-proton"
    {
      "install_path" "."
      "display_name" "Game Porting Toolkit 4"
      "from_oslist" "windows"
      "to_oslist" "macos"
    }
  }
}
EOF

cat > "$STEAM_COMPAT_DIR/toolmanifest.vdf" << 'EOF'
"manifest"
{
  "version" "2"
  "commandline" "/run %verb%"
}
EOF

cp -f "$REPO_ROOT/dylib/feats/compat_run.sh" "$STEAM_COMPAT_DIR/run"
chmod +x "$STEAM_COMPAT_DIR/run"
ok "Steam compatibility tool registered as 'Game Porting Toolkit 4'"

# ------------------------------------------------------------------------------
# 7. Verification
# ------------------------------------------------------------------------------
info "Verifying setup..."

TEST_PATH="$(STEAM_COMPAT_DATA_PATH="/tmp/steamgptk_test" "$STEAM_COMPAT_DIR/run" getcompatpath 2>/dev/null || true)"
if [ "$TEST_PATH" = "/tmp/steamgptk_test" ]; then
    ok "Compat run script responds correctly"
else
    warn "Compat run script returned unexpected test path: $TEST_PATH"
fi

echo ""
printf '%b%b==============================================================================%b\n' "$GREEN" "$BOLD" "$NC"
printf '%b%b  SteamGPTK with GPTK 4 (Beta 2) successfully installed!%b\n' "$GREEN" "$BOLD" "$NC"
printf '%b%b==============================================================================%b\n' "$GREEN" "$BOLD" "$NC"
echo ""
echo "How to run games:"
echo "  1. If Steam is currently running, restart it to load the patched dylib:"
echo "       pkill steam_osx && open -a /Applications/Steam.app"
echo "  2. In Steam, open Settings -> Compatibility:"
echo "       Enable Steam Play for all other titles -> Select 'Game Porting Toolkit 4'"
echo "     (Or right-click any game -> Properties -> Compatibility -> Game Porting Toolkit 4)"
echo "  3. To launch a game from command line or scripts:"
echo "       ./scripts/launch-game.sh <AppID>"
echo "  4. To enable the Metal Performance & Version HUD in game:"
echo "       Set Launch Options in Steam to: MTL_HUD_ENABLED=1 %command%"
echo ""
