# Testing without touching the system

`som.sh` takes `SWTOR_ON_MAC_ROOT=/abs/dir` (every path, official install included, under that
directory) and `SWTOR_ON_MAC_DRY_RUN=1` (print the changes, make none). The app passes both on,
so `SWTOR_ON_MAC_ROOT=/tmp/x "SWTOR on Mac.app/Contents/MacOS/SWTORonMac"` shows the window for
a sandbox. In a sandbox notifications go to `notifications.log`, and Play SWTOR opens only the sandbox's official app
(`SWTORonMac --play-target` prints what the button would do, without opening anything, and `--play-check` what a press does after the hook check). `scripts/test-sandbox.sh` builds a sandbox from an APFS clone of this Mac's
Broadsword Wine folder and a stand-in for the official app (its `Info.plist`, ad-hoc signed,
with the test's stand-ins for the launcher built in, so Gatekeeper never sees a changed copy
of Broadsword's signed app) and runs install, the settings, reinstall, the wrapper's update check (with a
stub engine and a local feed), a simulated launcher update and the app's hook check when it opens (`som.sh rehook`: it hooks
back in, leaves a running install and a launcher still writing alone; an update over 0.0.6,
0.1.3 and a development build removes their launchd job), leftover Wine processes (dummy programs under the sandbox engine and in
Broadsword's Wine folder: what `status` reports, that only they end, from `end-leftovers`,
install, uninstall and the wrapper, never while a wineserver of theirs runs, never another
prefix's, never Broadsword's `mac_wine`), the Wine session (a `mac_wine`-like call that starts
it returns at once although its system process lives on, `-p10`, nothing of the caller
inherited, one start for two calls at once), a failed
install, Collect Logs, what Play SWTOR would open, *Game keys by keyboard position* and *Raw
mouse-look* (the Mac driver's three files and the registry values, and what the game sees: a
probe program run as `swtor.exe` with Czech, German and US layouts, picked through the
driver's `WINEMAC_TEST_KEYBOARD_LAYOUT` test hook without changing the Mac's input source; the
app's PE side with the engine's own unix side, as an older installer leaves them), the
conflict cases and uninstall end to end, checking that uninstall
restores Broadsword's folder byte for byte, copies the game settings back and that no Wine
process is left behind. With an older app (`OLD_APP`, default `release/0.0.6`) it then tests the
way from 0.0.6 and back: a 0.0.6 install upgraded (a failed upgrade rolled back first: engine,
libraries, env and prefix as before, and Wine 9 still reads the prefix), everything kept and
the new engine in use; 0.0.6's Reinstall over it (Wine 9 runs programs in the prefix Wine 11
updated, game keys by position work); the upgrade again; and this version's Uninstall of a
0.0.6 install. With the previous release (`PREV_APP`, default `release/0.1.0`, the same
engine) it tests the way from it and back: this version's Reinstall over it changes only d9mt's
`d3d9.dll` in the prefix and adds the env lines (the engine's code stays the same, its
`winemetal.so` that of the previous release), and the previous release's Reinstall puts
prefix, engine and `env` back as it had them. A release build then goes on from a development
build (`DEV_APP`, default `release/0.1.1-dev.1`): its Reinstall removes the dev build's
`d9mt-ab.env` and test caches and keeps the prefix, engine and settings. It also checks
development builds' `d9mt-ab.sh`, the session report on a sample of d9mt's log lines, the
app's `ntdll.so` in the engine (the engine's own kept as `.stock`, also after an upgrade and
a downgrade), and a wrapper copied by hand from the template (`@CONF@` not filled in, or
another install's `env`), which the window and Play treat as unhooked and Reinstall and the
app's hook check repair. `scripts/test-btm.sh` (also run by `test-sandbox.sh`, and on its own
without the official app) tests `som.sh btm-check` on planted log text (the real lines of a field
report, `SWTOR_ON_MAC_BTM_LOG`; a sandbox never reads macOS's log), the wrapper's notification
after `hold-launcher` exit 3 (it doesn't hold up the Wine call, and nothing keeps running),
`hold-launcher`'s exit 3 with dummy programs, and Collect Logs' line; also that loginwindow's
*scheduling* line alone counts as no end, and that a query that never answers is ended at its
limit (alone, from the wrapper, and in Collect Logs behind a slow GPU query). `scripts/test-update.sh` tests app updates with two Developer ID builds and a
local feed, as in SWGL on Mac.

`scripts/test-fixtures.sh [app] [group...]` runs the checks that need neither the official app nor
Wine, in a folder of their own (`FIXTURE_ROOT`) with an empty home and an empty sandbox: the
session report on a sample log (the suite's section 6f, which `test-sandbox.sh` runs from the same
file in `scripts/fixtures/`), the suite's end under a job runner on planted sandboxes, and the
suite's `orphan_as`. That helper starts a stand-in with a rewritten argv[0], as Wine 11 shows its
processes. The argv[0] reaches the rewriting shell in the environment, never on its command line:
a game path there (section 2c's) makes that shell look like the game to `swtor-running.sh` and
the job runner, which then stops the suite's job. Both `orphan` and `orphan_as` return only once
the stand-in runs its program (`orphan_ready`, up to 5 s; a fixed delay sometimes still saw the
shell before its exec), and section 6d waits until its stand-in maps the server file that
`--reap` looks for (`orphan_maps`, an mmap, not an open file). A stand-in that isn't ready fails
the checks after it without running them, while it still runs something else and once after it
ended, so a check (a negative one above all) can't pass without its process. For the same reason section 2b's call by
executable names the launcher's file name outside any app's `Contents/MacOS` (the app checks only
the name): the launcher's own path there would make the call look like the running launcher, the
one process that stops the suite's job (group `is-launcher`). A check runs its `eval` string in
the suite's own shell, so no string may call `exit` outside a subshell: the suite would end there
with no `FAIL` line and no counts. Section 14a checks that over the suite and the fixture groups;
group `eval-exit` checks that check, and the suite's "app files gone" checks on a planted file.
Stand-ins
for `wine`, `wineserver`, `open` and the like fail the run if a check starts one. Under a job
runner (`JOB_ID` and `JOB_ROOT` set) both scripts refuse an output folder that isn't named (the
suite's default is `/tmp/som-sandbox`) or lies in `/tmp` or `$TMPDIR`; the job's adapter puts it
in the job's run directory. The suite then keeps its text output whatever the result, and removes
the sandbox's heavy children (`home/`, `prev-engine/`, `dev-engine/`). After a failure it first
keeps a reproducer set in `repro/`: the run's inputs (`inputs.txt`: the apps' versions and
CDHashes, the official app's version, the scripts' commit, macOS), SWTOR on Mac's files with the
prefix's registry, and its logs. If that copy fails (a full disk), `home/` itself is kept, moved
to `repro/home`.
