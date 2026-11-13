# shellcheck shell=bash
# The AIR codegen guard (scripts/air-codegen-guard.sh) on planted air-codegen-id.txt files,
# without building d9mt: first the guard itself with a made-up id and release, then through
# scripts/build-d9mt.sh --check-air-codegen, which calls it with the id and the release that
# script records. Fixture group air-codegen (scripts/test-fixtures.sh only). Sourced; check and
# its counters come from lib.sh.

# fx_acg <folder> <text>: the guard on a file holding <text> (printf's format, so \n is a line
# end), with the made-up id and release; FX_RC its exit status, <folder>/out.txt what it printed
fx_acg() {
  # shellcheck disable=SC2059 # (the text is the format, for its \n)
  printf "$2" >"$1/id.txt"
  FX_RC=0
  "$FX_ACG_GUARD" "$1/id.txt" "$FX_ACG_ID" 9.9.9 >"$1/out.txt" 2>&1 || FX_RC=$?
}
# fx_acg_build <folder> <text>: the same through build-d9mt.sh, with the id it records
fx_acg_build() {
  # shellcheck disable=SC2059
  printf "$2" >"$1/id.txt"
  FX_RC=0
  "$FX_ACG_BUILD" --check-air-codegen "$1/id.txt" >"$1/out.txt" 2>&1 || FX_RC=$?
}

