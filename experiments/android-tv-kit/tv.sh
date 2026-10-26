#!/usr/bin/env bash
# tv.sh — connect to, clean up and drive an Android TV over ADB, reversibly.
# Runs on macOS (bash 3.2) and Linux. Every TV change is preceded by a backup
# that holds the undo commands. Never roots, flashes, uninstalls system apps,
# types passwords or signs in.
set -u

STATE="${TV_KIT_HOME:-$HOME/.tv-kit}"
LOG="$STATE/commands.log"
PLAN="$STATE/plan.txt"
YT=com.google.android.youtube.tv
DNS_HOST="${TV_DNS_HOST:-dns.adguard-dns.com}"
ANIM_SCALE="${TV_ANIM_SCALE:-0.5}"
ASSUME_YES=0
mkdir -p "$STATE/backups" "$STATE/shots" "$STATE/downloads"

# Settings this kit may change: "namespace key".
TOUCHED_SETTINGS="global window_animation_scale
global transition_animation_scale
global animator_duration_scale
global private_dns_mode
global private_dns_specifier"

# Disable candidates: package|category|confidence|what it is.
# "sure" entries start selected in the plan; "guess" and "bloat" entries start
# commented out, so nothing unidentified is touched unless you uncomment it.
CANDIDATES="com.google.android.tvrecommendations|recommendation|sure|Android TV recommendation/sponsored rows service
com.google.android.feedback|feedback|sure|Google feedback reporter
com.android.retaildemo|demo|sure|Android retail demo mode
com.sony.dtv.sonyselect|ad|sure|Sony Select promoted-apps tile
com.sony.dtv.demosystemsupport|demo|guess|Sony store-demo support
com.sony.dtv.demomode|demo|guess|Sony store-demo mode
com.sony.dtv.promos|ad|guess|Sony promotions
com.sony.dtv.bravialifehack|ad|guess|probably the My BRAVIA promo/tips tile
com.sony.dtv.discovery|recommendation|guess|Sony Discover recommendation rows
com.google.android.music|bloat|sure|Google Play Music (service shut down in 2020)
com.google.android.play.games|bloat|sure|Google Play Games"

# Never disabled, even if uncommented in the plan: launcher, Play Services,
# Play Store, keyboards/input, remote, voice, live TV, tuners, providers,
# setup, HDMI/CEC, networking, WebView, YouTube and pay-TV provider apps.
PROTECTED='^android$|^com\.android\.(systemui|settings|shell|phone|networkstack|permissioncontroller|packageinstaller|vending|externalstorage|keychain)$|^com\.google\.android\.(gms|gsf)|^com\.google\.android\.tv$|^com\.google\.android\.youtube\.tv$|launcher|inputmethod|keyboard|ime$|\.ime|input|remote|katniss|provider|livetv|\.tvx|tuner|epg|channel|broadcast|setup|systemui|cec|hdmi|bluetooth|wifi|network|webview|sling|unplugged|hulu|directv|xfinity|spectrum|fubo|philo'

# ---------------------------------------------------------------- output ----

ts() { date '+%Y-%m-%d %H:%M:%S'; }
note() { printf '[%s] %s\n' "$(ts)" "$*" | tee -a "$LOG" >&2; }
say() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ask_yes() { # ask_yes "question" — requires the literal word YES
  [ "$ASSUME_YES" = 1 ] && return 0
  local a; read -r -p "$1 Type YES to continue: " a; [ "$a" = YES ]
}

# ------------------------------------------------------------------- adb ----

find_adb() {
  if [ -n "${ADB:-}" ]; then return; fi
  if [ -x "$STATE/platform-tools/adb" ]; then ADB="$STATE/platform-tools/adb"
  elif command -v adb >/dev/null 2>&1; then ADB=$(command -v adb)
  else die "adb not found — run: $0 install-adb"; fi
}

need_device() {
  find_adb
  [ -s "$STATE/device" ] || die "no TV yet — run: $0 connect <TV-IP>"
  SERIAL=$(cat "$STATE/device")
  [ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null)" = device ] || {
    "$ADB" connect "$SERIAL" >/dev/null 2>&1; sleep 1
    [ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null)" = device ] ||
      die "TV $SERIAL not reachable or not authorized — run: $0 connect ${SERIAL%:*}"
  }
}

