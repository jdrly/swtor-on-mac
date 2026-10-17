"""Compares three builds of winemac.so: the engine's (reference), our stock rebuild and our
patched rebuild (scripts/build-winemac.sh runs it before stripping).

    python3 -I scripts/winemac-compare.py ENGINE_SO STOCK_SO PATCHED_SO

Engine vs stock (is the toolchain right?): it compares what survives stripping (the engine's
file may have no local symbols): exports, imported symbols, linked libraries, load-command
facts, every Objective-C method (by class and selector, with its code size from
LC_FUNCTION_STARTS) and the registry option names (UTF-16 strings).
Stock vs patched (does the patch change only what it should?): every function by name with
its code size, from the local symbols both rebuilds still have.
Exits non-zero if the stock rebuild does not match the engine's file in exports, libraries,
ObjC methods or options, or if the patches change anything outside the keyboard code, the
mouse and cursor code (the mouse patches) and option parsing.
"""
import bisect
import re
import subprocess
import sys

OPTIONS = ("CursorClippingLocksWindows", "RetinaMode", "PhysicalKeyboard", "RawMouseWhenCursorHidden",
           "RawMouseMatchPointerSpeed")
# what the patches may change: keyboard.c, the option parsing (setup_options, inlined into
# macdrv_init), the test hook in cocoa_app.m (a block); the mouse patches: mouse.c, the
# cursor functions of cocoa_app.m, mouse event bookkeeping in cocoa_event.m, the unix call
# table's new entry and the init handshake (wow64_init), the blocks of those files, and the
# static inline CoreGraphics helpers (one more copy where the patches use them)
ALLOWED = re.compile(r"^(_macdrv_compute_keyboard_layout|_macdrv_GetKeyNameText|_macdrv_MapVirtualKeyEx|_us_key_char"
                     r"|_setup_options|_macdrv_init|_macdrv_get_input_source_info"
                     r"|___macdrv_get_input_source_info_block_invoke"
                     r"|_send_mouse_input|_macdrv_(Get|Set)CursorPos|_macdrv_mouse_\w+|_macdrv_(create|release)_event"
                     r"|_macdrv_\w*(raw|cursor|mouse|game_controller)\w*|_\w*(raw_mouse|raw_moves|thread_cpu|gc_calib|gc_mouse)\w*"
                     r"|_find_wineserver|_is_mouse_event_type|_wow64_init|_CG(Rect|Point|Size)\w+"
                     r"|___macdrv_(set_cursor_position|get_cursor_position|clip_cursor)_block_invoke(_\d+)?)$")


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def info(path):
    starts = sorted(int(x, 16) for x in re.findall(r"0x[0-9A-Fa-f]+",
                                                    run("xcrun", "dyld_info", "-function_starts", path)))
    methods, meta, cls = {}, "-", None
    for line in run("otool", "-ov", path).splitlines():
        if line.startswith("Meta Class"):
            meta = "+"
        elif re.match(r"^[0-9a-f]+ 0x", line):
            meta = "-"
        elif line.startswith("        name "):
            cls = line.split()[2]
        elif line.startswith("            name "):
            sel = line.split()[2]
        elif line.startswith("            imp "):
            # relative method lists (minos 11 and later): "imp <offset> (<address>) -[Class sel]",
            # the selector only in the symbol; else "imp <address> [symbol]"
            m = re.match(r"\s+imp\s+\S+\s+\((0x[0-9a-fA-F]+)\)\s*(.*)$", line)
            addr = int(m.group(1), 16) if m else int(line.split()[1], 16)
            sym = (m.group(2) if m else " ".join(line.split()[2:])).strip()
            key = sym if re.match(r"^[-+]\[.* .*\]$", sym) else f"{meta}[{cls} {sel}]"
            i = bisect.bisect_right(starts, addr)
            methods[key] = starts[i] - addr if i < len(starts) else 0
    # functions by name (local symbols too, if there are any): size up to the next function
    syms = []
    for line in run("nm", "-n", "--defined-only", path).splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tT":
            syms.append((int(parts[0], 16), parts[2]))
    funcs = {}
    for i, (addr, name) in enumerate(syms):
        j = bisect.bisect_right(starts, addr)
        end = starts[j] if j < len(starts) else (syms[i + 1][0] if i + 1 < len(syms) else addr)
        # compiler-numbered helpers (___Block_byref_object_copy_.934) by base name: the
        # numbers shift when a file gets another block
        funcs.setdefault(re.sub(r"\.\d+$", "", name), []).append(end - addr)
    funcs = {k: sorted(v) for k, v in funcs.items()}
    data = open(path, "rb").read()
    lc = run("otool", "-l", path)
    return {
        "size": len(data),
        "functions": len(starts),
        "exports": sorted(l.split()[-1] for l in run("nm", "-gU", path).splitlines()),
        "imports": set(run("nm", "-u", path).split()),
        "libs": [l.split()[0] for l in run("otool", "-L", path).splitlines()[1:]],
        "rpaths": re.findall(r"path (\S+) \(offset", lc),
        "minos": re.findall(r"minos (\S+)", lc),
        "methods": methods,
        "funcs": funcs,
        # (optimized builds inline the names as UTF-16 stores, in pieces: look for their start;
        # unoptimized ones keep the C strings)
        "options": {k: k.encode() + b"\0" in data or k[:8].encode("utf-16-le") in data for k in OPTIONS},
    }


