#!/bin/sh
# SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
# SteamGPTK Wine compatibility tool shim
set -e

verb="$1"
shift || true

# Options set from the Compatibility page are passed along as
# launch options.
launch_env=""
argc=$#
argi=0
while [ "$argi" -lt "$argc" ]; do
  arg="$1"
  shift
  # Upgrade launch options saved by earlier releases.
  case "$arg" in
    NOTPROTON_*=*) arg="STEAMGPTK_${arg#NOTPROTON_}" ;;
  esac
  case "$arg" in
    CX_GRAPHICS*=*|D3DM_*=*|DXMT_*=*|DXVK_*=*|MTL_*=*|STEAMGPTK_*=*|ROSETTA_*=*|VK_*=*|WINE*=*)
      # shellcheck disable=SC2163 # arg is a NAME=VALUE pair, which export takes as an assignment
      export "$arg"
      launch_env="$launch_env $arg"
      ;;
    *) set -- "$@" "$arg" ;;
  esac
  argi=$((argi+1))
done

case "$verb" in
  getcompatpath)
    printf '%s\n' "$STEAM_COMPAT_DATA_PATH"
    exit 0
    ;;
esac

CX_ROOT="$HOME/Library/Application Support/steamgptk/runners/current"
export CX_ROOT

if [ -d "$CX_ROOT/Contents/Resources/wine" ]; then
  CX_ROOT="$CX_ROOT/Contents/Resources/wine"
  export CX_ROOT
fi

app_id="$STEAM_COMPAT_APP_ID"
case "$app_id" in ''|0) app_id="$SteamAppId" ;; esac
case "$app_id" in ''|0) app_id=$(basename "$STEAM_COMPAT_DATA_PATH" 2>/dev/null) ;; esac
case "$app_id" in ''|*[!0-9]*) app_id=0 ;; esac

# Built-in defaults, applied before runner.env selects the graphics backend.
# Explicit Steam launch options always win. No per-game files in /tmp are used.
apply_game_profile() {
  game_profile=none
  profile_steam32=0
  [ "${STEAMGPTK_GAME_PROFILE:-1}" != 0 ] || return 0
  [ -f "$CX_ROOT/runner.env" ] || return 0
  case "$app_id" in
    220)
      game_profile=hl2-v1
      profile_steam32=1
      export CX_GRAPHICS_BACKEND="${CX_GRAPHICS_BACKEND-dxvk}"
      export ROSETTA_ADVERTISE_AVX="${ROSETTA_ADVERTISE_AVX-0}"
      export WINEDLLPATH_D9VK="${WINEDLLPATH_D9VK-$CX_ROOT/Frameworks/renderer/d9vk/wine}"
      if [ -z "${VK_DRIVER_FILES+x}${VK_ICD_FILENAMES+x}" ]; then
        export VK_DRIVER_FILES="$CX_ROOT/vulkan/icd.d/kosmickrisp_mesa_icd.json"
      fi
      if [ -z "${DXVK_CONFIG+x}${DXVK_CONFIG_FILE+x}" ]; then
        export DXVK_CONFIG="d3d9.presentInterval = 0"
      fi
      ;;
  esac
}
apply_game_profile

# cxcompatdb resolves its database through CX_HOME and logs an error for
# every module loaded without it :(
export CX_HOME="$HOME/Library/Application Support/CrossOver"

# Apple Game Porting Toolkit (GPTK) 4 default environment flags
export D3DM_MTL4="${D3DM_MTL4:-1}"
export D3DM_ENABLE_METALFX="${D3DM_ENABLE_METALFX:-1}"
export D3DM_SUPPORT_DXR="${D3DM_SUPPORT_DXR:-1}"
export ROSETTA_ADVERTISE_AVX="${ROSETTA_ADVERTISE_AVX:-1}"
export WINEMSYNC="${WINEMSYNC:-0}"
export WINEESYNC="${WINEESYNC:-1}"

wine_unix="$CX_ROOT/lib/wine/aarch64-unix"
[ -d "$wine_unix" ] || wine_unix="$CX_ROOT/lib/wine/x86_64-unix"

# Detect WINESERVER
if [ -x "$CX_ROOT/bin/wineserver" ]; then
  WINESERVER="$CX_ROOT/bin/wineserver"
elif [ -x "$CX_ROOT/CrossOver-Hosted Application/wineserver-arm64" ]; then
  WINESERVER="$CX_ROOT/CrossOver-Hosted Application/wineserver-arm64"
elif [ -x "$CX_ROOT/CrossOver-Hosted Application/wineserver" ]; then
  WINESERVER="$CX_ROOT/CrossOver-Hosted Application/wineserver"
elif [ -x "$CX_ROOT/CrossOver-Hosted Application/wineserver-x86" ]; then
  WINESERVER="$CX_ROOT/CrossOver-Hosted Application/wineserver-x86"
fi

# Detect WINELOADER
if [ -x "$CX_ROOT/bin/wine64" ]; then
  WINELOADER="$CX_ROOT/bin/wine64"
elif [ -x "$CX_ROOT/bin/wine" ]; then
  WINELOADER="$CX_ROOT/bin/wine"
elif [ -x "$wine_unix/wine.app/Contents/MacOS/wine" ]; then
  WINELOADER="$wine_unix/wine.app/Contents/MacOS/wine"
elif [ -x "$wine_unix/wine" ]; then
  WINELOADER="$wine_unix/wine"
fi

export WINELOADER WINESERVER
export WINEDLLPATH="$CX_ROOT/lib/wine/x86_64-windows:$wine_unix"
export PATH="$CX_ROOT/bin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="$CX_ROOT/lib/deps:$CX_ROOT/lib/external:${DYLD_FALLBACK_LIBRARY_PATH:-/usr/lib}"
# Free-Wine runners (e.g. Sikarugir Wine 11) ship their own environment
# shellcheck source=/dev/null
[ -f "$CX_ROOT/runner.env" ] && . "$CX_ROOT/runner.env"

if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
  [ -d "$STEAM_COMPAT_DATA_PATH" ] || mkdir -p "$STEAM_COMPAT_DATA_PATH"
  log="$STEAM_COMPAT_DATA_PATH/steamgptk-run.log"
else
  log=/dev/null
fi
[ "$(stat -f %z "$log" 2>/dev/null || echo 0)" -gt 262144 ] \
  && : > "$log" || true
{
  echo "=== steamgptk run $(date) ==="
  echo "verb=$verb"
  echo "args:"; for a in "$@"; do echo "  [$a]"; done
  echo "cwd=$(pwd)"
  echo "STEAM_COMPAT_DATA_PATH=$STEAM_COMPAT_DATA_PATH"
  echo "STEAM_COMPAT_INSTALL_PATH=$STEAM_COMPAT_INSTALL_PATH"
  echo "STEAM_COMPAT_APP_ID=$STEAM_COMPAT_APP_ID"
  echo "-- steam env passed through --"
  env | grep -iE '^(Steam|SDL_)' | sort
} >> "$log" 2>&1 || true

stage_step="startup"
# shellcheck disable=SC2329 # the trap below invokes this
report_early_exit() {
  status=$?
  [ "$status" = 0 ] && return 0
  echo "=== aborted during $stage_step (exit $status) before launch ===" \
    >> "$log" 2>&1 || true
}
trap report_early_exit EXIT

while :; do
  case "$STEAM_COMPAT_INSTALL_PATH" in
    ?*/) STEAM_COMPAT_INSTALL_PATH="${STEAM_COMPAT_INSTALL_PATH%/}" ;;
    *) break ;;
  esac
done
export STEAM_COMPAT_INSTALL_PATH

