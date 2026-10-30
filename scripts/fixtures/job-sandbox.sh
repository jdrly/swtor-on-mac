# shellcheck shell=bash
# The end of scripts/test-sandbox.sh's sandbox under a job runner (#59), sourced by the suite, and
# fixture group job-sandbox, which checks it on planted trees (scripts/test-fixtures.sh only: the
# suite's own end isn't a check of the suite, so its counts stay as they are). The functions use
# the suite's SANDBOX, H, SOM, LOGS, BS_WINE and fail.

# keep_repro: the reproducer set after a failure, in repro/ (small; the heavy children go after
# it): the run's inputs (inputs.txt), SWTOR on Mac's files with the prefix's registry, its logs,
# Broadsword's bin/ and bin-real/, and the sizes of what home/ held. False if any of it couldn't be
# copied (a full disk, an I/O error)
keep_repro() {
  local r="$SANDBOX/repro" f e=0
  mkdir -p "$r/SWTOR on Mac/prefix" || return 1
  [ ! -f "$SANDBOX/inputs.txt" ] || cp -p "$SANDBOX/inputs.txt" "$r/" || e=1
  for f in "$SOM"/*; do [ ! -f "$f" ] || cp -p "$f" "$r/SWTOR on Mac/" || e=1; done
  for f in "$SOM/prefix/"*.reg; do [ ! -f "$f" ] || cp -p "$f" "$r/SWTOR on Mac/prefix/" || e=1; done
  [ ! -d "$LOGS" ] || cp -R -p "$LOGS" "$r/Logs" || e=1
  # (ls fails for a bin-real/ that isn't there, du for a folder it can't read: only an empty file
  # is a failed copy)
  ls -la "$BS_WINE/bin" "$BS_WINE/bin-real" >"$r/broadsword-wine-bin.txt" 2>&1 || [ -s "$r/broadsword-wine-bin.txt" ] || e=1
  [ ! -d "$H" ] || du -k -d 5 "$H" >"$r/home-du.txt" 2>/dev/null || [ -s "$r/home-du.txt" ] || e=1
  return $e
}
# job_sandbox_end <exit code>: the end of a job's sandbox, normal or not (see test-sandbox.sh's
# top). When the reproducer set couldn't be copied, home/ itself is kept in its place in repro/
# (a rename, which needs no space): the job keeps repro/ after a failure and removes home/, so
# the sources stay. Only if even the rename fails does home/ stay where it is, said so; the job's
# manifest then keeps home/ too (the adapter's failpin), whole.
job_sandbox_end() {
  local c kept=""
  # shellcheck disable=SC2034 # (the suite's on_exit reads it)
  SANDBOX_ENDED=1
  if [ "$1" != 0 ] || [ "$fail" != 0 ]; then
    if ! keep_repro; then
      kept=1
      echo "== the reproducer set could not be copied: home/ is kept as repro/home instead"
      if [ -d "$SANDBOX/repro" ]; then mv "$H" "$SANDBOX/repro/home"; else mv "$H" "$SANDBOX/repro"; fi ||
        echo "== home/ could not be moved either: it stays in the sandbox, where the job keeps it after a failure"
    fi
  fi
  for c in "$H" "$SANDBOX/prev-engine" "$SANDBOX/dev-engine"; do
    [ -e "$c" ] || continue
    [ "$c" != "$H" ] || [ -z "$kept" ] || continue
    chmod -R u+w "$c" 2>/dev/null || true
    rm -rf "$c" || echo "== $c could not be removed"
  done
}

# Fixture group job-sandbox: job_sandbox_end on planted sandboxes, each a run of its own in a
# subshell: a pass, a failure, a failure whose copies fail (cp), one whose repro/ can't be made
# (mkdir) and one whose copies and rename both fail (mv), each with a read-only bin/ like the
# suite's.
#   fx_job_sandbox <folder>
fx_plant() { # <sandbox>: a sandbox as the suite leaves it, in the globals the functions use
  SANDBOX=$1 H="$1/home"
  SOM="$H/Library/Application Support/SWTOR on Mac" LOGS="$H/Library/Logs/SWTOR on Mac"
  BS_WINE="$H/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"
  mkdir -p "$SOM/prefix" "$SOM/engine/bin" "$LOGS" "$BS_WINE/bin" "$SANDBOX/prev-engine" "$SANDBOX/dev-engine"
  echo env >"$SOM/env"; echo reg >"$SOM/prefix/user.reg"; echo log >"$LOGS/install.log"
  echo pre >"$BS_WINE/bin/wine64-preloader"; chmod a-w "$BS_WINE/bin"
  echo inputs >"$SANDBOX/inputs.txt"; echo text >"$SANDBOX/install.txt"
}
fx_end() { # <name> <fail> <what to break: - | cp | mkdir | mv (and cp)>: the end of a planted sandbox
  ( fx_plant "$D/$1"; fail=$2
    case $3 in cp) cp() { return 1; } ;; mkdir) mkdir() { return 1; } ;; mv) cp() { return 1; }; mv() { return 1; } ;; esac
    job_sandbox_end 0 ) >"$D/$1.out" 2>&1
}
# (in C order: a UTF-8 locale, as on GitHub's runners, sorts repro/broadsword… before repro/Logs)
fx_ls() { (cd "$D/$1" && find . -type f | LC_ALL=C sort | sed 's|^\./||' | tr '\n' ' '); }
fx_job_sandbox() {
  D=$1
  mkdir -p "$D"
  fx_end pass 0 -
  check "job sandbox: a pass keeps the text only" test "$(fx_ls pass)" = "inputs.txt install.txt "
  fx_end fail 1 -
  check "job sandbox: a failure keeps the text and repro/, nothing heavy" \
    test "$(fx_ls fail)" = "inputs.txt install.txt repro/Logs/install.log repro/SWTOR on Mac/env repro/SWTOR on Mac/prefix/user.reg repro/broadsword-wine-bin.txt repro/home-du.txt repro/inputs.txt "
  fx_end nocp 1 cp
  check "job sandbox: copies that fail keep home/ as repro/home, said so" \
    eval '[ ! -e "$D/nocp/home" ] && [ ! -e "$D/nocp/prev-engine" ] && [ "$(cat "$D/nocp/repro/home/Library/Application Support/SWTOR on Mac/env")" = env ] && grep -qx "== the reproducer set could not be copied: home/ is kept as repro/home instead" "$D/nocp.out"'
  fx_end nomkdir 1 mkdir
  check "job sandbox: a repro/ that can't be made: home/ becomes repro/" \
    eval '[ ! -e "$D/nomkdir/home" ] && [ "$(cat "$D/nomkdir/repro/Library/Logs/SWTOR on Mac/install.log")" = log ] && [ ! -e "$D/nomkdir/dev-engine" ]'
  fx_end nomv 1 mv
  check "job sandbox: copies and the rename that fail leave home/ in place, said so" \
    eval '[ "$(cat "$D/nomv/home/Library/Application Support/SWTOR on Mac/env")" = env ] && [ ! -e "$D/nomv/prev-engine" ] && grep -qx "== home/ could not be moved either: it stays in the sandbox, where the job keeps it after a failure" "$D/nomv.out"'
}
