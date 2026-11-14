# shellcheck shell=bash
# The release receipt (#47): scripts/release-receipt.sh on a planted git repository (this
# repository's build.sh with another APP_VERSION, release notes, a source file) and planted
# release files (an app with app.properties and VERSIONS, a DMG, a delta, a feed). Each control
# changes one input and must make verify fail before the upload a publish would do, which a
# stand-in gh records; an unchanged tree after a squash merge, and a notes-only commit with the
# receipt written again, must pass. Also: the packaged app's VERSIONS names its source tree, and
# a receipt holds nothing but its own fields.

fx_release_receipt() {
  local rr=$1 buildsh=$2 app=$3 dir=$4 g v=9.8.7 src t_base t_feat sq c out
  mkdir -p "$dir/bin"
  src=$(sed -n 's/^source //p' "$app/Contents/Resources/VERSIONS")
  if printf '%s\n' "$src" | piped -Ex '([0-9a-f]{40}|[0-9a-f]{64}) (clean|changed)|unknown'; then
    ok "release-receipt: the app's VERSIONS names its source tree (source $src)"
  else
    bad "release-receipt: the app's VERSIONS has no source line in the receipt's format ('$src')"
  fi

  # a stand-in gh: records every call; "release download" copies $FX_ASSETS into --dir
  cat >"$dir/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >>"$FX_GH_LOG"
if [ "$1 $2" = "release download" ]; then
  while [ $# -gt 0 ]; do [ "$1" = --dir ] && d=$2; shift; done
  cp "$FX_ASSETS"/* "$d"/
fi
EOF
  chmod 755 "$dir/bin/gh"
  export FX_GH_LOG="$dir/gh.log" FX_ASSETS="$dir/assets"

  g="$dir/repo"
  mkdir -p "$g/release-notes" "$g/src"
  sed "s/^APP_VERSION=.*/APP_VERSION=\${SWTOR_ON_MAC_VERSION:-$v}/" "$buildsh" >"$g/build.sh"
  printf '## SWTOR on Mac %s\n\nA fixture.\n' "$v" >"$g/release-notes/$v.md"
  echo base >"$g/src/app.txt"
  fx_git() { git -C "$g" -c init.defaultBranch=main -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
  fx_git init -q && fx_git symbolic-ref HEAD refs/heads/main && fx_git add -A && fx_git commit -qm base
  t_base=$(fx_git rev-parse 'HEAD^{tree}')
  fx_git checkout -qb feature
  echo feature >"$g/src/app.txt"
  fx_git commit -qam "a change"
  t_feat=$(fx_git rev-parse 'HEAD^{tree}')
  # the release candidate, built from feature's tree: rr_rel <name> [<source>] makes $dir/<name>
  rr_rel() {
    local d="$dir/$1" res
    res="$d/SWTOR on Mac.app/Contents/Resources"
    mkdir -p "$res"
    printf 'version=%s\nbuild=%s\nchannel=release\n' "$v" "$v" >"$res/app.properties"
    printf 'app %s\nsource %s\n' "$v" "${2:-$t_feat clean}" >"$res/VERSIONS"
    printf 'a disk image\n' >"$d/SWTOR-on-Mac-$v.dmg"
    printf 'a delta\n' >"$d/SWTOR-on-Mac-$v-from-9.8.6.delta"
    printf '<sparkle:version>%s</sparkle:version>\n<sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "$v" "$v" >"$d/appcast.xml"
    "$rr" write "$d" "$g/release-notes/$v.md" >/dev/null
  }
  # rr_publish <reldir> <rev>: verify, then the upload a publish makes (the stand-in gh)
  rr_publish() { (cd "$g" && PATH="$dir/bin:$PATH" "$rr" verify "$1" --commit "$2" >"$dir/out.txt" 2>&1 &&
    PATH="$dir/bin:$PATH" gh release create "v$v" --target "$2" "$1/SWTOR-on-Mac-$v.dmg"); }
  rr_uploaded() { grep -q '^release create' "$FX_GH_LOG" 2>/dev/null; }
  # rr_refused <what> <reldir> <rev> <expected FAIL text>: verify fails with that, and nothing is uploaded
  rr_refused() {
    rm -f "$FX_GH_LOG"
    if rr_publish "$2" "$3"; then bad "release-receipt: $1: verify passed"
    elif rr_uploaded; then bad "release-receipt: $1: uploaded after a failed verify"
    elif piped -F "$4" "$dir/out.txt"; then ok "release-receipt: $1: verify fails, no upload ($(grep -m1 '^FAIL' "$dir/out.txt"))"
    else bad "release-receipt: $1: verify failed without '$4': $(grep -m1 '^FAIL' "$dir/out.txt")"; fi
  }

  rr_rel rc
  check "release-receipt: the receipt holds only its fields, no home path, no user name" \
    eval "! grep -Ev '^(receipt 1|version [0-9.]+|build [0-9.]+|channel release|source [0-9a-f]+ clean|notes [0-9a-f]{64}|file [0-9a-f]{64} [A-Za-z0-9._-]+)\$' '$dir/rc/RECEIPT' >/dev/null &&
      ! grep -qF -e '$HOME' -e '$(id -un)' -e '$dir' '$dir/rc/RECEIPT'"
  rm -f "$FX_GH_LOG"
  if rr_publish "$dir/rc" feature && rr_uploaded; then ok "release-receipt: the tested tree's commit passes, then the upload runs"
  else bad "release-receipt: the tested tree's commit: $(grep -m1 '^FAIL' "$dir/out.txt")"; fi

  # an equal tree after a squash merge: another commit id, the same tree
  fx_git checkout -q main && fx_git merge -q --squash feature >/dev/null && fx_git commit -qm "squash (#1)"
  sq=$(fx_git rev-parse HEAD)
  rm -f "$FX_GH_LOG"
  if [ "$sq" != "$(fx_git rev-parse feature)" ] && rr_publish "$dir/rc" "$sq" && rr_uploaded; then
    ok "release-receipt: the squash commit, same tree, other id: passes"
  else bad "release-receipt: the squash commit: $(grep -m1 '^FAIL' "$dir/out.txt")"; fi

  rr_rel other "$t_base clean"
  rr_refused "an app from another tree in dist/" "$dir/other" "$sq" "isn't the receipt's"
  rr_rel dirty "$t_feat changed"
  rr_refused "an app built from a changed working tree" "$dir/dirty" "$sq" "built from a working tree with changes"
  rr_rel nogit unknown
  rr_refused "an app built outside git" "$dir/nogit" "$sq" "built from a working tree with changes, or not from git"

  rr_rel dmg; printf 'X' | dd of="$dir/dmg/SWTOR-on-Mac-$v.dmg" bs=1 seek=3 conv=notrunc 2>/dev/null
  rr_refused "one altered byte in the DMG" "$dir/dmg" "$sq" "SWTOR-on-Mac-$v.dmg: sha256"
  rr_rel feed; echo '<!-- -->' >>"$dir/feed/appcast.xml"
  rr_refused "a changed feed" "$dir/feed" "$sq" "appcast.xml: sha256"
  rr_rel channel; sed -i.bak 's/^channel release$/channel dev/' "$dir/channel/RECEIPT"
  rr_refused "the channel" "$dir/channel" "$sq" "channel dev for $v"
  rr_rel version; sed -i.bak "s/^version $v\$/version 9.8.8/" "$dir/version/RECEIPT"
  rr_refused "the receipt's version" "$dir/version" "$sq" "no file SWTOR-on-Mac-9.8.8.dmg"
  rr_rel foreign; echo "path $HOME" >>"$dir/foreign/RECEIPT"
  rr_refused "a line outside the receipt's format" "$dir/foreign" "$sq" "lines outside its format"

  # the commit to be tagged moves on
  sed -i.bak "s/^APP_VERSION=.*/APP_VERSION=\${SWTOR_ON_MAC_VERSION:-9.8.8}/" "$g/build.sh"
  fx_git commit -qam "9.8.8"; c=$(fx_git rev-parse HEAD)
  rr_refused "build.sh's version at the commit" "$dir/rc" "$c" "APP_VERSION 9.8.8"
  fx_git reset -q --hard "$sq"
  echo later >"$g/src/app.txt"; fx_git commit -qam "a later change"; c=$(fx_git rev-parse HEAD)
  rr_refused "a changed tree at the commit" "$dir/rc" "$c" "src/app.txt"
  fx_git reset -q --hard "$sq"
  printf '## SWTOR on Mac %s\n\nA fixture, worded again.\n' "$v" >"$g/release-notes/$v.md"
  fx_git commit -qam "notes"; c=$(fx_git rev-parse HEAD)
  rr_refused "the notes changed after the build" "$dir/rc" "$c" "isn't the receipt's notes"
  # a notes edit after the build: the receipt written again keeps its gate runs and passes
  cp -R "$dir/rc" "$dir/renotes"
  "$rr" gate "$dir/renotes" sandbox-suite pass >/dev/null
  "$rr" write "$dir/renotes" "$g/release-notes/$v.md" >/dev/null
  rm -f "$FX_GH_LOG"
  if rr_publish "$dir/renotes" "$c" && rr_uploaded && piped -F 'gate: sandbox-suite pass' "$dir/out.txt"; then
    ok "release-receipt: a notes-only commit with the receipt written again passes, its gate run kept"
  else bad "release-receipt: a notes-only commit with the receipt written again: $(grep -m1 '^FAIL' "$dir/out.txt")"; fi
  printf 'X' >>"$dir/renotes/SWTOR-on-Mac-$v.dmg"
  check "release-receipt: a gate run isn't recorded on changed files" \
    eval "! '$rr' gate '$dir/renotes' smoke pass >/dev/null 2>&1 && ! grep -q '^gate smoke' '$dir/renotes/RECEIPT'"

  # after publishing: the downloaded assets against the receipt
  mkdir -p "$FX_ASSETS"
  cp "$dir/rc/SWTOR-on-Mac-$v.dmg" "$dir/rc/SWTOR-on-Mac-$v-from-9.8.6.delta" "$dir/rc/appcast.xml" "$FX_ASSETS/"
  if out=$(PATH="$dir/bin:$PATH" "$rr" verify "$dir/rc" --release "v$v") &&
    printf '%s\n' "$out" | piped -F "ok   SWTOR-on-Mac-$v.dmg"; then
    ok "release-receipt: the published assets pass, and verify names each file it compared"
  else bad "release-receipt: the published assets: $(printf '%s\n' "$out" | grep -m1 '^FAIL')"; fi
  printf 'X' >>"$FX_ASSETS/appcast.xml"
  check "release-receipt: a published asset that differs fails" \
    eval "! PATH='$dir/bin:$PATH' '$rr' verify '$dir/rc' --release v$v >/dev/null"
  cp "$dir/rc/appcast.xml" "$FX_ASSETS/"; echo extra >"$FX_ASSETS/extra.txt"
  check "release-receipt: an asset the receipt doesn't list fails" \
    eval "! PATH='$dir/bin:$PATH' '$rr' verify '$dir/rc' --release v$v >/dev/null"
  unset FX_GH_LOG FX_ASSETS
}
