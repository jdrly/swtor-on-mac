# shellcheck shell=bash
# Fixture group self: what scripts/test-fixtures.sh promises, each on a run of its own in this
# group's folder, with stand-in apps whose session-report.sh wraps the real one:
# - a wrong session report fails the checks (one line off: the prewarm's "built 37");
# - a check that starts Wine or the app fails the run and names the command, even when the
#   command's failure is ignored (the stand-ins run nothing; the paths don't exist either);
# - the cleanup removes the run's root and nothing beside it, and an existing folder is refused;
# - under a job runner a temporary or missing root is refused, and so is the sandbox of
#   scripts/test-sandbox.sh (on a stand-in app and a home without the official install: a run
#   that wasn't refused would stop at "official SWTOR install not found", before it makes
#   anything). Sourced; check and its counters come from lib.sh.
#
#   fx_self <test-fixtures.sh> <app> <folder>
fx_self() {
  local tf=$1 real=$2/Contents/Resources/session-report.sh d=$3 suite a sent
  suite="$(dirname "$1")/test-sandbox.sh"
  mkdir -p "$d"
  for a in wrong starts suite; do mkdir -p "$d/$a.app/Contents/Resources"; done
  printf '#!/bin/bash\n%q "$@" | sed "s/built 37, failed 1/built 36, failed 1/"\n' "$real" >"$d/wrong.app/Contents/Resources/session-report.sh"
  printf '#!/bin/bash\nwine --version >/dev/null 2>&1 || true\nopen /nonexistent/fixture-check.app 2>/dev/null || true\nexec %q "$@"\n' \
    "$real" >"$d/starts.app/Contents/Resources/session-report.sh"
  printf '#!/bin/sh\nexit 99\n' >"$d/suite.app/Contents/Resources/som.sh"
  chmod 755 "$d"/*.app/Contents/Resources/*.sh

  FX_RC=0; KEEP='' FIXTURE_ROOT="$d/wrong" "$tf" "$d/wrong.app" session-report >"$d/wrong.txt" 2>&1 || FX_RC=$?
  check "self: a wrong session report fails its check ($FX_RC)" eval '[ "$FX_RC" = 1 ] && grep -qx "  FAIL report: prewarm" "$d/wrong.txt" && [ "$(grep -c "^  FAIL" "$d/wrong.txt")" = 1 ]'
  FX_RC=0; KEEP='' FIXTURE_ROOT="$d/starts" "$tf" "$d/starts.app" session-report >"$d/starts.txt" 2>&1 || FX_RC=$?
  check "self: Wine or the app started by a check fails the run, named ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -qx "  FAIL end: no check started Wine or the app" "$d/starts.txt" && grep -qx "  started: wine --version" "$d/starts.txt" && grep -qx "  started: open /nonexistent/fixture-check.app" "$d/starts.txt" && [ "$(grep -c "^  FAIL" "$d/starts.txt")" = 1 ]'

  echo sentinel >"$d/sentinel"; touch -t 202001010000 "$d/sentinel"
  # shellcheck disable=SC2034 # (used in check's eval strings)
  sent="sentinel $(stat -f %m "$d/sentinel")"
  mkdir -p "$d/there"; echo keep >"$d/there/file"
  FX_RC=0; KEEP='' FIXTURE_ROOT="$d/clean" "$tf" "$2" session-report >"$d/clean.txt" 2>&1 || FX_RC=$?
  check "self: a passing run removes its root, the file beside it untouched ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ ! -e "$d/clean" ] && [ "$(cat "$d/sentinel") $(stat -f %m "$d/sentinel")" = "$sent" ]'
  FX_RC=0; KEEP='' FIXTURE_ROOT="$d/there" "$tf" "$2" session-report >"$d/there.txt" 2>&1 || FX_RC=$?
  check "self: an existing root is refused and left as it was ($FX_RC)" eval '[ "$FX_RC" = 2 ] && [ "$(ls "$d/there")" = file ] && [ "$(cat "$d/there/file")" = keep ]'

  FX_RC=0; KEEP='' JOB_ID=00000001 JOB_ROOT="$d/queue" FIXTURE_ROOT=/tmp/som-fixtures-refused "$tf" "$2" session-report >"$d/job-tmp.txt" 2>&1 || FX_RC=$?
  check "self: under a job runner a root in /tmp is refused ($FX_RC)" eval '[ "$FX_RC" = 64 ] && [ ! -e /tmp/som-fixtures-refused ] && grep -q "is in a temporary folder" "$d/job-tmp.txt"'
  FX_RC=0; ( unset FIXTURE_ROOT KEEP; JOB_ID=00000001 JOB_ROOT="$d/queue" "$tf" "$2" session-report ) >"$d/job-none.txt" 2>&1 || FX_RC=$?
  check "self: under a job runner a root must be named ($FX_RC)" eval '[ "$FX_RC" = 64 ] && grep -q "FIXTURE_ROOT: under a job runner, name a folder" "$d/job-none.txt"'
  # (a root of its own outside the temporary folders: only when this run's root is one)
  if owned_path FIXTURE_ROOT "$d/owned" 2>/dev/null; then
    FX_RC=0; KEEP='' JOB_ID=00000001 JOB_ROOT="$d/queue" FIXTURE_ROOT="$d/owned" "$tf" "$2" session-report >"$d/job-owned.txt" 2>&1 || FX_RC=$?
    check "self: under a job runner a root of its own passes ($FX_RC)" eval '[ "$FX_RC" = 0 ] && [ ! -e "$d/owned" ]'
  else
    echo "  (skipped: under a job runner a root of its own passes; this run's root is in a temporary folder)"
  fi

  mkdir -p "$d/nohome"
  FX_RC=0; HOME="$d/nohome" JOB_ID=00000001 JOB_ROOT="$d/queue" SANDBOX=/tmp/som-sandbox-refused "$suite" "$d/suite.app" >"$d/suite-tmp.txt" 2>&1 || FX_RC=$?
  check "self: under a job runner the suite refuses a sandbox in /tmp ($FX_RC)" eval '[ "$FX_RC" = 64 ] && [ ! -e /tmp/som-sandbox-refused ] && grep -q "SANDBOX=/tmp/som-sandbox-refused is in a temporary folder" "$d/suite-tmp.txt"'
  FX_RC=0; ( unset SANDBOX; HOME="$d/nohome" JOB_ID=00000001 JOB_ROOT="$d/queue" "$suite" "$d/suite.app" ) >"$d/suite-none.txt" 2>&1 || FX_RC=$?
  check "self: under a job runner the suite refuses its default sandbox ($FX_RC)" eval '[ "$FX_RC" = 64 ] && grep -q "SANDBOX: under a job runner, name a folder" "$d/suite-none.txt"'
}
