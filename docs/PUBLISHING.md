# Publishing SteamGPTK

The fork is `EzFroze/SteamGPTK`. The initial implementation branch is `codex/wine-gptk-ui`; its base is the tested standalone commit `5b8d18683b619b66390be8cbcffc1fbf47e45971`.

## Git remotes

Use the fork as `origin` and the original project as `upstream`:

```text
origin    git@github.com:EzFroze/SteamGPTK.git
upstream  https://github.com/NotProtonNot/NotProton.git
```

Push the implementation branch without rewriting the fork's existing `main`:

```bash
git push -u origin codex/wine-gptk-ui
```

To show this implementation on the repository landing page, choose `codex/wine-gptk-ui` as the repository's default branch in GitHub Settings. The README source-build command selects the branch explicitly until then. The original upstream `main` is retained for reference; it is a different, CrossOver-oriented implementation.

## Check a release candidate

```bash
./scripts/build-free-ui.sh
./scripts/test-free-ui.sh
make profilecheck compatcheck webpatch-fixtures compatsvc-check
```

For the local GPTK import/install smoke test:

```bash
NOTPROTON_INSTALL_SMOKE=1 \
NOTPROTON_GPTK_DMG="/path/to/your/GPTK4.dmg" \
./scripts/test-free-ui.sh --filter FreeInstallSmokeTests
```

The smoke test uses a disposable runtime. A GPTK DMG must never be added to Git, an Actions cache, an artifact, or a release. It is not required for the ordinary CI suite.

## GitHub Actions

Enable Actions for the fork if GitHub prompts. The app workflow builds `SteamGPTK.app` through `scripts/build-free-ui.sh`, runs checks and uploads `SteamGPTK.zip` plus its SHA-256 checksum as an artifact. The full GPTK installation smoke test is intentionally local because it requires a user-owned Apple download.

The workflows use GitHub-hosted Apple Silicon runners. They do not require the original author's signing key, Apple developer credentials, a CrossOver license, or a Sparkle update secret.

## Draft release

After this branch is the default branch and CI is green:

1. Open **Actions → release → Run workflow** and select the intended commit/branch.
2. Choose a new tag such as `steamgptk-v0.1.0` and enter release notes.
3. The workflow builds the app and creates a **draft** release with the app archive and checksum. Existing tags/releases are never force-replaced or deleted.
4. Review the draft and its artifact, then publish it explicitly in GitHub.

The app uses an ad-hoc signature and is not notarized. Do not describe it as Apple-signed or Apple-approved. The source archive for the release tag must correspond to the binary build; the built app includes its source revision and license notices.

Automatic updates to the original NotProton app are disabled. A future updater must use this fork's own feed and signing key.

## License/source notices

Keep LICENSE, NOTICE, existing component license files and upstream attribution. Release bundles include these notices, Dobby's Apache-2.0 license and Sparkle's MIT license. Wine engines/support libraries are downloaded separately; users obtain GPTK directly from Apple under Apple's terms.
