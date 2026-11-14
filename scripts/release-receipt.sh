#!/bin/bash
# The release receipt: which source tree and which files a release candidate is, so the files
# that passed the gates are the files that get published (docs/building.md, *Releasing*; #47).
# scripts/release.sh writes it next to the assets, as <dir>/RECEIPT, where <dir> is
# release/<version> with the signed app, the DMG, the deltas and appcast.xml:
#
#   receipt 1
#   version 0.1.9                       app.properties of the app in <dir>
#   build 0.1.9                         (CFBundleVersion)
#   channel release                     release or dev
#   source <git tree id> clean          the app's VERSIONS: the tree it was built from, and
#                                       whether the working tree had changes ("changed")
#   notes <sha256>                      the release notes the build used
#   file <sha256> <name>                the DMG, each delta and appcast.xml
#   gate <name> pass|fail <UTC time>    a gate run on exactly these files (added by "gate")
#
# Nothing else: no keys, no user names, no paths. Verify refuses any other line.
#
#   scripts/release-receipt.sh write <dir> <notes>
#       writes <dir>/RECEIPT. Written again after a notes edit (a new feed and notes), it keeps
#       the gate lines when the DMG and the deltas are unchanged.
#   scripts/release-receipt.sh gate <dir> <name> pass|fail
#       records a gate run, after checking that <dir>'s files are the receipt's
#   scripts/release-receipt.sh verify <dir> [--commit <rev> --notes <file>]
#       read-only, before publishing: the files in <dir> against their hashes, the DMG's name, the
#       channel and the feed's versions against the receipt; with --commit, the commit to be
#       tagged: its tree is the receipt's (a squash merge's equal tree passes; a tree that
#       differs only in release-notes/<version>.md passes if those notes are the receipt's), the
#       build was from a clean tree, its build.sh's APP_VERSION and its notes are the receipt's,
#       and so is <file>, the notes the publish uploads. The build number is checked with
#       bundle_version from the build.sh beside this script; nothing of <rev> runs. Runs git in
#       the current directory.
#   scripts/release-receipt.sh verify <dir> --release <tag>
#       after publishing: downloads the release's assets (gh) and compares them with the
#       receipt, the same files and the same hashes, and names each one it compared
#
# Exit status: 0 passed; 1 a check failed; 2 usage.
set -euo pipefail
REPO=jdrly/swtor-on-mac
HERE=$(cd "$(dirname "$0")" && pwd)
APP_NAME="SWTOR on Mac.app"

die() { echo "release-receipt: $*" >&2; exit 1; }
usage() { sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
fails=0
ok() { echo "ok   $*"; }
no() { echo "FAIL $*"; fails=$((fails + 1)); }

# field <receipt> <key>: the value of the receipt's one <key> line
field() { sed -n "s/^$2 //p" "$1"; }

# well_formed <receipt>: every line in the grammar above, and each single field exactly once
well_formed() {
  local r=$1 k n bad
  bad=$(grep -Ev '^(receipt 1|version [0-9][0-9A-Za-z.-]*|build [0-9][0-9.]*|channel (release|dev)|source ([0-9a-f]{40}|[0-9a-f]{64}) (clean|changed)|source unknown|notes [0-9a-f]{64}|file [0-9a-f]{64} [A-Za-z0-9._-]+|gate [a-z0-9-]+ (pass|fail) [0-9TZ:-]+)$' "$r" || true)
  [ -z "$bad" ] || { no "receipt: lines outside its format: $(printf '%s' "$bad" | head -3 | tr '\n' '|')"; return 1; }
  for k in receipt version build channel source notes; do
    n=$(grep -c "^$k " "$r" || true)
    [ "$n" = 1 ] || { no "receipt: $n '$k' lines, not 1"; return 1; }
  done
  grep -q '^file ' "$r" || { no "receipt: no files"; return 1; }
}

# check_files <receipt> <dir>: each file line's file in <dir>, with its hash
check_files() {
  local r=$1 d=$2 h name got
  while read -r _ h name; do
    if [ ! -f "$d/$name" ]; then no "$name: missing"; continue; fi
    got=$(sha "$d/$name")
    if [ "$got" = "$h" ]; then ok "$name $got"; else no "$name: sha256 $got, the receipt has $h"; fi
  done < <(grep '^file ' "$r")
}

# check_versions <receipt> <dir>: the DMG named for the version, the channel the version's,
# and the feed (a release has one) naming the version and the build
check_versions() {
  local r=$1 d=$2 v b c want short long
  v=$(field "$r" version) b=$(field "$r" build) c=$(field "$r" channel)
  sed -n 's/^file [0-9a-f]* //p' "$r" | grep -qxF "SWTOR-on-Mac-$v.dmg" && ok "the DMG is SWTOR-on-Mac-$v.dmg" ||
    no "no file SWTOR-on-Mac-$v.dmg in the receipt"
  case "$v" in *-*) want=dev ;; *) want=release ;; esac
  [ "$c" = "$want" ] && ok "channel $c for $v" || no "channel $c for $v, which is a $want version"
  if grep -q '^file [0-9a-f]* appcast\.xml$' "$r"; then
    [ -f "$d/appcast.xml" ] || return 0   # check_files reported it
    short=$(sed -n 's|.*<sparkle:shortVersionString>\([^<]*\)</sparkle:shortVersionString>.*|\1|p' "$d/appcast.xml" | sort -u)
    long=$(sed -n 's|.*<sparkle:version>\([^<]*\)</sparkle:version>.*|\1|p' "$d/appcast.xml" | sort -u)
    [ "$short" = "$v" ] && [ "$long" = "$b" ] && ok "the feed names $v (build $b)" ||
      no "the feed names $(echo $short) (build $(echo $long)), the receipt $v (build $b)"
  elif [ "$c" = release ]; then
    no "a release without appcast.xml in the receipt"
  fi
}

