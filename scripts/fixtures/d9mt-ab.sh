# shellcheck shell=bash
# Development builds' d9mt A/B switches (scripts/d9mt-ab.sh) on a planted install: an env that
# reads d9mt-ab.env as a development build's does, in a sandbox root of its own, without the app,
# Wine or a game start. The checks read what the game would get, by sourcing that env. Fixture
# group d9mt-ab (scripts/test-fixtures.sh only) covers the air-legacy switch and its own caches,
# and Mullion's safety switches;
# the other switches are checked by scripts/test-sandbox.sh's section 4d on an installed
# development build. Sourced; check and its counters come from lib.sh.

# fx_ab [d9mt-ab.sh's arguments]: the script in the planted sandbox; FX_RC its exit status,
# $FX_AB_D/out.txt what it printed
fx_ab() {
  FX_RC=0
  SWTOR_ON_MAC_ROOT="$FX_AB_D/root" "$FX_AB_SCRIPT" "$@" >"$FX_AB_D/out.txt" 2>&1 || FX_RC=$?
}
# fx_ab_env <variable>: its value as the game gets it from the planted env, or <unset>
fx_ab_env() { ( set -a; . "$FX_AB_SOM/env"; set +a; eval "printf '%s' \"\${$1-<unset>}\"" ); }

