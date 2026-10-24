#!/bin/bash
# Resources/collect-logs.sh: "Collect Logs…" in the app menu (src/native/App.swift). Zips what
# is needed to diagnose a problem into ~/Desktop/SWTOR-on-Mac-logs-<YYYY-MM-DD-HHMM>.zip (the
# logs folder if the Desktop cannot be written) and prints the zip's path.
#   collect-logs.sh [folder]   write the zip into folder instead
#
# In the zip: SWTOR on Mac's logs (the end of large ones; wine.log.1-4 are the game starts
# before the last), its env, settings.conf, dxvk.conf,
# install-manifest.json and d9mt-ab.env (a development build's A/B switches, if set), the app's VERSIONS, session-report.txt (the last game session in
# short, scripts/session-report.sh), a fresh system-info.txt (macOS, chip,
# memory, displays, versions, the state of the install, which crash reports are in the zip, the
# GPU error count), gpu-errors.txt (the GPU errors of the game and Wine in macOS's unified log of
# the last 2 hours, see gpu_errors) and
# crash-reports/: macOS's crash, hang and spin reports of the last 7 days for the game, Wine, the
# official launcher and SWTOR on Mac (see crash_reports), so nobody has to look for them. Never
# the game's command line (the launcher passes the account name and session on it), nor
# anything from the Wine prefixes. launcher-logs/: the official launcher's own logs (the end of
# large ones), with the game's command line, its account names, session tokens and ids, the
# Mac's name, IP and MAC addresses and home folders taken out as well (see launcher_rules).
# Every file is redacted on the way in: home folder → ~, user and full name → USER and NAME,
# account names (from the game's <account>_Account.ini names) → ACCOUNT, e-mail addresses → EMAIL, "-set <key> <value>" arguments and password/user name/token
# settings → REDACTED, serial numbers and device identifiers left out, the Mac's names and the
# launcher's account names → NAME. Then a leak check: a file that still has one of those names,
# a home folder path or an account name or token on a command line is left out of the zip
# (named in left-out.txt).
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
# the per-user cache dir (as som.sh's USER_CACHE), where macOS's Metal keeps its caches for the
# engine's processes, under their bundle id
if [ -n "$ROOT" ]; then USER_CACHE="$ROOT/usercache/"; else USER_CACHE="$(getconf DARWIN_USER_CACHE_DIR)"; fi
METAL_CACHE="${USER_CACHE}com.codeweavers.CrossOver.wineloader"
LAUNCHER_LOGS="$H/Library/Logs/Star Wars - The Old Republic Launcher"
BS_APP="${ROOT:+$ROOT/Applications}"
BS_APP="${BS_APP:-/Applications}/Star Wars - The Old Republic.app"

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
# ...and the ones the launcher logged: "-set username \<name>" on the game's command line (also
# JSON-escaped, "\\<name>")
launcher_accounts="$(LC_ALL=C grep -h -o -E -- "-set username [^ '\"]+" "$LAUNCHER_LOGS"/*.log 2>/dev/null |
  sed -E 's/^-set username \\*//; s/\\+$//' | sort -u)"
