# shellcheck shell=bash
# Section 2b's question to the app (scripts/test-sandbox.sh, sourced), and fixture group
# is-launcher, which checks the call's command line (scripts/test-fixtures.sh only).

# is_launcher <bundle id, or -> <executable>: what the app takes for the official launcher
is_launcher() { "$APP/Contents/MacOS/SWTORonMac" --is-launcher "$@" 2>/dev/null; }
# The executable 2b checks with another app's bundle id: the launcher's file name, which is all
# the app checks, in a folder that is no app's Contents/MacOS. The launcher's own path as the
# call's last argument would make the call itself a running launcher to tools/swtor-running.sh
# and the job runner, which stops the suite's job for the launcher (tools/job/runner/README.md,
# "Game-shaped jobs")
LAUNCHER_EXE="/x/Star Wars - The Old Republic Launcher"
# tools/swtor-running.sh's patterns for the launcher, over a command line
# shellcheck disable=SC2034 # (used in check's eval strings)
LAUNCHER_RX='Star Wars - The Old Republic Launcher\.app/|/Contents/MacOS/Star Wars - The Old Republic Launcher$'

# fx_is_launcher: 2b's call by executable, as a command line, isn't a running launcher, and its
# executable keeps the launcher's file name. No process starts (a launcher-shaped one would stop a
# job on this Mac).
fx_is_launcher() {
  # shellcheck disable=SC2034 # (used in check's eval strings)
  local som="$APP/Contents/MacOS/SWTORonMac --is-launcher org.example.other"
  check "is-launcher: the executable has the launcher's file name ($LAUNCHER_EXE)" \
    test "$(basename "$LAUNCHER_EXE")" = "Star Wars - The Old Republic Launcher"
  check "is-launcher: 2b's call doesn't look like the running launcher" \
    eval '! printf "%s\n" "$som $LAUNCHER_EXE" | piped -E "$LAUNCHER_RX"'
  check "is-launcher: the launcher's own path would (the patterns' control)" \
    eval 'printf "%s\n" "$som /Applications/Star Wars - The Old Republic.app/Contents/MacOS/Star Wars - The Old Republic Launcher" | piped -E "$LAUNCHER_RX"'
}
