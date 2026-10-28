# Selected Upstream Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Port the selected launch, Steam and overlay fixes onto a separate SteamGPTK branch and verify the application build and tests.

**Architecture:** Apply upstream regression tests before corresponding code. Adapt NotProton paths and identifiers to SteamGPTK and retain the existing free runner and game profile boundaries. Import isolated fixes rather than merging new upstream subsystems.

**Tech Stack:** Swift/Swift Testing, C, Objective-C/Metal, POSIX shell, Make, SwiftPM.

**Spec:** `docs/superpowers/specs/2026-10-29-upstream-fixes-design.md`

## Global Constraints

- Preserve SteamGPTK branding, user-imported GPTK, the free Wine runner, `hl2-v1`, manual profile overrides, Steam Cloud layout, the 32-bit bridge, and shader caches.
- Do not install the result, push, merge to main, bump the release, or modify the user's Steam/game configuration.
- Plugin, CEG, new library filters, global defaults UI, localization, and CrossOver build support are outside the scope.

## Review Focus

- Invalid UTF-8/CRLF and unreadable Steam config must not lose unrelated bytes (Task 1 config tests).
- A stalled download must fall back, while a local filesystem error must stop and identify the destination (Task 1 download tests).
- Concurrent prefix operations and stale asynchronous UI loads must not operate on an in-use prefix or publish stale state (Task 1 locking/load tests).
- Repeated overlay pipeline creation and encoder reuse must not retain application objects or bind stale formats (Task 2 ownership tests).
- Default HL2 settings, manual overrides, opt-out and the fixed 32-bit bridge must survive the launch optimizations and repeated Install/Repair (Task 3 GameProfileTests).

### Task 1: Steam and prefix safety

**Files:** Existing Swift models/support and their tests under `app/Sources/SteamGPTKApp` and `app/Tests/SteamGPTKAppTests`.

**Interfaces:** Preserve existing install/repair entry points. Add `PrefixStore.claim`/`PrefixClaim.release`, a bounded `PinnedDownload.session`, and a Steam-copy verification callback where required by the imported tests.

- [x] Port regression tests from `6506345`, `6bf5cae`, `734e4d5`, `83e62d9` (existing Swift boundaries only), `b5bf2a9`, `08467be`, `48f3ca4`, `dd41de2`, `48d7ce0`, and `f478d89`.
- [x] Run affected tests and record failures before porting production code; if a new interface is missing, record the compiler failure and then verify behavioral failures separately where possible.
- [x] Port matching implementation, preserving the free install path and SteamGPTK names. Omitted upstream-only boundaries are documented in `docs/UPSTREAM_SYNC_2026-10-29.md`.
- [x] Run the full Swift suite and commit the bounded task.

### Task 2: Native Steam and overlay ownership

**Files:** `dylib/feats/compat.c`, `dylib/hooks/hook_activate.c`, hook/loader wiring, `overlay-shim/overlay_shim.m`, native tests, `Makefile`, CI workflow.

**Interfaces:** Keep existing compatibility hooks. Add `np_hooks_activate_install()` at early loader initialization. Overlay exported entry points remain unchanged.

- [x] Import regression tests from `3a6c27c`, `3bd0bf4`, `f5a871a`, and the fixture correction `6b57bfa`; wire focused test targets.
- [x] Run the tests against the previous implementation and record failures.
- [x] Port the applicable allocator fix `3a6c27c` (the static buffer does not need `628bd17`), activation hook `3bd0bf4`, and overlay ownership fix `f5a871a`; adapt public environment names to SteamGPTK.
- [x] Run native checks, overlay tests and commit.

### Task 3: Launch correctness and overhead

**Files:** `dylib/feats/compat_run.sh` and packaged copy, `helpers/appinfo.swift`, shell checks, `GameProfileTests.swift`, `Makefile`, CI workflow, transfer notes.

**Interfaces:** `apply_game_profile()` and `wine_game_pids` remain authoritative. Keep manual environment priority, `hl2-v1`, fixed bridge selection and cache locations unchanged.

- [x] Import/adapt behavioral tests for `6bf5cae`, `cfe0194`, `2791679`, `886105c`, `a479c84` at existing script boundaries; check the default HL2 path and manual overrides with the existing integration tests.
- [x] Run focused checks against the old script and record failures.
- [x] Port the minimal compatible implementations, including launch-alert exit from `08467be`, with no new hidraw/plugin/defaults subsystem. Synchronize the packaged launcher.
- [x] Run full Swift/native/lint checks and build a relocated application with `scripts/build-free-ui.sh`; run packaged-resource and signature verification.
- [x] Document upstream source commits, adapted/omitted portions, results and limitations; commit.
- [x] Obtain a fresh whole-branch review and address important findings with regression tests.
- [x] Verify the branch is clean and report the branch, artifact path, checks and any remaining limitations. Keep it local.