echo "app_id=$app_id (STEAM_COMPAT_APP_ID=$STEAM_COMPAT_APP_ID)" >> "$log" 2>&1 || true
echo "profile: $game_profile (STEAMGPTK_GAME_PROFILE=${STEAMGPTK_GAME_PROFILE:-1})" >> "$log" 2>&1 || true
if [ "$game_profile" != none ]; then
  {
    echo "profile: backend=$CX_GRAPHICS_BACKEND D9VK=$WINEDLLPATH_D9VK"
    echo "profile: Vulkan=${VK_DRIVER_FILES:-$VK_ICD_FILENAMES} DXVK_CONFIG=$DXVK_CONFIG DXVK_CONFIG_FILE=$DXVK_CONFIG_FILE"
  } >> "$log" 2>&1 || true
fi

shortcut_game_id() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 20 ] || return 1
  high=0
  low="$1"
  if [ "${#1}" -gt 10 ]; then
    high="${1%??????????}"
    low="${1#"$high"}"
  fi
  high="${high#"${high%%[!0]*}"}"
  low="${low#"${low%%[!0]*}"}"
  [ $(( (${high:-0} % 4294967296 * 1410065408 + ${low:-0}) % 4294967296 )) = 33554432 ]
}


without_lock_fds() {
  (exec 8>&- 9>&-; exec "$@")
}

claim_prefix() {
  [ -n "$STEAM_COMPAT_DATA_PATH" ] || return 0
  [ -d "$STEAM_COMPAT_DATA_PATH" ] || mkdir -p "$STEAM_COMPAT_DATA_PATH" || return 1
  lock_file="$STEAM_COMPAT_DATA_PATH/.steamgptk-prefix.lock"
  [ ! -L "$lock_file" ] || return 1
  [ ! -e "$lock_file" ] || [ -f "$lock_file" ] || return 1
  exec 9>> "$lock_file"
  /usr/bin/lockf -s -t 30 9
}


case "$verb" in
  waitforexitandrun)
    if shortcut_game_id "$SteamGameId"; then
      unset SteamAppId
    else
      [ -n "$SteamAppId" ] || export SteamAppId="$app_id"
      if [ -n "$app_id" ] && [ "$app_id" != 0 ] && [ -d "$STEAM_COMPAT_INSTALL_PATH" ]; then
        printf '%s\n' "$app_id" > "$STEAM_COMPAT_INSTALL_PATH/steam_appid.txt" 2>/dev/null || true
      fi
    fi
    [ -n "$SteamGameId" ] || export SteamGameId="$app_id"
    ;;
esac

prefix_machine() {
  dll="$WINEPREFIX/drive_c/windows/system32/ntdll.dll"
  [ -f "$dll" ] || return 1
  off=$(od -A n -t u4 -j 60 -N 4 "$dll" 2>/dev/null | tr -d ' ')
  case "$off" in ''|*[!0-9]*) return 1 ;; esac
  sig=$(od -A n -t x1 -j "$off" -N 4 "$dll" 2>/dev/null | tr -d ' \n')
  [ "$sig" = 50450000 ] || return 1
  od -A n -t x2 -j "$((off + 4))" -N 2 "$dll" 2>/dev/null | tr -d ' \n'
}

tool_name() {
  case "$1" in
    aa64) printf 'the FEX build of CrossOver' ;;
    8664) printf 'the Rosetta build of CrossOver' ;;
    *) printf 'an older 32-bit setup' ;;
  esac
}

refuse_foreign_prefix() {
  case "${wine_unix##*/}" in
    aarch64-unix) want=aa64 ;;
    *) want=8664 ;;
  esac
  have=$(prefix_machine) || return 0
  [ "$have" = "$want" ] && return 0
  echo "=== prefix ntdll is $have and this compatibility tool wants $want, rebuild the prefix in SteamGPTK ===" >> "$log" 2>&1 || true

  if [ "$verb" != run ]; then
    # The user must be able to rebuild while this terminal refusal is displayed.
    exec 8>&- 9>&-
    osascript >/dev/null 2>&1 <<APPLESCRIPT || true
display alert "This game needs its prefix rebuilt" message "This game originally ran under $(tool_name "$have"), but $(tool_name "$want") is present now. The prefix needs to be rebuilt in SteamGPTK in order to run the game. You will not lose game saves by rebuilding the prefix." as critical
APPLESCRIPT
  fi
  exit 1
}
# Steam cloud related
merge_user_dir() {
  src=$1
  dst=$2
  failed=
  set -- ""
  while [ "$#" -gt 0 ]; do
    rest=$1
    shift
    src_dir="$src$rest"
    dst_dir="$dst$rest"
    if [ "${profile_merge_legacy_paths:-0}" = 1 ]; then
      case "$rest" in
        '/My Documents'|'/My Documents/'*)
          dst_dir="$dst/Documents${rest#'/My Documents'}" ;;
        '/Application Data'|'/Application Data/'*)
          dst_dir="$dst/AppData/Roaming${rest#'/Application Data'}" ;;
        '/Local Settings/Application Data'|'/Local Settings/Application Data/'*)
          dst_dir="$dst/AppData/Local${rest#'/Local Settings/Application Data'}" ;;
      esac
    fi
    if [ ! -r "$src_dir" ] || [ ! -x "$src_dir" ]; then failed=1; continue; fi
    if [ -L "$dst_dir" ]; then failed=1; continue; fi
    probe=$dst_dir
    through=
    while [ -n "$probe" ] && [ "$probe" != "$dst" ]; do
      if [ -L "$probe" ]; then through=1; break; fi
      probe=${probe%/*}
    done
    if [ -n "$through" ]; then
      echo "=== $rest is held by a link, merge refused ===" >> "$log" 2>&1 || true
      failed=1
      continue
    fi
    if [ -e "$dst_dir" ] && [ ! -d "$dst_dir" ]; then failed=1; continue; fi
    if ! mkdir -p "$dst_dir" 2>/dev/null; then failed=1; continue; fi
    for entry in "$src_dir"/* "$src_dir"/.[!.]* "$src_dir"/..?*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name=${entry##*/}
      if [ -d "$entry" ] && [ ! -L "$entry" ]; then
        set -- "$@" "$rest/$name"
        continue
      fi
      landing="$dst_dir/$name"
      # Already-shared saves include the earlier per-game Cloud repair.
      if [ -e "$entry" ] && [ -e "$landing" ] && [ "$entry" -ef "$landing" ]; then
        continue
      fi
      # Keep host-folder links in the backed-up profile, never traverse/import
      # Documents/Desktop/etc. outside this game's prefix.
      if [ -L "$entry" ] && [ "${profile_merge_skip_links:-0}" = 1 ]; then continue; fi
      if [ -e "$landing" ] || [ -L "$landing" ]; then
        if [ -L "$entry" ] && [ -L "$landing" ] \
          && [ "$(readlink "$entry")" = "$(readlink "$landing")" ]; then continue; fi
        if [ -f "$entry" ] && [ ! -L "$entry" ] && [ -f "$landing" ] \
          && [ ! -L "$landing" ] && cmp -s "$entry" "$landing"; then continue; fi
        echo "=== conflicting profile file: $landing ===" >> "$log" 2>&1 || true
        failed=1
        continue
      fi
      if [ -L "$entry" ]; then
        cp -Ppn "$entry" "$landing" 2>/dev/null || failed=1
      else
        if ! cp -pn "$entry" "$landing" 2>/dev/null || ! cmp -s "$entry" "$landing"; then
          failed=1
        fi
        chmod u+w "$landing" 2>/dev/null || true
      fi
    done
  done
  [ -z "$failed" ]
}