sh_q() { "$ADB" -s "$SERIAL" shell "$@" </dev/null 2>/dev/null | tr -d '\r'; } # quiet read

# look: read-only query, logged with a timestamp, no logcat.
look() { note "\$ adb shell $*"; sh_q "$@"; }

# run: TV-changing adb command. Prints it with a timestamp and streams the TV's
# logcat (warnings + activity/package events) only while the command runs.
run() {
  note "\$ adb -s $SERIAL $*"
  local fifo="$STATE/.logcat.$$" lpid="" ppid="" rc since
  if [ "${TV_LOGCAT:-1}" = 1 ]; then
    since=$(sh_q date '+%m-%d %H:%M:%S.000')
    rm -f "$fifo"; mkfifo "$fifo"
    (while IFS= read -r l; do printf '      | %s\n' "$l"; done <"$fifo" | tee -a "$LOG" >&2) &
    ppid=$!
    "$ADB" -s "$SERIAL" logcat -v time -T "$since" \
      ActivityManager:I ActivityTaskManager:I PackageManager:I '*:W' </dev/null >"$fifo" 2>/dev/null &
    lpid=$!
  fi
  "$ADB" -s "$SERIAL" "$@" </dev/null; rc=$?
  if [ -n "$lpid" ]; then
    sleep "${TV_LOGCAT_TAIL:-0.8}"
    kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null; wait "$ppid" 2>/dev/null
    rm -f "$fifo"
  fi
  [ "$rc" = 0 ] || note "  -> exit $rc"
  return "$rc"
}

key() { run shell input keyevent "KEYCODE_$1"; sleep "${TV_KEY_DELAY:-0.7}"; }

# ---------------------------------------------------------------- screen ----

shot() { # shot label — saves a PNG of the TV screen and prints its path
  local f="$STATE/shots/$(date +%Y%m%d-%H%M%S)-$1.png"
  "$ADB" -s "$SERIAL" exec-out screencap -p >"$f" 2>/dev/null
  printf '%s\n' "$f"
}

ui_text() { # visible text from the accessibility tree (empty for web-drawn UIs)
  "$ADB" -s "$SERIAL" exec-out uiautomator dump /dev/tty 2>/dev/null | tr '>' '\n' |
    sed -n -e 's/.* text="\([^"]*\)".*/\1/p' -e 's/.* content-desc="\([^"]*\)".*/\1/p' |
    grep -v '^$'
}

screen_text() { # ui_text, else OCR of a screenshot when tesseract is installed
  local t f
  t=$(ui_text)
  if [ -z "$t" ] && command -v tesseract >/dev/null 2>&1; then
    f=$(shot ocr); t=$(tesseract "$f" - 2>/dev/null)
  fi
  printf '%s' "$t"
}

# confirm_screen "description" "regex": checks the screen before an OK press.
# Returns 0 when the screen matches (or you confirm it), 1 otherwise.
confirm_screen() {
  local t f a
  note "check screen: expecting $1"
  t=$(screen_text)
  if [ -n "$t" ]; then
    if printf '%s' "$t" | grep -Eiq "$2"; then note "  screen shows $1"; return 0; fi
    note "  screen text does not match"
  fi
  f=$(shot check)
  say "  Screenshot: $f"
  [ "$ASSUME_YES" = 1 ] && { note "  --yes given, continuing without a text match"; return 0; }
  read -r -p "  Look at the TV. Does it show $1? [y = press OK / anything else = stop] " a
  [ "$a" = y ] || [ "$a" = Y ]
}

focused_pkg() {
  sh_q dumpsys window windows | grep -m1 -E 'mCurrentFocus' |
    sed -n 's/.* \([A-Za-z0-9_.]*\)\/.*/\1/p'
}