accounts="$(printf '%s\n%s\n' "$accounts" "$launcher_accounts" | sed '/^$/d' | sort -u)"
# Names to replace wherever they are, in any case (NAME), and to look for in the leak check:
# the Mac's names, the launcher's account names and the "Machine Name: ..." it logged. Only
# those of 4 characters or more (shorter ones only as whole words, as accounts above), and not
# a model's own name ("MacBook Pro", "iMac.local": the model has to stay readable) or a common
# word (as for the user name in redact); the longest first.
literals="$work/literals"
{ scutil --get ComputerName; scutil --get LocalHostName; scutil --get HostName; hostname -s; hostname
  printf '%s\n' "$launcher_accounts"
  LC_ALL=C grep -h -o -E 'Machine Name: .+$' "$LAUNCHER_LOGS"/*.log | sed 's/^Machine Name: //'
} 2>/dev/null | tr -d '\r' | LC_ALL=C awk '
  { l = tolower($0); sub(/\.local$/, "", l); gsub(/-/, " ", l) }
  length($0) >= 4 && l !~ /^(mac|imac|macbook|macbook air|macbook pro|mac mini|mac studio|mac pro|localhost)( [0-9]+)?$/ &&
  l !~ /^(admin|user|users|test|game|wine|guest|root|home|apple|swtor|shared|crossover)$/ {
    print length($0) "\t" $0 }' | sort -rn | cut -f2- | uniq >"$literals"

redact() {  # [launcher] stdin → stdout (launcher: also launcher_rules)
  SOM_HOME_PATH="$HOME" SOM_ROOT_HOME="$H" SOM_USER="$(id -un)" SOM_NAME="$(id -F 2>/dev/null)" SOM_ACCOUNTS="$accounts" \
  LC_ALL=C awk -v litfile="$literals" -v launcher="${1:+1}" '
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
    # IPv4 addresses, except 127.0.0.1 and version numbers ("Version: 7.2.207.0", "v1.2.3.4")
    function ipv4(s,    out, pre, m) {
      out = ""
      while (match(s, /[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?/)) {
        pre = substr(s, 1, RSTART - 1); m = substr(s, RSTART, RLENGTH)
        if (m == "127.0.0.1" || tolower(substr(pre, length(pre) - 9)) ~ /(version|ver|v)[:= ]*$/ || pre ~ /[0-9.]$/) out = out pre m
        else out = out pre "IP"
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    # The official launcher logs the game'"'"'s command line (account name, session token), its
    # session and machine ids, the Mac'"'"'s name, its addresses and home folders, also of other
    # users and in Wine'"'"'s user folders.
    function launcher_rules(s) {
      # (the game'"'"'s command line from its account name on: never in the zip, redacted or not;
      # the wrapper logs the game'"'"'s language itself)
      sub(/-set[ \t]+username.*/, "-set username ... [SWTOR on Mac: the rest of the game'"'"'s command line left out]", s)
      gsub("Session Id: .*", "Session Id: REDACTED", s)
      gsub("Machine Id: .*", "Machine Id: REDACTED", s)
      gsub("Machine Name: .*", "Machine Name: NAME", s)
      gsub("User Home: .*", "User Home: ~", s)
      gsub("Intranet IP: .*", "Intranet IP: IP", s)
      gsub("/Users/[^/ \"\047:]+", "/Users/USER", s)
      gsub("drive_c/users/[^/ \"\047:]+", "drive_c/users/USER", s)
      gsub("[Cc]:\\\\+[Uu]sers\\\\+[^\\\\ \"\047:]+", "C:\\users\\USER", s)
      gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "MAC-ADDRESS", s)
      s = ipv4(s)
      gsub(/[0-9A-Fa-f]+:[0-9A-Fa-f]*:[0-9A-Fa-f]*:[0-9A-Fa-f]*:[0-9A-Fa-f:]*[0-9A-Fa-f]/, "IP6", s)
      return s
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
      nl = 0; while ((getline l < litfile) > 0) lit[++nl] = l
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
      if (launcher) s = launcher_rules(s)
      for (i = 1; i <= nl; i++) s = rep(s, lit[i], "NAME", 0)
      # the launcher'"'"'s session token (its registry calls) and session, JWT-style tokens
      gsub("--registry-token -t [^ \"\047]+", "--registry-token -t TOKEN", s)
      gsub("--session=\"[^\"]*\"", "--session=\"REDACTED\"", s)
      gsub("--session=[^ \"\047]+", "--session=REDACTED", s)
      gsub(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)?/, "TOKEN", s)
      s = setargs(s)
      s = secrets(s)
      gsub(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z][A-Za-z]+/, "EMAIL", s)
      print s
    }'
}

add() {  # file [name in the zip]
  [ -f "$1" ] && redact <"$1" >"$out/${2:-${1##*/}}"
}

