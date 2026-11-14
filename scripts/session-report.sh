#!/bin/bash
# Summary of one game session from d9mt's log lines in wine.log (Debug Logging on in Settings):
# frame rate, slow frames, hitches (d9mt's share vs the game's), shader/pipeline compile waits,
# memory peak, render passes and the attachment traffic d9mt's load/store optimization saved.
#
#   session-report.sh [--skip <s>] [--mark <s>] [--keep] [wine.log]   one session (default:
#                                       the current ~/Library/Logs/SWTOR on Mac/wine.log)
#   session-report.sh [--skip <s>] [--mark <s>] --compare A.log B.log [C.log...]   2 to 5
#                                       sessions side by side (before/after; A/B/A: 3 arms)
#
#   --skip <s>  leave out the first <s> seconds (loading screens, character select)
#   --mark <s>  count only <s> seconds of elapsed time (STATS t), from 5 s after the last
#               return to the game window (the mark: Cmd-Tab away and back once, standing at
#               the spot); a session with no return counts as a whole, and says so
#   --keep      also save the log as ~/Library/Logs/SWTOR on Mac/sessions/wine-<date>-<version>.log:
#               wine.log starts afresh at every game start, so keep the sessions to compare
#
# Sources, all optional (SWTOR on Mac 0.0.5 logs have no STATS lines; then the frame numbers
# come from what there is):
#   the first line (SWTOR on Mac 0.1.0-dev.1 and later): the app version, Wine engine and d9mt
#             the session ran on
#   STATS     once a second (d9mt 0.0.6 dev and later): fps, frame times, slow frames, passes,
#             attachment loads/stores, compiles, Metal's allocated memory; from 0.0.6-dev.3 also
#             the render thread's CPU time in the attachment optimization and the clears
#   MtlPresenter visibility  (0.1.0 and later) the game window's visibility changes (0x3:
#             visible on the active Space), and d9mt's "window minimized, throttling Present"
#             lines. The frame rate, frame times and hitches count only the seconds it showed
#             the game, 1 s around each change left out (Cmd-Tab, a Space switch, the Dock:
#             d9mt throttles Present while hidden); the hidden seconds get their own line
#   HITCH     each frame over 50 ms: d9mt's time in it and by what, or the game's
#   COMPILE   render-thread frames with compiles or over 33 ms (shader/pipeline waits)
#   DIAG MEM  every 256 frames: Metal's allocated memory
#   RESTORE   seconds with attachment re-clears (d9mt 0.0.6-dev.2 and later): what was
#             re-cleared (format, size, aspects), why, and the D3D9 call it came from;
#             RESTORE-SUMMARY when the game released its device (not every exit does)
#   PACE      once a second (d9mt 4b7ab26 and later): the interval between the game's
#             Present calls (min/avg/max, sd), the Present thread's time per frame inside d9mt
#             and outside it, its CPU time split into d9mt's and the game's own
#   THREADCPU once a second (the app's Mac driver, 0.1.0-dev.2 and later): CPU time of the
#             game process, its busiest threads and the session's wineserver, in ms
#   RAWMOUSE  once a second while raw mouse-look moves (0.1.0-dev.2 and later): moves by
#             source (GCMouse, AppKit), the measured pixels per mouse count, the speed setting
#   STATECACHE (d9mt 6fa5df7 and later) the pipeline state cache: loaded at the start (entries,
#             how many can be prewarmed, guard=tripped if the last session ended during
#             prewarm builds), the background prewarm (built, failed), the pipelines the game
#             needed (hits: prewarmed in time, late: still building, misses: not in the cache),
#             written at the end; "STATECACHE off" when it is off
#   XFER      seconds with StretchRect/ColorFill calls (d9mt 6fa5df7 and later), by path;
#             XFER-SUMMARY with the session's totals when the game released its device
#   split=    in STATS (d9mt 6fa5df7 and later): passes per frame that reopen the attachments
#             the previous pass closed (splitSubmit: with a command buffer submit in between),
#             splitMiB the bytes they load again
#   d9mt's startup lines: its GPU path (lossless texture compression, the end-of-pass barrier,
#             clears that skip stores; d9mt-ab.sh switches them back) and DXVK_CONFIG
#   the wrapper's "d9mt-ab:" line: development builds' A/B switches (d9mt-ab.sh)
#   the wrapper's "frame rate limit:" line (0.1.3 and later): the Frame Rate Limit setting and,
#             with "Only on battery", the power source at the start; d9mt's "frame cap" line:
#             how it caps (every Nth refresh, the timer, or off because vsync caps already)
#   the wrapper's "flush cap:" line (0.1.7 and later): Settings' Fewer GPU Batches when it is on
#             (or the d9mt-ab switch that wins over it); d9mt's "flush cap" line (Debug Logging
#             only): the cap d9mt applies
#   D3D9 SM3 hazard  (d9mt 6fa5df7 and later) a shader with the patterns its converter fix
#             covers, once per shader
#   the wrapper's "native fullscreen:" line (0.1.9 and later): the Native fullscreen setting, on
#             or off; NATIVEFS (the app's Mac driver, channel nativefs, on with the setting): the
#             driver read the option ("NATIVEFS: on"), its entries into and exits from the
#             game's own Space (by reason), failures, the longest transition; a warning for an
#             "enter" without "entered", "stuck", "fight", or the wrapper's "on" without the
#             driver's
#   the wrapper's "settings:", "conditions:" and "d9mt files:" lines (0.1.7 and later): the
#             app's settings the game started with (Debug Logging, HUD, Game Mode, d9mt's and
#             DXVK's environment, paths left out), the power source, Low Power Mode and
#             macOS's thermal warning at the start, and the d9mt files' SHA-256
#
# What the numbers are. Every frame time comes from d9mt's profiling (STATS, PACE, HITCH: Debug
# Logging on, D9MT_PROFILE), so it is instrumented, not ordinary play's: "Measurement" says
# which. STATS has per-second numbers only: a second's average, 99th percentile and slowest
# frame (at 100 frames a second or fewer the 99th percentile is the slowest frame), so a
# session's 99th percentile and its true 1% low (the slowest 1% of frames) are not in the log,
# and the report says "missing" for them; "worst 1% of seconds" is the frame rate of the slowest
# seconds. "Data" names what is left out or lost: seconds hidden, gaps between STATS lines,
# lines d9mt's limiter suppressed, a second device, a missing header, a short interval.
# Also in Collect Logs (session-report.txt; sessions-compared.txt: the kept game starts side by
# side, --mark 60). Runs under macOS's /bin/bash 3.2 and awk.
set -euo pipefail

usage() { sed -n '2,/^# Sources/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }

SKIP=0 MARK=0 KEEP="" COMPARE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip) [ $# -ge 2 ] || usage; SKIP=$2; shift 2 ;;
    --mark) [ $# -ge 2 ] || usage; MARK=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --compare) COMPARE=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) break ;;
  esac
done
case "$SKIP" in ''|*[!0-9]*) usage ;; esac
case "$MARK" in ''|*[!0-9]*) usage ;; esac
# (the mark sets the interval; --skip would take seconds out of it, unseen)
if [ "$SKIP" -gt 0 ] && [ "$MARK" -gt 0 ]; then
  echo "--skip and --mark don't go together: the mark sets the interval" >&2; exit 2
fi

LOGS="${SWTOR_ON_MAC_ROOT:+$SWTOR_ON_MAC_ROOT/home}"
LOGS="${LOGS:-$HOME}/Library/Logs/SWTOR on Mac"

