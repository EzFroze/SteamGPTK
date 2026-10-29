# Selected NotProton fixes, 2026-10-29

Ported on `codex/upstream-launch-steam-overlay`, based on SteamGPTK 0.2.2 (`47b3d2d`). Upstream inspected through [`a479c84`](https://github.com/NotProtonNot/NotProton/commit/a479c84923e853ddf8bf3a965fb4287ebfdcfd28). These changes form SteamGPTK 0.2.3.

## Ported

| Upstream commits | Adaptation in SteamGPTK |
| --- | --- |
| `6506345` | Preserve unrelated `steam.cfg` bytes, invalid UTF-8 and CRLF; refuse unreadable required files. |
| `08467be`, `48f3ca4` | Distinguish local save errors from network errors; bound a download's total duration; restrict process detection to the current UID. Close preparation locks before showing a launch alert. |
| `83e62d9`, `b5bf2a9` | Preserve saves behind similarly named sibling paths; hold the same preparation lock during launch, backup, rebuild and delete. |
| `dd41de2` | Stage a replacement Steam bundle on its target volume and verify the copied bundle before replacing the existing one. |
| `f478d89` | Decode quotes, backslashes, tabs and newlines in manifest values. |
| `3a6c27c` | Release temporary tool paths using Steam's allocator; retain the fork's single-tool registration model. |
| `3bd0bf4` | Suppress unwanted Steam activation after menu bar clicks; keep normal activation after another application owned the menu bar. Opt out with `STEAMGPTK_DISABLE=activate`. |
| `f5a871a` | Correct ownership of Metal overlay pipelines and encoders; cover completion, discard and repeated pipeline rebuilds on both architectures. |
| `6bf5cae` (launch portion) | Prefer an installed Microsoft VC++ runtime over Wine builtins while retaining manual DLL override priority. |
| `cfe0194` | Avoid assigning a store AppID to non-Steam shortcuts and installation helpers; keep the shortcut GameID. |
| `2791679`, `886105c`, `a479c84` (existing launch boundaries) | Correct Retina DPI transitions, batch prefix settings into one import and skip unchanged current settings. Reuse unchanged launcher bundles, batch symlink creation, `exec` the game loader and avoid redundant LaunchServices registration. |

Launcher bundle comparison falls back for older installed helpers and compares bytes rather than timestamps. Bundle replacement retains the upstream rollback behavior. Background launch descendants do not inherit the prefix preparation lock. A first launch creates its compatdata root before opening the lock, and the launcher releases the parent lock before displaying a terminal prefix-rebuild alert.

## Preserved and excluded

The free Wine/GPTK setup, locally imported Apple files, `hl2-v1`, manual profile overrides, fixed 32-bit Steam bridge, Steam Cloud path layout and shader cache locations are preserved. `GameProfileTests` still checks default/manual/disabled profiles and two configure → Valve install passes.

This is not a full upstream merge. CrossOver/FEX build support, plugin and CEG subsystems, new library filters, global settings UI and localization are excluded. Some patches target APIs absent in this older fork: the Winetricks wrapper portion of `6bf5cae`, section-header extension checks from `48d7ce0`, new tool-scan state from `83e62d9`, and removed free-UI methods affected by `734e4d5`/`174e457`. `628bd17` frees an upstream heap allocation that this fork's static single-tool registration does not make.

## Verification

- Swift: 408 tests in 56 suites pass, including real Wine rebuild and automatic HL2 profile/repair integration.
- Native: signature, JS fixtures/panel behavior, compat/compatsvc, Steam Cloud profile, spawn environment, game session, launch settings, bundle reuse/rollback, activation, shell syntax/lint checks pass.
- Metal overlay: 8 tests pass across arm64/x86_64, with no skips when run with device access.
- Launch helper fixtures cover VC++ selection, shortcut IDs, DPI transitions, unchanged settings, preparation locks, first launch without a compatdata root, parent lock release before a rebuild prompt, unchanged bundle reuse and failed replacement rollback.

The initial real-Wine baseline test was blocked by an existing empty `/tmp/.wine-501` directory with mode 0755. Its ownership, directory type and emptiness were checked before restoring Wine's required mode 0700; the real test then passed. Installed Steam/game configuration and saves were not changed by this transfer. No game FPS or frame-pacing improvement is claimed without a live comparison.

## Review and build

A fresh independent review found two important launch-lock edge cases. Both were reproduced by behavioral tests before applying the fixes: create the first-launch compatdata directory before opening the lock, and close the parent's preparation lock before showing a terminal rebuild alert. Both tests now pass.

One minor finding is deferred: when `appinfo` is missing, outdated or reports a read error, the shell bundle-comparison fallback can lose a nested `find` permission error and keep an unreadable Resources directory. This affects the unreadable-directory edge case; normal bundle comparison, replacement and rollback are covered by passing tests. This is not treated as an FPS fix.

The development app built successfully. Deep strict code-signature validation and `--check-resources` passed after relocating the app to another temporary directory. Initial testing used a development build labeled 0.2.2; the release is versioned 0.2.3. See [release notes](releases/0.2.3.md) for the update procedure.
