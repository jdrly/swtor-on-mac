# shellcheck shell=bash
# The d9mt pin check (scripts/check-d9mt-pin.sh) on planted trees, with a stand-in gh that
# answers from planted files: GitHub's JSON goes through the script's own jq filter (jq), an
# "HTTP <status>" file is that error, an empty file an empty body (gh fails on it), and a
# missing file is no answer at all. Fixture group
# d9mt-pin (scripts/test-fixtures.sh only). Sourced; check and its counters come from lib.sh.

# fx_pin_run <folder> [check-d9mt-pin.sh's arguments]: the check on <folder>/tree with the
# stand-in gh and no waiting; FX_RC its exit status, <folder>/out.txt its output, and
# <folder>/gh/asked.txt the paths it asked for
fx_pin_run() {
  local d=$1; shift
  rm -f "$d/gh/asked.txt" "$d/gh/runs.n"
  FX_RC=0
  PIN_ROOT="$d/tree" GH="$d/gh/gh" FX_PIN="$d/gh" PIN_RETRY_SLEEP=0 PIN_POLL_SLEEP=0 \
    "$FX_PIN_SCRIPT" "$@" >"$d/out.txt" 2>&1 || FX_RC=$?
}
# fx_pin_asked <folder>: how many times the check asked GitHub
fx_pin_asked() { if [ -f "$1/gh/asked.txt" ]; then wc -l <"$1/gh/asked.txt" | tr -d ' '; else echo 0; fi; }
# fx_pin_runs <status> <conclusion> <event> <n>: one workflow run as GitHub lists it
fx_pin_runs() {
  printf '{"workflow_runs":[{"status":"%s","conclusion":%s,"event":"%s","html_url":"https://github.example/runs/%s"}]}\n' \
    "$1" "$2" "$3" "$4"
}

