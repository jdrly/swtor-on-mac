# shellcheck shell=bash
# The d9mt bridge over another version, in sections 15 and 16 of scripts/test-sandbox.sh: the
# engine's winemetal.so and winemetal.dll and the prefix's copy of winemetal.dll stay the other
# version's, unless the d9mt pin moved with a new bridge and they are now exactly this app's
# (0.1.6 over 0.1.5.1: d9mt b532e9c's bridge, #110 and #122). A changed bridge with the same pin,
# or one that isn't this app's, still fails. Fixture group bridge checks the rule on planted apps
# and engines, without Wine. Sourced; check, macho_same and the counters come from lib.sh.

# bridge_moved <app> <other app>: the d9mt pin moved (their Resources/d9mt/VERSION, the d9mt
# commit, differ) and with it the bridge (winemetal.so's code or winemetal.dll)
bridge_moved() {
  local a=$1/Contents/Resources/d9mt o=$2/Contents/Resources/d9mt
  [ -s "$a/VERSION" ] && [ -s "$o/VERSION" ] && ! cmp -s "$a/VERSION" "$o/VERSION" || return 1
  ! cmp -s "$a/winemetal.dll" "$o/winemetal.dll" || ! macho_same "$a/winemetal.so" "$o/winemetal.so"
}
# bridge_pinned <app> <other app> <engine> <system32>: bridge_moved, and the engine's winemetal.so
# is <app>'s code (its LC_UUID included), the engine's winemetal.dll and <system32>'s copy <app>'s
# byte for byte
bridge_pinned() {
  local a=$1/Contents/Resources/d9mt
  bridge_moved "$1" "$2" &&
    macho_same "$a/winemetal.so" "$3/lib/wine/x86_64-unix/winemetal.so" &&
    cmp -s "$a/winemetal.dll" "$3/lib/wine/x86_64-windows/winemetal.dll" &&
    cmp -s "$a/winemetal.dll" "$4/winemetal.dll"
}
# bridge_prefix_extra <prefix diff> <moved|kept>: the changed prefix paths other than d9mt's
# d3d9.dll and, when the bridge moved with the pin, its winemetal.dll
bridge_prefix_extra() {
  local w=./drive_c/windows/system32/d3d9.dll
  [ "$2" != moved ] || w=./drive_c/windows/system32/winemetal.dll
  grep -F -v -x -e ./drive_c/windows/system32/d3d9.dll -e "$w" -- "$1" || true
}

# fx_bridge <app> <folder>: the rule on planted apps (this one's bridge copied from <app>, another
# build's: <app>'s winemac.so and a text file) and an engine and prefix with this app's bridge
fx_bridge() {
  local app=$1 d=$2 a e y m x this other
  for x in this other samepin nobridge; do mkdir -p "$d/$x.app/Contents/Resources/d9mt"; done
  a="$d/this.app/Contents/Resources/d9mt"
  cp "$app/Contents/Resources/d9mt/winemetal.so" "$app/Contents/Resources/d9mt/winemetal.dll" "$a/"
  echo 1111111 >"$a/VERSION"
  for x in other samepin; do
    cp "$app/Contents/Resources/wine/winemac.so" "$d/$x.app/Contents/Resources/d9mt/winemetal.so"
    echo "another build" >"$d/$x.app/Contents/Resources/d9mt/winemetal.dll"
  done
  echo 2222222 >"$d/other.app/Contents/Resources/d9mt/VERSION"
  echo 1111111 >"$d/samepin.app/Contents/Resources/d9mt/VERSION"
  # (a pin that moved without a new bridge, 0.1.7-dev.1 over 0.1.6)
  cp "$a/winemetal.so" "$a/winemetal.dll" "$d/nobridge.app/Contents/Resources/d9mt/"
  echo 2222222 >"$d/nobridge.app/Contents/Resources/d9mt/VERSION"
  e="$d/engine"; y="$d/system32"
  mkdir -p "$e/lib/wine/x86_64-unix" "$e/lib/wine/x86_64-windows" "$y"
  cp "$a/winemetal.so" "$e/lib/wine/x86_64-unix/"; cp "$a/winemetal.dll" "$e/lib/wine/x86_64-windows/"; cp "$a/winemetal.dll" "$y/"
  this="$d/this.app" other="$d/other.app"
  check "bridge: the pin moved with a new bridge, the engine's and the prefix's are this app's: accepted" bridge_pinned "$this" "$other" "$e" "$y"
  check "bridge: a new bridge with the same pin: not accepted" eval '! bridge_pinned "$this" "$d/samepin.app" "$e" "$y"'
  check "bridge: the pin moved, the bridge didn't: not a bridge change (the checks as before)" eval '! bridge_moved "$this" "$d/nobridge.app"'
  rm "$d/other.app/Contents/Resources/d9mt/VERSION"
  check "bridge: another version without a d9mt VERSION: not accepted" eval '! bridge_pinned "$this" "$other" "$e" "$y"'
  echo 2222222 >"$d/other.app/Contents/Resources/d9mt/VERSION"
  cp "$d/other.app/Contents/Resources/d9mt/winemetal.so" "$e/lib/wine/x86_64-unix/"
  check "bridge: the engine's winemetal.so isn't this app's: not accepted" eval '! bridge_pinned "$this" "$other" "$e" "$y"'
  cp "$a/winemetal.so" "$e/lib/wine/x86_64-unix/"
  echo "a third build" >"$e/lib/wine/x86_64-windows/winemetal.dll"
  check "bridge: the engine's winemetal.dll isn't this app's: not accepted" eval '! bridge_pinned "$this" "$other" "$e" "$y"'
  cp "$a/winemetal.dll" "$e/lib/wine/x86_64-windows/"; echo "a third build" >"$y/winemetal.dll"
  check "bridge: the prefix's winemetal.dll isn't this app's: not accepted" eval '! bridge_pinned "$this" "$other" "$e" "$y"'
  m="$d/prefix.diff"
  printf '%s\n' ./drive_c/windows/system32/d3d9.dll ./drive_c/windows/system32/winemetal.dll >"$m"
  check "bridge: prefix, moved: d3d9.dll and winemetal.dll changed, nothing reported" eval '[ -z "$(bridge_prefix_extra "$m" moved)" ]'
  check "bridge: prefix, kept: a changed winemetal.dll is reported" eval '[ "$(bridge_prefix_extra "$m" kept)" = ./drive_c/windows/system32/winemetal.dll ]'
  echo ./drive_c/windows/syswow64/winemetal.dll >>"$m"
  check "bridge: prefix, moved: any other change is still reported" eval '[ "$(bridge_prefix_extra "$m" moved)" = ./drive_c/windows/syswow64/winemetal.dll ]'
  rm -rf "$d"
}
