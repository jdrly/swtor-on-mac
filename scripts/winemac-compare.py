"""Compares three builds of winemac.so: the engine's (reference), our stock rebuild and our
patched rebuild (scripts/build-winemac.sh runs it before stripping).

    python3 -I scripts/winemac-compare.py ENGINE_SO STOCK_SO PATCHED_SO

Engine vs stock (is the toolchain right?): the engine's file has no local symbols, so it
compares what survives stripping: exports, imported symbols, linked libraries, load-command
facts, every Objective-C method (by class and selector, with its code size from
LC_FUNCTION_STARTS) and the registry option names (UTF-16 strings).
Stock vs patched (does the patch change only what it should?): every function by name with
its code size, from the local symbols both rebuilds still have.
Exits non-zero if the stock rebuild does not match the engine's file in exports, libraries,
ObjC methods or options, or if the patch changes anything outside the keyboard code and
option parsing.
"""
import bisect
import re
import subprocess
import sys

OPTIONS = ("CursorClippingLocksWindows", "RetinaMode", "PhysicalKeyboard")
# what the patch may change: keyboard.c, the option parsing (setup_options, inlined into
# macdrv_init), the test hook in cocoa_app.m (a block)
ALLOWED = re.compile(r"^(_macdrv_compute_keyboard_layout|_macdrv_GetKeyNameText|_macdrv_MapVirtualKeyEx|_us_key_char"
                     r"|_setup_options|_macdrv_init|_macdrv_get_input_source_info"
                     r"|___macdrv_get_input_source_info_block_invoke)$")


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
            addr = int(line.split()[1], 16)
            i = bisect.bisect_right(starts, addr)
            methods[f"{meta}[{cls} {sel}]"] = starts[i] - addr if i < len(starts) else 0
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
        # (the names are inlined as UTF-16 stores, in pieces: look for their start)
        "options": {k: k[:8].encode("utf-16-le") in data for k in OPTIONS},
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
if not patched["options"]["PhysicalKeyboard"]:
    problems.append("the patched build has no PhysicalKeyboard option")
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
    problems.append(f"the patch changes functions outside the keyboard code: {outside}")
if not sf:
    problems.append("no local symbols in the rebuilds (compare before stripping)")
if problems:
    print("PROBLEMS:", *problems, sep="\n  ")
    sys.exit(1)
print("OK: the stock rebuild matches the engine's file; the patch changes only the keyboard code and options")
