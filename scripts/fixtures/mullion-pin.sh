# shellcheck shell=bash
# The Mullion pin check (scripts/check-mullion-pin.sh) on planted trees, with a stand-in gh that
# answers from planted files as d9mt-pin.sh's does (fx_pin_run, fx_pin_asked and fx_pin_runs come
# from there). Fixture group mullion-pin (scripts/test-fixtures.sh only). Sourced; check and its
# counters come from lib.sh.

# fx_mlp_tree <folder> <commit> [<title>]: a src/som.sh with a pin of that commit
fx_mlp_tree() {
  mkdir -p "$1/tree/src"
  cat >"$1/tree/src/som.sh" <<EOF
MULLION_COMMIT=$2
MULLION_TITLE="${3:-Mullion (jdrly/mullion ${2:0:7})}"
MULLION_URL=https://github.com/jdrly/mullion/releases/download/swtor-builds/mullion-swtor-$2.tar.xz
MULLION_API_URL=https://api.github.com/repos/jdrly/mullion/releases/assets/42
MULLION_SIZE=1000
MULLION_SHA256=$(printf 'a%.0s' $(seq 64))
EOF
}

# fx_mullion_pin <check-mullion-pin.sh> <the repo> <folder>
fx_mullion_pin() {
  local repo=$2 d=$3 pin=1111111111111111111111111111111111111111 g
  # shellcheck disable=SC2034 # (fx_pin_run, in d9mt-pin.sh, reads it)
  FX_PIN_SCRIPT=$1
  g="$d/gh"
  mkdir -p "$g"
  cat >"$g/gh" <<'GH'
#!/bin/bash
# stand-in gh: api --jq <filter> <path>, answered from $FX_PIN
[ "${1:-}" = api ] && [ "${2:-}" = --jq ] && [ $# = 4 ] || { echo "stand-in gh: unexpected arguments: $*" >&2; exit 64; }
filter=$3 path=$4
echo "$path" >>"$FX_PIN/asked.txt"
case "$path" in
  repos/jdrly/mullion/compare/*...swtor-on-mac) f=branch ;;
  repos/jdrly/mullion/releases/assets/*) f=asset ;;
  repos/jdrly/mullion/actions/workflows/swtor.yml/runs\?head_sha=*)
    n=$(( $(cat "$FX_PIN/runs.n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FX_PIN/runs.n"
    f=runs; [ ! -f "$FX_PIN/runs.$n" ] || f=runs.$n ;;
  *) echo "stand-in gh: unexpected path: $path" >&2; exit 64 ;;
esac
[ -f "$FX_PIN/$f" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
[ -s "$FX_PIN/$f" ] || { echo "unexpected end of JSON input" >&2; exit 1; }
case "$(head -n 1 "$FX_PIN/$f")" in
  "HTTP "*) echo "gh: planted error ($(head -n 1 "$FX_PIN/$f"))" >&2; exit 1 ;;
esac
exec jq -r "$filter" "$FX_PIN/$f"
GH
  chmod 755 "$g/gh"
  check "mullion-pin: jq is here (the stand-in gh filters with it)" eval 'command -v jq >/dev/null'
  fx_mlp_tree "$d" "$pin"
  echo '{"status":"ahead"}' >"$g/branch"
  printf '{"name":"mullion-swtor-%s.tar.xz","size":1000,"digest":"sha256:%s"}\n' "$pin" "$(printf 'a%.0s' $(seq 64))" >"$g/asset"

  fx_pin_runs completed '"success"' push 1 >"$g/runs"
  fx_pin_run "$d"
  check "mullion-pin: on swtor-on-mac, the asset pinned, a green push run: passes ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -qx "\[Mullion pin\] OK: the fork.s SWTOR workflow passed at the pin: https://github.example/runs/1" "$d/out.txt"'
  check "mullion-pin: it asked for exactly this commit's runs and the pinned asset" \
    eval 'grep -qx "repos/jdrly/mullion/actions/workflows/swtor.yml/runs?head_sha=$pin&per_page=100" "$g/asked.txt" && grep -qx repos/jdrly/mullion/releases/assets/42 "$g/asked.txt"'

  # the control: a commit without a green run must fail
  fx_pin_runs completed '"failure"' push 2 >"$g/runs"
  fx_pin_run "$d"
  check "mullion-pin: a failed push run, none green: fails and names it ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -qx "\[Mullion pin\]   push: failure https://github.example/runs/2" "$d/out.txt"'
  fx_pin_runs completed '"success"' pull_request 3 >"$g/runs"
  fx_pin_run "$d"
  check "mullion-pin: only a pull request's green run: fails, that run doesn't count ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "no green push run of the pin" "$d/out.txt" && grep -q "no push run of that commit at all" "$d/out.txt"'
  fx_pin_runs completed '"success"' workflow_dispatch 4 >"$g/runs"
  fx_pin_run "$d"
  check "mullion-pin: only a green run by hand: fails, it published nothing ($FX_RC)" eval '[ "$FX_RC" = 1 ]'

  fx_pin_runs in_progress null push 5 >"$g/runs"
  fx_pin_run "$d"
  check "mullion-pin: a run still going, no --wait: no verdict, exit 2 ($FX_RC)" \
    eval '[ "$FX_RC" = 2 ] && grep -q "NO VERDICT: the fork.s SWTOR run of the pin hasn.t finished: https://github.example/runs/5" "$d/out.txt"'
  cp "$g/runs" "$g/runs.1"
  fx_pin_runs completed '"success"' push 5 >"$g/runs.2"
  fx_pin_run "$d" --wait 1
  check "mullion-pin: the same with --wait, green at the second look: passes ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "still going" "$d/out.txt" && grep -q "passed at the pin: https://github.example/runs/5$" "$d/out.txt"'
  rm "$g/runs.1" "$g/runs.2"
  fx_pin_runs completed '"success"' push 1 >"$g/runs"

  printf '{"name":"mullion-swtor-%s.tar.xz","size":1001,"digest":"sha256:%s"}\n' "$pin" "$(printf 'a%.0s' $(seq 64))" >"$g/asset"
  fx_pin_run "$d"
  check "mullion-pin: the asset has another size than MULLION_SIZE: fails ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: the asset at MULLION_API_URL is .* 1001 " "$d/out.txt"'
  printf '{"name":"mullion-swtor-%s.tar.xz","size":1000,"digest":"sha256:%s"}\n' "$pin" "$(printf 'a%.0s' $(seq 64))" >"$g/asset"

  echo '{"status":"diverged"}' >"$g/branch"
  fx_pin_run "$d"
  check "mullion-pin: a commit beside swtor-on-mac: fails ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: the pin is not on jdrly/mullion.s swtor-on-mac (compared with swtor-on-mac: diverged)" "$d/out.txt"'
  echo "HTTP 404" >"$g/branch"
  fx_pin_run "$d"
  check "mullion-pin: a commit the fork doesn't have (404): fails, asked once ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: jdrly/mullion has no commit $pin" "$d/out.txt" && [ "$(fx_pin_asked "$d")" = 1 ]'
  rm "$g/branch"
  fx_pin_run "$d"
  check "mullion-pin: no answer at all: asked 3 times, no verdict, exit 2, no FAIL ($FX_RC)" \
    eval '[ "$FX_RC" = 2 ] && [ "$(fx_pin_asked "$d")" = 3 ] && grep -q "NO VERDICT: GitHub didn.t answer whether the pin is on" "$d/out.txt" && ! grep -q FAIL "$d/out.txt"'
  echo '{"status":"ahead"}' >"$g/branch"

  fx_mlp_tree "$d" "$pin" "Mullion (jdrly/mullion 2222222)"
  fx_pin_run "$d"
  check "mullion-pin: MULLION_TITLE of another commit: fails before asking GitHub ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: MULLION_TITLE doesn.t name MULLION_COMMIT" "$d/out.txt" && [ "$(fx_pin_asked "$d")" = 0 ]'
  fx_mlp_tree "$d" "$pin"
  sed -i.bak 's/mullion-swtor-1111111/mullion-swtor-2222222/' "$d/tree/src/som.sh"
  fx_pin_run "$d"
  check "mullion-pin: MULLION_URL of another commit: fails before asking GitHub ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "FAIL: MULLION_URL is not the swtor-builds asset of MULLION_COMMIT" "$d/out.txt" && [ "$(fx_pin_asked "$d")" = 0 ]'
  fx_mlp_tree "$d" 1111111
  fx_pin_run "$d"
  check "mullion-pin: a short MULLION_COMMIT: fails ($FX_RC)" eval '[ "$FX_RC" = 1 ] && grep -q "MULLION_COMMIT is not 40 hex" "$d/out.txt"'

  # this repo's own pin, as committed: the check reads it and its lines agree (GitHub's answers
  # planted from it)
  rm -rf "$d/tree"
  mkdir -p "$d/tree/src"
  cp "$repo/src/som.sh" "$d/tree/src/"
  pin=$(sed -n 's/^MULLION_COMMIT=//p' "$repo/src/som.sh")
  printf '{"name":"mullion-swtor-%s.tar.xz","size":%s,"digest":"sha256:%s"}\n' "$pin" \
    "$(sed -n 's/^MULLION_SIZE=//p' "$repo/src/som.sh")" "$(sed -n 's/^MULLION_SHA256=//p' "$repo/src/som.sh")" >"$g/asset"
  fx_pin_run "$d"
  check "mullion-pin: this repo's MULLION_* lines are read and agree ($FX_RC: $(head -n 1 "$d/out.txt"))" \
    eval '[ "$FX_RC" = 0 ] && grep -Eqx "\[Mullion pin\] pin [0-9a-f]{40}" "$d/out.txt"'
}