# Steam Cloud stuff
migrate_user_paths() {
  profile=$1
  migration_failed=0
  for pair in \
    "Local Settings/Application Data|AppData/Local|../AppData/Local" \
    "Application Data|AppData/Roaming|./AppData/Roaming" \
    "My Documents|Documents|./Documents"; do
    old_rel=${pair%%|*}
    rest=${pair#*|}
    new_rel=${rest%%|*}
    link=${rest#*|}
    old="$profile/$old_rel"
    new="$profile/$new_rel"
    case "$(readlink "$new" 2>/dev/null || true)" in
      *"drive_c/users/steamuser/$old_rel") rm -f "$new" 2>/dev/null || true ;;
    esac
    if [ -L "$new" ]; then
      echo "=== $new_rel is a link, rebuild the prefix for cloud saves ===" \
        >> "$log" 2>&1 || true
      migration_failed=1
      continue
    fi
    held=
    for rel in "$old_rel" "$new_rel"; do
      probe=$rel
      while [ "$probe" != "${probe%/*}" ]; do
        probe=${probe%/*}
        if [ -L "$profile/$probe" ]; then held=$probe; break; fi
      done
      if [ -n "$held" ]; then break; fi
    done
    if [ -n "$held" ]; then
      echo "=== $held is a link, rebuild the prefix for cloud saves ===" \
        >> "$log" 2>&1 || true
      migration_failed=1
      continue
    fi
    if [ -e "$old" ] && [ ! -L "$old" ]; then
      if ! merge_user_dir "$old" "$new"; then
        echo "=== $old_rel did not merge into $new_rel, left in place ===" \
          >> "$log" 2>&1 || true
        migration_failed=1
        continue
      fi
      backup="$old BACKUP"
      backup_number=2
      while [ -e "$backup" ] || [ -L "$backup" ]; do
        backup="$old BACKUP $backup_number"
        backup_number=$((backup_number + 1))
      done
      if ! mv "$old" "$backup" 2>> "$log"; then
        echo "=== $old_rel could not be moved aside, cloud saves stay split ===" \
          >> "$log" 2>&1 || true
        migration_failed=1
        continue
      fi
    fi
    if [ ! -e "$old" ] && [ ! -L "$old" ]; then
      mkdir -p "${old%/*}" 2>/dev/null || true
      ln -s "$link" "$old" 2>/dev/null \
        || echo "=== $old_rel could not be aliased onto $new_rel ===" >> "$log" 2>&1 \
        || true
    elif [ -L "$old" ] && [ "$(readlink "$old")" != "$link" ]; then
      rm -f "$old" 2>/dev/null || true
      ln -s "$link" "$old" 2>/dev/null \
        || echo "=== $old_rel could not be aliased onto $new_rel ===" >> "$log" 2>&1 \
        || true
    fi
  done
  [ "$migration_failed" -eq 0 ]
}

# CrossOver names its Wine user "crossover", but free Wine uses getpwuid().
# Alias that profile before wineboot so every Windows save root stays in the
# real steamuser directory that native Steam AutoCloud reads and writes.
alias_host_profile() (
  host_user=$(id -un) || return 1
  case "$host_user" in
    steamuser|crossover) return 0 ;;
    ''|.|..|Public|Default|*/*) return 1 ;;
  esac
  legacy="$users/$host_user"
  if [ -L "$legacy" ]; then
    [ -e "$legacy" ] && [ "$legacy" -ef "$profile" ] && return 0
    echo "=== host Wine profile points elsewhere, left in place: $legacy ===" >> "$log" 2>&1 || true
    return 1
  fi
  if [ -e "$legacy" ]; then
    [ -d "$legacy" ] || return 1
    profile_merge_skip_links=1
    profile_merge_legacy_paths=1
    if ! merge_user_dir "$legacy" "$profile"; then
      echo "=== profile migration refused; both versions remain in place ===" >> "$log" 2>&1 || true
      return 1
    fi
    held="$legacy.steamgptk-backup.$(date +%Y%m%d-%H%M%S)"
    while [ -e "$held" ] || [ -L "$held" ]; do held="$held.1"; done
    mv "$legacy" "$held" || return 1
    if ! ln -s steamuser "$legacy"; then
      mv "$held" "$legacy" || true
      return 1
    fi
    echo "=== preserved previous Wine profile at $held ===" >> "$log" 2>&1 || true
  else
    ln -s steamuser "$legacy" || return 1
  fi
  echo "=== linked Wine profile $host_user to steamuser for Steam Cloud ===" >> "$log" 2>&1 || true
)

lay_out_proton_profile() {
  users="$WINEPREFIX/drive_c/users"
  for root in "$WINEPREFIX" "$WINEPREFIX/drive_c" "$users"; do
    [ ! -L "$root" ] || return 1
    if [ -e "$root" ] && [ ! -d "$root" ]; then return 1; fi
  done
  if [ -d "$users/crossover" ] && [ ! -L "$users/crossover" ]; then
    echo "=== prefix predates the steamuser layout, rebuild it for cloud saves ===" \
      >> "$log" 2>&1 || true
    return 1
  fi
  profile="$users/steamuser"
  if [ -L "$profile" ]; then
    echo "=== the profile is a link, rebuild the prefix for cloud saves ===" \
      >> "$log" 2>&1 || true
    return 1
  fi
  mkdir -p "$profile" 2>/dev/null || return 1
  for folder in Documents Desktop Downloads Music Pictures Videos Templates \
      'Saved Games' AppData AppData/Local AppData/LocalLow AppData/Roaming; do
    [ ! -L "$profile/$folder" ] || return 1
    mkdir -p "$profile/$folder" 2>/dev/null || return 1
  done
  migrate_user_paths "$profile" || return 1
  alias_host_profile || return 1
  if [ -L "$users/crossover" ] && [ ! -e "$users/crossover" ]; then
    rm -f "$users/crossover" 2>/dev/null || true
  fi
  if [ ! -e "$users/crossover" ] \
    && ln -s steamuser "$users/crossover" 2>/dev/null; then
    echo "=== pointed crossover at steamuser ===" >> "$log" 2>&1 || true
  fi
}

native_vc_runtime() {
  for name in concrt140 msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait msvcp140_codecvt_ids \
    vcamp140 vccorlib140 vcomp140 vcruntime140 vcruntime140_1; do
    dll="$WINEPREFIX/drive_c/windows/system32/$name.dll"
    [ -f "$dll" ] || continue
    if [ "$(dd if="$dll" bs=1 skip=64 count=16 2>/dev/null)" != "Wine builtin DLL" ]; then
      printf '%s=n,b;' "$name"
    fi
  done
}

plan_logpixels() {
  dpi_value=""
  new_dpi=""
  dpi_registry=/dev/null
  [ ! -f "$WINEPREFIX/user.reg" ] || dpi_registry="$WINEPREFIX/user.reg"
  read -r retina_was dpi <<EOF
$(LC_ALL=C awk '
  /^\[/ { s = 0
    line = tolower($0)
    if (index(line, "[software\\\\wine\\\\mac driver]") == 1) s = 1
    else if (index(line, "[control panel\\\\desktop]") == 1) s = 2
    next }
  s { $0 = tolower($0) }
  s == 1 && $0 ~ /^"retinamode"="[yt1]/ { r = 1 }
  s == 2 && $0 ~ /^"logpixels"=dword:[0-9a-f]+$/ && length($0) <= 26 { d = substr($0, 19) }
  END { print r + 0, d }' "$dpi_registry")
EOF
  [ -n "$dpi" ] || [ ! -f "$WINEPREFIX/system.reg" ] || dpi=$(LC_ALL=C awk '
      /^\[/ { s = index(tolower($0), "[system\\\\controlset001\\\\hardware profiles\\\\current\\\\software\\\\fonts]") == 1; next }
      s { $0 = tolower($0) }
      s && $0 ~ /^"logpixels"=dword:[0-9a-f]+$/ && length($0) <= 26 { print substr($0, 19); exit }' "$WINEPREFIX/system.reg")
  dpi=$((0x${dpi:-0}))
  [ "$dpi" -gt 0 ] || dpi=96
  if [ "$STEAMGPTK_RETINA" = "1" ]; then
    [ "$retina_was" = 1 ] && [ "$dpi" -ge 110 ] || [ "$dpi" -gt 2147483647 ] || new_dpi=$((dpi * 2))
  elif [ "$retina_was" = 1 ]; then
    new_dpi=$((dpi / 2))
    [ "$new_dpi" -ge 96 ] || new_dpi=96
  fi
  [ -z "$new_dpi" ] || [ "$new_dpi" -eq "$dpi" ] || dpi_value=$(printf '"LogPixels"=dword:%08x' "$new_dpi")
}

prefix_up_to_date() {
  [ -r "$WINEPREFIX/.update-timestamp" ] || return 1
  read -r stamp _ < "$WINEPREFIX/.update-timestamp" || return 1
  stamp=${stamp%"$(printf '\r')"}
  case "$stamp" in '' | *[!0-9]*) return 1 ;; esac
  [ "$stamp" = "$(stat -f %m "$CX_ROOT/share/wine/wine.inf" 2>/dev/null)" ]
}

settings_already_applied() {
  prefix_up_to_date || return 1
  [ -f "$WINEPREFIX/system.reg" ] && [ -f "$WINEPREFIX/user.reg" ] || return 1
  LC_ALL=C awk '
    function double(s,   out, i) {
      out = ""
      while ((i = index(s, "\\")) > 0) { out = out substr(s, 1, i) "\\"; s = substr(s, i + 1) }
      return out s
    }
    FNR == 1 {
      file++
      root = file == 2 ? "hkey_local_machine\\" : "hkey_current_user\\"
      key = ""
    }
    { sub(/\r$/, "") }
    /^\[/ {
      key = ""
      end = index($0, "]")
      if (!end) { if (file == 1) bad = 1; next }
      name = tolower(substr($0, 2, end - 2))
      if (file == 1) {
        deleted = sub(/^-/, "", name)
        ccs = "hkey_local_machine\\system\\currentcontrolset\\"
        if (index(name, ccs) == 1)
          name = "hkey_local_machine\\system\\controlset001\\" substr(name, length(ccs) + 1)
        split(name, part, "\\")
        name = substr(name, 1, length(part[1]) + 1) double(substr(name, length(part[1]) + 2))
        if (deleted) gone[name] = 1
        else { key = name; wanted[name] = 1 }
        next
      }
      name = root name
      for (g in gone) if (name == g || index(name, g "\\\\") == 1) bad = 1
      if (name in wanted) key = name
      next
    }
    key == "" || !match($0, /^("([^"\\]|\\.)*"|@)=/) { next }
    {
      name = tolower(substr($0, 1, RLENGTH - 1))
      value = substr($0, RLENGTH + 1)
      if (file == 1) want[key, name] = value
      else have[key, name] = value
    }
    END {
      if (file != 3) exit 1
      for (kv in want) {
        if (want[kv] == "-") { if (kv in have) bad = 1 }
        else if (!(kv in have) || have[kv] != want[kv]) bad = 1
      }
      exit bad
    }
  ' "$settings_file" "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg"
}


video_lines() {
  [ "$verb" = waitforexitandrun ] || return 0
  printf '%s\r\n' '[HKEY_CURRENT_USER\Software\Wine\Mac Driver]' "$retina_line" '"OpenGLSurfaceMode"="behind"' ''
  [ -n "$dpi_value" ] || return 0
  printf '%s\r\n' '[HKEY_CURRENT_USER\Control Panel\Desktop]' "$dpi_value" ''
}

import_prefix_settings() {
  if [ "$STEAMGPTK_RETINA" = 1 ]; then retina_line='"RetinaMode"="y"'; else retina_line='"RetinaMode"=-'; fi
  dpi_value=""
  [ "$verb" != waitforexitandrun ] || plan_logpixels 2>/dev/null || dpi_value=""
  settings_file=$(mktemp "$WINEPREFIX/drive_c/steamgptk-settings.XXXXXX") || return 0
  if ! { printf '%s\r\n' 'Windows Registry Editor Version 5.00' '' \
      '[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug]' '"Auto"="0"' '' \
      '[HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug]' '"Auto"="0"' '' \
      '[HKEY_CURRENT_USER\Software\Wine\WineDbg]' '"ShowCrashDialog"=dword:00000000' '' \
      && video_lines && printf '%s\r\n' \
      '[HKEY_LOCAL_MACHINE\Software\Classes\steam]' '"URL Protocol"=""' '' \
      '[HKEY_LOCAL_MACHINE\Software\Classes\steam\shell\open\command]' \
      '@="\"C:\\Program Files (x86)\\Steam\\steam.exe\" \"%1\""' ''; } > "$settings_file"; then
    rm -f "$settings_file"
    echo '=== could not write prefix settings ===' >> "$log" 2>&1 || true
    return 0
  fi
  if settings_already_applied; then
    import_status=0
    echo '=== prefix settings already applied, skipped the import ===' >> "$log" 2>&1 || true
  else
    without_lock_fds "$WINELOADER" reg import "C:\\${settings_file##*/}" >> "$log" 2>&1 \
      && import_status=0 || import_status=$?
  fi
  rm -f "$settings_file"
  if [ "$import_status" -eq 0 ] && [ -n "$dpi_value" ]; then
    without_lock_fds "$WINESERVER" -k >> "$log" 2>&1 || true
    without_lock_fds "$WINESERVER" -w >> "$log" 2>&1 || true
    echo "video: LogPixels=$new_dpi" >> "$log" 2>&1 || true
  fi
}

if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
  export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
  stage_step="prefix lock"
  claim_prefix
  mkdir -p "$WINEPREFIX"
  msync_from=launch-options
  sync_marker="$STEAM_COMPAT_DATA_PATH/steamgptk-msync"
  [ -r "$sync_marker" ] || sync_marker="$STEAM_COMPAT_DATA_PATH/notproton-msync"
  if [ -z "$WINEMSYNC" ] && [ -r "$sync_marker" ]; then
    WINEMSYNC=$(tr -d ' \t\n' \
      < "$sync_marker" 2>/dev/null || true)
    msync_from=carried-over
  fi
  [ -n "$WINEMSYNC" ] || msync_from=default
  export WINEMSYNC="${WINEMSYNC:-0}"
  # 32-bit WoW64 processes on Apple Silicon deadlock with WINEMSYNC=1.
  if [ -f "$1" ] && file -b "$1" 2>/dev/null | grep -q "PE32 "; then
    if [ "$WINEMSYNC" = "1" ]; then
      echo "=== 32-bit binary ($1) detected: forcing WINEMSYNC=0 to prevent WoW64 deadlock ===" >> "$log" 2>&1 || true
      WINEMSYNC=0
      export WINEMSYNC=0
    fi
  fi
  printf '%s' "$WINEMSYNC" \
    > "$STEAM_COMPAT_DATA_PATH/steamgptk-msync" 2>/dev/null || true
  hud_marker="$STEAM_COMPAT_DATA_PATH/steamgptk-hud"
  [ -r "$hud_marker" ] || hud_marker="$STEAM_COMPAT_DATA_PATH/notproton-hud"
  if [ -z "$MTL_HUD_ENABLED" ] && [ -r "$hud_marker" ]; then
    MTL_HUD_ENABLED=$(tr -d ' \t\n' < "$hud_marker" 2>/dev/null || true)
    export MTL_HUD_ENABLED
    echo "hud: MTL_HUD_ENABLED=$MTL_HUD_ENABLED from carry-over" >> "$log" 2>&1 || true
  fi
  stage_step="prefix arch check"
  refuse_foreign_prefix
  echo "sync: WINEMSYNC=$WINEMSYNC from $msync_from" >> "$log" 2>&1 || true
  without_lock_fds "$WINESERVER" -k >> "$log" 2>&1 || true
  without_lock_fds "$WINESERVER" -w >> "$log" 2>&1 || true
  stage_step="profile layout"
  lay_out_proton_profile
  if ! prefix_up_to_date; then
    without_lock_fds "$WINELOADER" wineboot --init >> "$log" 2>&1 || true
  fi
  STEAMGPTK_RETINA="${STEAMGPTK_RETINA:-1}"
  echo "video: RetinaMode=$STEAMGPTK_RETINA" >> "$log" 2>&1 || true
  import_prefix_settings
fi

bridge_src="$HOME/Library/Application Support/steamgptk/bridge"
prefix_steam="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
verify_runner() {
  if [ ! -d "$bridge_src/wine" ]; then
    echo "=== no patched ntdll in the bridge, run SteamGPTK ===" >> "$log" 2>&1 || true
    return
  fi
  for arch in x86_64-windows i386-windows aarch64-windows; do
    staged="$bridge_src/wine/$arch/ntdll.dll"
    live="$CX_ROOT/lib/wine/$arch/ntdll.dll"
    [ -f "$staged" ] || continue
    if [ ! -f "$live" ]; then
      echo "=== runner has no $arch ntdll, set up the runner in SteamGPTK ===" >> "$log" 2>&1 || true
    elif ! cmp -s "$staged" "$live"; then
      echo "=== runner $arch ntdll is not the patched copy, set up the runner in SteamGPTK ===" >> "$log" 2>&1 || true
    fi
  done
  for arch in i386-windows x86_64-windows "${wine_unix##*/}"; do
    case "$arch" in
      *-unix) name="lsteamclient.so" ;;
      *) name="lsteamclient.dll" ;;
    esac
    [ -f "$CX_ROOT/lib/wine/$arch/$name" ] && continue
    echo "=== runner is missing $arch/$name, set up the runner in SteamGPTK ===" >> "$log" 2>&1 || true
  done
}
install_lsteamclient_trigger() {
  src="$bridge_src/i386-windows/lsteamclient.dll"
  dst="$WINEPREFIX/drive_c/windows/syswow64/lsteamclient.dll"
  if [ -f "$src" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ]; then
    if ! cmp -s "$src" "$dst"; then
      cp -f "$src" "$dst" && echo "=== installed syswow64 lsteamclient trigger ===" >> "$log" 2>&1 || true
    fi
  fi
  src64="$bridge_src/x86_64-windows/lsteamclient.dll"
  dst64="$WINEPREFIX/drive_c/windows/system32/lsteamclient.dll"
  dst64_sc="$WINEPREFIX/drive_c/windows/system32/steamclient64.dll"
  if [ -f "$src64" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ]; then
    if ! cmp -s "$src64" "$dst64"; then
      cp -f "$src64" "$dst64" && echo "=== installed system32 lsteamclient trigger ===" >> "$log" 2>&1 || true
    fi
    rm -f "$dst64_sc"
  fi
}

# A fix to match Proton
install_legacy_steam_dll() {
  src="$bridge_src/legacycompat/Steam.dll"
  dst="$WINEPREFIX/drive_c/windows/syswow64/Steam.dll"
  [ -f "$src" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ] || return 0
  cmp -s "$src" "$dst" && return 0
  if cp -f "$src" "$dst"; then
    echo "=== installed legacy Steam.dll ===" >> "$log" 2>&1 || true
  else
    echo "=== could not install the legacy Steam.dll ===" >> "$log" 2>&1 || true
  fi
}

# Steam runs a Windows game's installscript.vdf by invoking the standalone
# evaluator through the compat tool, the same way the linux client does, but
# the binaries are missing on macOS, so...
install_legacycompat() {
  src="$bridge_src/legacycompat"
  dst="$STEAM_COMPAT_CLIENT_INSTALL_PATH/legacycompat"
  [ -d "$src" ] && [ -n "$STEAM_COMPAT_CLIENT_INSTALL_PATH" ] || return 0
  mkdir -p "$dst" || return 0
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    cmp -s "$f" "$dst/$b" && continue
    cp -f "$f" "$dst/$b" && \
      echo "=== installed legacycompat/$b ===" >> "$log" 2>&1
  done
}

bridge_files="steamclient64.dll steamclient.dll tier0_s64.dll vstdlib_s64.dll"
bridge_files="$bridge_files tier0_s.dll vstdlib_s.dll"
bridge_files="$bridge_files lsteamclient.dll lsteamclient.so steam.exe steamclient.so steamclient64.so ntdll_compat.so"
if [ -d "$bridge_src" ] && [ -n "$WINEPREFIX" ]; then
  stage_step="bridge staging"
  mkdir -p "$prefix_steam"
  for f in $bridge_files; do
    src="$bridge_src/$f"
    case "$f" in
      *.so) src="$bridge_src/${wine_unix##*/}/$f" ;;
      steamclient.dll)
        if [ "$profile_steam32" = 1 ]; then
          src="$bridge_src/i386-windows/lsteamclient.dll"
          if [ ! -f "$src" ]; then
            echo "=== $game_profile needs the 32-bit Steam bridge; run Install / Repair in SteamGPTK ===" >> "$log" 2>&1 || true
            exit 1
          fi
          echo "=== $game_profile: using the 32-bit Steam bridge ===" >> "$log" 2>&1 || true
        fi
        ;;
    esac
    if [ ! -f "$src" ]; then
      echo "=== bridge missing $f ===" >> "$log" 2>&1 || true
      continue
    fi
    cp -f "$src" "$prefix_steam/$f" || \
      echo "=== failed to stage $f ===" >> "$log" 2>&1
  done
  for f in "$prefix_steam"/*.dll "$prefix_steam"/*.so "$prefix_steam"/*.exe; do
    [ -f "$f" ] || continue
    case " $bridge_files " in
      *" $(basename "$f") "*) ;;
      *) rm -f "$f" && echo "=== pruned stale $(basename "$f") ===" >> "$log" 2>&1 ;;
    esac
  done
  verify_runner
  install_lsteamclient_trigger
  install_legacy_steam_dll
  export WINEDLLPATH="$prefix_steam:$WINEDLLPATH"
  vc_overrides=$(native_vc_runtime)
  export WINEDLLOVERRIDES="${vc_overrides}steamclient=n,b;steamclient64=n,b;lsteamclient=b;d3dcompiler_43=n,b;d3dx9_43=n,b;d3dcompiler_47=n,b;nvapi64,nvngx=n,b;${WINEDLLOVERRIDES}"
  native_client="$STEAM_COMPAT_CLIENT_INSTALL_PATH"
  if [ -z "$native_client" ]; then
    native_client="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$native_client"
  fi
  install_legacycompat
  install_directx_redist() {
    redist_dir="$STEAM_COMPAT_INSTALL_PATH/DirectX_Redist"
    [ -d "$redist_dir" ] || redist_dir="$STEAM_COMPAT_INSTALL_PATH/_CommonRedist/DirectX/Jun2010"
    [ -d "$redist_dir" ] || return 0
    command -v cabextract >/dev/null 2>&1 || return 0
    wow64_dir="$WINEPREFIX/drive_c/windows/syswow64"
    [ -d "$wow64_dir" ] || return 0
    if [ ! -f "$wow64_dir/d3dcompiler_43.dll" ]; then
      cab=$(find "$redist_dir" -iname "*D3DCompiler_43_x86.cab" 2>/dev/null | head -1)
      if [ -n "$cab" ]; then
        cabextract -q -d "$wow64_dir" -F "D3DCompiler_43.dll" "$cab" 2>/dev/null && \
          echo "=== extracted D3DCompiler_43.dll from $cab ===" >> "$log" 2>&1 || true
      fi
    fi
    if [ ! -f "$wow64_dir/d3dx9_43.dll" ]; then
      cab=$(find "$redist_dir" -iname "*d3dx9_43_x86.cab" 2>/dev/null | head -1)
      if [ -n "$cab" ]; then
        cabextract -q -d "$wow64_dir" -F "d3dx9_43.dll" "$cab" 2>/dev/null && \
          echo "=== extracted d3dx9_43.dll from $cab ===" >> "$log" 2>&1 || true
      fi
    fi
  }
  install_directx_redist
  echo "=== bridge staged into $prefix_steam ===" >> "$log" 2>&1 || true
  echo "WINEDLLPATH=$WINEDLLPATH" >> "$log" 2>&1 || true
  echo "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_COMPAT_CLIENT_INSTALL_PATH" >> "$log" 2>&1 || true
fi

export WINEDEBUG="${WINEDEBUG:-err+all,fixme-all}"
trap - EXIT
echo "launch_env=$launch_env" >> "$log" 2>&1 || true
echo "=== launching ($verb): $WINELOADER $* ===" >> "$log" 2>&1 || true

target="$1"
case "$target" in
  "$STEAM_COMPAT_INSTALL_PATH"/*) foreground=1 ;;
  *) foreground=0 ;;
esac

if [ "$foreground" = 0 ]; then
  echo "=== running helper on raw loader: $* ===" >> "$log" 2>&1 || true
  case "$target" in
    *iscriptevaluator.exe*)
      echo "=== iscriptevaluator bypassed for macOS compatibility ===" >> "$log" 2>&1 || true
      exit 0
      ;;
  esac
  without_lock_fds "$WINELOADER" "$@" >> "$log" 2>&1
  status=$?
  echo "=== helper exited status=$status ===" >> "$log" 2>&1 || true
  exit $status
fi

# Fixes CrossOver window focus issues
steam_root="$(dirname "$(dirname "$(dirname "$STEAM_COMPAT_DATA_PATH")")")"
manifest="$steam_root/steamapps/appmanifest_$app_id.acf"
client_root="$STEAM_COMPAT_CLIENT_INSTALL_PATH"
while [ -n "$client_root" ] && [ "$client_root" != "/" ] && [ ! -d "$client_root/appcache" ]; do
  client_root=$(dirname "$client_root")
done
# Icon stuff
appinfo_tool="$HOME/Library/Application Support/steamgptk/appinfo"
appinfo_vdf="$client_root/appcache/appinfo.vdf"
meta_name=""
meta_icon=""
meta_clienticon=""
if [ -x "$appinfo_tool" ] && [ -f "$appinfo_vdf" ]; then
  meta=$("$appinfo_tool" "$appinfo_vdf" "$app_id" 2>> "$log") || meta=""
  meta_name=$(printf '%s\n' "$meta" | sed -n 's/^name=//p')
  meta_icon=$(printf '%s\n' "$meta" | sed -n 's/^icon=//p')
  meta_clienticon=$(printf '%s\n' "$meta" | sed -n 's/^clienticon=//p')
fi
game_name="$meta_name"
if [ -z "$game_name" ] && [ -f "$manifest" ]; then
  game_name=$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$manifest" | head -1)
fi
[ -z "$game_name" ] && game_name=$(basename "$STEAM_COMPAT_INSTALL_PATH")
[ -z "$game_name" ] && game_name="Steam Game"
# shellcheck disable=SC1003 # the pair deletes a literal backslash, not a quote
bundle_name=$(printf '%s' "$game_name" | tr -d '/:"`$\\')
game_name_xml=$(printf '%s' "$game_name" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
loader_root="$HOME/Library/Application Support/steamgptk/launchers/$app_id"
mkdir -p "$loader_root"
loader_app="$loader_root/$bundle_name.app"
find "$loader_root" -maxdepth 1 -name '.build.*' -mmin +60 -exec rm -rf {} + 2>/dev/null || true
loader_work=$(mktemp -d "$loader_root/.build.XXXXXX")
loader_stage="$loader_work/new/$bundle_name.app"
loader_contents="$loader_stage/Contents"
loader_macos="$loader_contents/MacOS"
loader_res="$loader_contents/Resources"
mkdir -p "$loader_macos" "$loader_res"

icon_arg=""
resolve_icon() {
  set +e
  iconmaker="$HOME/Library/Application Support/steamgptk/iconmaker"
  art_dir="$client_root/appcache/librarycache/$app_id"
  art=""
  if [ -n "$meta_clienticon" ]; then
    ico="$loader_root/clienticon-$meta_clienticon.ico"
    absent="$loader_root/clienticon-$meta_clienticon.absent"
    find "$loader_root" -maxdepth 1 -name 'clienticon-*'   ! -name "clienticon-$meta_clienticon.*" -delete 2>/dev/null || true
    find "$absent" -mtime +14 -delete 2>/dev/null || true
    if [ ! -s "$ico" ] && [ ! -f "$absent" ]; then
      url="https://shared.fastly.steamstatic.com/community_assets/images/apps/$app_id/$meta_clienticon.ico"
      code=$(curl -fsL --connect-timeout 5 --max-time 20 -w '%{http_code}' -o "$ico.new" "$url" 2>>"$log")
      magic=$(od -An -tx1 -N4 "$ico.new" 2>/dev/null | tr -d ' \n')
      if [ "$magic" = "00000100" ]; then
        mv -f "$ico.new" "$ico"
        echo "fetched client icon $meta_clienticon" >> "$log" 2>&1 || true
      else
        rm -f "$ico.new"
        if [ "$code" = "404" ]; then
          : > "$absent"
          echo "no client icon published for $meta_clienticon" >> "$log" 2>&1 || true
        else
          echo "client icon fetch for $meta_clienticon failed (http ${code:-none}), will retry" >> "$log" 2>&1 || true
        fi
      fi
    fi
    [ -s "$ico" ] && art="$ico"
  fi
  if [ -z "$art" ] && [ -n "$meta_icon" ] && [ -f "$art_dir/$meta_icon.jpg" ]; then
    art="$art_dir/$meta_icon.jpg"
  fi
  if [ -z "$art" ]; then
    art=$(find "$art_dir" -maxdepth 1 -type f -name '*.jpg' 2>/dev/null |   grep -E '/[0-9a-f]{40}\.jpg$' | head -1)
  fi
  # Capsule art (horrible) fallback if no icon at all exists...
  if [ -z "$art" ]; then
    for name in library_600x900.jpg header.jpg; do
      found=$(find "$art_dir" -name "$name" 2>/dev/null | head -1)
      [ -n "$found" ] && { art="$found"; break; }
    done
  fi
  # non-Steam shortcuts have no art, so (as a temporary measure while I think of
  # better ways to solve for this) let's use the icon in the EXE itself instead.
  if [ -z "$art" ] && [ -f "$target" ]; then
    case "$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')" in
      *.exe) art="$target" ;;
    esac
  fi
  icon_source=""
  if [ -n "$art" ]; then
    icon_source="$art $(stat -f %m "$art" 2>/dev/null || echo 0)"
  fi
  icon_cache="$loader_root/game.icns"
  if [ -n "$art" ] && [ -s "$icon_cache" ] &&   [ "$(cat "$loader_root/steamgptk-icon.source" 2>/dev/null)" =   "$icon_source" ] && cp -f "$icon_cache" "$loader_res/game.icns"; then
    icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
    echo "icon reused from $art" >> "$log" 2>&1 || true
  elif [ -n "$art" ] && [ -x "$iconmaker" ]; then
    if "$iconmaker" "$art" "$icon_cache" >> "$log" 2>&1 &&   cp -f "$icon_cache" "$loader_res/game.icns"; then
      icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
      printf '%s\n' "$icon_source" > "$loader_root/steamgptk-icon.source"
      echo "icon built from $art" >> "$log" 2>&1 || true
    elif [ "$art" = "$ico" ]; then
      # A cached .ico that iconmaker rejects is corrupt and passes the size
      # guard on every launch, so drop it to force a clean fetch next time.
      rm -f "$ico"
      echo "discarded unreadable client icon $meta_clienticon" >> "$log" 2>&1 || true
    fi
  fi
  set -e
  return 0
}
resolve_icon || true
[ -n "$icon_arg" ] || echo "no icon resolved, launching without one" >> "$log" 2>&1 || true

uielement_arg=""
if [ "${STEAMGPTK_HIDE_LAUNCHER_TILE:-0}" = "1" ]; then
  uielement_arg="  <key>LSUIElement</key><true/>"
  echo "launcher tile hidden by STEAMGPTK_HIDE_LAUNCHER_TILE" >> "$log" 2>&1 || true
fi
cat > "$loader_contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$game_name_xml</string>
  <key>CFBundleDisplayName</key><string>$game_name_xml</string>
  <key>CFBundleIdentifier</key><string>com.steamgptk.launcher.$app_id</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
$uielement_arg
$icon_arg
</dict>
</plist>
PLIST

# Invokes macOS Game Mode
(
  set --
  for f in "$wine_unix"/*; do
    [ -e "$f" ] || continue
    base=${f##*/}
    case "$base" in
      wine|wine.app) continue ;;
    esac
    set -- "$@" "$f"
  done
  [ "$#" -eq 0 ] || ln -sfn "$@" "$loader_macos/"
)
ln "$WINELOADER" "$loader_macos/wine" 2>/dev/null || cp "$WINELOADER" "$loader_macos/wine"
[ -d "$CX_ROOT/lib" ] && ln -sfn "$CX_ROOT/lib" "$loader_contents/lib"
loader_dir="$(dirname "$WINELOADER")"
if [ -f "$loader_dir/wine64-preloader" ]; then
  ln -sfn "$loader_dir/wine64-preloader" "$loader_macos/wine64-preloader" 2>/dev/null || true
  ln -sfn "$loader_dir/wine64-preloader" "$loader_macos/wine-preloader" 2>/dev/null || true
