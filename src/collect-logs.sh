#!/bin/bash
# Resources/collect-logs.sh: "Collect Logs…" in the app menu (src/native/App.swift). Zips what
# is needed to diagnose a problem into ~/Desktop/SWTOR-on-Mac-logs-<YYYY-MM-DD-HHMM>.zip (the
# logs folder if the Desktop cannot be written) and prints the zip's path.
#   collect-logs.sh [folder]   write the zip into folder instead
#
# In the zip: SWTOR on Mac's logs (the end of large ones), its env, settings.conf, dxvk.conf
# and install-manifest.json, the app's VERSIONS, a fresh system-info.txt (macOS, chip,
# memory, displays, versions, the state of the install), and crash reports of the last 7 days
# for the game, Wine and the app. Never the game's command line (the launcher passes the
# account name and session on it), nor anything from the Wine prefixes.
# Every file is redacted on the way in: home folder → ~, user and full name → USER and NAME,
# e-mail addresses → EMAIL, "-set <key> <value>" arguments and password/user name/token
# settings → REDACTED, serial numbers and device identifiers left out.
#
# SWTOR_ON_MAC_ROOT=/abs/dir: a sandbox (as for som.sh); the zip then goes to its Desktop.
set -u
RES="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SWTOR_ON_MAC_ROOT:-}"
H="${ROOT:+$ROOT/home}"
H="${H:-$HOME}"
SOM="$H/Library/Application Support/SWTOR on Mac"
LOGS="$H/Library/Logs/SWTOR on Mac"
BS_WINE="$H/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"

name="SWTOR-on-Mac-logs-$(date +%Y-%m-%d-%H%M)"
dest="${1:-$H/Desktop}"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT
out="$work/$name"
mkdir -p "$out/logs" "$out/crash-reports"

redact() {  # stdin → stdout
  SOM_HOME_PATH="$HOME" SOM_ROOT_HOME="$H" SOM_USER="$(id -un)" SOM_NAME="$(id -F 2>/dev/null)" \
  LC_ALL=C awk '
    # Replace w with r in s, ignoring case; only where w is a whole word if whole is set.
    function rep(s, w, r, whole,    ls, lw, res, p, n, before, after, last) {
      if (w == "") return s
      ls = tolower(s); lw = tolower(w); n = length(lw); res = ""; last = ""
      while ((p = index(ls, lw)) > 0) {
        before = p > 1 ? substr(ls, p - 1, 1) : last
        after = substr(ls, p + n, 1)
        if (!whole || (before !~ /[a-z0-9_]/ && after !~ /[a-z0-9_]/))
          res = res substr(s, 1, p - 1) r
        else
          res = res substr(s, 1, p - 1 + n)
        last = substr(ls, p + n - 1, 1)
        s = substr(s, p + n); ls = substr(ls, p + n)
      }
      return res s
    }
    # key=value, key: value, "key":"value" with a secret or identifying key: value → REDACTED.
    function secrets(s,    ls, res, p) {
      ls = tolower(s); res = ""
      while (match(ls, secret_key)) {
        p = RSTART + RLENGTH - 1
        res = res substr(s, 1, p); s = substr(s, p + 1); ls = substr(ls, p + 1)
        if (match(ls, secret_value)) {
          res = res "REDACTED"; s = substr(s, RLENGTH + 1); ls = substr(ls, RLENGTH + 1)
        }
      }
      return res s
    }
    # The launcher passes the account to the game as "-set username <name>" (and more -set
    # pairs): every -set value goes.
    function setargs(s,    res) {
      res = ""
      while (match(s, /-set[ \t]+[A-Za-z0-9_.]+[ \t]+/)) {
        res = res substr(s, 1, RSTART + RLENGTH - 1)
        s = substr(s, RSTART + RLENGTH)
        if (match(s, /^("[^"]*"|[^ \t"]+)/)) { res = res "REDACTED"; s = substr(s, RLENGTH + 1) }
      }
      return res s
    }
    BEGIN {
      secret_key = "(password|passwd|pwd|username|user_name|accountname|account|email|token|ticket|session|" \
        "crashreporterkey|deviceidentifierforvendor|bootsessionuuid|sleepwakeuuid)[\"\047]?[ \t]*[:=][ \t]*[\"\047]?"
      secret_value = "^[^\"\047&,; \t}]+"
      home = ENVIRON["SOM_HOME_PATH"]; rhome = ENVIRON["SOM_ROOT_HOME"]
      user = ENVIRON["SOM_USER"]; fullname = ENVIRON["SOM_NAME"]
      # A user name that is a common word is only replaced in paths, not everywhere.
      split("admin user users mac test game wine guest root home apple swtor shared crossover", w, " ")
      for (i in w) common[w[i]] = 1
    }
    {
      line = tolower($0)
      if (line ~ /serial number|hardware uuid|provisioning udid/) next
      s = $0
      if (rhome != home) s = rep(s, rhome, "~", 0)
      s = rep(s, home, "~", 0)
      s = rep(s, "/Users/" user, "/Users/USER", 1)
      s = rep(s, "\\users\\" user, "\\users\\USER", 1)
      if (length(user) >= 2 && !(tolower(user) in common)) s = rep(s, user, "USER", 1)
      if (length(fullname) >= 3) s = rep(s, fullname, "NAME", 1)
      s = setargs(s)
      s = secrets(s)
      gsub(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z][A-Za-z]+/, "EMAIL", s)
      print s
    }'
}

