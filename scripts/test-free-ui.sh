#!/bin/bash
# SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
# Run the UI tests with the same SDK as the documented build.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
build_dir="${NP_UI_BUILD_DIR:-/private/tmp/steamgptk-ui-build-$(id -u)}"
# shellcheck source=scripts/free-ui-env.sh
source "$repo_dir/scripts/free-ui-env.sh"
steamgptk_swift_options "$build_dir"
plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$plugin" ]]; then
    STEAMGPTK_SWIFT_ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
fi
swift test "${STEAMGPTK_SWIFT_ARGS[@]}" "$@"