wait_focus() { # wait_focus pkg seconds
  local i=0
  while [ "$i" -lt "$2" ]; do
    [ "$(focused_pkg)" = "$1" ] && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------- backup ----

new_backup() { # creates a backup dir with package lists, settings and undo.sh
  local d k ns v line
  d="$STATE/backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$d"
  note "backup -> $d"
  look pm list packages --show-versioncode >"$d/packages-all.txt"
  look pm list packages -d >"$d/packages-disabled.txt"
  look pm list packages -s >"$d/packages-system.txt"
  look pm list packages -3 >"$d/packages-third-party.txt"
  look cmd package query-activities --brief -a android.intent.action.MAIN \
    -c android.intent.category.LEANBACK_LAUNCHER >"$d/launcher-apps.txt"
  for ns in global secure system; do look settings list "$ns" >"$d/settings-$ns.txt"; done
  look getprop >"$d/getprop.txt"
  {
    printf '#!/usr/bin/env bash\n# Undo for backup %s (generated by tv.sh)\n' "${d##*/}"
    printf 'ADB="${ADB:-adb}"; S="${TV_SERIAL:-%s}"\nset -x\n' "$SERIAL"
    printf '%s\n' "$TOUCHED_SETTINGS" | while read -r ns k; do
      v=$(sh_q settings get "$ns" "$k")
      printf '%s %s=%s\n' "$ns" "$k" "$v" >>"$d/touched-settings.txt"
      if [ "$v" = null ] || [ -z "$v" ]; then
        printf '"$ADB" -s "$S" shell settings delete %s %s\n' "$ns" "$k"
      else
        printf '"$ADB" -s "$S" shell settings put %s %s %q\n' "$ns" "$k" "$v"
      fi
    done
  } >"$d/undo.sh"
  chmod +x "$d/undo.sh"
  printf '%s\n' "$d" >"$STATE/last-backup"
  BACKUP="$d"
}

# --------------------------------------------------------------- commands ----

cmd_install_adb() {
  if [ -x "$STATE/platform-tools/adb" ] || command -v adb >/dev/null 2>&1; then
    find_adb; say "adb already present: $ADB"; "$ADB" version | head -1; return
  fi
  local os url zip
  # Google ships Linux platform-tools for x86_64 only; iSH on iPhone is 32-bit Alpine.
  if [ "$(uname -s)" = Linux ] && [ "$(uname -m)" != x86_64 ]; then
    command -v apk >/dev/null 2>&1 || die "no Google adb build for $(uname -m); install your distro's android-tools package"
    say "Installing adb from Alpine's official android-tools package (Google has no build for $(uname -m))."
    apk add android-tools || die "apk add android-tools failed"
    find_adb; "$ADB" version | head -1; return
  fi
  case "$(uname -s)" in
    Darwin) os=darwin ;; Linux) os=linux ;;
    *) die "on Windows, download https://dl.google.com/android/repository/platform-tools-latest-windows.zip and run this script from WSL or Git Bash" ;;
  esac
  url="https://dl.google.com/android/repository/platform-tools-latest-$os.zip"
  say "Downloading Google's official Android SDK Platform-Tools: $url"
  say "(Using them means accepting Google's Platform-Tools license: https://developer.android.com/tools/releases/platform-tools)"
  zip="$STATE/downloads/platform-tools.zip"
  curl -fL --proto '=https' -o "$zip" "$url" || die "download failed"
  rm -rf "$STATE/platform-tools"
  unzip -q "$zip" -d "$STATE" || die "unzip failed"
  ADB="$STATE/platform-tools/adb"
  "$ADB" version | head -1
  say "Installed to $STATE/platform-tools (nothing else on your system was changed)."
}