elif [ -f "$loader_dir/wine-preloader" ]; then
  ln -sfn "$loader_dir/wine-preloader" "$loader_macos/wine-preloader" 2>/dev/null || true
fi
if [ -x "$loader_macos/wine" ]; then
  WINELOADER="$loader_app/Contents/MacOS/wine"
  echo "loader staged in bundle for game mode" >> "$log" 2>&1 || true
else
  echo "loader staging failed, game mode unavailable" >> "$log" 2>&1 || true
fi

cat > "$loader_macos/launcher" <<LAUNCHER
#!/bin/sh
export WINELOADER="$WINELOADER"
# SIP strips DYLD_* when exec-ing /bin/sh, so bake the runner lib path in here
export DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH"
wine_log="$loader_root/steamgptk-wine.log"
exec > "\$wine_log" 2>&1
shim="$HOME/Library/Application Support/steamgptk/overlay-shim.dylib"
if [ -f "\$shim" ]; then
  if [ -n "\$STEAM_DYLD_INSERT_LIBRARIES" ]; then
    export DYLD_INSERT_LIBRARIES="\$shim:\$STEAM_DYLD_INSERT_LIBRARIES"
  else
    export DYLD_INSERT_LIBRARIES="\$shim"
  fi
  export STEAMGPTK_OVERLAY_SHIM="\$shim"
  # The pinned bridge payload still reads its original protocol variable.
  export NOTPROTON_OVERLAY_SHIM="\$shim"