# analyze <log>: key=value lines
analyze() {
  LC_ALL=C awk -v skip="$SKIP" -v marklen="$MARK" -v settle=5 '
    function num(s) { return s + 0 }
    # value of key=... in this line ("" if none); stops at space
    function field(key,    p, s) {
      p = index($0, " " key "=")
      if (!p) return ""
      s = substr($0, p + length(key) + 2)
      sub(/[ |].*/, "", s)
      return s
    }
    # sort a[lo..hi] (heapsort: no recursion; the quicksort before it recursed once per equal
    # value, and a long session of steady 60 fps seconds crashed awk)
    function qs(a, lo, hi,    n, i, t) {
      n = hi - lo + 1
      if (n < 2) return
      for (i = int(n / 2); i >= 1; i--) sift(a, lo - 1, i, n)
      for (i = n; i > 1; i--) { t = a[lo]; a[lo] = a[lo + i - 1]; a[lo + i - 1] = t; sift(a, lo - 1, 1, i - 1) }
    }
    # the heap a[o+1..o+n]: moves a[o+i] down to its place
    function sift(a, o, i, n,    c, t) {
      while ((c = 2 * i) <= n) {
        if (c < n && a[o + c + 1] > a[o + c]) c++
        if (a[o + i] >= a[o + c]) return
        t = a[o + i]; a[o + i] = a[o + c]; a[o + c] = t; i = c
      }
    }
    function pct(a, n, p,    k) { if (!n) return ""; k = int((n - 1) * p + 0.5) + 1; return a[k] }
    function hex(s,    i, n) { n = 0; s = tolower(s); for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return n }
    # the presenter shows the game: visible, on the active Space, not in the Dock (d9mt'"'"'s isVisible)
    function shown(v) { return v % 2 == 1 && int(v / 2) % 2 == 1 && int(v / 4) % 2 == 0 }
    # "[3 earlier lines suppressed]": 3
    function suppressed(    l) { l = $0; if (!sub(/.*\[/, "", l) || l !~ /^[0-9]+ earlier lines suppressed/) return 0; sub(/ .*/, "", l); return num(l) }
    # the wall-clock stamp after "<prefix>" ("20:13:05.120"), or ""
    function stamp(prefix,    l) { l = $0; if (!sub(".*" prefix, "", l)) return ""; sub(/ .*/, "", l); return l ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ ? l : "" }
    # --mark: window k (by its STATS line) is in the interval; a line with t=: in it by line
    # and second (a second device counts t afresh)
    function ink(k) { return !marked || (k >= ks && k <= ke) }
    # NATIVEFS: the longest transition, from "... in <ms> ms"
    function nfms(l, what,    v) {
      v = l; if (!sub(/.* in /, "", v)) return; sub(/ ms.*/, "", v)
      if (num(v) > nfmax) { nfmax = num(v); nfmaxw = what }
    }
    function int_t(t) { return !marked || (FNR > ivlo && FNR < ivhi && t >= tof[ks] && t <= tof[ke]) }
    BEGIN { vs = -1; wstart = -1; useg = 1; lastmw = 1 }

    # Pass 1 (the log is read twice): which STATS seconds the window was hidden or switching in.
    # d9mt logs "MtlPresenter: <time> visibility 0x3 -> 0x0" from Present, where it also counts
    # the frames of STATS, so a line between "STATS t=N-1" and "STATS t=N" changed second N
    # (STATS has no wall-clock time: t is seconds since the first Present). Window k is the k-th
    # STATS line; bad[k]: the state wasn'"'"'t "shown" all through it. Minimized, Present returns
    # before it asks the presenter, so no visibility line comes: d9mt'"'"'s throttle lines tell it
    # ("window minimized, throttling Present to 10 fps", logged at every change of the throttle,
    # from Present as well).
    NR == FNR {
      if ($0 ~ / (STATS|PACE) t=| HITCH frame=| COMPILE frame=| THREADCPU [0-9.]+ s: /) prof = 1
      if ($0 ~ / STATS t=/) {
        t1 = num(field("t")); reset = nw && t1 < p1T
        # a window of 2 s or more: a frame that long, or Present not called (no STATS between)
        if (nw && !reset && t1 - p1T >= 2) { ngap++; if (t1 - p1T > gapmax) gapmax = t1 - p1T }
        p1T = t1
        nw++
        lineof[nw] = FNR; tof[nw] = t1; if (reset) devof[nw] = 1
        bad[nw] = wbad || (wstart >= 0 && !shown(wstart)) || wmin
        if (wstart < 0) unk[nw] = 1
        wbad = 0
        # a second device: its presenter logs no first state, the next line'"'"'s "from" tells it;
        # its throttle starts off and logs its first change (none in this second: not minimized)
        if (reset) { vs = -1; unk[nw] = 1; useg = nw; if (lastmw != nw) mn = 0 }
        wstart = vs; wmin = mn
      } else if ($0 ~ /MtlPresenter: .*visibility 0x[0-9a-fA-F]+ -> 0x[0-9a-fA-F]+/) {
        l = $0; sub(/.*visibility 0x/, "", l)
        pv = l; sub(/[^0-9a-fA-F].*/, "", pv); pv = hex(pv)
        nv = l; sub(/^[^>]*> 0x/, "", nv); sub(/[^0-9a-fA-F].*/, "", nv); nv = hex(nv)
        nsupp += suppressed()
        # back to the game (the mark: the last one counts)
        if (shown(nv) && !shown(pv)) { retk = nw + 1; retat = stamp("MtlPresenter: ") }
        if (vs < 0) {
          # the state since the start (or the device'"'"'s start) was this line'"'"'s "from"
          for (vw = useg; vw <= nw; vw++) if (unk[vw] && !shown(pv)) bad[vw] = 1
          if (wstart < 0) wstart = pv
        } else if (pv != vs || index($0, "earlier lines suppressed")) {
          # d9mt'"'"'s limiter left lines out: unknown since the last line
          for (vw = lastvw; vw <= nw; vw++) bad[vw] = 1
        }
        vs = nv; wbad = 1; lastvw = nw + 1
      } else if ($0 ~ /D9MT: .*(, throttling Present to [0-9]+ fps|presenting normally again)/) {
        m1 = index($0, " window minimized, throttling Present") > 0
        nsupp += suppressed()
        if (mn && !m1) { retk = nw + 1; retat = stamp("D9MT: ") }
        if (index($0, "earlier lines suppressed")) for (vw = lastmw; vw <= nw; vw++) bad[vw] = 1
        if (m1 != mn) wbad = 1
        mn = m1; lastmw = nw + 1
      }
      next
    }
    # Pass 2: hid[k]: window k, or the one before or after it, was bad (1 s around a change)
    !p2 {
      p2 = 1
      bad[nw + 1] = wbad || (wstart >= 0 && !shown(wstart)) || wmin
      for (vw = 1; vw <= nw + 1; vw++) hid[vw] = bad[vw] || bad[vw - 1] || bad[vw + 1]
      # --mark <s>: by elapsed time, not by lines. The return fell in window retk, which ends at
      # t = tof[retk]; the interval is the seconds its0..ite (<settle> s later, <s> long) of
      # the same device (a second device counts t from 0 again). Window k covers t from
      # tof[k-1] to tof[k]: windows ks..ke are those wholly inside the interval. A window of 2 s
      # or more (a frame that long, or no Present) is one line for several seconds: counted as
      # time, and named in Data. Lines between the STATS line before ks and the one after ke
      # belong to it.
      if (marklen > 0 && retk) {
        marked = 1; ks = 0; ke = -1
        segend = nw; for (vw = retk + 1; vw <= nw; vw++) if (devof[vw]) { segend = vw - 1; break }
        if (retk <= nw) {
          its0 = tof[retk] + settle; ite = its0 + marklen - 1
          for (vw = retk + 1; vw <= segend; vw++) {
            pt = devof[vw] ? 0 : tof[vw - 1]
            if (pt >= its0 - 1 && tof[vw] <= ite) { if (!ks) ks = vw; ke = vw }
            # a gap in the seconds between the mark and the interval
            else if (tof[vw] < its0 && tof[vw] - pt >= 2) ivsettlegap = 1
          }
          if (tof[segend] < ite) { if (segend < nw) ivdev = 1; else ivshort = 1 }
        }
        if (ivdev || !ks) { ivempty = !ivdev; ks = nw + 1; ke = nw }
        else {
          for (vw = ks; vw <= ke; vw++) {
            ivcov += tof[vw] - tof[vw - 1]
            if (tof[vw] - tof[vw - 1] >= 2) { ivgap++; ivgaps += tof[vw] - tof[vw - 1]; if (tof[vw] - tof[vw - 1] > ivgapmax) ivgapmax = tof[vw] - tof[vw - 1] }
          }
        }
        ivlo = ks > 1 ? lineof[ks - 1] : 0
        ivhi = ke < nw ? lineof[ke + 1] : FNR + 1e9
      }
    }
    FNR <= 5 && /^SWTOR on Mac [^:]*: engine / { header = 1 }
    /^SWTOR on Mac settings: / { settings = $0; sub(/^SWTOR on Mac settings: /, "", settings) }
    /^SWTOR on Mac conditions: / { conds = $0; sub(/^SWTOR on Mac conditions: /, "", conds) }
    /^SWTOR on Mac d9mt files: / { dfiles = $0; sub(/^SWTOR on Mac d9mt files: /, "", dfiles) }

    /D9MT: pipeline wait budget/ { budget = $0; sub(/.*budget /, "", budget); sub(/ per frame.*/, "", budget) }
    /D9MT: attachment load\/store optimization off/ { attoff = 1 }
    /D9MT: memory profile/ { mp = $0; sub(/.*memory profile /, "", mp); sub(/:.*/, "", mp) }
    /^SWTOR on Mac d9mt-ab: / { ab = $0; sub(/^SWTOR on Mac d9mt-ab: /, "", ab) }
    /^SWTOR on Mac frame rate limit: / { fpsl = $0; sub(/^SWTOR on Mac frame rate limit: /, "", fpsl) }
    /^SWTOR on Mac flush cap: / { flc = $0; sub(/^SWTOR on Mac flush cap: /, "", flc) }
    /D9MT: flush cap / { dflc = $0; sub(/.*D9MT: flush cap /, "", dflc) }
    # Native fullscreen: the wrapper names the setting; the Mac driver of the app logs its
    # NATIVEFS lines (channel nativefs, which the wrapper turns on with the setting)
    /^SWTOR on Mac native fullscreen: / { nfw = $0; sub(/^SWTOR on Mac native fullscreen: /, "", nfw) }
    /NATIVEFS: / {
      nfany = 1; l = $0; sub(/.*NATIVEFS: /, "", l)
      if (l ~ /^on( |$)/) nfon = 1
      else if (l ~ /^enter screen=/) { if (nfpend) nfnoent++; nfpend = 1; nfent++ }
      else if (l ~ /^entered /) { nfpend = 0; nfentd++; nfms(l, "entering") }
      else if (l ~ /^enter failed/) { nfpend = 0; nfefail++ }
      else if (l ~ /^exit reason=/) {
        nfr = l; sub(/^exit reason=/, "", nfr); sub(/ .*/, "", nfr); nfexit++
        if (!(nfr in nfreason)) nfrorder[++nfrn] = nfr
        nfreason[nfr]++
      }
      else if (l ~ /^exited /) nfms(l, "leaving")
      else if (l ~ /^exit failed/) nfxfail++
      else if (l ~ /^stuck/) nfstuck++
      else if (l ~ /^fight/) nffight++
    }
    # d9mt'"'"'s plan, logged again when the refresh rate or vsync changes: the last one counts
    /D9MT: .* frame cap [0-9]+ fps: / { fcap = $0; sub(/.* frame cap /, "", fcap); sub(/ \[[0-9]+ earlier lines suppressed\]$/, "", fcap) }
    # d9mt'"'"'s GPU path (d9mt 6fa5df7 and later; d9mt-ab.sh switches it back to the old one)
    /D9MT: PixelFormatView only on block-compressed textures/ { gpfv = "lossless compression on" }
    /D9MT: PixelFormatView on every texture/ { gpfv = "lossless compression off (D9MT_TEX_PFV=1)" }
    /D9MT: end-of-pass barrier before Fragment/ { gbar = "narrow pass barrier" }
    /D9MT: end-of-pass barrier before all stages/ { gbar = "pass barrier before all stages" }
    /D9MT: a clear that ends a pass skips/ { gclr = "clears skip stores" }
    /D9MT: a clear that ends a pass keeps/ { gclr = "clears keep stores" }
    /Found config env: / { cfgenv = $0; sub(/.*Found config env: /, "", cfgenv) }
    # shaders with the patterns the converter fix of d9mt 6fa5df7 covers (once per shader):
    # "D3D9 SM3 hazard: ps_<hash> PS crs-partial-mask:r2.yz packed-io:..."
    /D3D9 SM3 hazard: / {
      nhz++; l = $0; sub(/.*D3D9 SM3 hazard: [^ ]+ [^ ]+ /, "", l)
      nk = split(l, hk, " ")
      for (i = 1; i <= nk; i++) { k = hk[i]; sub(/:.*/, "", k); if (!(k in hzk)) { hzk[k] = 1; hzl = hzl (hzl == "" ? "" : ", ") k } }
    }
    # the pipeline state cache (lines at the start, when the prewarm drains, every 60 s, at the end)
    / STATECACHE off/ { scoff = $0; sub(/.* STATECACHE /, "", scoff); next }
    / STATECACHE load / {
      scload = sprintf("%s, %d entries, %d to prewarm%s", field("status"), num(field("entries")), num(field("prewarmable")),
        num(field("invalid")) ? sprintf(", %d invalid dropped", num(field("invalid"))) : "")
      if (index($0, " guard=tripped")) scguard = "tripped"
      next
    }
    / STATECACHE the last session ended while prewarm/ || / STATECACHE [0-9]+ sessions in a row ended/ {
      scguardmsg = $0; sub(/.* STATECACHE /, "", scguardmsg); next
    }
    / STATECACHE prewarm t=/ {
      v = field("t"); sub(/s$/, "", v)
      scpw = sprintf("built %d, failed %d, skipped %d, done %.1f s after the start (%d ms of builds, paused %d ms)",
        num(field("built")), num(field("failed")), num(field("skipped")), num(v), num(field("buildMs")), num(field("pausedMs")))
      next
    }
    / STATECACHE use t=/ {
      scuse = sprintf("hits %d, late %d, misses %d (build time saved %d ms)",
        num(field("hits")), num(field("late")), num(field("misses")), num(field("hitBuildMs")))
      screc = num(field("recorded")); scboost = num(field("boosts"))
      next
    }
    / STATECACHE write entries=/ { scwr = sprintf("%d entries, %d KB", num(field("entries")), num(field("bytes")) / 1024); next }
    / STATECACHE write failed/ { scwr = "failed"; next }
    # StretchRect and ColorFill by path: " | stretch copy=2 ... skip=0 | fill rt=1 ... skip=0"
    / XFER t=/ || / XFER-SUMMARY / {
      summary = index($0, "XFER-SUMMARY") > 0
      if (!summary) { if (num(field("t")) <= skip || !int_t(num(field("t")))) next; nxs++ } else if (skip || marked) next
      nseg = split($0, seg, / \| /)
      for (i = 2; i <= nseg; i++) {
        kind = seg[i]; sub(/ .*/, "", kind)
        nt = split(seg[i], tok, /[ ()]+/)
        for (j = 2; j <= nt; j++) {
          if (tok[j] !~ /=/) continue
          k = kind "_" tok[j]; sub(/=.*/, "", k); v = tok[j]; sub(/.*=/, "", v)
          if (summary) xsum[k] = num(v); else xlin[k] += num(v)
          if (summary) hasxsum = 1
        }
      }
      next
    }

    / STATS t=/ {
      t = num(field("t"))
      if (t < lastT) { resets++ }        # a second device: counted on
      lastT = t
      kw++
      if (t <= skip || !ink(kw)) next
      fps = num(field("fps")); split(field("ms"), ms, "/")
      nall++; frames += fps
      # the frame rate and frame times: seconds the window showed the game only
      if (hid[kw]) { hsecs++; hframes += fps }
      else {
        ns++; f[ns] = fps
        vframes += fps; ftime += num(ms[1]) * fps
        if (fps < 58) below58++
        p99[ns] = num(ms[2]); if (num(ms[3]) > maxft) maxft = num(ms[3])
        s33 += num(field("slow33")); s50 += num(field("slow50"))
      }
      rp += num(field("rp")) * fps; skp += num(field("skip")) * fps; cb += num(field("cb")) * fps
      dr += num(field("draws")) * fps; rst += num(field("restore")) * fps
      saved += num(field("savedMiB")) * fps
      if (field("attMs") != "") {
        na++; v = num(field("attMs")); attMs += v; if (v > attMax) attMax = v
        cfold += num(field("clrFold")) * fps; cpass += num(field("clrPass")) * fps
      }
      sh += num(field("sh")); pso += num(field("pso"))
      split(field("wait"), w, "/"); waits += num(w[1]); waitMs += num(w[2])
      a = num(field("allocMiB")); if (a > memPeak) memPeak = a
      att = field("att")
      if (field("split") != "") {
        nspl++; spl += num(field("split")) * fps; splSub += num(field("splitSubmit")) * fps
        splMiB += num(field("splitMiB")) * fps
      }
      next
    }
    / HITCH frame=/ {
      if (hid[kw + 1] || !ink(kw + 1)) next    # in the second the next STATS line closes
      nh++
      dt = num(field("dtMs")); hitchMs += dt
      in9 = num(field("inD9mtMs"))
      # the frame is d9mt'"'"'s when most of it was spent inside d9mt, or waiting on its render thread
      line = $0; cs = line; sub(/.*\| cs: /, "", cs)
      split(cs, cw, " "); rw = 0
      for (i in cw) if (cw[i] ~ /^renderWait=/) { v = cw[i]; sub(/.*\//, "", v); rw = num(v) }
      if (in9 + rw >= dt / 2) { nd++; dMs += dt } else { ng++; gMs += dt }
      # categories: "name=count/ms[/MiB]" between the first and the second "|"
      mid = line; sub(/^[^|]*\| /, "", mid); sub(/ \| cs:.*/, "", mid)
      nc = split(mid, parts, " ")
      for (i = 1; i <= nc; i++) {
        if (parts[i] !~ /=/) continue
        name = parts[i]; sub(/=.*/, "", name)
        v = parts[i]; sub(/^[^=]*=[0-9]*\//, "", v); sub(/ms.*/, "", v)
        if (name == "present" || name == "latencyWait" || name == "bgSleep" || name == "capSleep") continue   # mostly vsync/latency waits, the background and frame cap sleeps
        cat[name] += num(v)
      }
      if (rw > 0) cat["renderWait(compiles)"] += rw
      next
    }
    / COMPILE frame=/ {
      if (!ink(kw + 1)) next
      nco++
      dt = num(field("dtMs")); if (dt > 33.4) c33++; if (dt > 50) c50++
      split(field("renderWait"), w, "/"); cwaits += num(w[1]); v = w[2]; sub(/ms/, "", v); cwaitMs += num(v)
      v = field("shaders"); sub(/\/.*/, "", v); csh += num(v)
      v = field("psos"); sub(/\/.*/, "", v); cpso += num(v)
      next
    }
    / RESTORE t=/ {
      if (num(field("t")) <= skip || !int_t(num(field("t")))) next
      nrl++
      # " | 120x 2048x2048 Depth32Float_Stencil8 s sample@Draw | ... | +3 other"
      rl = $0; sub(/^[^|]*\| /, "", rl)
      nr = split(rl, rparts, / \| /)
      for (i = 1; i <= nr; i++) {
        p = rparts[i]
        if (p ~ /^\+[0-9]+ other/) { v = p; sub(/^\+/, "", v); sub(/ .*/, "", v); rc["(other: below a second'"'"'s top 5)"] += num(v); continue }
        if (p !~ /^[0-9]+x /) continue
        v = p; sub(/x .*/, "", v); k = p; sub(/^[0-9]+x /, "", k)
        rc[k] += num(v); rtot += num(v)
      }
      next
    }
    / RESTORE-SUMMARY frames=/ {
      rs = $0; sub(/.*RESTORE-SUMMARY /, "", rs); sub(/ \|.*/, "", rs)
      next
    }
    / PACE t=/ {
      if (num(field("t")) <= skip || !int_t(num(field("t")))) next
      np++
      split(field("present"), pr, "/"); psd[np] = num(field("sd")); pmax[np] = num(pr[3])
      split(field("d9mt"), dm, "/"); pd9[np] = num(dm[2])
      split(field("game"), gm, "/"); pgame[np] = num(gm[2]); pgmax[np] = num(gm[3])
      pwait[np] = num(field("wait"))
      v = field("cpu"); if (v != "n/a" && v != "") { npc++; pcpu[npc] = num(v); pbusy[npc] = num(field("d9mtBusy")); pgc[npc] = num(field("gameCpu")) }
      next
    }
    / THREADCPU [0-9.]+ s: / {
      if (!ink(kw + 1)) next
      ntc++
      l = $0; sub(/.* THREADCPU /, "", l)
      v = l; sub(/.*: process /, "", v); sub(/ ms.*/, "", v); tcp[ntc] = num(v)
      v = l; sub(/.*wineserver /, "", v); sub(/ ms.*/, "", v); tcw[ntc] = num(v)
      v = l; sub(/.*busiest \(ms\): /, "", v)
      nb = split(v, bt, ", ")
      for (i = 1; i <= nb; i++) {
        id = bt[i]; sub(/ [0-9]+$/, "", id)            # "1a2b3" or "1a2b3 \"name\""
        tms = bt[i]; sub(/.* /, "", tms)
        tct[id] += num(tms)
        if (i == 1) { ntop1++; top1[ntop1] = num(tms) }
      }
      next
    }
    / RAWMOUSE [0-9.]+ s: / {
      if (!ink(kw + 1)) next
      nrm++
      l = $0
      v = l; sub(/.*gcmouse /, "", v); sub(/ events.*/, "", v); gce = num(v); rmg += gce
      v = l; sub(/.*: nsevent /, "", v); sub(/ events.*/, "", v); rmn += num(v)
      v = l; sub(/.*nsevent left out /, "", v); sub(/ events.*/, "", v); rml += num(v)
      if (gce > 0) { ngc++; gcs[ngc] = gce }
      v = l; sub(/ GCMouse device.*/, "", v); sub(/.* /, "", v); rmdev = num(v)
      # the last measured ratio (0 until the first measurement)
      v = l; sub(/.*pixels\/count /, "", v); sub(/ \(.*/, "", v); if (num(v) > 0) rmppc = v
      v = l; sub(/.*speed /, "", v); rmspeed = v
      next
    }
    / DIAG MEM frame=/ {
      if (!ink(kw + 1)) next
      a = num(field("allocatedMiB")); if (a > diagPeak) diagPeak = a
      fr = num(field("frame")); if (fr > lastFrame) lastFrame = fr
      next
    }
    END {
      print "stats=" nall + 0
      # what the numbers are, and what is left out or lost
      if (prof) print "mode=instrumented: Debug Logging on (d9mt profiling): not ordinary play'"'"'s frame times"
      else print "mode=ordinary play (Debug Logging off): no frame times in the log, the Metal HUD only"
      if (nw) {
        if (marklen > 0 && !marked) print "interval=the whole session" (skip ? sprintf(" after the first %d s", skip) : "") ": no mark (no return to the game window)"
        else if (ivdev) printf "interval=none: a second device started before the %d s after the mark%s ended\n", marklen, (retat != "" ? " at " retat : "")
        else if (ivempty) printf "interval=none: the session ended within %d s of the mark%s\n", settle + marklen, (retat != "" ? " at " retat : "")
        else if (ivshort) printf "interval=STATS t %d-%d, %d s of the %d asked (the session ended), from %d s after the mark%s; %d lines\n",
          its0, tof[ke], ivcov, marklen, settle, (retat != "" ? " at " retat : ""), ke - ks + 1
        else if (marked) printf "interval=STATS t %d-%d, %d s from %d s after the mark%s; %d lines\n", its0, ite, marklen, settle,
          (retat != "" ? " at " retat : ""), ke - ks + 1
        else print "interval=the whole session" (skip ? sprintf(" after the first %d s", skip) : "")
      }
      d = ""
      if (!header) d = d "; no SWTOR on Mac line at the start (the log'"'"'s start is missing, or SWTOR on Mac 0.0.x)"
      if (marklen > 0 && nw && !marked) d = d "; no mark"
      if (ivshort || ivempty) d = d "; the interval is short"
      if (ivdev) d = d "; no interval: a second device after the mark"
      if (marked && !ivshort && !ivempty && !ivdev && ivcov < marklen) d = d sprintf("; %d s of the interval in a STATS window that began before it or ended after it (left out)", marklen - ivcov)
      if (ivsettlegap) d = d sprintf("; a STATS window of 2 s or more in the %d s after the mark", settle)
      if (marked && hsecs) d = d sprintf("; %d s of the interval hidden or switching (left out)", hsecs)
      ng2 = marked ? ivgap : ngap; gmx = marked ? ivgapmax : gapmax
      if (ng2) d = d sprintf("; %d STATS window%s of 2 s or more%s (the longest %d s: a frame that long, or no Present)", ng2, (ng2 > 1 ? "s" : ""),
        (marked ? sprintf(", %d s of the interval", ivgaps) : ""), gmx)
      if (nsupp) d = d sprintf("; %d visibility or throttle line%s suppressed by d9mt (those seconds left out)", nsupp, (nsupp > 1 ? "s" : ""))
      if (!marked && resets) d = d "; a second device (its seconds counted from 0 again)"
      # the interval is whole: every second of it in STATS windows of its own, shown, none lost
      # (and every one of its STATS lines counted: nothing else took any out)
      if (marklen > 0) print "interval_ok=" ((marked && !ivshort && !ivempty && !ivdev && ivcov == marklen && !ivgap && !ivsettlegap && !hsecs && nall == ke - ks + 1) ? "yes" : "no")
      print "data=" (d == "" ? "nothing left out or lost" : substr(d, 3))
      if (settings != "") print "settings=" settings
      if (conds != "") print "conditions=" conds
      if (dfiles != "") print "d9mt_files=" dfiles
      if (nall) {
        printf "duration=%d\n", nall
        if (hsecs) printf "hidden=%d s, not counted below (%.1f fps)\n", hsecs, hframes / hsecs
        if (ns) {
          qs(f, 1, ns); qs(p99, 1, ns)
          printf "frames=%d\n", vframes
          printf "fps_avg=%.1f\n", vframes / ns
          if (hsecs) printf "fps_avg_all=%.1f\n", frames / nall
          printf "fps_median=%.1f\n", pct(f, ns, 0.5)
          printf "fps_p1=%.1f\n", pct(f, ns, 0.01)
          printf "below58=%.1f\n", 100 * below58 / ns
          printf "ft_avg=%.2f\n", ftime / (vframes ? vframes : 1)
          printf "ft_p99_median=%.1f\n", pct(p99, ns, 0.5)
          printf "ft_max=%.1f\n", maxft
          print "ft_p99_session=missing (see below)"
          print "fps_low1=missing (see below)"
          printf "slow33=%d\nslow50=%d\n", s33, s50
        }
        if (frames) {
          printf "rp=%.1f\nskip=%.1f\ncb=%.1f\ndraws=%.0f\nrestore=%.2f\n", rp / frames, skp / frames, cb / frames, dr / frames, rst / frames
          printf "saved_mib_frame=%.1f\n", saved / frames
          printf "saved_gib=%.1f\n", saved / 1024
        }
        printf "compiles=%d shaders, %d pipelines\n", sh, pso
        printf "compile_waits=%d / %.0f ms\n", waits, waitMs
        if (na) {
          printf "att_cpu=%.2f ms/s (worst second %.2f)\n", attMs / na, attMax
          if (frames) printf "clears=%.1f folded, %.1f own pass\n", cfold / frames, cpass / frames
        }
        if (memPeak) printf "mem_peak=%d\n", memPeak
        printf "att=%s\n", att
        if (nspl && frames) printf "split=%.1f (%.1f with a submit), %.0f MiB loaded again\n", spl / frames, splSub / frames, splMiB / frames
      } else {
        if (lastFrame) printf "frames=%d\n", lastFrame
        if (nco) {
          printf "slow33_rt=%d\nslow50_rt=%d\n", c33, c50
          printf "compiles=%d shaders, %d pipelines\n", csh, cpso
          printf "compile_waits=%d / %.0f ms\n", cwaits, cwaitMs
        }
        printf "att=%s\n", attoff ? "off" : "n/a"
      }
      if (diagPeak > memPeak) printf "mem_peak=%d\n", diagPeak
      printf "hitches=%d\n", nh
      if (nh) {
        printf "hitch_ms=%.0f\n", hitchMs
        printf "hitch_d9mt=%d (%.0f%% of hitch time)\n", nd, 100 * dMs / (hitchMs ? hitchMs : 1)
        printf "hitch_game=%d (%.0f%% of hitch time)\n", ng, 100 * gMs / (hitchMs ? hitchMs : 1)
        top = ""
        for (k = 0; k < 3; k++) {
          best = ""; bv = 0
          for (c in cat) if (!(c in used) && cat[c] > bv) { best = c; bv = cat[c] }
          if (best == "") break
          used[best] = 1
          top = top (top == "" ? "" : ", ") sprintf("%s %.0f ms", best, bv)
        }
        print "hitch_top=" (top == "" ? "-" : top)
      }
      if (nrl) {
        printf "restore_seconds=%d\n", nrl
        for (k = 1; k <= 8; k++) {
          best = ""; bv = 0
          for (c in rc) if (!(c in rused) && rc[c] > bv) { best = c; bv = rc[c] }
          if (best == "") break
          rused[best] = 1
          if (frames) printf "restore_cause_%d=%7.2f/frame %7dx  %s\n", k, bv / frames, bv, best
          else        printf "restore_cause_%d=%7dx  %s\n", k, bv, best
        }
      }
      if (rs != "") print "restore_summary=" rs
      if (mp != "") print "memory_profile=" mp
      if (budget != "") print "wait_budget=" budget
      if (ab != "") print "ab=" ab
      if (fpsl != "") print "fps_limit=" fpsl
      if (fcap != "") print "fps_cap=" fcap
      if (flc != "") print "flush_cap=" flc
      if (dflc != "") print "flush_cap_d9mt=" dflc
      if (gpfv != "" || gbar != "" || gclr != "") {
        g = gpfv
        if (gbar != "") g = g (g == "" ? "" : ", ") gbar
        if (gclr != "") g = g (g == "" ? "" : ", ") gclr
        print "gpu_path=" g
      }
      if (cfgenv != "") print "config_env=" cfgenv
      if (nhz) printf "sm3_hazards=%d shaders (%s)\n", nhz, hzl
      if (scoff != "") print "statecache=" scoff
      else if (scload != "") print "statecache=" scload
      if (scpw != "") print "statecache_prewarm=" scpw
      if (scuse != "") printf "statecache_use=%s, %d new recorded%s\n", scuse, screc, scboost ? sprintf(", %d prewarms sped up", scboost) : ""
      if (scguardmsg != "") print "statecache_guard=" scguardmsg
      else if (scguard != "") print "statecache_guard=" scguard
      if (scwr != "") print "statecache_write=" scwr
      if (hasxsum || nxs) {
        if (hasxsum) { for (k in xsum) xt[k] = xsum[k]; xwhen = "session total" }
        else { for (k in xlin) xt[k] = xlin[k]; xwhen = sprintf("%d seconds with any", nxs) }
        xany = 0; for (k in xt) xany += xt[k]
      }
      if (xany) {
        printf "xfer_stretch=copy %d, resolve %d, blit %d (scaled %d, linear %d, convert %d, msaa %d), left alone %d (%s)\n",
          xt["stretch_copy"], xt["stretch_resolve"], xt["stretch_blit"], xt["stretch_scaled"], xt["stretch_linear"],
          xt["stretch_convert"], xt["stretch_msaa"], xt["stretch_skip"], xwhen
        printf "xfer_fill=render target %d, part %d, block-compressed %d, left alone %d\n",
          xt["fill_rt"], xt["fill_rect"], xt["fill_bc"], xt["fill_skip"]
      }
      if (resets) print "devices=" resets + 1
      if (np) {
        qs(psd, 1, np); qs(pmax, 1, np); qs(pd9, 1, np); qs(pgame, 1, np); qs(pgmax, 1, np); qs(pwait, 1, np)
        printf "pace_seconds=%d\n", np
        printf "pace_present_sd=%.2f ms median, %.2f p90 (max interval: %.1f median, %.1f p90)\n", pct(psd, np, 0.5), pct(psd, np, 0.9), pct(pmax, np, 0.5), pct(pmax, np, 0.9)
        printf "pace_frame=d9mt %.1f ms (of it waiting %.1f), game %.1f ms (worst frame of a second: %.1f median, %.1f p90)\n", pct(pd9, np, 0.5), pct(pwait, np, 0.5), pct(pgame, np, 0.5), pct(pgmax, np, 0.5), pct(pgmax, np, 0.9)
        if (npc) {
          qs(pcpu, 1, npc); qs(pbusy, 1, npc); qs(pgc, 1, npc)
          printf "pace_cpu=%d ms/s median (d9mt %d, game %d), %d p90\n", pct(pcpu, npc, 0.5), pct(pbusy, npc, 0.5), pct(pgc, npc, 0.5), pct(pcpu, npc, 0.9)
          printf "pace_cpu_med=%d\n", pct(pcpu, npc, 0.5)
        }
      }
      if (ntc) {
        qs(tcp, 1, ntc); qs(tcw, 1, ntc); qs(top1, 1, ntop1)
        printf "threadcpu_seconds=%d\n", ntc
        printf "cpu_process=%d ms/s median, %d p90, %d max\n", pct(tcp, ntc, 0.5), pct(tcp, ntc, 0.9), tcp[ntc]
        printf "cpu_process_med=%d\n", pct(tcp, ntc, 0.5)
        printf "cpu_busiest=%d ms/s median, %d p90, %d max\n", pct(top1, ntop1, 0.5), pct(top1, ntop1, 0.9), top1[ntop1]
        printf "cpu_wineserver=%d ms/s median, %d p90, %d max\n", pct(tcw, ntc, 0.5), pct(tcw, ntc, 0.9), tcw[ntc]
        top = ""
        for (k = 0; k < 4; k++) {
          best = ""; bv = -1
          for (c in tct) if (!(c in tused) && tct[c] > bv) { best = c; bv = tct[c] }
          if (best == "") break
          tused[best] = 1
          top = top (top == "" ? "" : ", ") sprintf("%s %.0f", best, bv / ntc)
        }
        print "cpu_threads=" top
      }
      if (nfw != "" || nfany) {
        if (nfw == "on") print "native_fullscreen=on, " (nfon ? "the driver confirmed it (NATIVEFS: on)" : "not confirmed by the driver (no NATIVEFS: on line)")
        else if (nfw != "") print "native_fullscreen=" nfw (nfon ? ", but the driver said NATIVEFS: on" : "")
        else print "native_fullscreen=no wrapper line" (nfon ? ", the driver said NATIVEFS: on" : "")
        if (nfpend) nfnoent++
        if (nfon || nfent || nfexit) {
          printf "nativefs_entries=%d entered, %d started\n", nfentd, nfent
          nfrs = ""; for (k = 1; k <= nfrn; k++) nfrs = nfrs (k > 1 ? ", " : "") nfrorder[k] " " nfreason[nfrorder[k]]
          printf "nativefs_exits=%d%s\n", nfexit, (nfrs == "" ? "" : " (" nfrs ")")
          if (nfreason["fight"] > nffight) nffight = nfreason["fight"]
          nffs = ""
          if (nfefail) nffs = nffs ", enter failed " nfefail
          if (nfxfail) nffs = nffs ", exit failed " nfxfail
          if (nfstuck) nffs = nffs ", stuck " nfstuck
          if (nffight) nffs = nffs ", fight " nffight
          print "nativefs_failures=" (nffs == "" ? "none" : substr(nffs, 3))
          if (nfmax) printf "nativefs_longest=%s ms (%s)\n", nfmax, nfmaxw
        }
        nfws = ""
        if (nfw == "on" && !nfon) nfws = nfws "; the wrapper turned it on, the driver never said NATIVEFS: on (the engine'"'"'s own Mac driver ran?)"
        if (nfnoent) nfws = nfws sprintf("; %d enter without entered or enter failed", nfnoent)
        if (nfstuck) nfws = nfws "; stuck in the Space"
        if (nffight) nfws = nfws "; a fight over the window size"
        if (nfws != "") print "nativefs_warning=" substr(nfws, 3)
      }
      if (nrm) {
        qs(gcs, 1, ngc)
        printf "rawmouse_seconds=%d\n", nrm
        printf "rawmouse_events=GCMouse %d, AppKit %d sent, %d left out\n", rmg, rmn, rml
        if (ngc) printf "rawmouse_gc_rate=%d/s median (seconds with GCMouse moves: %d)\n", pct(gcs, ngc, 0.5), ngc
        printf "rawmouse_calibration=%d GCMouse device(s), %s pixels/count, speed %s\n", rmdev, (rmppc == "" ? "not measured" : rmppc), rmspeed
      }
    }' "$1" "$1"
}

get() { sed -n "s/^$1=//p" "$2" | head -1; }

# build_of <log>: "0.1.0-dev.1 cx-26.3.0-8 d9mt 68c7190" (app, Wine engine, d9mt) from the
# wrapper's first line in wine.log (none in logs of 0.0.x); started_of <log>: its start time
build_of() {
  sed -n '1,5s/^SWTOR on Mac \([^:]*\): engine [^ ]* \([^,]*\), d9mt \([^,]*\), started .*/\1 \2 d9mt \3/p' "$1" | head -1
}
started_of() {
  sed -n '1,5s/^SWTOR on Mac [^:]*: engine .*, started \(.*\)$/\1/p' "$1" | head -1
}

# The analysis files, one per session (AN[0] alone, or 2 to 5 side by side), the logs' names;
# W: the width of a column but the last
AN=() ARMS=() W=36 HEADLINE=""
LETTERS=ABCDE
# label key: one line of the report from the analysis files (left out when no log has it)
row() {
  local label=$1 key=$2 i n=${#AN[@]} v any="" line
  local vals=()
  for ((i = 0; i < n; i++)); do v=$(get "$key" "${AN[$i]}"); vals[$i]=$v; any="$any$v"; done
  [ -n "$any" ] || return 0
  if [ "$n" -eq 1 ]; then printf '  %-38s %s\n' "$label" "${vals[0]}"; return 0; fi
  line=$(printf '  %-38s' "$label")
  for ((i = 0; i < n; i++)); do
    v=${vals[$i]:-n/a}
    if [ "$i" -lt $((n - 1)) ]; then line="$line $(printf "%-${W}s" "$v")"; else line="$line $v"; fi
  done
  printf '%s\n' "$line"
}

report() {
  local i n=${#AN[@]} per=""
  [ "$SKIP" -gt 0 ] && echo "  (first $SKIP s left out)"
  # what each session ran on and how it was measured: in a block of its own per session when
  # there are more (too long for columns)
  if [ "$n" -eq 1 ]; then ident "${AN[0]}" "  %-38s %s\n"
  else
    for ((i = 0; i < n; i++)); do
      echo "  ${LETTERS:$i:1}: ${ARMS[$i]}"
      ident "${AN[$i]}" "    %-36s %s\n"
    done
    printf '%s\n' "$HEADLINE"
  fi
  row "Seconds with STATS lines" duration
  row "  window hidden or switching" hidden
  row "Frames" frames
  row "FPS: average" fps_avg
  row "  with the hidden seconds" fps_avg_all
  row "FPS: median second" fps_median
  row "FPS: worst 1% of seconds" fps_p1
  row "FPS: 1% low (slowest 1% of frames)" fps_low1
  row "Seconds below 58 fps (%)" below58
  row "Frame time: average (ms)" ft_avg
  row "Frame time: median second's p99 (ms)" ft_p99_median
  row "Frame time: the session's p99" ft_p99_session
  row "Frame time: worst (ms)" ft_max
  row "Frames over 33 ms" slow33
  row "Frames over 50 ms" slow50
  row "Render-thread frames > 33 ms" slow33_rt
  row "Render-thread frames > 50 ms" slow50_rt
  row "Hitches (frames over 50 ms)" hitches
  row "  total hitch time (ms)" hitch_ms
  row "  d9mt's" hitch_d9mt
  row "  the game's" hitch_game
  row "  top d9mt causes" hitch_top
  row "Compiles" compiles
  row "Render-thread compile waits" compile_waits
  row "Memory peak (Metal, MiB)" mem_peak
  row "Render passes per frame" rp
  row "  skipped (no-op) per frame" skip
  row "Command buffers per frame" cb
  row "Draws per frame" draws
  row "Attachment traffic saved (MiB/frame)" saved_mib_frame
  row "  over the session (GiB)" saved_gib
  row "  re-clears per frame" restore
  row "  its render-thread CPU time" att_cpu
  row "Clears per frame" clears
  row "Attachment optimization" att
  row "Memory profile" memory_profile
  row "Pipeline wait budget" wait_budget
  row "A/B switches (d9mt-ab.sh)" ab
  row "Frame Rate Limit" fps_limit
  row "  d9mt's frame cap" fps_cap
  row "Fewer GPU Batches (flush cap)" flush_cap
  row "  d9mt's flush cap" flush_cap_d9mt
  row "GPU path" gpu_path
  row "DXVK_CONFIG" config_env
  row "Pass splits per frame" split
  row "Pipeline state cache" statecache
  row "  prewarm" statecache_prewarm
  row "  pipelines the game needed" statecache_use
  row "  guard (ended during a prewarm)" statecache_guard
  row "  written at the end" statecache_write
  row "StretchRect (XFER)" xfer_stretch
  row "ColorFill (XFER)" xfer_fill
  row "SM3 shaders the converter fix covers" sm3_hazards
  row "PACE seconds" pace_seconds
  row "  Present interval sd" pace_present_sd
  row "  per frame (medians)" pace_frame
  row "  game thread CPU" pace_cpu
  row "THREADCPU seconds" threadcpu_seconds
  row "  game process CPU" cpu_process
  row "  its busiest thread" cpu_busiest
  row "  wineserver CPU" cpu_wineserver
  row "  busiest threads (avg ms/s)" cpu_threads
  row "Raw mouse-look: seconds with moves" rawmouse_seconds
  row "  moves" rawmouse_events
  row "  GCMouse moves" rawmouse_gc_rate
  row "  speed" rawmouse_calibration
  row "Native fullscreen" native_fullscreen
  row "  entries" nativefs_entries
  row "  exits (by reason)" nativefs_exits
  row "  failures" nativefs_failures
  row "  longest transition" nativefs_longest
  row "  warning" nativefs_warning
  if [ "$n" -eq 1 ]; then causes "${AN[0]}" ""
  else for ((i = 0; i < n; i++)); do causes "${AN[$i]}" "${LETTERS:$i:1}: "; done; fi
  for ((i = 0; i < n; i++)); do per="$per$(get ft_p99_session "${AN[$i]}")"; done
  if [ -n "$per" ]; then
    echo "  (STATS lines have per-second numbers: a second's 99th percentile is its slowest frame at"
    echo "   100 frames a second or fewer, and the session's p99 and true 1% low are not in the log)"
  fi
}

# ident <analysis> <format>: the session's build, start, settings, measurement and data
ident() {
  local label key v
  while IFS='|' read -r label key; do
    v=$(get "$key" "$1")
    [ -z "$v" ] || printf "$2" "$label" "$v"
  done <<'ROWS'
SWTOR on Mac, Wine engine, d9mt|build
Game start|started
d9mt files (SHA-256)|d9mt_files
Settings at the start|settings
Power, thermal at the start|conditions
Measurement|mode
Interval|interval
Data|data
ROWS
}

# causes <analysis> <prefix>: the re-clears by cause, from the RESTORE lines
causes() {
  local k line n
  n=$(get restore_seconds "$1")
  [ -n "$n" ] || [ -n "$(get restore_summary "$1")" ] || return 0
  echo "  ${2}Re-clears by cause (RESTORE lines, ${n:-0} seconds with any):"
  for k in 1 2 3 4 5 6 7 8; do
    line=$(get "restore_cause_$k" "$1")
    [ -n "$line" ] && echo "    $line"
  done
  line=$(get restore_summary "$1")
  [ -z "$line" ] || echo "    session total at device release: $line"
}

# aba <first>: the three sessions from column <first> on as A/B/A arms (with more than three,
# the last three). Numbers only when every arm qualifies, else the reasons (the columns above
# stay): each arm names its build, d9mt files and settings (the wrapper's lines, 0.1.7 and
# later; without them nothing tells the arms apart), has instrumented frame times, and has the
# whole --mark interval (all <s> seconds in STATS windows of their own, shown, nothing short:
# every arm the same length, no tolerance); the first and the last ran the same build, d9mt
# files, A/B switches and settings. Then, per number, the drift between the two A arms and B
# against their mean. Arms of one sitting share the Mac's state and the scene: their frames
# are no independent samples, and this is no test.
aba() {
  local o=$1 j f k ok=1 why miss label key unit x y z
  local a=${AN[$1]} b=${AN[$1 + 1]} c=${AN[$1 + 2]}
  echo "The last three as A/B/A (${LETTERS:$o:1}, ${LETTERS:$o + 1:1}, ${LETTERS:$o + 2:1}: ${ARMS[$o]}, ${ARMS[$o + 1]}, ${ARMS[$o + 2]}):"
  for ((j = o; j < o + 3; j++)); do
    f=${AN[$j]} why="" miss=""
    for k in build settings d9mt_files; do [ -n "$(get "$k" "$f")" ] || miss="$miss, $k"; done
    [ -z "$miss" ] || why="; no ${miss#, } line (a log before 0.1.7, or its start is missing)"
    # known, not just there: both d9mt files hashed (not the wrapper's "unknown" after its
    # deadline, nor "missing"), and the build's version and d9mt named (not the wrapper's "?")
    k=$(get d9mt_files "$f")
    [ -z "$k" ] || printf '%s\n' "$k" | grep -qE '^d3d9\.dll [0-9a-f]{12}, winemetal\.so [0-9a-f]{12}$' ||
      why="$why; the d9mt files not verified ($k)"
    k=$(get build "$f")
    case "$k" in "" ) ;; *"?"*) why="$why; the build not known ($k)" ;; esac
    case "$(get mode "$f")" in instrumented*) ;; *) why="$why; no frame times (Debug Logging off)" ;; esac
    case "$(get interval_ok "$f")" in
      yes) ;;
      no) why="$why; the interval is not whole (Interval: $(get interval "$f" | grep . || echo "no STATS lines"); Data: $(get data "$f"))" ;;
      *) why="$why; no --mark interval" ;;
    esac
    [ -z "$why" ] || { ok=0; echo "  ${LETTERS:$j:1} (${ARMS[$j]}): ${why#; }"; }
  done
  # the A/B switches: none when the log has the settings line but no d9mt-ab line
  for k in build d9mt_files switches settings; do
    [ "$(sw "$k" "$a")" = "$(sw "$k" "$c")" ] || { ok=0; echo "  the first and the last differ in $k: not an A/B/A"; }
  done
  if [ "$ok" != 1 ]; then
    echo "  no A/B/A numbers: each arm needs its build, both d9mt files' hashes and settings, instrumented frame"
    echo "  times and the whole interval (all $MARK s), and the first and the last the same build"
    return 0
  fi
  [ "$(sw build "$a")|$(sw d9mt_files "$a")|$(sw switches "$a")|$(sw settings "$a")" != \
    "$(sw build "$b")|$(sw d9mt_files "$b")|$(sw switches "$b")|$(sw settings "$b")" ] ||
    echo "  B ran the same build, d9mt files, switches and settings as A: an A/A"
  while IFS='|' read -r label key unit; do
    x=$(get "$key" "$a"); y=$(get "$key" "$b"); z=$(get "$key" "$c")
    [ -n "$x" ] && [ -n "$y" ] && [ -n "$z" ] || continue
    awk -v l="$label" -v a="$x" -v b="$y" -v c="$z" -v u="$unit" 'BEGIN {
      m = (a + c) / 2
      printf "  %-36s A %s, A again %s (drift %+.2f%s); B %s: %+.2f%s against the A mean (%s)\n",
        l, a, c, c - a, u, b, b - m, u, (m != 0 ? sprintf("%+.1f%%", 100 * (b - m) / m) : "relative: n/a, the A mean is 0") }'
  done <<'ROWS'
