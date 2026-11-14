#!/bin/bash
# test-nativefs-decide.sh: the native fullscreen decision of the app's Mac driver, without AppKit.
# Cuts the decision (the block between "nativefs decision: begin" and "end") out of
# patches/winemac-native-fullscreen.patch, builds scripts/nativefs-decide-test.c against it with
# clang ($CC) and runs it; then builds it against two broken stubs (one that never enters, one
# that ignores the player's exit), each of which must fail. Needs only a C compiler.
# Exit status: 0 all passed; 1 a check failed, or a stub passed; 70 the build failed.
set -u
cd "$(dirname "$0")/.." || exit 70
CC=${CC:-clang}
work=$(mktemp -d "${TMPDIR:-/tmp}/nativefs-decide.XXXXXX") || exit 70
trap 'rm -rf "$work"' EXIT

awk '/^\+\/\* ---------- nativefs decision: begin/ { on = 1 }
     on { l = $0; sub(/^\+/, "", l); print l }
     on && /^\+\/\* ---------- nativefs decision: end/ { exit }' \
  patches/winemac-native-fullscreen.patch > "$work/nativefs.h"
grep -q 'nativefs decision: end' "$work/nativefs.h" ||
  { echo "the decision block is not in patches/winemac-native-fullscreen.patch" >&2; exit 70; }

rc=0
run() { # <name> <expect: pass|fail> [cflags...]
  local name=$1 expect=$2 out
  shift 2
  "$CC" -std=c99 -Wall -Wextra -Werror -I"$work" "$@" -o "$work/$name" scripts/nativefs-decide-test.c ||
    { echo "$name: build failed" >&2; exit 70; }
  if out=$("$work/$name"); then
    if [ "$expect" = pass ]; then echo "decision: $(printf '%s\n' "$out" | tail -n 1)"
    else echo "control $name passed, but must fail" >&2; rc=1; fi
  else
    if [ "$expect" = fail ]; then echo "control $name fails as it must ($(printf '%s\n' "$out" | tail -n 1))"
    else printf '%s\n' "$out" >&2; rc=1; fi
  fi
}
run decide pass
run never-enter fail -DSTUB_NEVER_ENTER
run ignore-declined fail -DSTUB_IGNORE_DECLINED
exit "$rc"