add() {  # file [name in the zip]
  [ -f "$1" ] && redact <"$1" >"$out/${2:-${1##*/}}"
}

add_log() {  # file max-bytes: the end of a log
  local f=$1 size
  [ -f "$f" ] || return 0
  size=$(stat -f %z "$f")
  if [ "$size" -gt "$2" ]; then
    { echo "[SWTOR on Mac: only the last $(($2 / 1000000)) MB of ${f##*/}]"
      tail -c "$2" "$f" | awk 'NR > 1'; } | redact >"$out/logs/${f##*/}"
  else
    redact <"$f" >"$out/logs/${f##*/}"
  fi
}

# Crash reports of the last 7 days for the game, Wine (and its preloader, the Game Mode
# bundle's swtor.exe), Metal's shader compiler working for them, and this app.
crash_reports() {
  local f
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -type f \( -iname 'swtor*' -o -iname '*wine*' \
    -o -name 'SWTORonMac*' -o -name 'MTLCompilerService*' -o -name 'hold-launcher*' -o -name 'setsid-exec*' \) \
    -mtime -7 -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | while IFS= read -r f; do
      case "${f##*/}" in
        MTLCompilerService*) LC_ALL=C grep -q -E '"responsibleProc" : "(swtor|wine)' "$f" || continue ;;
      esac
      echo "$f"
    done | head -10
}

for f in "$LOGS"/*; do
  case "$f" in *.zip) continue ;; esac
  [ -f "$f" ] && add_log "$f" 20000000
done
for f in env settings.conf dxvk.conf install-manifest.json; do add "$SOM/$f"; done
add "$RES/VERSIONS"
crash_reports | while IFS= read -r f; do add "$f" "crash-reports/${f##*/}"; done

{
  echo "SWTOR on Mac logs, collected $(date '+%F %T %z')"
  echo "Versions: $(tr -s '\n' ' ' <"$RES/VERSIONS" 2>/dev/null)"
  echo "Installed: $(plutil -extract version raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo no)," \
    "d9mt $(plutil -extract d9mt raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo -)," \
    "engine $(plutil -extract engine raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo -)"
  echo "Mac: $(sysctl -n hw.model), $(sysctl -n machdep.cpu.brand_string)" \
    "($(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)+$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null) cores)," \
    "$(($(sysctl -n hw.memsize) / 1073741824)) GB, macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "Rosetta: $([ -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ] && echo installed || echo "not installed")"
  echo "Power: $(pmset -g ps 2>/dev/null | sed -n "1s/.*'\(.*\)'.*/\1/p")$(pmset -g 2>/dev/null | awk '$1 == "lowpowermode" && $2 == 1 { print ", Low Power Mode" }')"
  echo "Free space: $(df -h "$H" 2>/dev/null | awk 'NR == 2 { print $4 " of " $2 }')"
  system_profiler SPDisplaysDataType 2>/dev/null | awk '
    function out() {
      if (name != "") print "Display: " name (type != "" ? " (" type ")" : "") ", " res (ui != "" ? ", looks like " ui : "") (main ? ", main" : "")
      name = type = res = ui = ""; main = 0
    }
    /^ *$/ { next }
    { i = match($0, /[^ ]/); line = substr($0, i) }
    line == "Displays:" { out(); d = i; next }
    d && i <= d { out(); d = 0 }
    d && line ~ /:$/ { out(); name = substr(line, 1, length(line) - 1); next }
    d && sub(/^Display Type: /, "", line) { type = line }
    d && sub(/^Resolution: /, "", line) { res = line }
    d && sub(/^UI Looks like: /, "", line) { ui = line }
    d && line == "Main Display: Yes" { main = 1 }
    END { out() }'
  echo
  echo "Broadsword's Wine (bin, bin-real):"
  for d in bin bin-real; do
    for f in "$BS_WINE/$d"/wine64-preloader "$BS_WINE/$d"/wine-preloader "$BS_WINE/$d"/hold-launcher "$BS_WINE/$d"/setsid-exec; do
      [ -e "$f" ] || continue
      echo "  $d/${f##*/}: $(file -b "$f" | cut -c1-40), $(stat -f '%Sm %z bytes' "$f")$(grep -q SWTOR_ON_MAC_WRAPPER "$f" 2>/dev/null && echo ", SWTOR on Mac's wrapper")"
    done
  done
  echo "Launcher-update guard: $([ -f "$H/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist" ] && echo "installed" || echo "not installed")"
  echo
  # names only, never the command line (it has the account)
  echo "Running SWTOR, Wine and SWTOR on Mac processes (name only):"
  ps -axww -o pid=,etime=,rss=,comm= 2>/dev/null |
    awk '/[Ww]ine|swtor|Star Wars|SWTOR|winetemp|hold-launcher/ && !/awk|collect-logs/'
  echo
  system_profiler SPHardwareDataType 2>/dev/null | grep -v -i -E 'serial|uuid|udid|activation lock'
} 2>&1 | redact >"$out/system-info.txt"

mkdir -p "$dest" 2>/dev/null
zip="$dest/$name.zip"
( cd "$work" && zip -q -r -X "$name.zip" "$name" ) || { echo "Could not create the zip" >&2; exit 1; }
if ! mv -f "$work/$name.zip" "$zip" 2>/dev/null; then
  # No access to the Desktop (privacy settings): leave it with the logs instead.
  mkdir -p "$LOGS"
  zip="$LOGS/$name.zip"
  mv -f "$work/$name.zip" "$zip" || exit 1
fi
echo "$zip"