# check_commit <receipt> <rev>: the commit to be tagged against the receipt
check_commit() {
  local r=$1 rev=$2 notes=$3 v b src tree state t diff want_b app_v
  v=$(field "$r" version) b=$(field "$r" build) src=$(field "$r" source)
  git rev-parse -q --verify "$rev^{commit}" >/dev/null || { no "$rev: not a commit here"; return; }
  tree=${src% *} state=${src##* }
  [ "$state" = clean ] && ok "built from a clean tree" || no "built from a working tree with changes, or not from git ($src)"
  t=$(git rev-parse "$rev^{tree}")
  if [ "$t" = "$tree" ]; then
    ok "$rev's tree is the receipt's ($t)"
  elif ! git cat-file -e "$tree^{tree}" 2>/dev/null; then
    no "$rev's tree $t isn't the receipt's $tree, which this repository doesn't have"
  else
    diff=$(git diff --name-only "$tree" "$t")
    if [ "$diff" = "release-notes/$v.md" ]; then ok "$rev's tree differs from the receipt's in release-notes/$v.md only"
    else no "$rev's tree $t isn't the receipt's $tree: $(printf '%s' "$diff" | head -5 | tr '\n' ' ')"; fi
  fi
  app_v=$(git show "$rev:build.sh" | sed -n 's/^APP_VERSION=\${SWTOR_ON_MAC_VERSION:-\(.*\)}$/\1/p')
  [ "$app_v" = "$v" ] && ok "build.sh at $rev: APP_VERSION $v" || no "build.sh at $rev: APP_VERSION $app_v, the receipt $v"
  # the mapping of the build.sh beside this script, never code from <rev>
  want_b=$(eval "$(sed -n '/^bundle_version() {$/,/^}$/p' "$HERE/../build.sh")"; bundle_version "$v" 2>&1) || want_b="(refused: $want_b)"
  [ "$want_b" = "$b" ] && ok "bundle_version $v = $b" || no "bundle_version $v is $want_b, the receipt has $b"
  if git cat-file -e "$rev:release-notes/$v.md" 2>/dev/null &&
    [ "$(git show "$rev:release-notes/$v.md" | shasum -a 256 | cut -d' ' -f1)" = "$(field "$r" notes)" ]; then
    ok "release-notes/$v.md at $rev is the receipt's"
  else
    no "release-notes/$v.md at $rev isn't the receipt's notes"
  fi
  if [ -f "$notes" ] && [ "$(sha "$notes")" = "$(field "$r" notes)" ]; then ok "the notes to upload ($notes) are the receipt's"
  else no "the notes to upload ($notes) aren't the receipt's"; fi
}

# check_release <receipt> <tag>: the published assets, downloaded, against the receipt
check_release() {
  local r=$1 tag=$2 tmp names want
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/release-receipt.XXXXXX")
  if ! gh release download "$tag" --repo "$REPO" --dir "$tmp" >/dev/null; then
    rm -rf "$tmp"; no "gh release download $tag failed"; return
  fi
  names=$(cd "$tmp" && ls -A | sort)
  want=$(sed -n 's/^file [0-9a-f]* //p' "$r" | sort)
  [ "$names" = "$want" ] && ok "$tag has the receipt's $(printf '%s\n' "$want" | grep -c .) files, no others" ||
    no "$tag's assets ($(echo $names)) aren't the receipt's files ($(echo $want))"
  check_files "$r" "$tmp"
  rm -rf "$tmp"
}

cmd=${1:-}; [ $# -ge 2 ] || usage
dir=${2%/}; R="$dir/RECEIPT"
case "$cmd" in
  write)
    [ $# = 3 ] || usage
    notes=$3 res="$dir/$APP_NAME/Contents/Resources"
    [ -f "$res/app.properties" ] && [ -f "$res/VERSIONS" ] || die "no $APP_NAME in $dir"
    [ -f "$notes" ] || die "no release notes at $notes"
    v=$(sed -n 's/^version=//p' "$res/app.properties")
    [ -f "$dir/SWTOR-on-Mac-$v.dmg" ] || die "no SWTOR-on-Mac-$v.dmg in $dir"
    src=$(sed -n 's/^source //p' "$res/VERSIONS"); [ -n "$src" ] || src=unknown
    tmp="$R.tmp"
    { echo "receipt 1"
      echo "version $v"
      echo "build $(sed -n 's/^build=//p' "$res/app.properties")"
      echo "channel $(sed -n 's/^channel=//p' "$res/app.properties")"
      echo "source $src"
      echo "notes $(sha "$notes")"
      for f in "$dir/SWTOR-on-Mac-$v.dmg" "$dir/SWTOR-on-Mac-$v"-from-*.delta "$dir/appcast.xml"; do
        if [ -f "$f" ]; then echo "file $(sha "$f") ${f##*/}"; fi
      done
    } >"$tmp"
    # a notes edit: the same DMG and deltas keep the gate runs made on them
    if [ -f "$R" ]; then
      if [ "$(grep '^file ' "$R" | grep -v ' appcast\.xml$')" = "$(grep '^file ' "$tmp" | grep -v ' appcast\.xml$')" ]; then
        grep '^gate ' "$R" >>"$tmp" || true
      else
        echo "release-receipt: the DMG or the deltas changed; the old gate runs don't apply" >&2
      fi
    fi
    fails=0; well_formed "$tmp" >/dev/null || { cat "$tmp" >&2; rm -f "$tmp"; die "the receipt isn't well formed"; }
    mv "$tmp" "$R"
    echo "release-receipt: $R ($(grep -c '^file ' "$R") files, source $src)" ;;
  gate)
    [ $# = 4 ] || usage
    case "$3" in ''|*[!a-z0-9-]*) die "a gate's name is lower-case letters, digits and -" ;; esac
    case "$4" in pass|fail) ;; *) usage ;; esac
    [ -f "$R" ] || die "no receipt at $R"
    well_formed "$R" && check_files "$R" "$dir" >/dev/null
    [ "$fails" = 0 ] || die "$dir's files aren't the receipt's: not recording the gate"
    echo "gate $3 $4 $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$R"
    echo "release-receipt: gate $3 $4 recorded" ;;
  verify)
    [ -f "$R" ] || die "no receipt at $R"
    mode=${3:-} arg=${4:-} notes=""
    case "$mode" in
      '') [ $# = 2 ] || usage ;;
      --release) [ $# = 4 ] || usage ;;
      --commit) [ $# = 6 ] && [ "$5" = --notes ] || usage; notes=$6 ;;
      *) usage ;;
    esac
    echo "== $R: $(field "$R" version) $(field "$R" channel), source $(field "$R" source)"
    if well_formed "$R"; then
      if [ "$mode" = --release ]; then
        check_release "$R" "$arg"
      else
        check_files "$R" "$dir"
        check_versions "$R" "$dir"
        [ "$mode" != --commit ] || check_commit "$R" "$arg" "$notes"
      fi
      sed -n 's/^gate \([^ ]*\) \([^ ]*\) \(.*\)/gate: \1 \2 (\3)/p' "$R"
    fi
    if [ "$fails" = 0 ]; then echo "verify: PASS"; else echo "verify: FAIL ($fails)"; exit 1; fi ;;
  *) usage ;;
esac
