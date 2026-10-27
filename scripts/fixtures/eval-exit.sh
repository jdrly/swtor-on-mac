# shellcheck shell=bash
# A check's eval string never ends the run (#66): check runs eval in the caller's shell, so an
# exit there would end the whole suite, with no FAIL line and no counts. eval_exits is section
# 14a's (scripts/test-sandbox.sh, sourced); fixture group eval-exit checks it, and the suite's
# "app files gone" checks on a planted file (scripts/test-fixtures.sh only). Sourced; check and
# its counters come from lib.sh.

# eval_exits <file>...: the lines whose eval string calls exit outside a subshell (outside any
# parentheses, which in a check are a subshell or a command substitution), as file:line: text
eval_exits() {
  awk '!/^[ \t]*#/ && (i = index($0, "eval \047")) {
    s = substr($0, i + 6); t = ""; d = 0
    for (k = 1; k <= length(s); k++) {
      c = substr(s, k, 1)
      if (c == "(") d++; else if (c == ")") d--; else if (d == 0) t = t c
    }
    if (t ~ /(^|[;&|{!]|do|then|else)[ \t]*exit([^A-Za-z0-9_]|$)/) print FILENAME ":" FNR ": " $0
  }' "$@"
}

# fx_eval_exit <test-sandbox.sh> <folder>: eval_exits finds a planted exit and passes one in a
# subshell, and finds none in the suite and the fixture groups; the suite's "app files gone"
# checks, run on their own, count a planted env as FAIL and the run goes on
fx_eval_exit() {
  local suite=$1 d=$2 x=exit
  # shellcheck disable=SC2034 # (the suite's names, used in the checks sourced below)
  local SOM="$2/som" H="$2/home" PREVV=prev DEVV=dev
  mkdir -p "$d/som" "$d/home"
  # (the planted lines are built here, so this file holds no such eval string itself)
  printf "check \"bare\" eval 'for c in a b; do [ ! -e \"\$c\" ] || %s 1; done'\n" "$x" >"$d/bare.sh"
  printf "check \"in a subshell\" eval '( for c in a b; do [ ! -e \"\$c\" ] || %s 1; done ) && true'\n" "$x" >"$d/subshell.sh"
  check "eval-exit: a bare exit in an eval string is found" eval '[ "$(eval_exits "$d/bare.sh")" = "$d/bare.sh:1: $(cat "$d/bare.sh")" ]'
  check "eval-exit: an exit in a subshell is not" test -z "$(eval_exits "$d/subshell.sh")"
  eval_exits "$suite" "$(dirname "$suite")"/fixtures/*.sh | sed 's/^/  exit in eval: /'
  check "eval-exit: no check of the suite or the fixture groups has one" test -z "$(eval_exits "$suite" "$(dirname "$suite")"/fixtures/*.sh)"

  grep -E '^ *check "[^"]*app files[^"]*gone[^"]*" eval ' "$suite" >"$d/gone.sh" || true
  echo x >"$d/som/env"
  FX_RC=0; ( pass=0 fail=0; . "$d/gone.sh"; echo "went on: $pass passed, $fail failed" ) >"$d/gone.txt" 2>&1 || FX_RC=$?
  check "eval-exit: the suite's 3 \"app files gone\" checks, env left: each FAILs and the run goes on ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(grep -c "^  FAIL .*app files.*gone" "$d/gone.txt")" = 3 ] && grep -qx "went on: 0 passed, 3 failed" "$d/gone.txt"'
  rm "$d/som/env"
  FX_RC=0; ( pass=0 fail=0; . "$d/gone.sh"; echo "went on: $pass passed, $fail failed" ) >"$d/clean.txt" 2>&1 || FX_RC=$?
  check "eval-exit: the same checks, nothing left: each passes ($FX_RC)" eval '[ "$FX_RC" = 0 ] && grep -qx "went on: 3 passed, 0 failed" "$d/clean.txt"'
}
