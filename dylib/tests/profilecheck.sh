#!/bin/sh
# SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
set -eu
SRC="${1:-$(dirname "$0")/../feats/compat_run.sh}"
work=$(mktemp -d "${TMPDIR:-/tmp}/np-profilecheck.XXXXXX")
trap 'chmod -R u+rwX "$work"; rm -rf "$work"' EXIT
functions=$(awk '
  /^merge_user_dir\(\) \{/ { on=1 }
  on && /^if \[ -n "\$STEAM_COMPAT_DATA_PATH" \]; then/ { found=1; exit }
  on { print }
  END { exit !found }
' "$SRC")
eval "$functions"
task_user=$(id -un)
fails=0
check() {
  if "$@"; then printf 'ok: %s\n' "$*"; else
    printf 'FAIL: %s\n' "$*"
    fails=$((fails + 1))
  fi
}
fixture() {
  case_root=$(mktemp -d "$work/case.XXXXXX")
  WINEPREFIX="$case_root/pfx"
  export WINEPREFIX
  # Used by the launcher functions loaded through eval above.
  # shellcheck disable=SC2034
  log="$case_root/log"
  native="$WINEPREFIX/drive_c/users/$task_user"
  cloud="$WINEPREFIX/drive_c/users/steamuser"
  mkdir -p "$WINEPREFIX"
}
reject_layout() {
  ! lay_out_proton_profile
}

# A new game must share all profile roots before wineboot runs.
fixture
check lay_out_proton_profile
check test -L "$native"
check test "$native" -ef "$cloud"
check test -d "$cloud/AppData/LocalLow"
mkdir -p "$native/Saved Games/Game"
printf progress > "$native/Saved Games/Game/slot.sav"
check test "$(cat "$cloud/Saved Games/Game/slot.sav" 2>/dev/null || true)" = progress
mkdir -p "$cloud/Saved Games/Game"
printf downloaded > "$cloud/Saved Games/Game/slot.sav"
check test "$(cat "$native/Saved Games/Game/slot.sav")" = downloaded
check lay_out_proton_profile
check test "$native" -ef "$cloud"

# Existing profiles merge inside already populated AppData directories.
fixture
mkdir -p "$native/AppData/LocalLow/Game" "$cloud/AppData/LocalLow/Game"
mkdir -p "$native/Documents/Game"
printf local > "$native/AppData/LocalLow/Game/local.sav"
printf downloaded > "$cloud/AppData/LocalLow/Game/cloud.sav"
printf document > "$native/Documents/Game/slot.sav"
check lay_out_proton_profile
check test "$native" -ef "$cloud"
check test "$(cat "$cloud/AppData/LocalLow/Game/local.sav" 2>/dev/null || true)" = local
check test "$(cat "$native/AppData/LocalLow/Game/cloud.sav" 2>/dev/null || true)" = downloaded
check test "$(cat "$cloud/Documents/Game/slot.sav" 2>/dev/null || true)" = document
backups=0
for backup in "$WINEPREFIX/drive_c/users/$task_user".steamgptk-backup.*; do
  [ -d "$backup" ] || continue
  backups=$((backups + 1))
  check test "$(cat "$backup/AppData/LocalLow/Game/local.sav")" = local
done
check test "$backups" -eq 1
check lay_out_proton_profile

# Conflicting progress must leave both originals available and refuse launch.
fixture
mkdir -p "$native/AppData/LocalLow/Game" "$cloud/AppData/LocalLow/Game"
printf local-progress > "$native/AppData/LocalLow/Game/slot.sav"
printf cloud-progress > "$cloud/AppData/LocalLow/Game/slot.sav"
check reject_layout
check test ! -L "$native"
check test "$(cat "$native/AppData/LocalLow/Game/slot.sav")" = local-progress
check test "$(cat "$cloud/AppData/LocalLow/Game/slot.sav")" = cloud-progress

# A previous per-game alias (Death's Door) must not become a broken relative link.
fixture
mkdir -p "$native/AppData/LocalLow/Studio/Game" "$cloud/AppData/LocalLow/Studio/Game/SAVEDATA"
printf old-progress > "$cloud/AppData/LocalLow/Studio/Game/SAVEDATA/slot.sav"
ln -s '../../../../../steamuser/AppData/LocalLow/Studio/Game/SAVEDATA' \
  "$native/AppData/LocalLow/Studio/Game/SAVEDATA"
check lay_out_proton_profile
check test "$native" -ef "$cloud"
check test "$(cat "$native/AppData/LocalLow/Studio/Game/SAVEDATA/slot.sav")" = old-progress

# Host Documents links must not import or modify the user's real Documents.
fixture
mkdir -p "$native/AppData" "$case_root/external"
printf private > "$case_root/external/untouched"
ln -s "$case_root/external" "$native/Documents"
check lay_out_proton_profile
check test "$native" -ef "$cloud"
check test ! -L "$cloud/Documents"
check test ! -e "$cloud/Documents/untouched"
check test "$(cat "$case_root/external/untouched")" = private

# Real legacy Windows folders must land in the corresponding modern roots.
fixture
mkdir -p "$native/My Documents/Game" "$native/Application Data/Game"
mkdir -p "$native/Local Settings/Application Data/Game"
printf documents > "$native/My Documents/Game/doc.sav"
printf roaming > "$native/Application Data/Game/roam.sav"
printf local > "$native/Local Settings/Application Data/Game/local.sav"
check lay_out_proton_profile
check test "$native" -ef "$cloud"
check test "$(cat "$cloud/Documents/Game/doc.sav" 2>/dev/null || true)" = documents
check test "$(cat "$cloud/AppData/Roaming/Game/roam.sav" 2>/dev/null || true)" = roaming
check test "$(cat "$cloud/AppData/Local/Game/local.sav" 2>/dev/null || true)" = local

# Never route a profile or its parents outside this game's prefix.
fixture
mkdir -p "$native" "$case_root/external"
ln -s "$case_root/external" "$cloud"
check reject_layout
check test -L "$cloud"
fixture
mkdir -p "${native%/*}" "$case_root/external"
ln -s "$case_root/external" "$native"
check reject_layout
check test "$(readlink "$native")" = "$case_root/external"
fixture
mkdir -p "$WINEPREFIX/drive_c" "$case_root/external"
ln -s "$case_root/external" "$WINEPREFIX/drive_c/users"
check reject_layout
check test ! -e "$case_root/external/steamuser"
fixture
rmdir "$WINEPREFIX"
mkdir -p "$case_root/external"
ln -s "$case_root/external" "$WINEPREFIX"
check reject_layout
check test ! -e "$case_root/external/drive_c"

printf '%s profile checks failed\n' "$fails"
test "$fails" -eq 0
