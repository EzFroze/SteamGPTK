#!/bin/bash
# SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
# Build the free Wine/GPTK UI. No Apple GPTK files are packaged or downloaded.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
app_path="${1:-$repo_dir/out/SteamGPTK.app}"
build_dir="${NP_UI_BUILD_DIR:-/private/tmp/steamgptk-ui-build-$(id -u)}"
cache_dir="$HOME/Library/Caches/notproton-free/downloads"
archive="$cache_dir/NotProton-v1.0.1.zip"
mkdir -p "$cache_dir"
archive_sha='1f1f4038ef44e48454c7746fad2b9964f7c82c4ae04af117e474a2d129eda52d'
if [[ ! -f "$archive" ]] || [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f1)" != "$archive_sha" ]]; then
    curl --fail --location --output "$archive.part" 'https://github.com/NotProtonNot/NotProton/releases/download/v1.0.1/NotProton.zip'
    [[ "$(shasum -a 256 "$archive.part" | cut -d ' ' -f1)" == "$archive_sha" ]] || { echo 'Bridge archive checksum mismatch' >&2; exit 1; }
    mv "$archive.part" "$archive"
fi
dobby_commit=5dfc8546954ce3b3198132ab13fddb89ee92cdd7
if [[ ! -d vendor/dobby/.git ]]; then
    git clone --no-checkout https://github.com/jmpews/Dobby.git vendor/dobby
    git -C vendor/dobby checkout "$dobby_commit"
fi
[[ "$(git -C vendor/dobby rev-parse HEAD)" == "$dobby_commit" ]] || {
    echo 'Dobby checkout differs from the pinned source; preserve your changes before rebuilding.' >&2
    exit 1
}
if [[ ! -f build/dobby/libdobby.a ]]; then
    command -v cmake >/dev/null || { echo 'CMake is required to build Dobby.' >&2; exit 1; }
    make dobby
fi
# Stage only bridge files and icons from the pinned release; retain NOTICE licenses.
python3 - "$archive" <<'PY'
from pathlib import Path
import sys, zipfile
base = 'NotProton.app/Contents/Resources/'
payload = base + 'NotProtonApp_NotProtonApp.bundle/Contents/Resources/payload/bridge/'
resources = Path('app/Sources/NotProtonApp/Resources')
(resources / 'payload/bridge').mkdir(parents=True, exist_ok=True)
Path('out/free-ui-icons').mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(sys.argv[1]) as archive:
    for name in ['steam.exe', 'x86_64-windows-lsteamclient.dll', 'i386-windows-lsteamclient.dll',
                 'x86_64-unix-lsteamclient.so', 'aarch64-unix-lsteamclient.so']:
        (resources / 'payload/bridge' / name).write_bytes(archive.read(payload + name))
    for name in ['NotProton.icns', 'Assets.car']:
        Path('out/free-ui-icons', name).write_bytes(archive.read(base + name))
PY
make app-payload
cp dylib/feats/compat_run.sh app/Sources/NotProtonApp/Resources/compat_run.sh
# shellcheck source=scripts/free-ui-env.sh
source "$repo_dir/scripts/free-ui-env.sh"
steamgptk_swift_options "$build_dir"
swift build "${STEAMGPTK_SWIFT_ARGS[@]}"
bin_path="$(swift build "${STEAMGPTK_SWIFT_ARGS[@]}" --show-bin-path)"
python3 - "$repo_dir" "$bin_path" "$app_path" "$build_dir" <<'PY'
from pathlib import Path
import plistlib, shutil, subprocess, sys, uuid
repo, products, app, swift_cache = map(Path, sys.argv[1:])
stage = app.parent / ('.free-ui-' + str(uuid.uuid4()) + '.app')
try:
    contents = stage / 'Contents'
    for name in ['MacOS', 'Resources', 'Frameworks']:
        (contents / name).mkdir(parents=True, exist_ok=True)
    info = plistlib.loads((repo / 'app/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='io.github.ezfroze.steamgptk', CFBundleName='SteamGPTK',
                CFBundleDisplayName='SteamGPTK', CFBundleShortVersionString='0.1.1',
                CFBundleVersion='2', SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
    info.pop('SUFeedURL', None)
    info.pop('SUPublicEDKey', None)
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2(products / 'NotProtonApp', contents / 'MacOS/NotProtonApp')
    for name, target in [('Sparkle.framework', 'Frameworks'), ('NotProtonApp_NotProtonApp.bundle', 'Resources')]:
        subprocess.run(['/usr/bin/ditto', str(products / name), str(contents / target / name)], check=True)
    for name in ['NotProton.icns', 'Assets.car']:
        shutil.copy2(repo / 'out/free-ui-icons' / name, contents / 'Resources' / name)
    licenses = contents / 'Resources/Licenses'
    licenses.mkdir()
    for relative, name in [('LICENSE', 'NotProton-GPL-3.0.txt'), ('NOTICE', 'NOTICE.txt'),
                           ('LICENSE.mac-windows-gaming', 'mac-windows-gaming-MIT.txt'),
                           ('LICENSE.lsteamclient', 'lsteamclient-LICENSE.txt'),
                           ('LICENSE.steam-shim', 'steam-shim-LICENSE.txt'),
                           ('vendor/dobby/LICENSE', 'Dobby-Apache-2.0.txt')]:
        shutil.copy2(repo / relative, licenses / name)
    sparkle_repo = swift_cache / 'checkouts/Sparkle/LICENSE'
    if sparkle_repo.is_file():
        shutil.copy2(sparkle_repo, licenses / 'Sparkle-MIT.txt')
    else:
        raise RuntimeError('Sparkle license was not found in the Swift package checkout')
    for relative, name in [('vendor/cJSON.c', 'cJSON-MIT.txt'),
                           ('steam-shim/jsoncpp.cpp', 'JsonCpp-LICENSE.txt')]:
        source = (repo / relative).read_text()
        license_text = source.split('/*', 1)[1].split('*/', 1)[0]
        (licenses / name).write_text(license_text.strip() + '\n')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo))
    (licenses / 'SOURCE.txt').write_text('Source: https://github.com/EzFroze/SteamGPTK\nRevision: ' + revision + '\nWorking tree changes: ' + str(dirty) + '\n')
    # Fail if any Apple renderer or old manually staged Wine patch leaked into a build cache.
    for item in (contents / 'Resources').rglob('*'):
        if 'd3dmetal' in item.name.lower() or item.name == 'libd3dshared.dylib' or item.name == 'ntdll.dll':
            raise RuntimeError('Runtime binary must not be bundled: ' + str(item))
    subprocess.run(['/usr/bin/install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(contents / 'MacOS/NotProtonApp')], check=True)
    subprocess.run(['/usr/bin/codesign', '-f', '-s', '-', str(stage)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
    # Preserve the previous local build rather than changing /Applications/NotProton.app.
    if app.exists():
        previous = app.parent / (app.stem + '.previous-' + str(uuid.uuid4()) + '.app')
        app.rename(previous)
    stage.rename(app)
    print('Built: ' + str(app))
finally:
    if stage.exists():
        shutil.rmtree(stage)
PY
