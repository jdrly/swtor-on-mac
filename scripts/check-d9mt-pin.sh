#!/bin/bash
# Checks the d9mt pin against d9mt's own CI, so a release can't ship a d9mt commit that never
# passed it:
#   1. prebuilt/d9mt/VERSION is the pin of scripts/build-d9mt.sh (COMMIT=<40 hex>);
#   2. the pin is a commit of jdrly/d9mt's main;
#   3. d9mt's Checks workflow has a green run of exactly that commit: a push, a nightly or a
#      run by hand. A pull request's run doesn't count: it tests the merge with main, another
#      tree. A pin older than d9mt's CI (before 45fcedb, 2026-11-12) has no run to ask for and
#      passes with a note.
#
#   scripts/check-d9mt-pin.sh [--wait <minutes>]
#
# --wait: while a run of the pin is still going, ask again every 30 s for that long (CI, where
# the pin may have been merged minutes ago). Without it a run in progress is exit status 2.
#
# Exit status: 0 the pin is green; 1 the pin fails a check; 2 no verdict: GitHub didn't answer
# (asked 3 times), or the run hasn't finished. 2 says nothing about the pin: run it again.
#
# Needs gh, logged in or with GH_TOKEN (any token can read a public repo).
# Env, for the fixtures: PIN_ROOT (the tree to read, default this repo), GH (default gh),
# PIN_RETRY_SLEEP and PIN_POLL_SLEEP (seconds, default 10 and 30).
set -u
cd "$(dirname "$0")/.." || exit 70
ROOT="${PIN_ROOT:-$PWD}"
GH="${GH:-gh}"
REPO=jdrly/d9mt
CI_START=45fcedb7e9e99bf4950d7d489337cab45502bacc
RETRY_SLEEP="${PIN_RETRY_SLEEP:-10}"
POLL_SLEEP="${PIN_POLL_SLEEP:-30}"
WAIT_MIN=0
case "${1:-}" in
  "") ;;
  --wait)
    case "${2:-}" in ''|*[!0-9]*) echo "usage: $0 [--wait <minutes>]" >&2; exit 64 ;; esac
    WAIT_MIN=$2 ;;
  *) echo "usage: $0 [--wait <minutes>]" >&2; exit 64 ;;
esac

say() { echo "[d9mt pin] $*"; }
no_verdict() {
  say "NO VERDICT: $*"
  say "This says nothing about the pin. Run the check again."
  exit 2
}

# api <jq filter> <path>: GitHub's answer through the filter, in API_OUT (never called in a
# subshell: it sets variables). On failure API_HTTP is the error's HTTP status, or 000 when no
# answer came, and API_ERROR its first line. A missing answer, a server error and a rate limit
# are asked again, 3 times in all.
API_OUT="" API_HTTP=000 API_ERROR=""
api() {
  local filter=$1 path=$2 try err rc
  err="$(mktemp "${TMPDIR:-/tmp}/d9mt-pin.XXXXXX")"
  for try in 1 2 3; do
    rc=0
    API_OUT="$("$GH" api --jq "$filter" "$path" 2>"$err")" || rc=$?
    if [ "$rc" = 0 ]; then API_HTTP=200; rm -f "$err"; return 0; fi
    API_HTTP="$(sed -n 's/.*(HTTP \([0-9][0-9][0-9]\)).*/\1/p' "$err" | head -n 1)"
    [ -n "$API_HTTP" ] || API_HTTP=000
    API_ERROR="$(head -n 1 "$err")"
    case "$API_HTTP" in
      000|403|429|5??) [ "$try" = 3 ] || sleep "$RETRY_SLEEP" ;;
      *) break ;;
    esac
  done
  rm -f "$err"
  return 1
}

pin="$(sed -n 's/^COMMIT=//p' "$ROOT/scripts/build-d9mt.sh")"
case "$pin" in
  *[!0-9a-f]*|"") say "FAIL: scripts/build-d9mt.sh has no COMMIT=<40 hex> line (got '$pin')"; exit 1 ;;