# fx_d9mt_ab <d9mt-ab.sh> <folder>
fx_d9mt_ab() {
  local d=$2 c
  FX_AB_SCRIPT=$1 FX_AB_D=$2
  FX_AB_SOM="$d/root/home/Library/Application Support/SWTOR on Mac"
  c="$d/root/home/Library/Caches/SWTOR on Mac/d9mt-ab"
  mkdir -p "$FX_AB_SOM"
  # (the lines som.sh's write_env gives a development build's env)
  printf 'D9MT_STATE_CACHE="%s"\n[ ! -f "%s" ] || . "%s"\n' "$d/usercache/d9mt/state" "$FX_AB_SOM/d9mt-ab.env" "$FX_AB_SOM/d9mt-ab.env" >"$FX_AB_SOM/env"

  fx_ab air-legacy
  check "d9mt-ab: air-legacy: the game gets D9MT_AIR_LEGACY=1, and the switch is named ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_ab_env D9MT_AIR_LEGACY)/$(fx_ab_env SWTOR_D9MT_AB)" = 1/air-legacy ]'
  check "d9mt-ab: air-legacy: a shader cache and pipeline archives of its own, in the sandbox's d9mt-ab/air-legacy" \
    eval '[ "$(fx_ab_env D9MT_AIR_CACHE)" = "$c/air-legacy/air-cache.sqlite3" ] && [ "$(fx_ab_env D9MT_PSO_ARCHIVE_DIR)" = "$c/air-legacy/pso" ]'
  check "d9mt-ab: air-legacy: the state cache stays the normal one" test "$(fx_ab_env D9MT_STATE_CACHE)" = "$d/usercache/d9mt/state"
  fx_ab
  check "d9mt-ab: the status names air-legacy and shows its three lines ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -qx "d9mt A/B switches for the next game start: air-legacy" "$d/out.txt" && [ "$(grep -c -e "^  D9MT_AIR_LEGACY=1$" -e "^  D9MT_AIR_CACHE=" -e "^  D9MT_PSO_ARCHIVE_DIR=" "$d/out.txt")" = 3 ]'

  # the game made its caches there; the next call keeps them, without the note for a cold name
  mkdir -p "$c/air-legacy/pso"
  echo kept >"$c/air-legacy/air-cache.sqlite3"
  fx_ab air-legacy air-legacy
  check "d9mt-ab: air-legacy again, its caches there: the same caches, kept, and no \"used before\" note ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && ! grep -q "used before" "$d/out.txt" && [ "$(cat "$c/air-legacy/air-cache.sqlite3")" = kept ] && [ "$(fx_ab_env D9MT_AIR_CACHE)" = "$c/air-legacy/air-cache.sqlite3" ]'
  check "d9mt-ab: air-legacy given twice: named once, one D9MT_AIR_LEGACY line" \
    eval '[ "$(fx_ab_env SWTOR_D9MT_AB)" = air-legacy ] && [ "$(grep -c "^D9MT_AIR_LEGACY=" "$FX_AB_SOM/d9mt-ab.env")" = 1 ]'

  fx_ab air-legacy cold=c1
  check "d9mt-ab: air-legacy cold=c1: the cold name's caches, D9MT_AIR_LEGACY=1 still ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_ab_env D9MT_AIR_LEGACY)" = 1 ] && [ "$(fx_ab_env D9MT_AIR_CACHE)" = "$c/c1/air-cache.sqlite3" ] && [ "$(fx_ab_env D9MT_PSO_ARCHIVE_DIR)" = "$c/c1/pso" ]'
  fx_ab cold=c2 air-legacy
  check "d9mt-ab: cold=c2 air-legacy, the other order: the cold name's caches too ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_ab_env D9MT_AIR_LEGACY)" = 1 ] && [ "$(fx_ab_env D9MT_AIR_CACHE)" = "$c/c2/air-cache.sqlite3" ] && [ "$(grep -c "^D9MT_AIR_CACHE=" "$FX_AB_SOM/d9mt-ab.env")" = 1 ]'
  fx_ab cold=c3
  check "d9mt-ab: cold=c3 alone: its caches as before, no D9MT_AIR_LEGACY ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_ab_env D9MT_AIR_LEGACY)" = "<unset>" ] && [ "$(fx_ab_env D9MT_AIR_CACHE)" = "$c/c3/air-cache.sqlite3" ]'
  fx_ab air-legacy
  fx_ab cold=air-legacy
  check "d9mt-ab: cold=air-legacy: refused, the folder is the switch's own, and the switches stay ($FX_RC)" \
    eval '[ "$FX_RC" = 2 ] && grep -q "cold=air-legacy: " "$d/out.txt" && [ "$(fx_ab_env SWTOR_D9MT_AB)" = air-legacy ]'
  fx_ab pfv
  check "d9mt-ab: pfv after air-legacy: no D9MT_AIR_LEGACY and d9mt's own caches again ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_ab_env D9MT_TEX_PFV)/$(fx_ab_env D9MT_AIR_LEGACY)/$(fx_ab_env D9MT_AIR_CACHE)/$(fx_ab_env D9MT_PSO_ARCHIVE_DIR)" = "1/<unset>/<unset>/<unset>" ]'

  # Mullion's safety switches (off in the pinned build): each one's variable, named together
  fx_ab mullion-guard-static mullion-check-ranges mullion-reset-waits mullion-msaa-auto
  check "d9mt-ab: Mullion's four safety switches: the game gets each one's variable, and they are named ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_ab_env MULLION_D3D12_GUARD_STATIC_RANGES)/$(fx_ab_env MULLION_D3D12_CHECK_RANGES)/$(fx_ab_env MULLION_D3D12_RESET_WAITS)/$(fx_ab_env MULLION_TEX_MSAA_COMPRESSION)" = 1/1/1/auto ] && [ "$(fx_ab_env SWTOR_D9MT_AB)" = "mullion-guard-static mullion-check-ranges mullion-reset-waits mullion-msaa-auto" ]'
  fx_ab mullion-check-ranges
  check "d9mt-ab: mullion-check-ranges alone: the other three off again ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_ab_env MULLION_D3D12_GUARD_STATIC_RANGES)/$(fx_ab_env MULLION_D3D12_CHECK_RANGES)/$(fx_ab_env MULLION_D3D12_RESET_WAITS)/$(fx_ab_env MULLION_TEX_MSAA_COMPRESSION)" = "<unset>/1/<unset>/<unset>" ]'

  fx_ab air-legacy
  fx_ab reset
  check "d9mt-ab: reset after air-legacy: no switches, its caches stay for the next time ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ ! -e "$FX_AB_SOM/d9mt-ab.env" ] && [ "$(fx_ab_env D9MT_AIR_LEGACY)" = "<unset>" ] && [ "$(cat "$c/air-legacy/air-cache.sqlite3")" = kept ]'
  fx_ab reset --clean
  check "d9mt-ab: reset --clean: air-legacy's caches go with the other test caches ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ ! -e "$c" ] && [ -d "$FX_AB_SOM" ]'
}