cmd_connect() {
  [ $# -ge 1 ] || die "usage: $0 connect <TV-IP> [port]"
  find_adb
  local target="$1:${2:-5555}" out i st
  note "\$ adb connect $target"
  out=$("$ADB" connect "$target" 2>&1); say "  $out"
  case "$out" in
    *"connected to"* | *authenticate*) ;;
    *"No route to host"*)
      [ "$(uname -s)" = Darwin ] && say "macOS: System Settings > Privacy & Security > Local Network > turn on your terminal app, then retry."
      die "no route to $target — check the IP and that this computer is on the TV's network" ;;
    *)
      say "Connection refused/failed. Check on the TV: Developer options > USB debugging is ON, and the IP is right."
      say "Android 11+ TVs: Developer options > Wireless debugging > Pair device with pairing code, then run:"
      say "  $0 pair <IP:pairing-port>   and then   $0 connect <IP> <port shown under Wireless debugging>"
      die "could not connect to $target" ;;
  esac
  for i in $(seq 1 60); do
    st=$("$ADB" -s "$target" get-state 2>&1)
    case "$st" in
      device) break ;;
      *unauthorized*) [ "$i" = 1 ] && say "On the TV: tick 'Always allow from this computer', then press OK on 'Allow USB debugging?'." ;;
    esac
    sleep 2
  done
  [ "$st" = device ] || die "not authorized yet — approve the prompt on the TV and run connect again"
  printf '%s\n' "$target" >"$STATE/device"
  SERIAL=$target
  say "Connected: $(sh_q getprop ro.product.manufacturer) $(sh_q getprop ro.product.model), Android $(sh_q getprop ro.build.version.release), CPU ABIs $(sh_q getprop ro.product.cpu.abilist)"
}