# fx_d9mt_pin <check-d9mt-pin.sh> <the repo> <folder>
fx_d9mt_pin() {
  local repo=$2 d=$3 pin=1111111111111111111111111111111111111111 g
  FX_PIN_SCRIPT=$1
  g="$d/gh"
  mkdir -p "$d/tree/scripts" "$d/tree/prebuilt/d9mt" "$g"
  cat >"$g/gh" <<'GH'
#!/bin/bash
# stand-in gh: api --jq <filter> <path>, answered from $FX_PIN
[ "${1:-}" = api ] && [ "${2:-}" = --jq ] && [ $# = 4 ] || { echo "stand-in gh: unexpected arguments: $*" >&2; exit 64; }
filter=$3 path=$4
echo "$path" >>"$FX_PIN/asked.txt"
case "$path" in
  repos/jdrly/d9mt/compare/*...main) f=main ;;
  repos/jdrly/d9mt/compare/45fcedb7e9e99bf4950d7d489337cab45502bacc...*) f=ci ;;
  repos/jdrly/d9mt/actions/workflows/checks.yml/runs\?head_sha=*)
    # runs.1, runs.2, … are the answers to the first, second, … question; else runs
    n=$(( $(cat "$FX_PIN/runs.n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FX_PIN/runs.n"
    f=runs; [ ! -f "$FX_PIN/runs.$n" ] || f=runs.$n ;;
  *) echo "stand-in gh: unexpected path: $path" >&2; exit 64 ;;
esac
[ -f "$FX_PIN/$f" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
# (an empty body: gh api --jq fails on it, jq alone wouldn't)
[ -s "$FX_PIN/$f" ] || { echo "unexpected end of JSON input" >&2; exit 1; }
case "$(head -n 1 "$FX_PIN/$f")" in
  "HTTP "*) echo "gh: planted error ($(head -n 1 "$FX_PIN/$f"))" >&2; exit 1 ;;
esac
exec jq -r "$filter" "$FX_PIN/$f"
GH
  chmod 755 "$g/gh"
  check "d9mt-pin: jq is here (the stand-in gh filters with it)" eval 'command -v jq >/dev/null'
  echo "COMMIT=$pin" >"$d/tree/scripts/build-d9mt.sh"
  echo 1111111 >"$d/tree/prebuilt/d9mt/VERSION"
  echo '{"status":"ahead"}' >"$g/main"
  echo '{"status":"ahead"}' >"$g/ci"

  fx_pin_runs completed '"success"' push 1 >"$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: on main with a green push run: passes ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -qx "\[d9mt pin\] OK: d9mt.s Checks passed at the pin: https://github.example/runs/1" "$d/out.txt"'
  check "d9mt-pin: it asked for exactly this commit's runs" \
    grep -qx "repos/jdrly/d9mt/actions/workflows/checks.yml/runs?head_sha=$pin&per_page=100" "$g/asked.txt"

  fx_pin_runs completed '"success"' pull_request 2 >"$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: only a pull request's green run: fails, that run doesn't count ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: d9mt.s Checks has no green run of the pin" "$d/out.txt" && grep -q "no run of that commit at all" "$d/out.txt"'

  fx_pin_runs completed '"failure"' push 3 >"$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: a failed push run: fails and names it ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -qx "\[d9mt pin\]   push: failure https://github.example/runs/3" "$d/out.txt"'

  printf '{"workflow_runs":[{"status":"completed","conclusion":"cancelled","event":"push","html_url":"https://github.example/runs/4"},{"status":"completed","conclusion":"success","event":"workflow_dispatch","html_url":"https://github.example/runs/5"}]}\n' >"$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: a cancelled push run and a green run by hand: passes on the second ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "passed at the pin: https://github.example/runs/5$" "$d/out.txt"'

  fx_pin_runs in_progress null push 6 >"$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: a run still going, no --wait: no verdict, exit 2 ($FX_RC)" \
    eval '[ "$FX_RC" = 2 ] && grep -q "NO VERDICT: d9mt.s Checks run of the pin hasn.t finished: https://github.example/runs/6" "$d/out.txt" && grep -q "This says nothing about the pin" "$d/out.txt"'
  cp "$g/runs" "$g/runs.1"
  fx_pin_runs completed '"success"' push 6 >"$g/runs.2"
  fx_pin_run "$d" --wait 1
  check "d9mt-pin: the same with --wait, green at the second look: passes ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "still going" "$d/out.txt" && grep -q "passed at the pin: https://github.example/runs/6$" "$d/out.txt"'
  rm "$g/runs.1" "$g/runs.2"

  echo "HTTP 502" >"$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: GitHub answers 502 for the runs: asked 3 times, no verdict, exit 2 ($FX_RC, $(fx_pin_asked "$d") questions)" \
    eval '[ "$FX_RC" = 2 ] && [ "$(fx_pin_asked "$d")" = 5 ] && grep -q "NO VERDICT: GitHub didn.t answer for the pin.s Checks runs" "$d/out.txt" && ! grep -q FAIL "$d/out.txt"'

  echo '{"status":"behind"}' >"$g/ci"
  rm "$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: a pin older than d9mt's CI: passes with a note and asks for no run ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "OK: the pin is older than d9mt.s CI" "$d/out.txt" && [ "$(fx_pin_asked "$d")" = 2 ]'
  echo '{"status":"ahead"}' >"$g/ci"

  echo '{"status":"diverged"}' >"$g/main"
  fx_pin_run "$d"
  check "d9mt-pin: a pin beside main: fails ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: the pin is not on jdrly/d9mt.s main (compared with main: diverged)" "$d/out.txt"'
  echo "HTTP 404" >"$g/main"
  fx_pin_run "$d"
  check "d9mt-pin: a commit d9mt doesn't have (404): fails, asked once ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: jdrly/d9mt has no commit $pin" "$d/out.txt" && [ "$(fx_pin_asked "$d")" = 1 ]'
  rm "$g/main"
  fx_pin_run "$d"
  check "d9mt-pin: no answer at all: asked 3 times, no verdict, exit 2, no FAIL ($FX_RC)" \
    eval '[ "$FX_RC" = 2 ] && [ "$(fx_pin_asked "$d")" = 3 ] && grep -q "NO VERDICT: GitHub didn.t answer whether the pin is on" "$d/out.txt" && ! grep -q FAIL "$d/out.txt"'
  : >"$g/main"
  fx_pin_run "$d"
  check "d9mt-pin: an empty answer: asked 3 times, no verdict, exit 2, no FAIL ($FX_RC)" \
    eval '[ "$FX_RC" = 2 ] && [ "$(fx_pin_asked "$d")" = 3 ] && grep -q "NO VERDICT: GitHub didn.t answer whether the pin is on" "$d/out.txt" && ! grep -q FAIL "$d/out.txt"'
  echo '{"status":"ahead"}' >"$g/main"

  echo 2222222 >"$d/tree/prebuilt/d9mt/VERSION"
  fx_pin_run "$d"
  check "d9mt-pin: prebuilt/d9mt/VERSION of another commit: fails before asking GitHub ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: prebuilt/d9mt/VERSION (2222222) is not the pin" "$d/out.txt" && [ "$(fx_pin_asked "$d")" = 0 ]'
  echo 1111111 >"$d/tree/prebuilt/d9mt/VERSION"
  echo "COMMIT=1111111" >"$d/tree/scripts/build-d9mt.sh"
  fx_pin_run "$d"
  check "d9mt-pin: a short COMMIT: fails ($FX_RC)" eval '[ "$FX_RC" = 1 ] && grep -q "COMMIT is not 40 hex" "$d/out.txt"'

  # this repo's own pin, as committed: the check reads it (GitHub's answers planted)
  rm -rf "$d/tree"
  mkdir -p "$d/tree/scripts" "$d/tree/prebuilt/d9mt"
  cp "$repo/scripts/build-d9mt.sh" "$d/tree/scripts/"
  cp "$repo/prebuilt/d9mt/VERSION" "$d/tree/prebuilt/d9mt/"
  fx_pin_runs completed '"success"' push 7 >"$g/runs"
  fx_pin_run "$d"
  check "d9mt-pin: this repo's COMMIT= line and prebuilt/d9mt/VERSION are read and agree ($FX_RC: $(head -n 1 "$d/out.txt"))" \
    eval '[ "$FX_RC" = 0 ] && grep -Eqx "\[d9mt pin\] pin [0-9a-f]{40}, prebuilt/d9mt/VERSION [0-9a-f]{7,40}" "$d/out.txt"'
}
