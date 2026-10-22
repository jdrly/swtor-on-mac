#!/bin/bash
# Resources/collect-logs.sh: "Collect Logs…" in the app menu (src/native/App.swift). Zips what
# is needed to diagnose a problem into ~/Desktop/SWTOR-on-Mac-logs-<YYYY-MM-DD-HHMM>.zip (the
# logs folder if the Desktop cannot be written) and prints the zip's path.
#   collect-logs.sh [folder]   write the zip into folder instead
#
# In the zip: SWTOR on Mac's logs (the end of large ones), its env, settings.conf, dxvk.conf,
# install-manifest.json and d9mt-ab.env (a development build's A/B switches, if set), the app's VERSIONS, session-report.txt (the last game session in
# short, scripts/session-report.sh), a fresh system-info.txt (macOS, chip,
# memory, displays, versions, the state of the install, which crash reports are in the zip), and
# crash-reports/: macOS's crash, hang and spin reports of the last 7 days for the game, Wine, the
# official launcher and SWTOR on Mac (see crash_reports), so nobody has to look for them. Never
# the game's command line (the launcher passes the account name and session on it), nor
# anything from the Wine prefixes.
# Every file is redacted on the way in: home folder → ~, user and full name → USER and NAME,
# account names (from the game's <account>_Account.ini names) → ACCOUNT, e-mail addresses → EMAIL, "-set <key> <value>" arguments and password/user name/token
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
DIAG="$H/Library/Logs/DiagnosticReports"
BS_WINE="$H/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"

name="SWTOR-on-Mac-logs-$(date +%Y-%m-%d-%H%M)"
dest="${1:-$H/Desktop}"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT
out="$work/$name"
mkdir -p "$out/logs" "$out/crash-reports"

# Account names to hide: the game names its per-account settings <account>_Account.ini (in
# both Wine prefixes; only the names are read).
accounts="$(find "$BS_WINE/drive_c/users" "$SOM/prefix/drive_c/users" -path '*/AppData/Local/SWTOR/swtor/settings/*' \
  -maxdepth 7 -name '*_Account*.ini' 2>/dev/null | sed 's|.*/||; s/_Account.*\.ini$//' | sort -u)"

redact() {  # stdin → stdout
  SOM_HOME_PATH="$HOME" SOM_ROOT_HOME="$H" SOM_USER="$(id -un)" SOM_NAME="$(id -F 2>/dev/null)" SOM_ACCOUNTS="$accounts" \
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
      n = split(ENVIRON["SOM_ACCOUNTS"], accounts, "\n")
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
      for (i = 1; i <= n; i++) if (length(accounts[i]) >= 2) s = rep(s, accounts[i], "ACCOUNT", 1)
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

# Crash reports: macOS's reports in ~/Library/Logs/DiagnosticReports (crashes .ips/.crash,
# hangs .hang, spins .spin, .diag) of the last 7 days, of what SWTOR on Mac runs: the game and
# Wine (wine, wine64-preloader, wineserver, mac_wine; swtor.exe, the Game Mode bundle's), the
# official launcher (Star Wars - The Old Republic Launcher), this app and its helpers, and
# Metal's shader compiler when it worked for the game or Wine. The newest first, at most
# CRASH_MAX of them, CRASH_MAX_BYTES together and CRASH_FILE_MAX each (larger ones are left
# out, and named in system-info.txt). Prints "add <path>" or "skip <name> (<why>)" per report.
CRASH_MAX=20
CRASH_MAX_BYTES=10000000
CRASH_FILE_MAX=3000000
crash_reports() {
  local size f n=0 total=0
  find "$DIAG" -maxdepth 1 -type f \( -iname '*wine*' -o -iname 'swtor*' -o -name 'Star Wars*' -o -name 'launcher*' \
    -o -name 'SWTOR on Mac*' -o -name 'SWTORonMac*' -o -name 'hold-launcher*' -o -name 'setsid-exec*' \
    -o -name 'MTLCompilerService*' \) \( -name '*.ips' -o -name '*.crash' -o -name '*.hang' -o -name '*.spin' -o -name '*.diag' \) \
    -mtime -7 -exec stat -f '%m %z %N' {} + 2>/dev/null | sort -rn | while read -r _ size f; do
      case "${f##*/}" in
        MTLCompilerService*) LC_ALL=C grep -q -E '"responsibleProc" : "(swtor|wine)' "$f" || continue ;;
      esac
      if [ "$n" -ge "$CRASH_MAX" ]; then echo "skip ${f##*/} (more than $CRASH_MAX reports)"
      elif [ "$size" -gt "$CRASH_FILE_MAX" ]; then echo "skip ${f##*/} ($(((size + 999) / 1000)) KB, too large)"
      elif [ $((total + size)) -gt "$CRASH_MAX_BYTES" ]; then echo "skip ${f##*/} (over $((CRASH_MAX_BYTES / 1000000)) MB together)"
      else
        echo "add $f"
        n=$((n + 1)); total=$((total + size))
      fi
    done
}

