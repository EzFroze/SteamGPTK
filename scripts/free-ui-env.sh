#!/bin/bash
# SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
# Shared Swift toolchain selection for SteamGPTK builds and tests.
steamgptk_swift_options() {
    local swift_cache="$1"
    local sdk_path="${NP_UI_SDK:-}"
    if [[ -z "$sdk_path" ]]; then
        if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
            sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
        else
            sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
        fi
    fi
    # Consumed by the build/test scripts that source this helper.
    # shellcheck disable=SC2034
    STEAMGPTK_SWIFT_ARGS=(--package-path app -c debug --arch arm64 --sdk "$sdk_path"
        --scratch-path "$swift_cache" -Xswiftc -DNOTPROTON_SDK26)
}