add_log() {  # file max-bytes [folder in the zip [launcher]]: the end of a log
  local f=$1 size dir="$out/${3:-logs}"
  [ -f "$f" ] || return 0
  mkdir -p "$dir"
  size=$(stat -f %z "$f")
  if [ "$size" -gt "$2" ]; then
    { echo "[SWTOR on Mac: only the last $(($2 / 1000000)) MB of ${f##*/}]"
      tail -c "$2" "$f" | awk 'NR > 1'; } | redact ${4:+"$4"} >"$dir/${f##*/}"
  else
    redact ${4:+"$4"} <"$f" >"$dir/${f##*/}"
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

# GPU errors: macOS's unified log of the last GPU_HOURS hours (the game's wine.log is written
# anew at every start, the unified log keeps them for days). A GPU page fault in the game's
# command buffers shows there as two "IOGPUMetalError" lines of the game's process (wine, or
# swtor.exe) and nothing in wine.log; the game then draws wrong or pink textures, or freezes.
# Counted per process of the game and Wine (other apps' only as a number, never their names),
# then the last GPU_LINES lines of them and of the GPU driver in the kernel (AGX), and the last
# METAL_LINES of Metal's other errors in the game and Wine ("MDB_MAP_FULL" only counted: it is
# Metal's archive usage index, com.apple.metal/archiveUsage.db, that is full; the compiled
# shaders next to it are still cached). The GPU driver's own text can name any app or path, so of its
# lines only the time, the sender, the kind of event and whether it names the game or Wine. The
# query takes 10-30 s; it is ended after GPU_TIMEOUT s (KILL GPU_GRACE s after TERM). In a
# sandbox the unified log is $ROOT/bin/log if there is one (a test's), else it is not read, and
# SWTOR_ON_MAC_GPU_TIMEOUT can shorten the limit.
GPU_HOURS=2
GPU_LINES=50
METAL_LINES=20
GPU_TIMEOUT=90
GPU_GRACE=5
UNIFIED_LOG=/usr/bin/log
if [ -n "$ROOT" ]; then
  UNIFIED_LOG="$ROOT/bin/log"
  GPU_TIMEOUT="${SWTOR_ON_MAC_GPU_TIMEOUT:-$GPU_TIMEOUT}"
fi
gpu_errors() {  # → stdout; the count's line also into $work/gpu-summary
  local pid killer st timedout=0
  echo "GPU errors in macOS's unified log, the last $GPU_HOURS hours (until $(date '+%F %T %z'))"
  if [ ! -x "$UNIFIED_LOG" ]; then
    echo "not read (no $UNIFIED_LOG)" | tee "$work/gpu-summary"
    return 0
  fi
  "$UNIFIED_LOG" show --last "${GPU_HOURS}h" --style compact --predicate 'process != "log" AND (eventMessage CONTAINS "IOGPUMetalError"
    OR ((process BEGINSWITH "wine" OR process == "swtor.exe") AND (messageType == error OR messageType == fault)
      AND (sender CONTAINS[c] "metal" OR sender CONTAINS[c] "IOGPU" OR sender CONTAINS[c] "AGX"))
    OR (process == "kernel" AND sender BEGINSWITH "AGX"))' </dev/null >"$work/gpu-log" 2>/dev/null &
  pid=$!
  # (the time limit: TERM, and KILL for a query that ignores it. The mark says it ran out of
  # time, also for a query that ends with status 0 on TERM; it goes again if the TERM finds no
  # query to end.)
  ( sleep "$GPU_TIMEOUT" && : >"$work/gpu-timeout" &&
    { kill "$pid" || { rm -f "$work/gpu-timeout"; exit 0; }; } &&
    sleep "$GPU_GRACE" && kill -KILL "$pid" ) </dev/null >/dev/null 2>&1 &
  killer=$!
  wait "$pid" 2>/dev/null; st=$?  # (2>: not bash's "Terminated" line for a query that ran out of time)
  # The query has ended: end the watchdog wherever it is, so it never signals that pid again.
  # Stopped first, it can't start a sleep in between; then its sleep, if any, and itself.
  kill -STOP "$killer" 2>/dev/null
  pkill -KILL -P "$killer" 2>/dev/null
  kill -KILL "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null
  [ ! -e "$work/gpu-timeout" ] || timedout=1
  # (a line: date time type process[pid:tid] (sender) message; only other apps' names have spaces)
  LC_ALL=C awk -v lines="$GPU_LINES" -v mlines="$METAL_LINES" -v st="$st" -v timedout="$timedout" \
      -v summary="$work/gpu-summary" -v mdbfull="$work/gpu-mdbfull" '
    !/^[0-9][0-9][0-9][0-9]-/ { next }
    { name = $4; sub(/\[.*/, "", name); ours = name ~ /^wine/ || name == "swtor.exe" }
    name == "kernel" {
      sender = $5; if (sender !~ /^\([A-Za-z0-9_.-]+\)$/) sender = "(AGX)"
      body = $0; for (i = 1; i <= 5; i++) sub(/^[^ ]+ +/, "", body); body = tolower(body)
      kind = body ~ /restart|reset|recover/ ? "GPU restart" : body ~ /fault/ ? "GPU fault" : \
        body ~ /timeout|timed out|hang|stall/ ? "GPU timeout" : body ~ /error|fail/ ? "GPU error" : "other"
      gpu[++g] = $1 " " $2 " " $3 " kernel " sender ": " kind (body ~ /wine|swtor/ ? ", names the game or Wine" : "")
      next
    }
    /IOGPUMetalError/ {
      if (!ours) { other++; next }
      pid = $4; sub(/^[^[]*\[/, "", pid); sub(/:.*/, "", pid)
      key = name " (pid " pid ")"
      if (!(key in n)) { order[++keys] = key; first[key] = $1 " " $2 }
      n[key]++; last[key] = $1 " " $2; total++
    }
    /MDB_MAP_FULL/ { if (ours) cachefull++; next }
    !ours { next }
    /IOGPUMetalError/ || name == "kernel" { gpu[++g] = $0; next }
    { metal[++m] = $0 }
    END {
      if (timedout) print "(the query ran out of time: what came until then)"
      else if (st) print "(the query failed, status " st ")"
      s = "IOGPUMetalError (GPU command buffer errors, 2 lines each): " total + 0 " in the game and Wine"
      if (other) s = s ", " other " in other apps"
      print s; print s >summary
      for (i = 1; i <= keys; i++) print "  " order[i] ": " n[order[i]] ", " first[order[i]] " to " last[order[i]]
      print cachefull + 0 >mdbfull
      if (cachefull) print "Metal'"'"'s archive usage index full (MDB_MAP_FULL) in the game and Wine: " cachefull " lines; compiled shaders are still cached"
      print ""
      print "The last " lines " lines of them and of the GPU driver (AGX):"
      if (!g) print "  none"
      for (i = (g > lines ? g - lines + 1 : 1); i <= g; i++) print gpu[i]
      print ""
      print "The last " mlines " of Metal'"'"'s other errors in the game and Wine (" m + 0 " in all):"
      if (!m) print "  none"
      for (i = (m > mlines ? m - mlines + 1 : 1); i <= m; i++) print metal[i]
    }' "$work/gpu-log"
}

for f in "$LOGS"/*; do
  case "$f" in
    *.zip) continue ;;
    # (the game starts before the last: what matters is how they ended)
    */wine.log.[0-9]) add_log "$f" 5000000 ;;
    *) [ -f "$f" ] && add_log "$f" 20000000 ;;
  esac
done
# the official launcher's own logs, with launcher_rules
for f in "$LAUNCHER_LOGS"/*.log; do
  [ -f "$f" ] && add_log "$f" 5000000 launcher-logs launcher
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
gpu_errors 2>&1 | redact >"$out/gpu-errors.txt"

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
  echo
  # the official launcher app: a self-update that did not finish leaves *.solidpartial files
  # in it, and a launcher that won't open
  echo "Official launcher app:"
  if [ -d "$BS_APP" ]; then
    plist="$BS_APP/Contents/Info.plist"
    echo "  version $(plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null || echo ?)" \
      "($(plutil -extract CFBundleVersion raw -o - "$plist" 2>/dev/null || echo ?))," \
      "bundle id $(plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null || echo ?)"
    echo "  owner $(stat -f '%Su:%Sg %Sp' "$BS_APP"), changed $(stat -f '%Sm' -t '%F %R' "$BS_APP")"
    partial=$(find "$BS_APP" -name '*.solidpartial' 2>/dev/null | sed "s|^$BS_APP/||")
    if [ -n "$partial" ]; then
      echo "  half-written files of a self-update that did not finish (*.solidpartial):"
      printf '%s\n' "$partial" | head -20 | sed 's/^/    /'
    else
      echo "  half-written files (*.solidpartial): none"
    fi
    if cs=$(codesign --verify --deep --strict "$BS_APP" 2>&1); then echo "  signature (codesign --verify --deep --strict): valid"
    else echo "  signature (codesign --verify --deep --strict): not valid: $(printf '%s\n' "$cs" | head -5 | tr '\n' ' ')"; fi
  else
    echo "  not found at $BS_APP"
  fi
  echo "  its logs: $(ls "$LAUNCHER_LOGS"/*.log 2>/dev/null | wc -l | tr -d ' ') (in launcher-logs/)"
  echo "Launcher-update launchd job of an older version: $([ -f "$H/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist" ] && echo "still there (Reinstall removes it)" || echo "none")"
  echo
  # (the wrapper's hold-launcher logs a line when the game ends: wine.log, wine.log.1-4 are
  # those starts' logs, the newest first)
  echo "Game starts, the last 10 (in logs/hold.log; how long each ran and how it ended):"
  grep 'game ended after' "$LOGS/hold.log" 2>/dev/null | tail -10 | sed 's/^/  /' | grep . || echo "  none recorded"
  echo
  echo "Crash reports of the last 7 days (newest first; in crash-reports/):"
  if [ -s "$work/crash-index" ]; then cat "$work/crash-index"; else echo "  none"; fi
  echo
  echo "GPU errors of the last $GPU_HOURS hours (in gpu-errors.txt):"
  echo "  $(cat "$work/gpu-summary" 2>/dev/null || echo "not read")"
  echo
  # Metal's caches of the engine's processes (macOS's, not the app's; nothing is changed here):
  # gpuarchiver grows by a folder per process that uses Metal, com.apple.metal holds the
  # compiled shaders and the archive usage index (an LMDB with a map of about 1 MiB). The index's
  # size alone doesn't say it is full (LMDB reuses freed pages; the one that failed on 2026-10-18
  # was 1,044,480 bytes), and the MDB_MAP_FULL lines gpu_errors counted may be from an earlier index
  # or another cache: so the size and those events side by side, its fullness now unknown. Other
  # CrossOver-based apps (CrossOver, SWGL on Mac, GameToMac) share the bundle id, so their
  # processes count in here too.
  echo "Metal's caches of the engine's processes (in the user cache dir, ${METAL_CACHE##*/}/; shared with other CrossOver-based apps, whose processes count too):"
  for c in com.apple.gpuarchiver com.apple.metal; do
    if [ -d "$METAL_CACHE/$c" ]; then
      echo "  $c: $(du -sk "$METAL_CACHE/$c" 2>/dev/null | awk '{ printf "%.1f MB", $1 / 1024 }'), $(ls -A "$METAL_CACHE/$c" 2>/dev/null | wc -l | tr -d ' ') entries"
    else
      echo "  $c: none"
    fi
  done
  idx="$METAL_CACHE/com.apple.metal/archiveUsage.db/data.mdb"
  full=$(cat "$work/gpu-mdbfull" 2>/dev/null || echo 0)
  if [ -f "$idx" ]; then
    n=$(stat -f %z "$idx" 2>/dev/null || echo 0)
    # (the events can be an older index's, or another bundle's cache's: they don't make this one full)
    if [ "${full:-0}" -gt 0 ]; then note="; $full MDB_MAP_FULL events in game/Wine processes during the last $GPU_HOURS hours; current index fullness unknown (compiled shaders are still cached)"
    elif [ "$n" -ge 1000000 ]; then note=", near its map's size (about 1 MB; no MDB_MAP_FULL events in the last $GPU_HOURS hours)"
    else note=""; fi
    echo "  archive usage index (com.apple.metal/archiveUsage.db): $n bytes$note"
  else
    echo "  archive usage index (com.apple.metal/archiveUsage.db): none"
  fi
  echo
  # names only, never the command line (it has the account)
  echo "Running SWTOR, Wine and SWTOR on Mac processes (name only):"
  ps -axww -o pid=,etime=,rss=,comm= 2>/dev/null |
    awk '/[Ww]ine|swtor|Star Wars|SWTOR|winetemp|hold-launcher/ && !/awk|collect-logs/'
  echo
  system_profiler SPHardwareDataType 2>/dev/null | grep -v -i -E 'serial|uuid|udid|activation lock'
} 2>&1 | redact >"$out/system-info.txt"

# The leak check: a file that still has one of the names above, a home folder's path or an
# account name or token on a command line is left out (left-out.txt names it).
( cd "$out" && find . -type f ) | sed 's|^\./||' | while IFS= read -r rel; do
  f="$out/$rel"
  if { [ -s "$literals" ] && LC_ALL=C grep -q -i -F -f "$literals" "$f"; } ||
     LC_ALL=C grep -q -F -e "$HOME/" -e "$H/" -e "/Users/$(id -un)/" "$f" ||
     LC_ALL=C grep -q -E -e '-set[[:space:]]+username[[:space:]]+[^R.[:space:]]' -e '--registry-token -t [^T]' "$f"; then
    rm -f "$f"
    echo "$rel"
  fi
done >"$work/leaks"
if [ -s "$work/leaks" ]; then
  { echo "Left out: a name, home folder or token the redaction missed was still in these files"
    sed 's/^/  /' "$work/leaks"; } >"$out/left-out.txt"
fi

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
