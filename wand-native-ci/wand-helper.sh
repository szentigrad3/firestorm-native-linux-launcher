#!/usr/bin/env bash
set -Eeuo pipefail

TOOL_ID="GE-Proton-Wand-SHA256"
TOOL_DISPLAY="GE Proton Wand SHA256"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wand"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wand-native"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/wand-native"
APPDIR="${APPDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
PAYLOAD64="$APPDIR/usr/lib/wand-native/payload/x86_64-windows/crypt32.dll"
WRAPPER_SRC="$APPDIR/usr/lib/wand-native/wand-steam-wrap"
VDF_TOOL="$APPDIR/usr/lib/wand-native/wand-vdf.py"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "$DATA_DIR"

log(){ printf '%s\n' "$*"; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

resolve(){ readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"; }

steam_roots(){
  {
    printf '%s\n'       "/mnt/games/Steam"       "$HOME/.local/share/Steam"       "$HOME/.steam/root"       "$HOME/.steam/steam"       "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
  } | while IFS= read -r p; do
    [[ -d "$p/steamapps" ]] && resolve "$p"
  done | awk 'NF && !seen[$0]++'
}

steam_root(){
  local p
  while IFS= read -r p; do
    [[ -f "$p/config/config.vdf" || -f "$p/steamapps/libraryfolders.vdf" ]] && { printf '%s\n' "$p"; return 0; }
  done < <(steam_roots)
  return 1
}

steam_libraries(){
  local root vdf
  root="$(steam_root)" || return 1
  {
    printf '%s\n' "$root"
    for vdf in "$root/steamapps/libraryfolders.vdf" "$root/config/libraryfolders.vdf"; do
      [[ -f "$vdf" ]] || continue
      sed -nE 's/^[[:space:]]*"path"[[:space:]]+"([^"]+)".*/\1/p' "$vdf" | sed 's#\\\\#/#g'
    done
  } | while IFS= read -r p; do [[ -d "$p/steamapps" ]] && resolve "$p"; done | awk 'NF && !seen[$0]++'
}

list_games(){
  local lib m appid name
  while IFS= read -r lib; do
    for m in "$lib"/steamapps/appmanifest_*.acf; do
      [[ -f "$m" ]] || continue
      appid="$(sed -nE 's/^[[:space:]]*"appid"[[:space:]]+"([^"]+)".*/\1/p' "$m" | head -1)"
      name="$(sed -nE 's/^[[:space:]]*"name"[[:space:]]+"([^"]+)".*/\1/p' "$m" | head -1)"
      [[ -n "$appid" && -n "$name" ]] && printf '%s\t%s\t%s\n' "$appid" "$name" "$lib"
    done
  done < <(steam_libraries)
}

game_library(){
  local appid="$1" lib
  while IFS= read -r lib; do
    [[ -f "$lib/steamapps/appmanifest_${appid}.acf" ]] && { printf '%s\n' "$lib"; return 0; }
  done < <(steam_libraries)
  return 1
}

localconfig(){
  local root
  root="$(steam_root)" || return 1
  find "$root/userdata" -mindepth 3 -maxdepth 3 -type f -path '*/config/localconfig.vdf' -printf '%T@ %p\n' 2>/dev/null     | sort -nr | head -1 | cut -d' ' -f2-
}

find_base_proton(){
  local root lib d
  root="$(steam_root)" || return 1
  for d in     "$root/compatibilitytools.d/Proton-GE Latest"     "$root/compatibilitytools.d/GE-Proton11-7"     "$HOME/.local/share/Steam/compatibilitytools.d/Proton-GE Latest"     "$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-7"
  do
    [[ -x "$d/proton" ]] && { resolve "$d"; return 0; }
  done
  while IFS= read -r lib; do
    d="$(find "$lib/compatibilitytools.d" -mindepth 1 -maxdepth 1 -type d \( -name 'GE-Proton*' -o -name 'Proton-GE*' \) -print 2>/dev/null | sort -V | tail -1)"
    [[ -n "$d" && -x "$d/proton" ]] && { resolve "$d"; return 0; }
  done < <(steam_libraries)
  return 1
}

download_ge(){
  local root compat tmp json tarurl sumurl archive sumfile extracted
  root="$(steam_root)" || die "Steam not found"
  compat="$root/compatibilitytools.d"
  mkdir -p "$compat" "$CACHE_DIR"
  tmp="$(mktemp -d "$CACHE_DIR/ge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  log "No Proton-GE installation found. Downloading official GE-Proton11-7..."
  json="$tmp/release.json"
  curl -fL --retry 3 -o "$json" "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/tags/GE-Proton11-7"
  read -r tarurl sumurl < <(python3 - "$json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
tar=sum(a["browser_download_url"]+" " for a in j["assets"] if a["name"]=="GE-Proton11-7-x86_64.tar.gz")
chk=sum(a["browser_download_url"]+" " for a in j["assets"] if a["name"].endswith(".sha512sum") and "GE-Proton11-7" in a["name"])
print(tar.strip(),chk.strip())
PY
)
  [[ -n "$tarurl" && -n "$sumurl" ]] || die "Could not resolve official GE-Proton11-7 assets"
  archive="$tmp/GE-Proton11-7-x86_64.tar.gz"
  sumfile="$tmp/GE-Proton11-7-x86_64.sha512sum"
  curl -fL --retry 3 -o "$archive" "$tarurl"
  curl -fL --retry 3 -o "$sumfile" "$sumurl"
  ( cd "$tmp"; sed -i 's#  .*/#  #' "$(basename "$sumfile")"; sha512sum -c "$(basename "$sumfile")" )
  tar -xzf "$archive" -C "$compat"
  extracted="$(find "$compat" -mindepth 1 -maxdepth 1 -type d -name 'GE-Proton11-7*' -print | sort | head -1)"
  [[ -x "$extracted/proton" ]] || die "Downloaded Proton-GE did not install correctly"
  resolve "$extracted"
}

wand_exe(){
  local prefix="$1"
  find "$prefix/pfx/drive_c/users" -type f \( -iname 'Wand.exe' -o -iname 'WeMod.exe' \)     -path '*/AppData/Local/*' -print 2>/dev/null     | grep -E '/(Wand|WeMod)/(app-[^/]+/)?(Wand|WeMod)\.exe$'     | sort -V | tail -1
}

install_wand(){
  local appid="$1" tool="$2" lib prefix installer w
  lib="$(game_library "$appid")" || die "Game AppID $appid is not installed"
  prefix="$lib/steamapps/compatdata/$appid"
  mkdir -p "$prefix" "$CACHE_DIR"
  w="$(wand_exe "$prefix" || true)"
  if [[ -n "$w" ]]; then
    log "Wand already installed: $w"
    return 0
  fi
  installer="$CACHE_DIR/WandSetup.exe"
  log "Downloading Wand from the official WeMod download endpoint..."
  curl -fL --retry 3 -A 'Mozilla/5.0' -o "$installer.tmp" "https://www.wemod.com/download/direct"
  [[ $(stat -c '%s' "$installer.tmp") -gt 1000000 ]] || die "Wand installer download was unexpectedly small"
  mv -f "$installer.tmp" "$installer"
  log "Installing Wand into this game's Proton prefix..."
  STEAM_COMPAT_DATA_PATH="$prefix"   STEAM_COMPAT_CLIENT_INSTALL_PATH="$(steam_root)"   SteamAppId="$appid" SteamGameId="$appid"     "$tool/proton" waitforexitandrun "$installer" || true
  sleep 3
  w="$(wand_exe "$prefix" || true)"
  [[ -n "$w" ]] || die "Wand installer finished but Wand.exe was not found in the game prefix"
  log "Wand installed: $w"
  if [[ -x "$tool/files/bin/wineserver" ]]; then
    WINEPREFIX="$prefix/pfx" "$tool/files/bin/wineserver" -k >/dev/null 2>&1 || true
  fi
}

stop_steam_for_setup(){
  if pgrep -x steam >/dev/null 2>&1 || pgrep -f 'steamwebhelper' >/dev/null 2>&1; then
    log "Steam must close once while Setup/Repair writes its compatibility settings."
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      pgrep -x steam >/dev/null 2>&1 || return 0
      sleep 0.5
    done
    die "Steam did not close. Exit Steam manually and press Setup / Repair again."
  fi
}

setup_game(){
  local appid="$1" root lib base dest dst mode cfg local launch
  [[ "$appid" =~ ^[0-9]+$ ]] || die "Invalid AppID: $appid"
  root="$(steam_root)" || die "Steam was not detected"
  lib="$(game_library "$appid")" || die "Selected game is not installed"
  [[ -f "$PAYLOAD64" ]] || die "RC4 patched crypt32 payload is missing"
  stop_steam_for_setup

  base="$(find_base_proton || true)"
  [[ -n "$base" ]] || base="$(download_ge)"
  log "Base Proton: $base"

  dest="$root/compatibilitytools.d/$TOOL_ID"
  rm -rf "$dest"
  mkdir -p "$dest"
  log "Creating isolated Wand Proton tool..."
  rsync -aL --delete "$base/" "$dest/"

  dst="$(find "$dest/files" -type f -path '*/x86_64-windows/crypt32.dll' -print -quit)"
  [[ -n "$dst" ]] || die "Could not find x86_64 Wine crypt32.dll in Proton-GE"
  mode="$(stat -c '%a' "$dst")"
  cp -a "$dst" "$dst.wand-original"
  chmod u+w "$dst"
  cp -f "$PAYLOAD64" "$dst"
  chmod "$mode" "$dst"

  cat > "$dest/compatibilitytool.vdf" <<EOF
"compatibilitytools"
{
  "compat_tools"
  {
    "$TOOL_ID"
    {
      "install_path" "."
      "display_name" "$TOOL_DISPLAY"
      "from_oslist" "windows"
      "to_oslist" "linux"
    }
  }
}
EOF
  cat > "$dest/WAND-HYBRID.txt" <<EOF
Wand Native 0.1.41 RC4
Base: $base
Only x86_64 Wine crypt32.dll is replaced with the source-built property-107 patch.
Normal PLAY WITH WAND does not stop or restart Steam.
EOF

  mkdir -p "$HOME/.local/bin"
  install -m755 "$WRAPPER_SRC" "$HOME/.local/bin/wand-steam-wrap"

  install_wand "$appid" "$dest"

  cfg="$root/config/config.vdf"
  local="$(localconfig)" || die "Steam localconfig.vdf was not found"
  launch="$HOME/.local/bin/wand-steam-wrap %command%"
  python3 "$VDF_TOOL" set "$cfg" "$local" "$appid" "$TOOL_ID" "$launch" rc4

  log "Setup complete."
  log "Starting Steam again. This restart happens only during Setup / Repair."
  nohup steam >/dev/null 2>&1 &
  log "READY: PLAY WITH WAND will now launch through Steam without restarting it."
}

verify(){
  local appid="$1" root dest dst cfg local lib prefix w
  root="$(steam_root)" || die "Steam not found"
  dest="$root/compatibilitytools.d/$TOOL_ID"
  [[ -x "$dest/proton" ]] || die "Wand Proton tool is not installed"
  dst="$(find "$dest/files" -type f -path '*/x86_64-windows/crypt32.dll' -print -quit)"
  [[ -n "$dst" && -f "$dst.wand-original" ]] || die "Patched crypt32 installation is incomplete"
  cmp -s "$dst" "$PAYLOAD64" || die "Installed crypt32 does not match the RC4 payload"
  cfg="$root/config/config.vdf"
  local="$(localconfig)" || die "localconfig.vdf not found"
  python3 "$VDF_TOOL" check "$cfg" "$local" "$appid" "$TOOL_ID"
  lib="$(game_library "$appid")" || die "Game is not installed"
  prefix="$lib/steamapps/compatdata/$appid"
  w="$(wand_exe "$prefix" || true)"
  [[ -n "$w" ]] || die "Wand is not installed in this game prefix"
  log "Wand compatibility tool is healthy."
  log "Wand: $w"
  log "PLAY WITH WAND does not restart Steam."
}

play(){
  local appid="$1"
  verify "$appid" >/dev/null
  command -v steam >/dev/null 2>&1 || die "steam command not found"
  if ! pgrep -x steam >/dev/null 2>&1; then
    log "Steam is not running; starting Steam and launching AppID $appid."
  else
    log "Steam is already running; it will NOT be restarted."
  fi
  nohup steam -applaunch "$appid" >/dev/null 2>&1 &
  log "PLAY WITH WAND dispatched AppID $appid through the Steam %command% wrapper."
}

health(){
  local appid="$1" lib prefix logs
  lib="$(game_library "$appid")" || die "Game is not installed"
  prefix="$lib/steamapps/compatdata/$appid"
  logs="$prefix/pfx/drive_c/users"
  log "AppID: $appid"
  if pgrep -f "/steamapps/common/.*" >/dev/null 2>&1; then log "Steam game processes: detected"; else log "Steam game processes: not detected"; fi
  if pgrep -fi 'Wand.exe\|WeMod.exe\|tophat' >/dev/null 2>&1; then log "Wand/Tophat processes: detected"; else log "Wand/Tophat processes: not detected"; fi
  local tlog
  tlog="$(find "$logs" -type f -path '*/AppData/Local/Wand/logs/tophat/*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
  if [[ -n "$tlog" ]]; then
    log "Tophat log: $tlog"
    grep -E 'Plugin signature verification failed|plugin_init returned 0|registered [0-9]+ commands|trainer_run_mod_json|trainer_push_' "$tlog" | tail -20 || true
  else
    log "Tophat log: not found yet"
  fi
}

case "${1:-}" in
  list-games) list_games ;;
  setup) [[ $# -eq 2 ]] || die "setup APPID"; setup_game "$2" ;;
  verify) [[ $# -eq 2 ]] || die "verify APPID"; verify "$2" ;;
  play) [[ $# -eq 2 ]] || die "play APPID"; play "$2" ;;
  health) [[ $# -eq 2 ]] || die "health APPID"; health "$2" ;;
  *) die "usage: wand-helper.sh list-games|setup APPID|verify APPID|play APPID|health APPID" ;;
esac