cmd_pair() {
  [ $# -ge 1 ] || die "usage: $0 pair <IP:pairing-port>   (you type the 6-digit code shown on the TV)"
  find_adb; note "\$ adb pair $1"; "$ADB" pair "$1"
}

cmd_backup() { need_device; new_backup; say "Saved. Undo commands: $BACKUP/undo.sh"; }

is_protected() { printf '%s\n' "$1" | grep -Eq "$PROTECTED"; }

cmd_plan() {
  need_device
  local installed disabled tiles p cat conf desc listed=""
  installed=$(look pm list packages | sed 's/^package://' | sort)
  disabled=$(look pm list packages -d | sed 's/^package://' | sort)
  tiles=$(look cmd package query-activities --brief -a android.intent.action.MAIN \
    -c android.intent.category.LEANBACK_LAUNCHER | sed -n 's#^ *\([A-Za-z0-9_.]*\)/.*#\1#p' | sort -u)
  {
    echo "# tv.sh cleanup plan for $SERIAL — $(ts)"
    echo "# Uncommented lines get 'pm disable-user' (reversible with 'pm enable')."
    echo "# Nothing is uninstalled. Protected packages are skipped even if uncommented."
    echo
    printf '%s\n' "$CANDIDATES" | while IFS='|' read -r p cat conf desc; do
      printf '%s\n' "$installed" | grep -qx "$p" || continue
      if is_protected "$p"; then echo "# PROTECTED, skipped: $p  ($desc)"
      elif printf '%s\n' "$disabled" | grep -qx "$p"; then echo "# already disabled: $p  ($desc)"
      elif [ "$conf" = sure ] && [ "$cat" != bloat ]; then printf '%-45s # %s: %s\n' "$p" "$cat" "$desc"
      else printf '# %-43s # %s (%s, uncomment to include): %s\n' "$p" "$cat" "$conf" "$desc"; fi
    done
    echo
    echo "# Other apps on your Apps screen. Not selected. Uncomment only apps you recognise:"
    listed=$(printf '%s\n' "$CANDIDATES" | cut -d'|' -f1)
    printf '%s\n' "$tiles" | while read -r p; do
      [ -n "$p" ] || continue
      printf '%s\n' "$listed" | grep -qx "$p" && continue
      if is_protected "$p"; then echo "#   (protected) $p"
      elif printf '%s\n' "$disabled" | grep -qx "$p"; then echo "#   (already disabled) $p"
      else echo "# $p"; fi
    done
  } >"$PLAN"
  say ""; cat "$PLAN" >&2
  say ""
  say "Settings that 'apply' will also change:"
  say "  animations (window/transition/animator scale) -> $ANIM_SCALE"
  say "  Private DNS -> $DNS_HOST  (blocks ad/tracker domains; some ad-supported apps may stop working)"
  say ""
  say "Plan saved to $PLAN. Edit it if you want, then run: $0 apply"
}

cmd_apply() {
  need_device
  [ -s "$PLAN" ] || die "no plan yet — run: $0 plan"
  local installed pkgs="" p k
  installed=$(sh_q pm list packages | sed 's/^package://')
  for p in $(sed -e 's/#.*//' "$PLAN"); do
    printf '%s\n' "$p" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$' || die "bad package name in plan: $p"
    if is_protected "$p"; then say "skipping protected package: $p"; continue; fi
    printf '%s\n' "$installed" | grep -qx "$p" || { say "not installed, skipping: $p"; continue; }
    pkgs="$pkgs $p"
  done
  say "Will disable:${pkgs:- (no apps)}"
  say "Will set animations to $ANIM_SCALE and Private DNS to $DNS_HOST."
  ask_yes "Apply these changes to the TV?" || die "cancelled, nothing changed"
  new_backup
  for p in $pkgs; do
    printf '"$ADB" -s "$S" shell pm enable %s\n' "$p" >>"$BACKUP/undo.sh"
    run shell pm disable-user --user 0 "$p"
  done
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    run shell settings put global "$k" "$ANIM_SCALE"
  done
  run shell settings put global private_dns_specifier "$DNS_HOST"
  run shell settings put global private_dns_mode hostname
  say ""
  say "Done. Disabled now: $(sh_q pm list packages -d | wc -l | tr -d ' ') packages."
  say "Private DNS: $(sh_q settings get global private_dns_mode) $(sh_q settings get global private_dns_specifier)"
  say "Undo everything: $0 undo"
}

cmd_undo() {
  need_device
  local dirs d
  dirs=$(ls -1d "$STATE"/backups/*/ 2>/dev/null | grep -v '\.undone/$' | sort -r)
  [ -n "$dirs" ] || die "nothing to undo"
  say "Undo scripts, newest first (restores the original state):"
  for d in $dirs; do say "---- $d"; grep -v '^#\|^ADB=\|^set ' "$d/undo.sh" | sed 's/^/  /' >&2; done
  ask_yes "Run them all?" || die "cancelled"
  for d in $dirs; do
    note "undo ${d%/}"
    TV_SERIAL=$SERIAL ADB=$ADB bash "${d}undo.sh" 2>&1 | tee -a "$LOG" >&2
    mv "${d%/}" "${d%/}.undone"
  done
  say "Undone. Backups kept as *.undone in $STATE/backups"
}

cmd_install_github() { # install-github owner/repo [asset-name]
  [ $# -ge 1 ] || die "usage: $0 install-github <owner/repo> [exact .apk asset name]"
  need_device
  local repo=$1 want=${2:-} json assets abis abi pick n f name digest url sum before after newpkgs p
  printf '%s\n' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || die "bad repo: $repo"
  note "GET https://api.github.com/repos/$repo/releases/latest"
  json=$(curl -fsSL --proto '=https' -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$repo/releases/latest") || die "no published release for $repo"
  # name|digest|url for each .apk asset hosted on this repo's GitHub releases.
  assets=$(printf '%s' "$json" |
    grep -Eo '"(name|digest|browser_download_url)": *("[^"]*"|null)' |
    awk -F'"' '/"name"/{n=$4; d=""} /"digest"/{d=$4} /"browser_download_url"/{print n "|" d "|" $4}' |
    grep -E "\|https://github\.com/$repo/releases/download/[^|]*\.apk$")
  [ -n "$assets" ] || die "the latest $repo release has no .apk asset"
  say "APK assets in the latest release:"; printf '%s\n' "$assets" | cut -d'|' -f1 | sed 's/^/  /' >&2
  if [ -n "$want" ]; then pick=$(printf '%s\n' "$assets" | awk -F'|' -v w="$want" '$1==w')
  else
    abis=$(sh_q getprop ro.product.cpu.abilist | tr ',' ' ')
    pick=""
    for abi in $abis universal; do
      pick=$(printf '%s\n' "$assets" | grep -i -- "^[^|]*$abi")
      [ -n "$pick" ] && break
    done
    [ -n "$pick" ] || { [ "$(printf '%s\n' "$assets" | wc -l)" -eq 1 ] && pick=$assets; }
  fi
  n=$(printf '%s' "$pick" | grep -c .)
  [ "$n" = 1 ] || die "pick one asset (TV ABIs: $(sh_q getprop ro.product.cpu.abilist)): $0 install-github $repo '<asset name>'"
  IFS='|' read -r name digest url <<EOF
$pick
EOF
  f="$STATE/downloads/$name"
  note "download $url"
  curl -fL --proto '=https' -o "$f" "$url" || die "download failed"
  if [ "${digest#sha256:}" != "$digest" ] && [ "${url##*/}" = "$name" ]; then
    sum=$( (shasum -a 256 "$f" 2>/dev/null || sha256sum "$f") | cut -d' ' -f1)
    [ "$sum" = "${digest#sha256:}" ] || die "SHA-256 mismatch for $name — not installing"
    say "SHA-256 verified against GitHub: $sum"
  else
    say "GitHub published no digest for this asset; SHA-256: $( (shasum -a 256 "$f" 2>/dev/null || sha256sum "$f") | cut -d' ' -f1)"
  fi
  new_backup
  before=$(sh_q pm list packages -3 | sort)
  run install -r "$f" || die "install failed"
  after=$(sh_q pm list packages -3 | sort)
  newpkgs=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^package://')
  for p in $newpkgs; do
    printf '"$ADB" -s "$S" uninstall %s\n' "$p" >>"$BACKUP/undo.sh"
    say "Installed $p — opening it on the TV."
    run shell monkey -p "$p" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null
  done
  [ -n "$newpkgs" ] || say "Updated an app that was already installed (undo will not remove it)."
}

urlencode() {
  local LC_ALL=C s=$1 i c out=""
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case "$c" in [A-Za-z0-9.~_-]) out="$out$c" ;; *) out="$out$(printf '%%%02X' "'$c")" ;; esac
  done
  printf '%s' "$out"
}

