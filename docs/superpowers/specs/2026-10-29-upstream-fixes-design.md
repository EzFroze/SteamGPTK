# Selected upstream fixes for SteamGPTK

The requested scope is a separate branch containing launch, Steam integration, and overlay fixes from NotProton through `a479c84923e853ddf8bf3a965fb4287ebfdcfd28`, with a passing build and tests. The user approved this selective approach on 2026-10-29.

Preserve SteamGPTK branding, user-imported GPTK, the free Wine runner, `hl2-v1`, manual profile overrides, Steam Cloud layout, the 32-bit bridge, and shader caches. Do not install the result, push, merge to main, bump the release, or modify the user's Steam/game configuration.

## Approaches

A full upstream merge was considered and rejected for this iteration: it has 79 conflicting paths and introduces unrelated CrossOver/FEX changes and new features. The selected approach is to port individual bug fixes with their regression tests, adapting renamed paths and the free runner. Plugin, CEG, new library filters, global defaults UI, localization, and CrossOver build support are outside the scope.

## Components

- Steam/config/download safety and prefix-operation locking: preserve arbitrary config bytes, distinguish local storage failures, bound downloads, validate copied Steam bundles, handle stale UI loads and quoted manifest names.
- Native integration and overlay: correct Steam allocator ownership, prevent unwanted focus activation, and fix Metal pipeline/encoder ownership.
- Launch path: prefer installed Microsoft VC++ libraries, handle non-Steam shortcut IDs, correct Retina DPI, skip unchanged prefix settings and font links, and reduce launcher registration/bundle comparison overhead.

Upstream patches that depend on omitted features are adapted only at the affected existing boundary. Tests exercise real helpers/scripts with temporary fixtures; live Steam, game, and UI interaction are not needed for this change.