# fx_air_codegen <air-codegen-guard.sh> <build-d9mt.sh> <folder>
fx_air_codegen() {
  local d=$3 id other why real lineage changed
  FX_ACG_GUARD=$1 FX_ACG_BUILD=$2
  id=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  other=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
  # (d9mt's own words, scripts/build-bridge.sh)
  why="no lineage: a new AIR codegen, every player's AIR cache recompiles once"
  FX_ACG_ID=$id
  mkdir -p "$d"

  fx_acg "$d" "AIR codegen $id ($why)\n"
  check "air-codegen: the recorded id with no lineage: passes ($FX_RC)" eval '[ "$FX_RC" = 0 ] && [ ! -s "$d/out.txt" ]'
  fx_acg "$d" "AIR codegen $id ($why)"
  check "air-codegen: the same line without its line end: passes ($FX_RC)" test "$FX_RC" = 0
  fx_acg "$d" "AIR codegen $other (lineage 9.9.9: players keep their AIR caches)\n"
  check "air-codegen: another id that a lineage carries back to the release: passes ($FX_RC)" test "$FX_RC" = 0

  rm "$d/id.txt"
  FX_RC=0; "$FX_ACG_GUARD" "$d/id.txt" "$id" 9.9.9 >"$d/out.txt" 2>&1 || FX_RC=$?
  check "air-codegen: no file: refused, and the message says what a different id costs ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "built:    no $d/id.txt" "$d/out.txt" && grep -q "recorded: AIR codegen $id " "$d/out.txt" && grep -q "every player.s shaders recompile again" "$d/out.txt"'
  fx_acg "$d" ""
  check "air-codegen: an empty file: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen $other ($why)\n"
  check "air-codegen: another id with no lineage: refused, with both ids in the message ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "built:    AIR codegen $other " "$d/out.txt" && grep -q "recorded: AIR codegen $id " "$d/out.txt"'
  fx_acg "$d" "AIR codegen $other (no lineage: not $id)\n"
  check "air-codegen: the recorded id inside another id's line: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "built: AIR codegen $id ($why)\n"
  check "air-codegen: text before the line: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen $id ($why) and more\n"
  check "air-codegen: text after the line: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen $other (lineage 0.1: x) (lineage 9.9.9: y)\n"
  check "air-codegen: a second pair of parentheses that names the release: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen ${id}0 ($why)\n"
  check "air-codegen: a longer id that starts with the recorded one: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen $id ($why)\nAIR codegen $other ($why)\n"
  check "air-codegen: a second line after the recorded id's: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen $other ($why)\nAIR codegen $id ($why)\n"
  check "air-codegen: the recorded id's line as the second line: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen $id (lineage 0.1.5.1: players keep their AIR caches)\n"
  check "air-codegen: the old lineage 0.1.5.1 line, even with the recorded id: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg "$d" "AIR codegen $other (lineage 9.9.90: players keep their AIR caches)\n"
  local longer=$FX_RC
  fx_acg "$d" "AIR codegen $other (lineage 9x9x9: players keep their AIR caches)\n"
  check "air-codegen: a lineage whose release only starts like this one, or has other characters for the dots: refused ($longer, $FX_RC)" \
    eval '[ "$longer" = 1 ] && [ "$FX_RC" = 1 ]'
  fx_acg "$d" "AIR codegen (lineage 9.9.9: players keep their AIR caches)\n"
  check "air-codegen: a lineage line without an id: refused ($FX_RC)" test "$FX_RC" = 1

  # a wrong call is neither a pass nor a refusal: an id nobody filled in passes nothing
  printf 'AIR codegen %s (lineage 9.9.9: players keep their AIR caches)\n' "$other" >"$d/id.txt"
  FX_RC=0; "$FX_ACG_GUARD" "$d/id.txt" not-an-id-yet 9.9.9 >"$d/out.txt" 2>&1 || FX_RC=$?
  check "air-codegen: a recorded id that isn't 64 hex digits: a wrong call, even on a lineage line that would pass ($FX_RC)" \
    eval '[ "$FX_RC" = 2 ] && grep -q "the recorded id is not 64 hex digits" "$d/out.txt"'
  FX_RC=0; "$FX_ACG_GUARD" "$d/id.txt" "$id" >"$d/out.txt" 2>&1 || FX_RC=$?
  local noarg=$FX_RC
  FX_RC=0; "$FX_ACG_GUARD" "$d/id.txt" "$id" "" >"$d/out.txt" 2>&1 || FX_RC=$?
  check "air-codegen: no release, or an empty one: a wrong call ($noarg, $FX_RC)" eval '[ "$noarg" = 2 ] && [ "$FX_RC" = 2 ]'

  # the real call: build-d9mt.sh's own id and release
  real=$(sed -n 's/^AIR_CODEGEN=//p' "$FX_ACG_BUILD")
  lineage=$(sed -n 's/^AIR_LINEAGE=//p' "$FX_ACG_BUILD")
  check "air-codegen: build-d9mt.sh records one id of 64 hex digits, and not 0.1.7's ($real)" \
    eval '[[ $real =~ ^[0-9a-f]{64}$ ]] && [ "$real" != 38243f7b8e00a9493710fa1072a108c393acbcb2d4f7b74f6e6a681f3bb54a93 ]'
  fx_acg_build "$d" "AIR codegen $real ($why)\n"
  check "air-codegen: build-d9mt.sh --check-air-codegen, the id it records: passes ($FX_RC)" test "$FX_RC" = 0
  # one digit changed: the first, to another hex digit
  case $real in 0*) changed=1${real#?} ;; *) changed=0${real#?} ;; esac
  fx_acg_build "$d" "AIR codegen $changed ($why)\n"
  check "air-codegen: build-d9mt.sh, one digit of the id changed: refused, with both ids in the message ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "built:    AIR codegen $changed " "$d/out.txt" && grep -q "recorded: AIR codegen $real " "$d/out.txt"'
  fx_acg_build "$d" "AIR codegen 38243f7b8e00a9493710fa1072a108c393acbcb2d4f7b74f6e6a681f3bb54a93 (lineage 0.1.5.1: players keep their AIR caches)\n"
  check "air-codegen: build-d9mt.sh, 0.1.7's line: refused ($FX_RC)" test "$FX_RC" = 1
  fx_acg_build "$d" "AIR codegen $other (lineage $lineage: players keep their AIR caches)\n"
  check "air-codegen: build-d9mt.sh, another id with lineage $lineage: passes ($FX_RC)" test "$FX_RC" = 0
  printf 'AIR codegen %s (%s)\n' "$real" "$why" >"$d/id.txt"
  FX_RC=0; ( cd "$d" && "$FX_ACG_BUILD" --check-air-codegen id.txt ) >"$d/out.txt" 2>&1 || FX_RC=$?
  local rel=$FX_RC
  FX_RC=0; "$FX_ACG_BUILD" --check-air-codegen >"$d/out.txt" 2>&1 || FX_RC=$?
  check "air-codegen: build-d9mt.sh reads a relative name in the caller's folder, and without a file it is a wrong call that builds nothing ($rel, $FX_RC)" \
    eval '[ "$rel" = 0 ] && [ "$FX_RC" = 64 ] && grep -q "^usage: " "$d/out.txt"'
}
