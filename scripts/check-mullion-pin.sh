#!/bin/bash
# Checks the Mullion pin (MULLION_* in src/som.sh) against my fork's own CI, so a development
# build can't install a Mullion commit that never passed it:
#   1. MULLION_COMMIT is 40 hex, and MULLION_URL and MULLION_TITLE name that commit;
#   2. the commit is on jdrly/mullion's swtor-on-mac branch;
#   3. MULLION_API_URL is the asset of that URL, with MULLION_SIZE and MULLION_SHA256 (GitHub's
#      digest of it);
#   4. the fork's SWTOR workflow has a green push run of exactly that commit (the run that built
#      and published the asset). A pull request's run or one by hand doesn't count.
#
#   scripts/check-mullion-pin.sh [--wait <minutes>]
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
REPO=jdrly/mullion
BRANCH=swtor-on-mac
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

say() { echo "[Mullion pin] $*"; }
fail() { say "FAIL: $*"; exit 1; }
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
  err="$(mktemp "${TMPDIR:-/tmp}/mullion-pin.XXXXXX")"
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

# 1. the pin's own lines agree
val() { sed -n "s/^$1=//p" "$ROOT/src/som.sh" | head -n 1 | tr -d '"'; }
pin="$(val MULLION_COMMIT)"
case "$pin" in
  *[!0-9a-f]*|"") fail "src/som.sh has no MULLION_COMMIT=<40 hex> line (got '$pin')" ;;
esac
[ "${#pin}" = 40 ] || fail "MULLION_COMMIT is not 40 hex ('$pin')"
name="mullion-swtor-$pin.tar.xz"
url="$(val MULLION_URL)"
[ "$url" = "https://github.com/$REPO/releases/download/swtor-builds/$name" ] ||
  fail "MULLION_URL is not the swtor-builds asset of MULLION_COMMIT ($url)"
title="$(val MULLION_TITLE)"
[ "$title" = "Mullion ($REPO ${pin:0:7})" ] || fail "MULLION_TITLE doesn't name MULLION_COMMIT ('$title')"
api_url="$(val MULLION_API_URL)" size="$(val MULLION_SIZE)" sha="$(val MULLION_SHA256)"
case "${api_url#"https://api.github.com/repos/$REPO/releases/assets/"}" in
  "$api_url"|""|*[!0-9]*) fail "MULLION_API_URL is not an asset of $REPO's releases ($api_url)" ;;
esac
say "pin $pin"

# 2. on the branch: the branch is ahead of the pin, or is the pin
if ! api .status "repos/$REPO/compare/$pin...$BRANCH"; then
  case "$API_HTTP" in
    404) fail "$REPO has no commit $pin, or it shares no history with $BRANCH ($API_ERROR)" ;;
    *) no_verdict "GitHub didn't answer whether the pin is on $REPO's $BRANCH ($API_ERROR)" ;;
  esac
fi
case "$API_OUT" in
  ahead|identical) say "the pin is on $REPO's $BRANCH" ;;
  behind|diverged) fail "the pin is not on $REPO's $BRANCH (compared with $BRANCH: $API_OUT)" ;;
  *) no_verdict "GitHub's answer about the pin and $BRANCH isn't one I know ('$API_OUT')" ;;
esac

# 3. the asset is the one pinned
if ! api '"\(.name) \(.size) \(.digest)"' "${api_url#https://api.github.com/}"; then
  case "$API_HTTP" in
    404) fail "MULLION_API_URL names no asset ($API_ERROR)" ;;
    *) no_verdict "GitHub didn't answer for the pin's asset ($API_ERROR)" ;;
  esac
fi
[ "$API_OUT" = "$name $size sha256:$sha" ] ||
  fail "the asset at MULLION_API_URL is '$API_OUT', not '$name $size sha256:$sha' (MULLION_SIZE, MULLION_SHA256)"
say "the asset is $name, $size bytes, sha256 $sha"

# 4. The push runs of exactly this commit, one per line.
runs_filter='.workflow_runs[] | select(.event == "push") | "\(.status) \(.conclusion) \(.event) \(.html_url)"'
deadline=$(( $(date +%s) + WAIT_MIN * 60 ))
while :; do
  if ! api "$runs_filter" "repos/$REPO/actions/workflows/swtor.yml/runs?head_sha=$pin&per_page=100"; then
    no_verdict "GitHub didn't answer for the pin's SWTOR runs ($API_ERROR)"
  fi
  runs=$API_OUT
  green="$(printf '%s\n' "$runs" | awk '$1 == "completed" && $2 == "success" { print $4; exit }')"
  if [ -n "$green" ]; then
    say "OK: the fork's SWTOR workflow passed at the pin: $green"
    exit 0
  fi
  going="$(printf '%s\n' "$runs" | awk 'NF && $1 != "completed" { print $4; exit }')"
  [ -n "$going" ] || break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    no_verdict "the fork's SWTOR run of the pin hasn't finished: $going"
  fi
  say "the fork's SWTOR run of the pin is still going ($going); asking again in $POLL_SLEEP s"
  sleep "$POLL_SLEEP"
done

say "FAIL: the fork's SWTOR workflow has no green push run of the pin."
if [ -n "$runs" ]; then
  printf '%s\n' "$runs" | awk 'NF { print "[Mullion pin]   " $3 ": " $2 " " $4 }'
else
  say "  It has no push run of that commit at all."
fi
say "Pin a commit of $BRANCH whose push run built and published it."
exit 1