ref, stock, patched = (info(p) for p in sys.argv[1:4])
for name, x in (("engine", ref), ("stock", stock), ("patched", patched)):
    print(f"{name:8} {x['size']:7} bytes, {x['functions']} functions, {len(x['methods'])} ObjC methods, "
          f"minos {x['minos']}, rpaths {x['rpaths']}, options {x['options']}")
problems = []
r, s, p = ref["methods"], stock["methods"], patched["methods"]
if not ref["exports"] == stock["exports"] == patched["exports"]:
    problems.append("exports differ")
if ref["libs"] != stock["libs"]:
    problems.append(f"libraries differ: {sorted(set(ref['libs']) ^ set(stock['libs']))}")
if set(r) != set(s):
    problems.append(f"ObjC methods differ: {sorted(set(r) ^ set(s))}")
if ref["options"] != stock["options"]:
    problems.append("registry options differ between the engine and the stock rebuild")
for o in ("PhysicalKeyboard", "RawMouseWhenCursorHidden", "RawMouseMatchPointerSpeed"):
    if not patched["options"][o]:
        problems.append(f"the patched build has no {o} option")
print("exports:", ref["exports"])
print("imports only in engine:", sorted(ref["imports"] - stock["imports"]),
      "| only in stock:", sorted(stock["imports"] - ref["imports"]))
far = [(k, r[k], s[k]) for k in r if k in s and r[k] and abs(r[k] - s[k]) > 96 and abs(r[k] - s[k]) / r[k] > 0.3]
print(f"ObjC method code: engine {sum(r.values())} bytes, stock {sum(s.values())}; "
      f"methods differing >30% and >96 bytes: {far or 'none'}")

sf, pf = stock["funcs"], patched["funcs"]
changed = sorted(k for k in set(sf) | set(pf) if sf.get(k) != pf.get(k))
print("patched vs stock, functions changed (name: stock -> patched bytes):")
for k in changed:
    print(f"  {k}: {sf.get(k, '-')} -> {pf.get(k, '-')}")
print("patched vs stock, ObjC methods changed:", [k for k in s if s[k] != p.get(k)] or "none",
      "| imports changed:", sorted(stock["imports"] ^ patched["imports"]))
outside = [k for k in changed if not ALLOWED.match(k)]
if outside:
    problems.append(f"the patches change functions outside the keyboard and mouse code: {outside}")
if not sf:
    problems.append("no local symbols in the rebuilds (compare before stripping)")
if problems:
    print("PROBLEMS:", *problems, sep="\n  ")
    sys.exit(1)
print("OK: the stock rebuild matches the engine's file; the patches change only the keyboard and mouse code and options")
