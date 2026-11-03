#!/bin/bash
# Resources/collect-logs.sh: "Collect Logs…" in the app menu (src/native/App.swift). Zips what
# is needed to diagnose a problem into ~/Desktop/SWTOR-on-Mac-logs-<YYYY-MM-DD-HHMM>.zip (the
# logs folder if the Desktop cannot be written) and prints the zip's path.
#   collect-logs.sh [folder]   write the zip into folder instead
#
# In the zip: SWTOR on Mac's logs (the end of large ones; wine.log.1-4 are the game starts
# before the last), its env, settings.conf, dxvk.conf,
# install-manifest.json and d9mt-ab.env (a development build's A/B switches, if set), the app's VERSIONS, session-report.txt (the last game session in
# short, scripts/session-report.sh), sessions-compared.txt (the kept game starts side by side:
# a before/after test's arms), a fresh system-info.txt (macOS, chip, thermal warnings,
# memory, displays, versions, the state of the install, which crash reports are in the zip, when
# macOS ended the launcher's leftovers in the last 7 days because it is not allowed in the
# background, the GPU error count), gpu-errors.txt (the GPU errors of the game and Wine in macOS's unified log of
# the last 2 hours, see gpu_errors), system-reports/ (extracts of macOS's own reports in
# /Library/Logs/DiagnosticReports of the last 48 hours: GPU faults, WindowServer watchdog
# restarts, kernel panics, the game's resource reports; no other process names, see
# system_reports; their counts in system-info.txt and session-report.txt) and
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
# the Mac's names, the launcher's account names and the "Machine Name: ..." it logged; those of
# 2 or 3 characters only as whole words ($literals_short: "Rex", not the "rex" in "Index").
# Not a model's own name ("MacBook Pro", "iMac.local": the model has to stay readable) or a
# common word (as for the user name in redact); the longest first.
literals="$work/literals" literals_short="$work/literals-short"
{ scutil --get ComputerName; scutil --get LocalHostName; scutil --get HostName; hostname -s; hostname
  printf '%s\n' "$launcher_accounts"
  LC_ALL=C grep -h -o -E 'Machine Name: .+$' "$LAUNCHER_LOGS"/*.log | sed 's/^Machine Name: //'
} 2>/dev/null | tr -d '\r' | LC_ALL=C awk '
  { l = tolower($0); sub(/\.local$/, "", l); gsub(/-/, " ", l) }
  length($0) >= 2 && l !~ /^(mac|imac|macbook|macbook air|macbook pro|mac mini|mac studio|mac pro|localhost)( [0-9]+)?$/ &&
  l !~ /^(admin|user|users|test|game|wine|guest|root|home|apple|swtor|shared|crossover)$/ {
    print length($0) "\t" $0 }' | sort -rn | cut -f2- | uniq >"$work/names"
awk 'length($0) >= 4' "$work/names" >"$literals"
awk 'length($0) < 4' "$work/names" >"$literals_short"

redact() {  # [launcher] stdin → stdout (launcher: also launcher_rules)
  SOM_HOME_PATH="$HOME" SOM_ROOT_HOME="$H" SOM_USER="$(id -un)" SOM_NAME="$(id -F 2>/dev/null)" SOM_ACCOUNTS="$accounts" \
  LC_ALL=C awk -v litfile="$literals" -v shortfile="$literals_short" -v launcher="${1:+1}" '
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
        if (m == "127.0.0.1" || tolower(" " pre) ~ /[^a-z](version|ver|v)[:= ]*$/ || pre ~ /[0-9.]$/) out = out pre m
        else out = out pre "IP"
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    # IPv6 addresses: a run of hex digits and colons, not part of a word, with "::" (fe80::1,
    # 2001:db8::1) or 4 colons or more (the full form; MAC addresses are taken before)
    function ipv6(s,    out, pre, m, rest, nc, t) {
      out = ""
      while (match(s, /[0-9A-Fa-f:]*:[0-9A-Fa-f:]*/)) {
        pre = substr(s, 1, RSTART - 1); m = substr(s, RSTART, RLENGTH); rest = substr(s, RSTART + RLENGTH)
        t = m; nc = gsub(/:/, ":", t)
        if ((index(m, "::") || nc >= 4) && m ~ /[0-9A-Fa-f]/ && pre !~ /[A-Za-z0-9_.]$/ && rest !~ /^[A-Za-z0-9_]/) out = out pre "IP6"
        else out = out pre m
        s = rest
      }
      return out s
    }
    # The official launcher logs the game'"'"'s command line (account name, session token), its
    # session and machine ids, the Mac'"'"'s name, its addresses and home folders, also of other
    # users and in Wine'"'"'s user folders.
    function launcher_rules(s) {
      # (the game'"'"'s command line from its account name on: never in the zip, redacted or not;
      # the wrapper logs the game'"'"'s language itself)
      sub(/-set[ \t]+username.*/, "[SWTOR on Mac: the rest of the game'"'"'s command line, from its account name on, left out]", s)
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
      s = ipv6(s)
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
      ns = 0; while ((getline l < shortfile) > 0) short[++ns] = l
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
      for (i = 1; i <= ns; i++) s = rep(s, short[i], "NAME", 1)
      # the launcher'"'"'s session token (its registry calls) and session, JWT-style tokens
      # (a value in quotes, also JSON-escaped ones, \"...\", is one value with its spaces)
      gsub("--registry-token[ \t]+-t[ \t]+\\\\*\"[^\"]*\"", "--registry-token -t TOKEN", s)
      gsub("--registry-token[ \t]+-t[ \t]+\\\\*\047[^\047]*\047", "--registry-token -t TOKEN", s)
      gsub("--registry-token[ \t]+-t[ \t]+[^ \t\"\047\\\\]+", "--registry-token -t TOKEN", s)
      gsub("--session=\\\\*\"[^\"]*\"", "--session=REDACTED", s)
      gsub("--session=\\\\*\047[^\047]*\047", "--session=REDACTED", s)
      gsub("--session=[^ \t\"\047\\\\]+", "--session=REDACTED", s)
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

add_log() {  # file max-bytes [folder in the zip [launcher]]: the end of a log (of wine.log and
  # wine.log.1-4 also the wrapper's "SWTOR on Mac ..." lines at its start: what the game start
  # ran with, its build, settings and conditions)
  local f=$1 size dir="$out/${3:-logs}"
  [ -f "$f" ] || return 0
  mkdir -p "$dir"
  size=$(stat -f %z "$f")
  if [ "$size" -gt "$2" ]; then
    { case "${f##*/}" in wine.log|wine.log.[0-9]) head -n 12 "$f" | LC_ALL=C grep -a '^SWTOR on Mac ' ;; esac
      echo "[SWTOR on Mac: only the last $(($2 / 1000000)) MB of ${f##*/}]"
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

# System reports: macOS's own reports in /Library/Logs/DiagnosticReports (root:_analyticsusers;
# what isn't readable is named, never asked for: no password prompt) of the last SYS_HOURS hours,
# or since the game's last start (wine.log is written anew at each start) if that is longer.
# They tell a GPU fault, a WindowServer watchdog restart (the Mac froze and logged out) and a
# kernel panic (the Mac restarted) apart from a game crash. They are large and list every running
# process, so only extracts go into system-reports/, the newest SYS_MAX of each kind:
#   gpuEvent-swtor.exe-*, gpuEvent-wine*  the whole file (the GPU's analysis, about 1 KB)
#   WindowServer*.ips                     timestamp, termination and thermal pressure
#   *.userspace_watchdog_timeout.spin     known header lines, WindowServer's and the game's threads
#   panic-full-*.panic                    the panic string's head, WindowServer's, loginwindow's
#                                         and the game's uptime and thread names
#   swtor.exe_*.diag, wine*_*.diag        the event, limit and duration lines
# No other names: every line of an extract (but the GPU event's) must have one of the forms in
# sys_forms, Apple's lines in these reports with their numbers in number places; any other line is
# replaced by a note. A form's identity places (a process, a service, a kext, a thread's or queue's
# name) keep their whole value only if it is one of SYS_IDS (processes) or sys_labels (thread and
# queue names); else OTHER. The Mac's and the user's names have no place in any form. The counts'
# line goes into $work/sys-summary, the list into $work/sys-index. In a sandbox the folder is
# $ROOT/system-diagnostics (a test's; the real one is never read).
SYS_DIAG=/Library/Logs/DiagnosticReports
[ -z "$ROOT" ] || SYS_DIAG="$ROOT/system-diagnostics"
SYS_HOURS=48
SYS_MAX=10
SYS_FILE_MAX=20000000
SYS_THREADS=200
# The processes whose names are kept: macOS's display server, login and kernel, the game, Wine's
# and the app's (exact names, as macOS writes them)
SYS_IDS="WindowServer loginwindow kernel_task swtor.exe wine wine64 wine-preloader wine64-preloader wineserver winedevice.exe SWTORonMac"
# The thread and queue names that are kept (exact): WindowServer's and loginwindow's (Apple's),
# the game's, Wine's and d9mt's, as in real reports; com.apple.coreanimation's display, frame-info
# and cursor threads per display are matched in sys_resolve
sys_labels() {
  cat <<'EOF'
ws_main_thread
com.apple.main-thread
com.apple.windowserver.root_queue
com.apple.coreanimation.render-server
com.apple.coreanimation.msr_runloop
com.apple.NSEventThread
IOHIDService - RunLoopCompatibilityThread
com.apple.audio.IOThread.client
com.apple.VirtualDisplayListener
com.apple.rosetta.exceptionserver
GameThread
SF Movie Maker
audio_client_timer
d9mt-compile
d9mt-prewarm
d9mt-statecache
d9mt-retire
d9mt-drawable
dxvk-cs
wine_sechost_service
wine_nsi_notification
wine_macdrv_raw_input
wine_dsound_mixer
EOF
}
# The forms (a sed -E script): each known line is kept as it is, or with its identity places
# marked (` ~ around a process's name, ! = around a thread's or queue's name; sys_form turns them
# into \001 \002 and \003 \004); a line of no known form becomes a note. Numbers only in number
# places ([0-9.]); no free text
sys_forms() {
  cat <<'EOF'
s#^Report: (WindowServer-[0-9.-]+\.ips|panic-full-[0-9.-]+\.panic)$#&#
t
s#^\(its JSON is cut off: only the fields of its first lines\)$#&#
t
s#^(Timestamp|Capture time): ([0-9][0-9: .+-]*|\?)$#&#
t
s#^bug_type: ([0-9]+|\?)$#&#
t
s#^Termination namespace: (WATCHDOG|SIGNAL|CODESIGNING|DYLD|SPRINGBOARD|RUNNINGBOARD|FRONTBOARD|EXEC|JETSAM|TCC|LIBXPC|KERNEL|none)$#&#
t
s#^Termination code: ([0-9]+|0x[0-9a-fA-F]+|-)$#&#
t
s#^Termination indicator: (monitoring timed out for service|-)$#&#
t
s#^(Termination details|Reason):$#&#
t
s#^  \(not a text\)$#&#
t
s#^Thermal pressure: (ThermalPressureLevel(Nominal|Moderate|Heavy|Trapping|Sleeping) \([0-9]+\)|\?)$#&#
t
s#^Uptime: ([0-9.]+|\?) s$#&#
t
s#^Panic string \(up to the Debugger message\):$#&#
t
s#^WindowServer, loginwindow and the game's processes \(uptime, thread names; no others\):$#&#
t
s#^  none in the report$#&#
t
s#^  ([^ ()][^()]*)( \(pid [0-9]+\): up ([0-9]+ s|\?), [0-9]+ threads)$#  `\1~\2#
t
s#^      \([0-9]+ (more|without a name)\)$#&#
t
s#^      (.+)$#      !\1=#
t
s#^(  \([0-9]+ monitored services? unresponsive\): checkin with service: )([^()]+)( \([0-9]+ induced crashes\) returned not alive with context:)$#\1`\2~\3#
t
s#^  is_alive_func returned unhealthy : [0-9A-Fa-fx|:]+$#&#
t
s#^  [0-9]+ seconds since last successful checkin(, [0-9]+ total successful checkins since [0-9]+ seconds ago)?(, has not exited since first loaded)?$#&#
t
s#^(  panic\(cpu [0-9]+ caller 0x[0-9a-fA-F]+\): userspace watchdog timeout: no successful checkins from )([^()]+)( \([0-9]+ induced crashes\))?( in [0-9]+ seconds)$#\1`\2~\3\4#
t
s#^(  panic\(cpu [0-9]+ caller 0x[0-9a-fA-F]+\): ).*$#\1(the rest, of an unknown form, left out)#
t
s#^  service returned not alive with context : is_alive_func returned unhealthy : [0-9A-Fa-fx|:]+$#&#
t
s#^(  service returned not alive with context : is_alive_func returned unhealthy : )([^()]+)( initialization not complete \(post IOKitWaitQuiet\))$#\1`\2~\3#
t
s#^(  service: )([^(),]+)(( \([0-9]+ induced crashes\))?, total successful checkins (in [0-9]+ seconds|since wake \([0-9]+ seconds ago\)): [0-9]+, last successful checkin: ([0-9]+ seconds ago|never))$#\1`\2~\3#
t
s#^  Debugger message: panic$#&#
t
s#^ *$##
t
s#^(Date/Time|End time): +[0-9][0-9: .+-]*$#&#
t
s#^OS Version: +(macOS|Mac OS X) [0-9.]+ \(Build [0-9][0-9][A-Z][0-9]{1,5}[a-z]?\)$#&#
t
s#^Architecture: +(arm64e|arm64|x86_64)$#&#
t
s#^Report Version: +[0-9]+$#&#
t
s#^Data Source: +(Stackshots|Microstackshots)$#&#
t
s#^(Command: +)(.+)$#\1`\2~#
t
s#^PID: +[0-9]+$#&#
t
s#^Event: +(service process watchdog|cpu usage|disk writes|wakeups)$#&#
t
s#^Action taken: +none$#&#
t
s#^Duration: +[0-9.]+s$#&#
t
s#^Duration Sampled: +[0-9.]+s( \(event starts [0-9.]+s before samples\))?$#&#
t
s#^Steps: +[0-9]+( \([0-9]+ samples lost, [0-9.]+ [KMGT]?B/step\))?$#&#
t
s#^Hardware model: +(Mac|MacBookPro|MacBookAir|Macmini|MacPro|iMac|iMacPro|VirtualMac)[0-9]+,[0-9]+$#&#
t
s#^Active cpus: +[0-9]+$#&#
t
s#^Memory size: +[0-9.]+ [KMGT]?B$#&#
t
s#^Time (Since Boot|Awake Since Boot|Since Wake): +[0-9.]+s$#&#
t
s#^Total CPU Time: +<?[0-9.]+s$#&#
t
s#^(Process: )(.+)$#\1`\2~#
t
s#^Footprint: +[0-9.]+ [KMGT]?B$#&#
t
s#^Time Since Fork: +[0-9]+s$#&#
t
s#^Num samples: +[0-9]+ \([0-9]+-[0-9]+\)$#&#
t
s#^CPU Time: +<?[0-9.]+s$#&#
t
s#^Num threads: +[0-9]+$#&#
t
s#^Note: +[0-9]+ idle work queue threads? omitted$#&#
t
s#^  \(more threads left out\)$#&#
t
/^  Thread 0x/s#(DispatchQueue|Thread name) "([^"]*)"#\1 "!\2="#g
t thread
:thread
s#^  Thread 0x[0-9a-fA-F]+(    (DispatchQueue "![^!=]*="\([0-9]+\)|DispatchQueue [0-9]+|Thread name "![^!=]*="|[0-9]+ samples? \([0-9-]+\)|priority [0-9]+( \(base [0-9]+\))?|cpu time <?[0-9.]+s|last ran [0-9.]+s ago|OTHER))*$#&#
t
s#^Writes: +[0-9.]+ [KMGT]?B of file backed memory dirtied over [0-9]+ seconds \([0-9.]+ [KMGT]?B per second average\), exceeding limit of [0-9.]+ [KMGT]?B per second over [0-9]+ seconds$#&#
t
s#^(Writes limit|Writes caused): +[0-9.]+ [KMGT]?B$#&#
t
s#^(Limit duration|Writes duration|Wakeups duration|CPU duration): +[0-9.]+s$#&#
t
s#^Wakeups: +[0-9]+ wakeups over the last [0-9]+ seconds \([0-9]+ wakeups per second average\), exceeding limit of [0-9]+ wakeups per second over [0-9]+ seconds$#&#
t
s#^(Wakeups limit|Wakeups caused): +[0-9]+$#&#
t
s#^CPU: +[0-9.]+s? ?(seconds )?cpu time over [0-9]+ seconds \([0-9]+% cpu average\), exceeding limit of [0-9]+% cpu over [0-9]+ seconds$#&#
t
s#^(CPU limit|CPU used): +[0-9.]+s$#&#
t
s#.*#(a line of an unknown form, left out)#
EOF
}
# sys_resolve: stdin → stdout, each marked place by its value if it is one of SYS_IDS (\001...\002)
# or sys_labels (\003...\004), else OTHER
sys_resolve() {
  LC_ALL=C awk -v ids="$SYS_IDS" -v labf="$work/sysr/labels" '
    BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) id[a[i]] = 1; while ((getline l < labf) > 0) lab[l] = 1 }
    function label(x) { return (x in lab) || (x in id) || x ~ /^com\.apple\.coreanimation\.(display|frameinfo|cursor)\.(primary|external-[0-9]+)$/ }
    { s = $0; out = ""
      while (match(s, /\001[^\001\002\003\004]*\002|\003[^\001\002\003\004]*\004/)) {
        x = substr(s, RSTART + 1, RLENGTH - 2)
        out = out substr(s, 1, RSTART - 1) ((substr(s, RSTART, 1) == "\001" ? (x in id) : label(x)) ? x : "OTHER")
        s = substr(s, RSTART + RLENGTH)
      }
      out = out s; gsub(/[\001-\004]/, "", out); print out }'
}
# sys_form: stdin → stdout, every line in one of sys_forms or a note (control bytes as markers
# can't come in from a report: removed first)
sys_form() {
  LC_ALL=C tr -d '\001-\004' | LC_ALL=C sed -E -f "$work/sysr/forms.sed" | sys_resolve
}
# sys_procs: of a processByPid's plist XML on stdin, WindowServer's, loginwindow's and the game's
# (SYS_IDS but kernel_task) uptime and thread names to stdout (sys_form follows)
sys_procs() {
  LC_ALL=C awk -v maxt="$SYS_THREADS" -v ids="$SYS_IDS" '
    BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) if (a[i] != "kernel_task") ours[a[i]] = 1; n = 0 }
    function val(s) { sub(/^[ \t]*<[^>]*>/, "", s); sub(/<\/[^>]*>[ \t]*$/, "", s)
      gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "\047", s); gsub(/&amp;/, "\\&", s); return s }
    function flush(    i, t, list, c) {
      if (pid == "") return
      if (name in ours) {
        n++; out[n] = name " (pid " pid "): up " (up == "" ? "?" : sprintf("%.0f s", up)) ", " nt " threads"
        list = ""; c = 0; unnamed = 0
        for (i = 1; i <= nt; i++) {
          t = th[i]
          if (t == "") { unnamed++; continue }
          if (++c > maxt) { list = list "\n    (" nt - maxt " more)"; break }
          list = list "\n    " t
        }
        if (unnamed) list = list "\n    (" unnamed " without a name)"
        out[n] = out[n] list
      }
      pid = name = up = ""; nt = 0; delete th
    }
    { d = match($0, /[^\t]/) - 1 }
    d == 1 && /<key>/ { flush(); pid = val($0); k2 = ""; next }
    d == 2 && /<key>/ { k2 = val($0); k4 = ""; next }
    d == 2 && k2 == "procname" && /<string>/ { name = val($0); next }
    d == 2 && k2 == "processUptime" && /<(real|integer)>/ { up = val($0); next }
    d == 3 && k2 == "threadById" && /<key>/ { nt++; th[nt] = ""; next }
    d == 4 && /<key>/ { k4 = val($0); next }
    d == 4 && k2 == "threadById" && k4 == "name" && /<string>/ { th[nt] = val($0); next }
    END { flush(); for (i = 1; i <= n; i++) print out[i] }'
}
# sys_get <field> <json file>: a field's value (raw; an array's: its count), or false
sys_get() { plutil -extract "$1" raw -o - "$2" 2>/dev/null; }
# sys_lines <label> [end]: a JSON value on stdin as "<label><value><end>"; the value's further
# lines (a newline in a JSON text) start with "  | ", which no form has, so they are left out:
# a JSON text can't pass for a line of another kind
sys_lines() { LC_ALL=C awk -v l="$1" -v e="${2:-}" 'NR == 1 { print l $0 e; next } { print "  | " $0 }'; }
# sys_zname <file name>: its name in the zip, or nothing if it has none of the known forms. The
# process in it is kept only if it is one of SYS_IDS (else OTHER); the Mac's name (between the date
# and the kind's suffix in .spin and .diag names, dots and all) goes
sys_zname() {
  local d='_[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' a b
  a=$(printf '\001') b=$(printf '\002')
  printf '%s\n' "$1" | LC_ALL=C tr -d '\001-\004' | LC_ALL=C sed -E -n \
    -e 's#^WindowServer-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}(\.[0-9]+)?\.ips$#&#p' -e t \
    -e 's#^panic-full-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}(\.[0-9]+)?\.panic$#&#p' -e t \
    -e "s#^gpuEvent-(.+)(-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}(\\.[0-9]+)?\\.ips)\$#gpuEvent-$a\\1$b\\2#p" -e t \
    -e "s#^(.+)($d)(_.*)?(\\.userspace_watchdog_timeout\\.spin)\$#$a\\1$b\\2\\4#p" -e t \
    -e "s#^(.+)($d)(_.*)?(\\.(cpu|diskwrites|wakeups)_resource\\.diag)\$#$a\\1$b\\2\\4#p" -e t \
    -e "s#^(.+)($d)(_.*)?(\\.diag)\$#$a\\1$b\\2\\4#p" | sys_resolve
}
system_reports() {  # → $work/sys/<name in the zip>, $work/sys-index, $work/sys-summary
  local mins s b label f base kind zname gpu=0 wd=0 ws=0 panics=0 diag=0 bad=0 cutn=0 unread=0 ns=0 nx=0 i n ts x cut
  local w="$work/sysr"
  mkdir -p "$work/sys" "$w"
  : >"$work/sys-index"
  sys_labels >"$w/labels"
  sys_forms | LC_ALL=C tr '`~!=' '\001\002\003\004' >"$w/forms.sed"
  mins=$((SYS_HOURS * 60)) label="of the last $SYS_HOURS h"
  if b=$(stat -f %B "$LOGS/wine.log" 2>/dev/null) && [ -n "$b" ]; then
    s=$((($(date +%s) - b) / 60 + 1))
    if [ "$s" -gt "$mins" ]; then mins=$s label="since the game's last start ($(((s + 59) / 60)) h)"; fi
  fi
  echo "$label" >"$work/sys-label"
  if [ ! -d "$SYS_DIAG" ]; then
    echo "not read (no $SYS_DIAG)" >"$work/sys-summary"; return 0
  fi
  if ! ls "$SYS_DIAG" >/dev/null 2>&1; then
    echo "not read (no access to $SYS_DIAG)" >"$work/sys-summary"; return 0
  fi
  # (newest first; equal times by name, in C order, in every locale)
  find "$SYS_DIAG" -maxdepth 1 -type f \( -name 'gpuEvent-swtor.exe-*' -o -name 'gpuEvent-wine*' -o -name 'WindowServer*.ips' \
    -o -name '*.userspace_watchdog_timeout.spin' -o -name 'panic-full-*.panic' \
    -o \( \( -name 'swtor.exe_*' -o -name 'wine*_*' \) -name '*.diag' \) \) -mmin "-$mins" \
    -exec stat -f '%m %z %N' {} + 2>/dev/null | LC_ALL=C sort -k1,1rn -k3 >"$w/list"
  while read -r _ s f; do
    base=${f##*/}
    case "$base" in
      gpuEvent-*) kind=gpu ;; WindowServer*.ips) kind=ws ;; *.spin) kind=spin ;; panic-full-*) kind=panic ;; *) kind=diag ;;
    esac
    # the newest SYS_MAX of each kind
    eval "x=\${count_$kind:-0}"; x=$((x + 1)); eval "count_$kind=$x"
    zname=$(sys_zname "$base")
    [ -n "$zname" ] || zname="OTHER-$kind-$x"
    if [ "$x" -gt "$SYS_MAX" ]; then echo "  left out: $zname (more than $SYS_MAX of its kind)" >>"$work/sys-index"; continue; fi
    if [ "$s" -gt "$SYS_FILE_MAX" ]; then echo "  left out: $zname ($(((s + 999) / 1000)) KB, too large)" >>"$work/sys-index"; continue; fi
    # (a GPU event or resource report of another process, e.g. wine-something: not ours)
    case $kind:$zname in
      gpu:*OTHER* | diag:*OTHER*) echo "  left out: $zname (not the game's)" >>"$work/sys-index"; continue ;;
    esac
    if [ ! -r "$f" ]; then
      unread=$((unread + 1)); echo "  not readable: $zname" >>"$work/sys-index"; continue
    fi
    ts=$(stat -f '%Sm' -t '%F %R' "$f") cut=""
    case $kind in
      gpu)
        gpu=$((gpu + 1))
        if [ "$s" -gt 65536 ]; then echo "  left out: $zname ($(((s + 999) / 1000)) KB, not a GPU event's size)" >>"$work/sys-index"; continue; fi
        cp "$f" "$w/x"
        ;;
      diag)
        diag=$((diag + 1))
        # the header up to the stacks; Path and identifiers stay out
        LC_ALL=C awk '/^Heaviest stack|^Powerstats|^Binary Images/ { exit }
          /^(Date\/Time|End time|OS Version|Command|Event|Action taken|Duration|Duration Sampled|Steps|Limit duration|Writes[A-Za-z ]*|Wakeups[A-Za-z ]*|CPU[A-Za-z ]*|[A-Za-z ]*[Ll]imit[A-Za-z ]*):/' "$f" | sys_form >"$w/x"
        ;;
      spin)
        # the header's known lines (the reason split into its parts), WindowServer's and the
        # game's thread lines (Thread 0x..., its queue and name, samples, priority, CPU; a part of
        # no known form as OTHER); no stacks, no other process's block
        LC_ALL=C awk -v maxt="$SYS_THREADS" -v ids="$SYS_IDS" '
          BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) if (a[i] != "kernel_task" && a[i] != "loginwindow") ours[a[i]] = 1 }
          function field(f) {
            if (f ~ /^DispatchQueue "[^"]*"\([0-9]+\)$/ || f ~ /^DispatchQueue [0-9]+$/ || f ~ /^Thread name "[^"]*"$/ ||
                f ~ /^[0-9]+ samples? \([0-9-]+\)$/ || f ~ /^priority [0-9]+( \(base [0-9]+\))?$/ || f ~ /^cpu time <?[0-9.]+s$/ ||
                f ~ /^last ran [0-9.]+s ago$/) return f
            return "OTHER"
          }
          /^Process: / { hdr = 0; n = $0; sub(/^Process: +/, "", n); sub(/ +\[[0-9]+\].*$/, "", n); sub(/ \([^()]*\)$/, "", n)
            keep = n in ours; t = 0; if (keep) print "\nProcess: " n; next }
          NR == 1 { hdr = 1 }
          hdr && /^Reason: / { r = $0; sub(/^Reason: +/, "", r); sub(/with context: /, "with context:  ", r)
            print "Reason:"; m = split(r, p, /  +/); for (i = 1; i <= m; i++) print "  " p[i]; next }
          hdr && /^(Date\/Time|End time|OS Version|Architecture|Report Version|Data Source|Command|PID|Event|Duration|Duration Sampled|Steps|Hardware model|Active cpus|Memory size|Time Since Boot|Time Awake Since Boot|Time Since Wake|Total CPU Time): / { print; next }
          hdr { next }
          keep && /^(Footprint|Time Since Fork|Num samples|CPU Time|Num threads|Note): / { print; next }
          keep && /^  Thread 0x/ {
            if (++t > maxt) { if (t == maxt + 1) print "  (more threads left out)"; next }
            m = split(substr($0, 3), p, /    +/); l = "  " p[1]; for (i = 2; i <= m; i++) l = l "    " field(p[i]); print l }' "$f" |
          sys_form >"$w/x"
        ;;
      ws|panic)
        head -1 "$f" >"$w/head.json"; tail -n +2 "$f" >"$w/body.json"
        if ! plutil -convert json -o /dev/null "$w/body.json" 2>/dev/null; then
          # A WindowServer report cut off (written while the Mac went down) still has its
          # termination and thermal pressure in its first lines, one line each: those alone
          if [ "$kind" = ws ] &&
             LC_ALL=C awk '/^  "(termination|thermalPressureLevel|captureTime|uptime)" : / { l = $0; sub(/,[ \t]*$/, "", l); a[++n] = l }
               END { print "{"; for (i = 1; i <= n; i++) print a[i] (i < n ? "," : ""); print "}" }' "$w/body.json" >"$w/cut.json" &&
             plutil -convert json -o /dev/null "$w/cut.json" 2>/dev/null && sys_get termination.namespace "$w/cut.json" >/dev/null; then
            cut=1; cutn=$((cutn + 1)); mv -f "$w/cut.json" "$w/body.json"
          else
            bad=$((bad + 1)); [ "$kind" = panic ] && panics=$((panics + 1))
            echo "  $zname ($ts): its JSON could not be read (malformed), left out" >>"$work/sys-index"; continue
          fi
        fi
        {
          echo "Report: ${zname}"
          [ -z "$cut" ] || echo "(its JSON is cut off: only the fields of its first lines)"
          { sys_get timestamp "$w/head.json" || echo ?; } | sys_lines "Timestamp: "
          { sys_get bug_type "$w/head.json" || sys_get bug_type "$w/body.json" || echo ?; } | sys_lines "bug_type: "
          if [ "$kind" = ws ]; then
            ws=$((ws + 1))
            { sys_get captureTime "$w/body.json" || echo ?; } | sys_lines "Capture time: "
            x=$(sys_get termination.namespace "$w/body.json")
            [ "$x" != WATCHDOG ] || wd=$((wd + 1))
            printf '%s\n' "${x:-none}" | sys_lines "Termination namespace: "
            { sys_get termination.code "$w/body.json" || echo -; } | sys_lines "Termination code: "
            { sys_get termination.indicator "$w/body.json" || echo -; } | sys_lines "Termination indicator: "
            # details: a list of texts (one not a text, e.g. null, is named, the rest still go)
            echo "Termination details:"
            case $(plutil -extract termination.details json -o - "$w/body.json" 2>/dev/null) in
              \[*)
                n=$(sys_get termination.details "$w/body.json"); case $n in '' | *[!0-9]*) n=0 ;; esac
                i=0
                while [ "$i" -lt "$n" ] && [ "$i" -lt 20 ]; do
                  { sys_get "termination.details.$i" "$w/body.json" || echo "(not a text)"; } | sys_lines "  "; i=$((i + 1))
                done ;;
              \"*) sys_get termination.details "$w/body.json" | sys_lines "  " ;;
            esac
            { sys_get thermalPressureLevel "$w/body.json" || echo ?; } | sys_lines "Thermal pressure: "
            { sys_get uptime "$w/body.json" || echo ?; } | sys_lines "Uptime: " " s"
          else
            panics=$((panics + 1))
            plutil -extract processByPid xml1 -o - "$w/body.json" 2>/dev/null | sys_procs >"$w/procs"
            echo "Panic string (up to the Debugger message):"
            sys_get panicString "$w/body.json" | LC_ALL=C awk '{ print "  " $0 } /^Debugger message/ || NR >= 40 { exit }'
            echo
            echo "WindowServer, loginwindow and the game's processes (uptime, thread names; no others):"
            if [ -s "$w/procs" ]; then sed 's/^/  /' "$w/procs"; else echo "  none in the report"; fi
          fi
        } >"$w/raw"
        sys_form <"$w/raw" >"$w/x"
        ;;
    esac
    zname="$zname.txt"
    [ "$kind" != gpu ] || zname="${zname%.ips.txt}.ips"
    mv -f "$w/x" "$work/sys/$zname"
    nx=$((nx + 1))
    echo "  $zname ($ts${cut:+; cut off, only its first lines})" >>"$work/sys-index"
  done <"$w/list"
  ns=$(wc -l <"$w/list" | tr -d ' ')
  s="$gpu GPU faults, $wd WindowServer watchdog restarts, $panics kernel panics"
  [ "$ns" -gt 0 ] || s="$s (no reports)"
  [ "$bad" = 0 ] || s="$s; $bad malformed"
  [ "$cutn" = 0 ] || s="$s; $cutn cut off"
  [ "$unread" = 0 ] || s="$s; $unread not readable (no access)"
  echo "$s" >"$work/sys-summary"
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
# The game starts the wrapper kept, the oldest first, side by side (session-report.sh --mark 60
# --compare; a before/after test's sessions, its A/B/A arms the last three), from the whole
# logs: what each ran with, how it was measured and what is missing. A few seconds for long
# logs: it runs beside the queries below, and the zip waits for it (cmp_pid).
kept=() cmp_pid=""
for f in "$LOGS/wine.log.4" "$LOGS/wine.log.3" "$LOGS/wine.log.2" "$LOGS/wine.log.1" "$LOGS/wine.log"; do
  [ -f "$f" ] && kept[${#kept[@]}]=$f
done
if [ ${#kept[@]} -ge 2 ] && [ -x "$RES/session-report.sh" ]; then
  { "$RES/session-report.sh" --mark 60 --compare "${kept[@]}" 2>&1
    [ ! -f "$LOGS/wine.log.4" ] || echo "(wine.log.4 is the oldest game start kept: the wrapper keeps the last 5, earlier ones are gone)"
  } </dev/null | redact >"$out/sessions-compared.txt" &
  cmp_pid=$!
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
# Whether macOS ended what the launcher left running (the game's Wine) when it quit, because it
# is not allowed in the background (Login Items > App Background Activity): som.sh btm-check over the last
# BTM_DAYS days, next to the GPU query. The check ends its query itself after BTM_TIMEOUT s
# (SWTOR_ON_MAC_BTM_TIMEOUT), whatever the GPU query does; should it still run 5 s later, its
# process group (set -m) is ended here. (In a sandbox it reads only a test's
# SWTOR_ON_MAC_BTM_LOG, and SWTOR_ON_MAC_BTM_TIMEOUT can shorten the limit.)
BTM_DAYS=7
BTM_TIMEOUT=90
[ -z "$ROOT" ] || BTM_TIMEOUT="${SWTOR_ON_MAC_BTM_TIMEOUT:-$BTM_TIMEOUT}"
btm_t0=$SECONDS
set -m
SWTOR_ON_MAC_BTM_TIMEOUT="$BTM_TIMEOUT" /bin/bash "$RES/som.sh" btm-check "${BTM_DAYS}d" </dev/null >"$work/btm" 2>/dev/null &
btm_pid=$!
set +m
gpu_errors 2>&1 | redact >"$out/gpu-errors.txt"
# (redacted on the way in like the rest; their names too)
system_reports
for f in "$work/sys"/*; do
  [ -f "$f" ] || continue
  mkdir -p "$out/system-reports"
  redact <"$f" >"$out/system-reports/$(printf '%s\n' "${f##*/}" | redact)"
done
sys_line="System reports $(cat "$work/sys-label"): $(cat "$work/sys-summary")"
# the session report's summary repeats it, after its first line
if [ -f "$out/session-report.txt" ]; then
  { sed -n 1p "$out/session-report.txt"; echo "$sys_line"; sed 1d "$out/session-report.txt"; } | redact >"$work/sr.txt" &&
    mv -f "$work/sr.txt" "$out/session-report.txt"
fi
[ -z "$cmp_pid" ] || wait "$cmp_pid"
while kill -0 "$btm_pid" 2>/dev/null && [ $((SECONDS - btm_t0)) -lt $((BTM_TIMEOUT + 5)) ]; do sleep 1; done
btm_late=0
if kill -0 "$btm_pid" 2>/dev/null; then
  btm_late=1
  kill -TERM -- "-$btm_pid" 2>/dev/null; sleep 1; kill -KILL -- "-$btm_pid" 2>/dev/null
fi
wait "$btm_pid" 2>/dev/null; btm_st=$?
grep -q "ran out of time" "$work/btm" 2>/dev/null && btm_late=1
case "$btm_late:$btm_st" in
  0:0) btm=$(paste -sd, "$work/btm" | sed 's/,/, /g') ;;
  0:1) btm=none ;;
  0:*) btm="not read" ;;
  *) btm="not read (ran out of time)" ;;