yt_state() { # prints the YouTube media-session state: 3 playing, 2 paused, 6 buffering
  sh_q dumpsys media_session | grep -A 25 "package=$YT" |
    grep -m1 -o 'state=PlaybackState {state=[0-9]*' | grep -o '[0-9]*$'
}

handle_whos_watching() { # picks the highlighted profile; never signs in
  local t i
  for i in 1 2 3; do
    t=$(screen_text)
    if printf '%s' "$t" | grep -Eiq "who.?s watching|who is watching|choose an account"; then
      note "'Who's watching?' screen — selecting the highlighted profile"
      say "  Screenshot: $(shot whos-watching)"
      key DPAD_CENTER; sleep 3
    elif printf '%s' "$t" | grep -Eiq "^sign in|sign in to|enter (your )?password"; then
      die "YouTube is asking to sign in. Please do that yourself with the remote, then run this again."
    else
      return 0
    fi
  done
}

cmd_youtube() { # youtube "search words" | youtube --id <VIDEO_ID or URL>
  need_device
  local id="" q url s="" i pre
  if [ "${1:-}" = --id ]; then
    shift; id=$(printf '%s' "${1:-}" | sed -E 's#.*(v=|youtu\.be/|/shorts/|/live/)##; s#[?&].*##')
    printf '%s' "$id" | grep -Eq '^[A-Za-z0-9_-]{11}$' || die "not a YouTube video id or URL: ${1:-}"
  fi
  q="$*"; [ -n "$q" ] || die "usage: $0 youtube \"what to play\"   or   $0 youtube --id <id-or-url>"
  sh_q pm path "$YT" | grep -q . || die "YouTube for Android TV ($YT) is not installed"
  key WAKEUP
  key HOME
  run shell monkey -p "$YT" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null
  wait_focus "$YT" 20 || say "  (YouTube not in focus yet, continuing)"
  sleep 3
  handle_whos_watching
  pre=$(yt_state)
  if [ -n "$id" ]; then
    url="https://www.youtube.com/watch?v=$id"
    run shell am start -a android.intent.action.VIEW -d "'$url'" "$YT" >/dev/null
  else
    url="https://www.youtube.com/results?search_query=$(urlencode "$q")"
    run shell am start -a android.intent.action.VIEW -d "'$url'" "$YT" >/dev/null
    sleep 5
    handle_whos_watching
    confirm_screen "search results for \"$q\" with the first video highlighted" \
      "$(printf '%s' "$q" | cut -d' ' -f1 | tr -cd '[:alnum:]')" ||
      die "stopped before pressing OK. Use the remote, or run: $0 key DPAD_CENTER"
    key DPAD_CENTER
  fi
  [ "$pre" = 3 ] && say "  (YouTube already reported playing before this step)"
  for i in $(seq 1 30); do
    s=$(yt_state)
    [ "$s" = 3 ] && { note "YouTube reports: playing"; say "Playing. (Screenshots of video come out black because of DRM — that's normal.)"; return 0; }
    [ "$i" = 10 ] && handle_whos_watching
    sleep 1
  done
  say "Playback not confirmed (state: ${s:-unknown}). Screenshot: $(shot youtube)"
  return 1
}

