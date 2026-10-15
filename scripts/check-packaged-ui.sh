#!/bin/bash
# SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
# Check a relocated app without opening a window or inspecting an installed runtime.
set -euo pipefail
app_path="${1:?Usage: check-packaged-ui.sh /path/to/SteamGPTK.app}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/steamgptk-resources.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
ditto "$app_path" "$scratch/SteamGPTK.app"
codesign --verify --deep --strict "$scratch/SteamGPTK.app"
python3 - "$scratch/SteamGPTK.app/Contents/MacOS/SteamGPTKApp" <<'PY'
import os, subprocess, sys
environment = os.environ.copy()
for name in ['PACKAGE_RESOURCE_BUNDLE_PATH', 'PACKAGE_RESOURCE_BUNDLE_URL']:
    environment.pop(name, None)
subprocess.run([sys.argv[1], '--check-resources'], env=environment, check=True, timeout=30)
PY