elif [ -n "\$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  export DYLD_INSERT_LIBRARIES="\$STEAM_DYLD_INSERT_LIBRARIES"
fi
[ -n "\$STEAMGPTK_GAME_CWD" ] && cd "\$STEAMGPTK_GAME_CWD"
exec "$WINELOADER" "\$@"
LAUNCHER
chmod +x "$loader_macos/launcher"

np_support="$HOME/Library/Application Support/steamgptk"
bundle_listing() {
  (cd "$1" || exit 1
    find . | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then
      printf 'l %s %s\n' "$p" "$(readlink "$p")"
    elif [ -d "$p" ]; then
      printf 'd %s\n' "$p"
    else
      printf 'f %s %s %s\n' "$p" "$(stat -f %Lp "$p")" "$(cksum < "$p")"
    fi
  done)
}
bundle_matches() {
  if [ -x "$np_support/appinfo" ]; then
    if "$np_support/appinfo" --same-bundle "$1" "$2" 2>/dev/null; then
      return 0
    else
      case "$?" in 1) return 1 ;; esac
    fi
  fi
  left_listing=$(bundle_listing "$1") || return 1
  right_listing=$(bundle_listing "$2") || return 1
  [ "$left_listing" = "$right_listing" ]
}
install_bundle() (
  exec 7>> "$loader_root/.lock"
  /usr/bin/lockf -s -t 30 7 || exit 1
  same=""
  for b in "$loader_root"/*.app; do
    if [ "$b" = "$loader_app" ] && [ -d "$b" ] && [ ! -L "$b" ] &&
       bundle_matches "$b" "$loader_stage"; then
      same=1
    fi
  done
  if [ -n "$same" ]; then
    for b in "$loader_root"/*.app "$loader_root"/.[!.]*.app; do
      if [ "$b" != "$loader_app" ]; then rm -rf "$b" || true; fi
    done
    echo "launcher bundle unchanged" >> "$log" 2>&1 || true
  else
    stage_identity=$(stat -f '%d:%i' "$loader_stage") || exit 1
    loader_backup=$(mktemp -d "$loader_root/.backup.XXXXXX") || exit 1
    finish_bundle() {
      result=$?
      trap - EXIT
      trap '' HUP INT TERM
      installed_identity=$(stat -f '%d:%i' "$loader_app" 2>/dev/null) || installed_identity=""
      if [ "$installed_identity" != "$stage_identity" ]; then
        for saved in "$loader_backup"/* "$loader_backup"/.[!.]*; do
          [ -e "$saved" ] || [ -L "$saved" ] || continue
          mv "$saved" "$loader_root/${saved##*/}" || result=1
        done
        rmdir "$loader_backup" 2>/dev/null || result=1
      else
        rm -rf "$loader_backup" || true
      fi
      rm -rf "$loader_work" || true
      exit "$result"
    }
    trap 'finish_bundle' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    for b in "$loader_root"/*.app "$loader_root"/.[!.]*.app "$loader_app"; do
      if [ -e "$b" ] || [ -L "$b" ]; then
        mv "$b" "$loader_backup/${b##*/}" || exit 1
      fi
    done
    mv "$loader_stage" "$loader_app" || exit 1
    echo "launcher bundle updated" >> "$log" 2>&1 || true
    finish_bundle
  fi
  rm -rf "$loader_work" || true
)
install_bundle

