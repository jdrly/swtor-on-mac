#!/bin/bash
# The release's check of the AIR codegen id d9mt's bridge build reports (d9mt ADR-0006).
# scripts/build-d9mt.sh calls it after the bridge is built, and fixture group air-codegen
# (scripts/test-fixtures.sh) tests it without building d9mt.
#
#   scripts/air-codegen-guard.sh <air-codegen-id.txt> <recorded id, 64 hex> <release>
#
# d9mt's scripts/build-bridge.sh writes one line into build/bridge/air-codegen-id.txt. The guard
# passes only when the file is that one line and the line is, from its first character to its
# last, one of
#   AIR codegen <the recorded id> (no lineage: <text>)
#   AIR codegen <64 hex> (lineage <release>: <text>)
# The second form is a later toolchain whose id d9mt's lineage table carries back to the
# release's AIR cache. <text> has no parentheses and no control characters. Anything else is
# refused: another id, another release's lineage, the recorded id somewhere inside another line,
# a second line, a NUL byte or another control character anywhere, no file.
#
# Exit status: 0 the id is the recorded one; 1 refused, with the built line and the recorded id
# on stderr; 2 a wrong call. A recorded id that isn't 64 hex digits is a wrong call, so an id
# nobody filled in passes nothing.
set -u
# bytes, not a locale's characters: [0-9a-f] is those sixteen and nothing a collation adds
export LC_ALL=C
usage() { echo "usage: $0 <air-codegen-id.txt> <recorded id, 64 hex> <release>" >&2; exit 2; }
[ $# = 3 ] || usage
file=$1 id=$2 release=$3
hex='^[0-9a-f]{64}$'
[[ $id =~ $hex ]] || { echo "$0: the recorded id is not 64 hex digits ('$id')" >&2; exit 2; }
rel='^[0-9]+(\.[0-9]+)*$'
[[ $release =~ $rel ]] || { echo "$0: the release is not a version number ('$release')" >&2; exit 2; }

refuse() {
  echo "winemetal.so's AIR codegen is not the one this release records." >&2
  echo "  built:    $1" >&2
  echo "  recorded: AIR codegen $id (no lineage), or an id with lineage $release" >&2
  echo "A different id means every player's shaders recompile again. Build with the toolchain the" >&2
  echo "id was recorded with, or record the new id on purpose (AIR_CODEGEN in scripts/build-d9mt.sh)." >&2
  exit 1
}

[ -f "$file" ] || refuse "no $file"
# A command substitution drops NUL bytes, so a line with one in it would be checked without it:
# count the bytes with and without them first.
all=$(wc -c <"$file") && plain=$(tr -d '\000' <"$file" | wc -c) || refuse "$file can't be read"
[ "$all" -eq "$plain" ] || refuse "$file has NUL bytes"
# the whole file, less one final newline (the x keeps the others from the command substitution)
line=$(cat "$file" && echo x) || refuse "$file can't be read"
line=${line%x}
line=${line%$'\n'}
[ -n "$line" ] || refuse "$file is empty"
case $line in *$'\n'*) refuse "$file has more than one line, the first: $(head -n 1 "$file")" ;; esac
recorded="^AIR codegen $id \\(no lineage: [^()[:cntrl:]]*\\)\$"
carried="^AIR codegen [0-9a-f]{64} \\(lineage ${release//./\\.}: [^()[:cntrl:]]*\\)\$"
[[ $line =~ $recorded ]] || [[ $line =~ $carried ]] || refuse "$line"