cmd_status() {
  need_device
  say "TV: $(sh_q getprop ro.product.manufacturer) $(sh_q getprop ro.product.model) ($SERIAL), Android $(sh_q getprop ro.build.version.release)"
  say "Disabled packages:"; sh_q pm list packages -d | sed 's/^package:/  /' >&2
  printf '%s\n' "$TOUCHED_SETTINGS" | while read -r ns k; do say "  $ns $k = $(sh_q settings get "$ns" "$k")"; done
  say "Memory: $(sh_q cat /proc/meminfo | grep -E '^Mem(Total|Available)' | tr -s ' ' | tr '\n' ' ')"
  say "Foreground: $(focused_pkg)"
}

cmd_help() {
  cat <<EOF
tv.sh — Android TV over ADB (state in $STATE)

  install-adb                 download Google's official platform-tools if adb is missing
  connect <IP> [port]         connect + wait for you to approve on the TV (port 5555)
  pair <IP:port>              Android 11+ Wireless debugging pairing (you type the code)
  backup                      save package lists, settings and undo commands
  plan                        propose the cleanup (writes $PLAN; changes nothing)
  apply                       backup, then disable the planned apps + animations + Private DNS
  undo                        run every undo script, newest first
  install-github <owner/repo> [asset]   install the latest .apk from official GitHub releases
  install-tvbro               same, for the TV Bro browser (truefedex/tv-bro)
  youtube "words"             open YouTube, search, check the screen, press OK, confirm playback
  youtube --id <id|url>       open YouTube and play that exact video
  key <NAME>                  press a remote key (HOME, BACK, DPAD_UP, DPAD_CENTER, ...)
  shot                        save a screenshot of the TV
  status                      model, disabled apps, touched settings, memory
  monitor                     follow the command log from another terminal window

Options: --yes skips YES prompts and screen confirmations.
EOF
}

# ------------------------------------------------------------------- main ----

args=()
for a in "$@"; do
  if [ "$a" = --yes ]; then ASSUME_YES=1; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}
cmd=${1:-help}; [ $# -gt 0 ] && shift
case "$cmd" in
  install-adb) cmd_install_adb ;;
  connect) cmd_connect "$@" ;;
  pair) cmd_pair "$@" ;;
  backup) cmd_backup ;;
  plan) cmd_plan ;;
  apply) cmd_apply ;;
  undo) cmd_undo ;;
  install-github) cmd_install_github "$@" ;;
  install-tvbro) cmd_install_github truefedex/tv-bro "$@" ;;
  youtube) cmd_youtube "$@" ;;
  key) need_device; for k in "$@"; do key "$k"; done ;;
  shot) need_device; shot manual ;;
  status) cmd_status ;;
  monitor) touch "$LOG"; tail -n 20 -f "$LOG" ;;
  help | -h | --help) cmd_help ;;
  *) cmd_help; exit 2 ;;
esac
