#!/bin/bash
# Summary of one game session from d9mt's log lines in wine.log (Debug Logging on in Settings):
# frame rate, slow frames, hitches (d9mt's share vs the game's), shader/pipeline compile waits,
# memory peak, render passes and the attachment traffic d9mt's load/store optimization saved.
#
#   session-report.sh [--skip <s>] [--keep] [wine.log]   one session (default: the current
#                                                        ~/Library/Logs/SWTOR on Mac/wine.log)
#   session-report.sh [--skip <s>] --compare A.log B.log  two sessions side by side (before/after)
#
#   --skip <s>  leave out the first <s> seconds (loading screens, character select)
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
#   D3D9 SM3 hazard  (d9mt 6fa5df7 and later) a shader with the patterns its converter fix
#             covers, once per shader
# Also in Collect Logs (session-report.txt). Runs under macOS's /bin/bash 3.2 and awk.
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

SKIP=0 KEEP="" COMPARE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip) [ $# -ge 2 ] || usage; SKIP=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --compare) COMPARE=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) break ;;
  esac
done
case "$SKIP" in ''|*[!0-9]*) usage ;; esac

LOGS="${SWTOR_ON_MAC_ROOT:+$SWTOR_ON_MAC_ROOT/home}"
LOGS="${LOGS:-$HOME}/Library/Logs/SWTOR on Mac"