esac

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
  echo "Power: $(pmset -g ps 2>/dev/null | sed -n "1s/.*'\(.*\)'.*/\1/p")$(pmset -g 2>/dev/null | awk '($1 == "lowpowermode" || $1 == "powermode") && $2 == 1 { print ", Low Power Mode" } $1 == "powermode" && $2 == 2 { print ", High Power Mode" }')"
  # (now; each game start's own is in its wine.log, "SWTOR on Mac conditions:")
  echo "Thermal and performance warnings now (pmset -g therm): $(pmset -g therm 2>/dev/null | LC_ALL=C awk '
    /^Note: No .* has been recorded/ { notes++; next }
    /[A-Za-z]/ { w = w (w == "" ? "" : ", ") $0 }
    END { if (w != "") print w; else if (notes) print "none"; else print "unknown" }')"
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
    # (the owner as root, you or another user: another user's name is theirs)
    o=$(stat -f '%Su' "$BS_APP"); g=$(stat -f '%Sg' "$BS_APP")
    case "$o" in root) ;; "$(id -un)") o="you" ;; *) o="another user" ;; esac
    case "$g" in wheel|admin|staff) ;; *) g="another group" ;; esac
    echo "  owner $o, group $g, $(stat -f '%Sp' "$BS_APP"), changed $(stat -f '%Sm' -t '%F %R' "$BS_APP")"
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
  echo "Launcher off in Login Items > App Background Activity, macOS ended what it left running (the last $BTM_DAYS days): $btm"
  echo
  echo "GPU errors of the last $GPU_HOURS hours (in gpu-errors.txt):"
  echo "  $(cat "$work/gpu-summary" 2>/dev/null || echo "not read")"
  echo
  # (macOS's own reports in $SYS_DIAG, see system_reports)
  echo "$sys_line"
  echo "  (extracts in system-reports/; GPU faults: gpuEvent, watchdog restarts: WindowServer .ips, panics: panic-full)"
  [ ! -s "$work/sys-index" ] || cat "$work/sys-index"
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
# account name, session or token on a command line is left out (left-out.txt names it). (A
# redacted value may end a quoted string, REDACTED" or REDACTED\", not go on after one; a token
# that begins as a JWT's header, eyJ..., is one even when cut off.)
cat >"$work/leak-patterns" <<'EOF'
-set[[:space:]]+username[[:space:]]+[^R[:space:]]
--registry-token[[:space:]]+-t[[:space:]]+[^T]
--session=[^R]
--session=REDACTED[^[:space:],;)}"'\\]
--session=REDACTED\\*["'][A-Za-z0-9]
eyJ[A-Za-z0-9_-]{8}
EOF
# found <grep options>: a match, or grep failed (the check fails closed); found_name: the same
# on the file without this script's own markers, also inside words (a name "Name" is not found
# in NAME or app_NAME; redact replaces names in any case, so a marker hides none)
found() { LC_ALL=C grep -q "$@"; [ $? != 1 ]; }
found_name() {  # <file> <grep options>
  local f=$1; shift
  LC_ALL=C sed -E 's/NAME|ACCOUNT|USER|REDACTED|TOKEN|EMAIL|MAC-ADDRESS|IP6|IP//g' "$f" | LC_ALL=C grep -q "$@"
  [ $? != 1 ]
}
( cd "$out" && find . -type f ) | sed 's|^\./||' | while IFS= read -r rel; do
  f="$out/$rel"
  if { [ -s "$literals" ] && found_name "$f" -i -F -f "$literals"; } ||
     { [ -s "$literals_short" ] && found_name "$f" -i -w -F -f "$literals_short"; } ||
     found -F -e "$HOME/" -e "$H/" -e "/Users/$(id -un)/" "$f" ||
     found -E -f "$work/leak-patterns" "$f"; then
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