esac
[ "${#pin}" = 40 ] || { say "FAIL: scripts/build-d9mt.sh's COMMIT is not 40 hex ('$pin')"; exit 1; }
version="$(cat "$ROOT/prebuilt/d9mt/VERSION" 2>/dev/null || true)"
case "$version" in
  *[!0-9a-f]*|"") say "FAIL: prebuilt/d9mt/VERSION is not a commit hash ('$version')"; exit 1 ;;
esac
if [ "${#version}" -lt 7 ] || [ "${pin#"$version"}" = "$pin" ]; then
  say "FAIL: prebuilt/d9mt/VERSION ($version) is not the pin ($pin): prebuilt/d9mt was built from another commit"
  exit 1
fi
say "pin $pin, prebuilt/d9mt/VERSION $version"

# 2. on main: main is ahead of the pin, or is the pin
if ! api .status "repos/$REPO/compare/$pin...main"; then
  case "$API_HTTP" in
    404) say "FAIL: $REPO has no commit $pin, or it shares no history with main ($API_ERROR)"; exit 1 ;;
    *) no_verdict "GitHub didn't answer whether the pin is on $REPO's main ($API_ERROR)" ;;
  esac
fi
case "$API_OUT" in
  ahead|identical) say "the pin is on $REPO's main" ;;
  behind|diverged) say "FAIL: the pin is not on $REPO's main (compared with main: $API_OUT)"; exit 1 ;;
  *) no_verdict "GitHub's answer about the pin and main isn't one I know ('$API_OUT')" ;;
esac

# 3. older than d9mt's CI: nothing to ask for
if ! api .status "repos/$REPO/compare/$CI_START...$pin"; then
  no_verdict "GitHub didn't answer whether the pin is older than d9mt's CI ($API_ERROR)"
fi
case "$API_OUT" in
  ahead|identical) ;;
  behind)
    say "OK: the pin is older than d9mt's CI (${CI_START:0:7}), so there is no Checks run to ask for"
    exit 0 ;;
  *) no_verdict "GitHub's answer about the pin and d9mt's first CI commit isn't one I know ('$API_OUT')" ;;
esac

# The runs of exactly this commit that aren't a pull request's, one per line.
runs_filter='.workflow_runs[] | select(.event != "pull_request" and .event != "pull_request_target") | "\(.status) \(.conclusion) \(.event) \(.html_url)"'
deadline=$(( $(date +%s) + WAIT_MIN * 60 ))
while :; do
  if ! api "$runs_filter" "repos/$REPO/actions/workflows/checks.yml/runs?head_sha=$pin&per_page=100"; then
    no_verdict "GitHub didn't answer for the pin's Checks runs ($API_ERROR)"
  fi
  runs=$API_OUT
  green="$(printf '%s\n' "$runs" | awk '$1 == "completed" && $2 == "success" { print $4; exit }')"
  if [ -n "$green" ]; then
    say "OK: d9mt's Checks passed at the pin: $green"
    exit 0
  fi
  going="$(printf '%s\n' "$runs" | awk 'NF && $1 != "completed" { print $4; exit }')"
  [ -n "$going" ] || break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    no_verdict "d9mt's Checks run of the pin hasn't finished: $going"
  fi
  say "d9mt's Checks run of the pin is still going ($going); asking again in $POLL_SLEEP s"
  sleep "$POLL_SLEEP"
done

say "FAIL: d9mt's Checks has no green run of the pin."
if [ -n "$runs" ]; then
  printf '%s\n' "$runs" | awk 'NF { print "[d9mt pin]   " $3 ": " $2 " " $4 }'
else
  say "  It has no run of that commit at all (a pull request's run doesn't count)."
fi
say "Pin a commit of main that has one, or run Checks on that commit by hand in $REPO (a branch at the pin, then gh workflow run checks.yml --ref <branch>)."
exit 1