for f in "$LOGS"/*; do
  case "$f" in *.zip) continue ;; esac
  [ -f "$f" ] && add_log "$f" 20000000
done
for f in env settings.conf dxvk.conf install-manifest.json d9mt-ab.env; do add "$SOM/$f"; done
add "$RES/VERSIONS"
# the last game session in short (Resources/session-report.sh: frame rate, hitches, compile
# waits, memory, d9mt's render-pass statistics)
if [ -f "$LOGS/wine.log" ] && [ -x "$RES/session-report.sh" ]; then
  "$RES/session-report.sh" "$LOGS/wine.log" 2>&1 | redact >"$out/session-report.txt"
fi
# (redacted like every other file; the list goes into system-info.txt)
crash_reports >"$work/crash-list"
while IFS= read -r line; do
  case "$line" in
    "add "*) f=${line#add }; add "$f" "crash-reports/${f##*/}" &&
      echo "  ${f##*/} ($(stat -f '%Sm' -t '%F %R' "$f"), $((($(stat -f %z "$f") + 999) / 1000)) KB)" ;;
    "skip "*) echo "  left out: ${line#skip }" ;;
  esac
done <"$work/crash-list" >"$work/crash-index"

{
  echo "SWTOR on Mac logs, collected $(date '+%F %T %z')"
  echo "Versions: $(tr -s '\n' ' ' <"$RES/VERSIONS" 2>/dev/null)"
  echo "Installed: $(plutil -extract version raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo no)," \
    "d9mt $(plutil -extract d9mt raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo -)," \
    "engine $(plutil -extract engine_id raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo cx24)" \
    "$(plutil -extract engine raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo -)," \
    "Mac driver $(plutil -extract winemac raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo -)," \
    "ntdll.so $(plutil -extract ntdll raw -o - "$SOM/install-manifest.json" 2>/dev/null || echo stock)" \
    "$(cut -c1-12 <<<"$(shasum -a 256 "$SOM/engine/lib/wine/x86_64-unix/ntdll.so" 2>/dev/null)")"
  echo "Wine engine in place: $(ls "$SOM/engine/bin/wine-preloader" >/dev/null 2>&1 && echo "CrossOver 24.0.7 (0.0.x)" ||
    { [ -x "$SOM/engine/lib/wine/x86_64-unix/wine" ] && echo "CrossOver 26.3, $("$SOM/engine/bin/wine" --version 2>/dev/null || echo "version unknown")"; } || echo none)," \
    "sha256 $(cut -c1-12 "$SOM/engine/.som-source" 2>/dev/null || echo -)$([ -d "$SOM/upgrade-backup" ] && echo ", an upgrade from 0.0.x did not finish")"
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
      echo "  $d/${f##*/}: $(file -b "$f" | cut -c1-40), $(stat -f '%Sm %z bytes' "$f")$(grep -q SWTOR_ON_MAC_WRAPPER "$f" 2>/dev/null && echo ", SWTOR on Mac's wrapper")$(grep -qx 'CONF="@CONF@"' "$f" 2>/dev/null && echo " NOT FILLED IN (@CONF@: it runs Broadsword's Wine)")"
    done
  done
  # (0.1.3 and older set up a launchd job for launcher updates; since 0.1.4 the app checks the
  # hook when it opens, and Install removes the job)
  echo "Launcher-update launchd job of an older version: $([ -f "$H/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist" ] && echo "still there (Reinstall removes it)" || echo "none")"
  echo
  echo "Crash reports of the last 7 days (newest first; in crash-reports/):"
  if [ -s "$work/crash-index" ]; then cat "$work/crash-index"; else echo "  none"; fi
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