FPS: average|fps_avg|
Frame time: average (ms)|ft_avg|
Seconds below 58 fps (%)|below58| pp
Game process CPU (ms/s, median)|cpu_process_med|
Game thread CPU (ms/s, median)|pace_cpu_med|
ROWS
  echo "  (one sitting: no significance test. A difference no larger than the drift shows nothing;"
  echo "   a speed claim needs the same A/B/A again on another day)"
}

# sw <key> <analysis>: get, and for "switches" the A/B switches, "none" when the log has the
# wrapper's settings line but no d9mt-ab line (unknown, empty, without the settings line)
sw() {
  if [ "$1" = switches ]; then
    if [ -n "$(get ab "$2")" ]; then get ab "$2"; elif [ -n "$(get settings "$2")" ]; then echo none; fi
  else get "$1" "$2"; fi
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# analysis <log> <file>: the analysis and the wrapper's first line
analysis() {
  analyze "$1" >"$2"
  { echo "build=$(build_of "$1")"; echo "started=$(started_of "$1")"; } >>"$2"
}

if [ -n "$COMPARE" ]; then
  [ $# -ge 2 ] && [ $# -le 5 ] || usage
  for f in "$@"; do [ -r "$f" ] || { echo "Cannot read $f" >&2; exit 1; }; done
  i=0 ns0=""
  for f in "$@"; do
    analysis "$f" "$tmp/$i"; AN[$i]="$tmp/$i"; ARMS[$i]=${f##*/}
    [ "$(get stats "$tmp/$i")" != 0 ] || ns0=1
    i=$((i + 1))
  done
  [ $# -eq 2 ] || W=28
  echo "SWTOR on Mac session report: comparison"
  # the columns' heading, above the numbers (report)
  HEADLINE=$(printf '  %-38s' "")
  for ((i = 0; i < $#; i++)); do
    if [ "$i" -lt $(($# - 1)) ]; then HEADLINE="$HEADLINE $(printf "%-${W}s" "${LETTERS:$i:1}: ${ARMS[$i]}")"
    else HEADLINE="$HEADLINE ${LETTERS:$i:1}: ${ARMS[$i]}"; fi
  done
  report
  if [ -n "$ns0" ]; then
    echo "  (n/a: no STATS lines in that log: Debug Logging was off, or the session ran a build"
    echo "   before 0.0.6-dev. Hitches and compile waits still compare.)"
  fi
  [ $# -lt 3 ] || { echo; aba $(($# - 3)); }
  exit 0
fi

[ $# -le 1 ] || usage
LOG="${1:-$LOGS/wine.log}"
[ -r "$LOG" ] || { echo "Cannot read $LOG" >&2; exit 1; }
analysis "$LOG" "$tmp/a"
AN=("$tmp/a")
echo "SWTOR on Mac session report: $LOG"
report
if [ "$(get stats "${AN[0]}")" = 0 ]; then
  echo "  (no STATS lines: Debug Logging was off, or the session ran a build before 0.0.6-dev;"
  echo "   frame numbers from HITCH/COMPILE/DIAG MEM lines only)"
fi
if [ -n "$KEEP" ]; then
  version=$(sed -n 's/^# SWTOR on Mac \([^:]*\):.*/\1/p' "$LOGS/../../Application Support/SWTOR on Mac/env" 2>/dev/null | head -1 || true)
  mkdir -p "$LOGS/sessions"
  dest="$LOGS/sessions/wine-$(date -r "$LOG" +%Y%m%d-%H%M)${version:+-$version}.log"
  cp "$LOG" "$dest"
  echo "Saved a copy: $dest"
fi
