# Logs and debugging

What Collect Logs puts in its zip, and the tools for a report about stutter or frame rate. How to send a report is in the [README](../README.md#getting-help).

## What Collect Logs collects

Choose **SWTOR on Mac > Collect Logs…**. After 10–30 seconds (the menu item says
*Collecting Logs…* meanwhile) it saves `SWTOR-on-Mac-logs-<date>.zip` to your Desktop (or,
without access to the Desktop, to `~/Library/Logs/SWTOR on Mac`) and says where it is. **Show in
Finder** shows it there; **Close** (Return or Esc) just closes the message. To get help, create a
post in #swtor-on-mac-issues on the [SWTOR on Mac Discord](https://discord.gg/AnV3fZWz2b) with the
zip and tag @Pharaphobia, or attach the zip to a
[GitHub issue](https://github.com/jdrly/swtor-on-mac/issues/new/choose).

The zip holds SWTOR on Mac's logs, `env`, `settings.conf`, `dxvk.conf`,
`install-manifest.json`, the versions, system information (macOS, chip, memory, displays, the size of macOS's Metal caches for the engine's processes, shared with other CrossOver-based apps, the size of Metal's archive usage index and the MDB_MAP_FULL events of the last 2 hours beside it) and
macOS's crash, hang and spin reports of the last 7 days (from `~/Library/Logs/DiagnosticReports`)
for the game, Wine, the official launcher and SWTOR on Mac, so you don't have to look for them:
the newest 20, up to 10 MB together; `system-info.txt` lists which are in the zip and which were
left out, and when in the last 7 days macOS ended what the launcher left running because it is
not allowed in the background (`som.sh btm-check 7d`, the times or *none*). `gpu-errors.txt` has the GPU errors of the game and Wine from macOS's unified log
of the last 2 hours (`IOGPUMetalError` counted per process, the last fault lines, the GPU
driver's events by time and kind, Metal's other errors), since `wine.log` starts anew with every
game start; other apps' errors are only counted, never named. `wine.log.1` to `wine.log.4` are
the game starts before the last, and `system-info.txt` lists the last 10 starts from `hold.log`:
how long each ran and how it ended (exit code or signal), with the game's language. With them
come the official launcher's own logs (`launcher-logs/`, from `~/Library/Logs/Star Wars - The
Old Republic Launcher`) and, in `system-info.txt`, a check of the launcher app: its version,
bundle id, owner, signature (`codesign --verify --deep --strict`) and any `*.solidpartial`
files, which a launcher self-update that did not finish leaves behind. Your home folder, user name, account
names and e-mail addresses are replaced, serial numbers and device identifiers are left out,
and the game's command line (the launcher passes the account on it) is never included. Your
Mac's name is replaced too, and in the launcher's logs its IP and MAC addresses, the launcher's
machine and session ids and session tokens. Last, a leak check: a file that still holds one of
those names, a home folder or a token is left out of the zip, and `left-out.txt` names it. Turn on
**Settings > Debug Logging** only when asked: it makes the logs much more detailed for the next
game start, at some cost in performance, so turn it off again afterwards.

`D9MT-GPU-HUNG` in `wine.log` means that submitted GPU work didn't complete for about 10 seconds
and d9mt ended the game (`D9MT_GPU_HUNG=continue` keeps the old behaviour, a frozen game). Collect
Logs before starting the game again, which replaces `wine.log`.

## Debug Logging, session reports and live d9mt flags

For a bug report about stutter or frame rate: turn on Settings > Troubleshooting > **Debug
Logging**, start the game, play the part that misbehaves, quit, then use **Collect Logs…** (it
includes the session report below). Turn Debug Logging off again afterwards: it costs a little
performance. A setting you choose is kept through updates and Reinstall.

**Session report.** `"/Applications/SWTOR on Mac.app/Contents/Resources/session-report.sh"`
(`scripts/session-report.sh`) sums up the last game session from
`~/Library/Logs/SWTOR on Mac/wine.log`:
- the app version, Wine engine and d9mt the session ran on (0.1.0-dev.1 and later: the
  wrapper's first line in `wine.log`; also in `effective-env.txt`, and Collect Logs'
  `system-info.txt` names the engine in place);
- duration, median and 1%-low fps, the seconds below 58 fps;
- frames over 33 ms and 50 ms;
- hitches, split into d9mt's and the game's, and d9mt's top causes;
- compile waits and the memory peak;
- render passes and the attachment traffic d9mt saved, and (0.0.6 and later) the
  render thread's CPU time in that optimization and the clears per frame, to tell its cost
  apart from compile waits (a cold shader cache);
- the attachment re-clears by cause, from the `RESTORE` lines (0.0.6 and later):
  image format and size, the aspects re-cleared, why and the D3D9 call, per frame;
- (0.1.1 and later) d9mt's GPU path (lossless texture compression, the end-of-pass barrier,
  clears that skip stores) and the A/B switches the session ran with; the pass splits per
  frame (`split=`, with a submit, `splitMiB=`) from the `STATS` lines; the pipeline state
  cache from the `STATECACHE` lines: what it loaded (and whether the last session ended
  during its prewarm, `guard`), what the prewarm built or failed, and how many pipelines the
  game then found prewarmed (`hits`), still building (`late`) or not in it (`misses`);
  StretchRect and ColorFill by path from the `XFER` lines.

`wine.log` starts afresh at every game start (the wrapper keeps the 4 before it as
`wine.log.1` to `wine.log.4`, the newest first), so `--keep` saves a copy to `sessions/`.
`--compare A.log B.log` puts two sessions side by side. `--skip <s>` leaves out the first
seconds (loading). Collect Logs adds the report as `session-report.txt`. Logs from 0.0.5 have
no `STATS` lines: hitches, compile waits and memory still compare.

**Live d9mt flags.** With Debug Logging on, d9mt reads
`~/Library/Application Support/SWTOR on Mac/prefix/drive_c/d9mt/flags.txt` (`C:\d9mt\flags.txt`)
once a second while the game runs: one flag per line, `#` comments; the file is written with
every flag commented out, and edits are kept. `no_attach_opt` switches d9mt's attachment
load/store optimization off and back on live (A/B), `att_trace` logs up to 400 render-pass
decisions and re-clears to `wine.log` (remove and re-add the line for 400 more), `dump` dumps
the next frame's draws into that folder. For example:

```bash
F="$HOME/Library/Application Support/SWTOR on Mac/prefix/drive_c/d9mt/flags.txt"
echo att_trace >>"$F"                          # trace on
sed -i '' '/^att_trace$/d' "$F"                # trace off
echo no_attach_opt >>"$F"                      # optimization off (A/B)
sed -i '' '/^no_attach_opt$/d' "$F"            # back on
```