wine_helpers='winedevice\.exe|services\.exe|plugplay\.exe|svchost\.exe'
wine_helpers="$wine_helpers|rpcss\.exe|explorer\.exe|steam\.exe"
wine_helpers="$wine_helpers|winemenubuilder\.exe|conhost\.exe|start\.exe"
wine_helpers="$wine_helpers|wineboot\.exe|rundll32\.exe|tabtip\.exe"
wine_helpers="$wine_helpers|vc_redist|vcredist|dxsetup\.exe|msiexec\.exe"
wine_helpers="$wine_helpers|installinf|iscriptevaluator\.exe|regsvr32\.exe"
wine_helpers="$wine_helpers|winedbg\.exe|unitycrashhandler"
prefix_server_dir() {
  [ -n "$WINEPREFIX" ] || return 1
  ids=$(stat -f '%d-%i' "$WINEPREFIX" 2>/dev/null) || return 1
  [ -n "$ids" ] || return 1
  printf '/tmp/.wine-%s/server-%s' "$(id -u)" \
    "$(printf '%s' "$ids" | awk -F- '{printf "%x-%x", $1, $2}')"
}

wine_game_pids() {
  # ucomm identifies the native loader even after Wine replaces argv[0] with
  # a Windows executable. Matching /wine anywhere in argv also matches other
  # shell launchers' renderer options, keeping closed sessions alive forever.
  ps -ww -eo pid=,ucomm=,args= 2>/dev/null | \
    STEAMGPTK_WINE_HELPERS="$wine_helpers" awk '
      BEGIN { helpers = ENVIRON["STEAMGPTK_WINE_HELPERS"] }
      $1 !~ /^[0-9]+$/ { next }
      {
        image = tolower($2)
        if (image !~ /^(wine|wine64|wine-preloader|wine64-preloader)$/) next
        pid = $1
        command = tolower($0)
        sub(/^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", command)
        if (!match(command, /\.exe([[:space:]"]|$)/)) next
        executable = substr(command, 1, RSTART + 3)
        gsub(/\\/, "/", executable)
        sub(/^.*\//, "", executable)
        # Exclude the helper executable, not helper names passed to a game.
        if (executable ~ helpers) next
        print pid
      }
    '
}

prefix_game_running() {
  [ -n "$(wine_game_pids)" ]
}

activate_game() {
  echo "=== activating game window ===" >> "$log" 2>&1 || true
  game_pid=$(wine_game_pids | sed -n '1p')
  if [ -n "$game_pid" ]; then
    swift - "$game_pid" << 'EOF' >> "$log" 2>&1 || osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $game_pid) to true" >> "$log" 2>&1 || true
import AppKit
if let pidStr = CommandLine.arguments.dropFirst().first, let pid = pid_t(pidStr) {
  _ = NSRunningApplication(processIdentifier: pid)?.activate()
}
EOF
  fi
}

wait_prefix_idle() {
  idle=0
  activated=0
  # Wait up to 20 seconds for the game process to appear
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    prefix_game_running && break
    sleep 1
  done
  # Wait as long as the game is actively running
  while :; do
    if prefix_game_running; then
      idle=0
      if [ "$activated" -eq 0 ]; then
        activate_game
        activated=1
      fi
    else
      idle=$((idle + 1))
      activated=0
      if [ "$idle" -ge 6 ]; then
        break
      fi
    fi
    sleep 1
  done
  echo "wait_prefix_idle done, game session concluded" >> "$log" 2>&1 || true
}

kill_wine_prefix() {
  "$WINESERVER" -k >> "$log" 2>&1 || true
  "$WINESERVER" -w >> "$log" 2>&1 || true
  if command -v lsof >/dev/null 2>&1 && server_dir=$(prefix_server_dir); then
    if [ -d "$server_dir" ]; then
      survivors=$(lsof -t +D "$server_dir" 2>/dev/null | sort -u)
      if [ -n "$survivors" ]; then
        echo "=== sweeping prefix stragglers: $survivors ===" >> "$log" 2>&1 || true
        # shellcheck disable=SC2086 # survivors is a list of pids and has to split
        kill -9 $survivors 2>/dev/null || true
      fi
    fi
  fi
}

# Steam's "Exit Game" and the client shutting the game down both send a
# termination signal to this run script, this handles it
# shellcheck disable=SC2329 # the trap below invokes this
terminate() {
  echo "=== termination signal received, killing wine prefix ===" >> "$log" 2>&1 || true
  kill_wine_prefix
  [ -n "$open_pid" ] && kill "$open_pid" 2>/dev/null || true
  exit 0
}
trap terminate TERM INT HUP

shim_exe="C:\\Program Files (x86)\\Steam\\steam.exe"

game_cwd="$(pwd)"
game_name="$(basename "$1" 2>/dev/null || true)"
if [ -n "$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  echo "=== overlay injected from $STEAM_DYLD_INSERT_LIBRARIES ===" >> "$log" 2>&1 || true
else
  echo "=== client staged no overlay renderer, overlay disabled ===" >> "$log" 2>&1 || true
fi


set -- --args "$shim_exe" "$@"
for name in $(env | sed -nE 's/^(Steam[A-Za-z0-9]*|SikarugirApp[A-Za-z0-9]*|GST_PLUGIN_PATH|VK_DRIVER_FILES|VK_ICD_FILENAMES|WINEBOOT_HIDE_DIALOG|WINEESYNC|(CX_GRAPHICS|CX_D3DMETAL|CX_APPLEGPT|CX_FWD|WINEDLLPATH_|D3DM_|DXMT_|DXVK_|MVK_|MTL_|ROSETTA_)[A-Z0-9_]*)=.*/\1/p'); do
  eval "value=\$$name"
  # shellcheck disable=SC2154 # eval assigns value on the line above
  set -- --env "$name=$value" "$@"
done
set -- \
  --env CX_ROOT="$CX_ROOT" \
  --env CX_HOME="$CX_HOME" \
  --env WINESERVER="$WINESERVER" \
  --env WINEDLLPATH="$WINEDLLPATH" \
  --env WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  --env WINEMSYNC="$WINEMSYNC" \
  --env WINEPREFIX="$WINEPREFIX" \
  --env WINEDEBUG="$WINEDEBUG" \
  --env DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH" \
  --env PATH="$PATH" \
  --env STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
  --env STEAM_COMPAT_INSTALL_PATH="$STEAM_COMPAT_INSTALL_PATH" \
  --env STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_COMPAT_CLIENT_INSTALL_PATH" \
  --env STEAM_COMPAT_APP_ID="$STEAM_COMPAT_APP_ID" \
  --env STEAM_DYLD_INSERT_LIBRARIES="$STEAM_DYLD_INSERT_LIBRARIES" \
  --env STEAMGPTK_GAME_CWD="$game_cwd" "$@"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A"
lsregister="$lsregister/Frameworks/LaunchServices.framework/Support/lsregister"
registered="$loader_root/.launchservices-registered"
if [ ! -f "$registered" ] || [ "$loader_app/Contents/Info.plist" -nt "$registered" ]; then
  if [ -x "$lsregister" ] && "$lsregister" -f "$loader_app" >> "$log" 2>&1; then
    touch "$registered" 2>/dev/null || true
  fi
fi
(exec 8>&- 9>&-; exec open -n -W -a "$loader_app" "$@") >> "$log" 2>&1 &
open_pid=$!
status=0
seen=0
idle=0
while :; do
  if prefix_game_running; then
    if [ "$seen" -eq 0 ]; then
      activate_game
    fi
    seen=1
    idle=0
  else
    idle=$((idle + 1))
  fi
  if ! kill -0 "$open_pid" 2>/dev/null; then
    wait "$open_pid" || status=$?
    echo "=== bundle exited status=$status ===" >> "$log" 2>&1 || true
    if [ "$status" -le 128 ]; then
      wait_prefix_idle
    fi
    break
  fi
  if [ "$seen" -eq 1 ] && [ "$idle" -ge 10 ]; then
    echo "=== game tree gone, ending session ===" >> "$log" 2>&1 || true
    break
  fi
  sleep 1
done
echo "=== game exited status=$status, killing wine prefix ===" >> "$log" 2>&1 || true
kill_wine_prefix
echo "=== wine prefix killed, session ending ===" >> "$log" 2>&1 || true
exit $status