# analyze <log>: key=value lines
analyze() {
  LC_ALL=C awk -v skip="$SKIP" '
    function num(s) { return s + 0 }
    # value of key=... in this line ("" if none); stops at space
    function field(key,    p, s) {
      p = index($0, " " key "=")
      if (!p) return ""
      s = substr($0, p + length(key) + 2)
      sub(/[ |].*/, "", s)
      return s
    }
    # quicksort a[1..n]
    function qs(a, lo, hi,    i, last, t) {
      if (lo >= hi) return
      t = a[lo]; a[lo] = a[int((lo + hi) / 2)]; a[int((lo + hi) / 2)] = t
      last = lo
      for (i = lo + 1; i <= hi; i++) if (a[i] < a[lo]) { last++; t = a[last]; a[last] = a[i]; a[i] = t }
      t = a[lo]; a[lo] = a[last]; a[last] = t
      qs(a, lo, last - 1); qs(a, last + 1, hi)
    }
    function pct(a, n, p,    k) { if (!n) return ""; k = int((n - 1) * p + 0.5) + 1; return a[k] }
    function hex(s,    i, n) { n = 0; s = tolower(s); for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return n }
    # the presenter shows the game: visible, on the active Space, not in the Dock (d9mt'"'"'s isVisible)
    function shown(v) { return v % 2 == 1 && int(v / 2) % 2 == 1 && int(v / 4) % 2 == 0 }
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
      if ($0 ~ / STATS t=/) {
        t1 = num(field("t")); reset = nw && t1 < p1T; p1T = t1
        nw++
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
    }

    /D9MT: pipeline wait budget/ { budget = $0; sub(/.*budget /, "", budget); sub(/ per frame.*/, "", budget) }
    /D9MT: attachment load\/store optimization off/ { attoff = 1 }
    /D9MT: memory profile/ { mp = $0; sub(/.*memory profile /, "", mp); sub(/:.*/, "", mp) }
    /^SWTOR on Mac d9mt-ab: / { ab = $0; sub(/^SWTOR on Mac d9mt-ab: /, "", ab) }
    /^SWTOR on Mac frame rate limit: / { fpsl = $0; sub(/^SWTOR on Mac frame rate limit: /, "", fpsl) }
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
      if (!summary) { if (num(field("t")) <= skip) next; nxs++ } else if (skip) next
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
      if (t <= skip) next
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
      if (hid[kw + 1]) next    # in the second the next STATS line closes
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
      nco++
      dt = num(field("dtMs")); if (dt > 33.4) c33++; if (dt > 50) c50++
      split(field("renderWait"), w, "/"); cwaits += num(w[1]); v = w[2]; sub(/ms/, "", v); cwaitMs += num(v)
      v = field("shaders"); sub(/\/.*/, "", v); csh += num(v)
      v = field("psos"); sub(/\/.*/, "", v); cpso += num(v)
      next
    }
    / RESTORE t=/ {
      if (num(field("t")) <= skip) next
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
      if (num(field("t")) <= skip) next
      np++
      split(field("present"), pr, "/"); psd[np] = num(field("sd")); pmax[np] = num(pr[3])
      split(field("d9mt"), dm, "/"); pd9[np] = num(dm[2])
      split(field("game"), gm, "/"); pgame[np] = num(gm[2]); pgmax[np] = num(gm[3])
      pwait[np] = num(field("wait"))
      v = field("cpu"); if (v != "n/a" && v != "") { npc++; pcpu[npc] = num(v); pbusy[npc] = num(field("d9mtBusy")); pgc[npc] = num(field("gameCpu")) }
      next
    }
    / THREADCPU [0-9.]+ s: / {
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
      a = num(field("allocatedMiB")); if (a > diagPeak) diagPeak = a
      fr = num(field("frame")); if (fr > lastFrame) lastFrame = fr
      next
    }
    END {
      print "stats=" nall + 0
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
        }
      }
      if (ntc) {
        qs(tcp, 1, ntc); qs(tcw, 1, ntc); qs(top1, 1, ntop1)
        printf "threadcpu_seconds=%d\n", ntc
        printf "cpu_process=%d ms/s median, %d p90, %d max\n", pct(tcp, ntc, 0.5), pct(tcp, ntc, 0.9), tcp[ntc]
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
# wrapper's first line in wine.log (none in logs of 0.0.x)
build_of() {
  sed -n '1,5s/^SWTOR on Mac \([^:]*\): engine [^ ]* \([^,]*\), d9mt \([^,]*\), started .*/\1 \2 d9mt \3/p' "$1" | head -1
}

# label key [unit]: one line of the report from the analysis files A (and B)
row() {  # (left out when no log has it)
  local label=$1 key=$2 a b=""
  a=$(get "$key" "$A")
  [ -z "${B:-}" ] || b=$(get "$key" "$B")
  [ -n "$a$b" ] || return 0
  if [ -n "${B:-}" ]; then
    printf '  %-38s %-36s %s\n' "$label" "${a:-n/a}" "${b:-n/a}"
  else
    printf '  %-38s %s\n' "$label" "$a"
  fi
}

report() {
  [ "$SKIP" -gt 0 ] && echo "  (first $SKIP s left out)"
  row "SWTOR on Mac, Wine engine, d9mt" build
  row "Seconds with STATS lines" duration
  row "  window hidden or switching" hidden
  row "Frames" frames
  row "FPS: average" fps_avg
  row "  with the hidden seconds" fps_avg_all
  row "FPS: median second" fps_median
  row "FPS: 1% low (worst seconds)" fps_p1
  row "Seconds below 58 fps (%)" below58
  row "Frame time: average (ms)" ft_avg
  row "Frame time: median 99th pct (ms)" ft_p99_median
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
  causes "$A" "${B:+A: }"
  [ -z "${B:-}" ] || causes "$B" "B: "
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

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [ -n "$COMPARE" ]; then
  [ $# -eq 2 ] || usage
  for f in "$1" "$2"; do [ -r "$f" ] || { echo "Cannot read $f" >&2; exit 1; }; done
  analyze "$1" >"$tmp/a"; analyze "$2" >"$tmp/b"
  echo "build=$(build_of "$1")" >>"$tmp/a"; echo "build=$(build_of "$2")" >>"$tmp/b"
  A="$tmp/a" B="$tmp/b"
  echo "SWTOR on Mac session report: comparison"
  printf '  %-38s %-36s %s\n' "" "A: ${1##*/}" "B: ${2##*/}"
  report
  if [ "$(get stats "$A")" = 0 ] || [ "$(get stats "$B")" = 0 ]; then
    echo "  (n/a: no STATS lines in that log: Debug Logging was off, or the session ran a build"
    echo "   before 0.0.6-dev. Hitches and compile waits still compare.)"
  fi
  exit 0
fi

[ $# -le 1 ] || usage
LOG="${1:-$LOGS/wine.log}"
[ -r "$LOG" ] || { echo "Cannot read $LOG" >&2; exit 1; }
analyze "$LOG" >"$tmp/a"
echo "build=$(build_of "$LOG")" >>"$tmp/a"
A="$tmp/a" B=""
echo "SWTOR on Mac session report: $LOG"
report
if [ "$(get stats "$A")" = 0 ]; then
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
