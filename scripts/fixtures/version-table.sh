# shellcheck shell=bash
# The version table (#47): the supported release and development versions in order, run through
# the production code of all three places that compare them. build.sh's bundle_version gives the
# CFBundleVersion Sparkle compares (dotted numbers, compared here as Sparkle's standard comparator
# compares numeric versions); the Wine wrapper's daily check (the awk in update_check) and the
# app's Installer.isNewer decide whether a feed's release is newer than the installed version. The
# feed carries releases only, so those two are checked with a release as the newer side. Sparkle
# stays authoritative; this checks that the three agree with it. A control: a bundle_version that
# drops dev.N's 1000 + N must fail the table.

# oldest first; each sorts above the one before it
VT_ORDER="0.0.5 0.0.6-dev.1 0.0.6-dev.2 0.0.6 0.1.0-dev.1 0.1.0 0.1.1-dev.1 0.1.1 0.1.5 0.1.5.1
0.1.6-dev.1 0.1.6 0.1.7 0.1.7.1 0.1.8 0.1.9-dev.1 0.1.9 0.1.10-dev.3 0.1.10 0.2.0-dev.1 0.2.0
1.0.0-dev.1 1.0.0"
# version and CFBundleVersion (build.sh's comment)
VT_MAP="0.0.6-dev.1 0.0.5.1001
0.1.0-dev.2 0.0.9999.1002
0.1.1-dev.1 0.1.0.1001
0.1.6-dev.1 0.1.5.1001
0.1.10-dev.3 0.1.9.1003
1.0.0-dev.1 0.9999.9999.1001
0.1.8 0.1.8
0.1.7.1 0.1.7.1"
# versions build.sh refuses
VT_REFUSED="0.1.5.2-dev.1 0.1.8-rc.1"

# vt_older <a> <b>: dotted numbers, a before b
vt_older() {
  awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
    for (i = 1; i <= n; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }
    exit 1 }'
}

# vt_bundle_table <file with bundle_version()>: the mapping, the refusals and the order through
# that function; prints a line per wrong answer
vt_bundle_table() {
  ( set +e
    eval "$(sed -n '/^bundle_version() {$/,/^}$/p' "$1")"
    command -v bundle_version >/dev/null || { echo "no bundle_version() in $1"; exit; }
    printf '%s\n' "$VT_MAP" | while read -r v want; do
      got=$(bundle_version "$v" 2>/dev/null)
      [ "$got" = "$want" ] || echo "bundle_version $v: $got, not $want"
    done
    for v in $VT_REFUSED; do
      if got=$(bundle_version "$v" 2>/dev/null); then echo "bundle_version $v: $got, not refused"; fi
    done
    prev="" pb=""
    for v in $VT_ORDER; do
      b=$(bundle_version "$v" 2>/dev/null) || { echo "bundle_version refuses $v"; continue; }
      if [ -n "$prev" ] && ! vt_older "$pb" "$b"; then echo "bundle_version: $prev ($pb) doesn't sort before $v ($b)"; fi
      prev=$v pb=$b
    done )
}

# vt_pairs: "newer older expected" for every pair with a release as the first, newer side:
# 1 when it sorts above the second, else 0 (equal included)
vt_pairs() {
  local i=0 j a b
  for a in $VT_ORDER; do
    i=$((i + 1)); j=0
    case "$a" in *-*) continue ;; esac
    for b in $VT_ORDER; do
      j=$((j + 1))
      if [ "$j" -lt "$i" ]; then echo "$a $b 1"; else echo "$a $b 0"; fi
    done
  done
}

fx_version_table() {
  local buildsh=$1 wrapper=$2 appswift=$3 dir=$4 out prog n
  mkdir -p "$dir"
  out=$(vt_bundle_table "$buildsh")
  if [ -z "$out" ]; then ok "version-table: bundle_version maps, refuses and orders the table ($(echo $VT_ORDER | wc -w | tr -d ' ') versions)"
  else bad "version-table: bundle_version: $(printf '%s\n' "$out" | head -3 | tr '\n' ';')"; fi
  # the control: dev.N as .N instead of .(1000 + N)
  sed 's/\$((1000 + n))/$n/g' "$buildsh" >"$dir/build-wrong.sh"
  out=$(vt_bundle_table "$dir/build-wrong.sh")
  if grep -q '\$((1000 + n))' "$dir/build-wrong.sh" || [ -z "$out" ]; then
    bad "version-table: a bundle_version without 1000 + N passes the table"
  else
    ok "version-table: a bundle_version without 1000 + N fails it (${out%%
*})"
  fi
  vt_pairs >"$dir/pairs.txt"
  n=$(wc -l <"$dir/pairs.txt" | tr -d ' ')

  # the wrapper's comparison, cut out of the packaged wine-wrapper.sh as it runs there
  prog=$(sed -n "/awk -v a=\"\$latest\" -v b=\"\$SWTOR_ON_MAC_VERSION\" 'BEGIN {/,/exit !(pb && !pa) }'/p" "$wrapper" |
    sed "1s/^[^']*'//; \$s/'.*\$//")
  case "$prog" in
    BEGIN*'exit !(pb && !pa) }')
      out=$(while read -r a b want; do
        if awk -v a="$a" -v b="$b" "$prog"; then got=1; else got=0; fi
        [ "$got" = "$want" ] || echo "$a over $b: $got, not $want"
      done <"$dir/pairs.txt")
      if [ -z "$out" ]; then ok "version-table: the wrapper's update check agrees on $n pairs"
      else bad "version-table: the wrapper's update check: $(printf '%s\n' "$out" | head -3 | tr '\n' ';')"; fi ;;
    *) bad "version-table: the comparison isn't in $wrapper's update_check (cut: ${prog:0:60})" ;;
  esac

  # the app's Installer.isNewer, cut out of App.swift and compiled with swiftc
  sed -n '/^  static func isNewer(_ a: String, than b: String) -> Bool {$/,/^  }$/p' "$appswift" >"$dir/isNewer.swift.part"
  if ! grep -q 'static func isNewer' "$dir/isNewer.swift.part"; then
    bad "version-table: no Installer.isNewer in $appswift"
  elif ! command -v swiftc >/dev/null; then
    bad "version-table: isNewer not checked: no swiftc"
  else
    { echo "enum Installer {"; cat "$dir/isNewer.swift.part"; echo "}"
      echo 'while let l = readLine() { let f = l.split(separator: " ").map(String.init); print("\(f[0]) \(f[1]) \(Installer.isNewer(f[0], than: f[1]) ? 1 : 0) \(f[2])") }'
    } >"$dir/isNewer.swift"
    if swiftc -o "$dir/isNewer" "$dir/isNewer.swift" >"$dir/swiftc.txt" 2>&1; then
      out=$("$dir/isNewer" <"$dir/pairs.txt" | awk '$3 != $4 { print $1 " over " $2 ": " $3 ", not " $4 }')
      if [ -z "$out" ]; then ok "version-table: Installer.isNewer agrees on $n pairs"
      else bad "version-table: Installer.isNewer: $(printf '%s\n' "$out" | head -3 | tr '\n' ';')"; fi
    else
      bad "version-table: isNewer didn't compile: $(head -3 "$dir/swiftc.txt" | tr '\n' ' ')"
    fi
  fi
}
