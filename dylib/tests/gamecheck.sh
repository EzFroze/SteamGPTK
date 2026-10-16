#!/bin/sh
# SteamGPTK fork modifications, 2026-10-16. Existing component licenses apply.
# Exercise the launcher's real session checks without Wine, Steam or UI actions.
set -eu
SRC="${1:-$(dirname "$0")/../feats/compat_run.sh}"
work=$(mktemp -d "${TMPDIR:-/tmp}/steamgptk-gamecheck.XXXXXX")
trap 'rm -rf "$work"' EXIT
functions=$(awk '
  /^wine_helpers=/ { on=1 }
  on && /^kill_wine_prefix\(\) \{/ { found=1; exit }
  on { print }
  END { exit !found }
' "$SRC")
eval "$functions"
# shellcheck disable=SC2034 # the functions loaded above write their session log
log="$work/log"
fixture="$work/processes"
poll_mode=static
fails=0

# Only the OS process table and window activation are replaced. Both old and
# new ps column layouts are supported so the original bug fails behaviorally.
ps() {
  table="$fixture"
  if [ "$poll_mode" = advancing ]; then
    polls=$(cat "$work/polls")
    polls=$((polls + 1))
    printf '%s\n' "$polls" > "$work/polls"
    [ "$polls" -le 3 ] || table="$work/wrappers"
  fi
  case "$*" in
    *ucomm*) cat "$table" ;;
    *) awk '{ pid=$1; $1=$2=""; sub(/^[[:space:]]+/, ""); print pid, $0 }' "$table" ;;
  esac
}
# shellcheck disable=SC2329 # activate_game, loaded from SRC, invokes this
swift() {
  printf '%s\n' "$2" > "$work/activated"
  cat >/dev/null
}
# shellcheck disable=SC2329 # wait_prefix_idle, loaded from SRC, invokes this
sleep() {
  test_sleeps=$((test_sleeps + 1))
  if [ "$test_sleeps" -gt 12 ]; then
    printf 'FAIL: a closed game left the session watcher running\n'
    exit 1
  fi
}
check_running() {
  if prefix_game_running; then actual=running; else actual=idle; fi
  if [ "$actual" = "$1" ]; then
    printf 'ok: %s\n' "$2"
  else
    printf 'FAIL: %s (expected %s, got %s)\n' "$2" "$1" "$actual"
    fails=$((fails + 1))
  fi
}

# Real regression: renderer options put /wine and hl2.exe on shell argv.
cat > "$fixture" <<'PROCESSES'
101 bash /bin/sh /Steam/compatibilitytools.d/steamgptk-proton/run waitforexitandrun /Steam/Half-Life 2/hl2.exe WINEDLLPATH_D9VK=/Runner/renderer/dxvk/wine
102 bash /bin/sh /Steam/compatibilitytools.d/steamgptk-proton/run waitforexitandrun /Steam/Half-Life 2/hl2.exe WINEDLLPATH_D9VK=/Runner/renderer/dxvk/wine
103 python3 python3 /tools/wine-check.py game.exe
PROCESSES
cp "$fixture" "$work/wrappers"
check_running idle 'wrappers and unrelated programs are not games'

# Wine rewrites argv[0] to a Windows path: /wine can disappear entirely.
cat > "$fixture" <<'PROCESSES'
204 wine Z:\Users\player\Library\Application Support\Steam\Half-Life 2\hl2.exe -steam
PROCESSES
check_running running 'a Wine game with a Windows argv[0] remains visible'

cat > "$fixture" <<'PROCESSES'
205 wine64-preloader /Applications/Runner.app/Contents/MacOS/wine64 C:\Games\Game.exe
PROCESSES
check_running running 'the Wine preloader is recognized'

cat > "$fixture" <<'PROCESSES'
206 wine64 game.exe
PROCESSES
check_running running 'a Wine game with a relative executable remains visible'

cat > "$fixture" <<'PROCESSES'
301 wine C:\windows\system32\services.exe
302 wine64 C:\windows\system32\winedevice.exe
303 wine-preloader /Runner/wine C:\Program Files (x86)\Steam\steam.exe /Steam/Half-Life 2/hl2.exe
304 wine C:\Game\UnityCrashHandler64.exe
305 wineserver /Runner/wineserver
PROCESSES
check_running idle 'Wine services, the Steam shim and crash helpers are not games'

cat > "$fixture" <<'PROCESSES'
207 wine C:\Games\Game.exe --helper C:\windows\system32\services.exe
PROCESSES
check_running running 'a helper name in game arguments does not hide the game'

# The same selection must choose the real game when activating its window.
cat "$work/wrappers" > "$fixture"
cat >> "$fixture" <<'PROCESSES'
301 wine C:\windows\system32\services.exe
204 wine Z:\Users\player\Steam\Half-Life 2\hl2.exe
PROCESSES
activate_game
activated=$(cat "$work/activated" 2>/dev/null || true)
if [ "$activated" = 204 ]; then
  printf 'ok: activation selects the game, not a wrapper or service\n'
else
  printf 'FAIL: activation selected %s instead of game 204\n' "$activated"
  fails=$((fails + 1))
fi

# A session that had a game must finish after it exits, even while other shell
# wrappers linger. A bounded sleep stub makes a broken loop fail, not hang CI.
poll_mode=advancing
printf '0\n' > "$work/polls"
test_sleeps=0
wait_prefix_idle
printf 'ok: session finishes after the real game exits\n'

printf '%s game process checks failed\n' "$fails"
test "$fails" -eq 0
