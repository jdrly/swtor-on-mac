"""Compares three builds of ntdll.so: the engine's (reference), our stock rebuild and our
patched rebuild (scripts/build-ntdll.sh runs it before signing).

    python3 -I scripts/ntdll-compare.py ENGINE_SO STOCK_SO PATCHED_SO

Each pair is compared in its exports, imported symbols, linked libraries, and every function
(the symbols of __text, from nm, which keeps local ones): its code, disassembled, with
addresses, offsets and immediates masked (they move with the layout), so what is left is the
instructions, registers and the symbols called.
Engine vs stock (is the toolchain right?): all of that the same. (The files differ in layout:
athei's engine was linked by Xcode 26's ld, ours by a newer one, which orders a section
differently and sizes the stubs differently.)
Stock vs patched (do the patches change only what they should?): exports and libraries the
same, imports the same plus exactly PATCHED_IMPORTS, and the functions that differ are exactly
those in PATCHED_ONLY (all of them, so a patch that didn't apply shows too).
Exits non-zero otherwise.
"""
import bisect
import re
import subprocess
import sys

# what the patches change: patches/ntdll-msync-alert-fd.patch pthread_exit_wrapper,
# patches/ntdll-foreign-thread-faults.patch the three fault handlers and its own guard (a
# function of its own in this unoptimized build, so only in the patched file)
PATCHED_ONLY = {"_pthread_exit_wrapper", "_segv_handler", "_trap_handler", "_fpe_handler",
                "_is_foreign_thread_fault"}
# the imports they add: the guard's raise()
PATCHED_IMPORTS = {"_raise"}


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def exports(path):
    return sorted(line.split()[2] for line in run("nm", "-gU", path).splitlines() if len(line.split()) == 3)


def imports(path):
    return sorted(run("nm", "-u", path).split())


def libraries(path):
    return [re.sub(r" \(compatibility version.*\)$", "", line.strip()) for line in run("otool", "-L", path).splitlines()[1:]]


def normalize(insn):
    insn = re.sub(r"0x[0-9a-fA-F]+", "X", insn)     # addresses, offsets, immediates
    insn = re.sub(r"\$[_A-Za-z][\w.$]*", "$X", insn)  # an immediate otool names after a symbol at that address
    insn = re.sub(r"\s*## imm = .*", "", insn)          # (and then prints without its "## imm =" comment)
    insn = re.sub(r"\b\d+\b", "N", insn)
    insn = re.sub(r"## literal pool.*", "## literal", insn)
    return insn.strip()


def disassembly(path, *opts):
    """[(address, normalized instruction)] from otool's disassembly of __text"""
    code = []
    for line in run("otool", "-tV", *opts, path).splitlines():
        fields = line.split("\t", 1)
        if len(fields) == 2 and re.fullmatch(r"[0-9a-f]+", fields[0]):
            code.append((int(fields[0], 16), normalize(fields[1])))
    return code


def functions(path):
    """{name: [normalized instructions]} for the symbols of __text, each from its address to the next
    symbol's. Where otool's disassembly runs over a symbol's start (it decodes data in the code
    before it, such as a jump table, as instructions), that symbol is disassembled again from its
    start (otool -p), so where the layout puts a function doesn't change its code."""
    syms = []
    for line in run("nm", "-n", "-s", "__TEXT", "__text", path).splitlines():
        f = line.split()
        if len(f) == 3:
            syms.append((int(f[0], 16), f[2]))
    code = disassembly(path)
    addrs = [a for a, _ in code]
    starts = set(addrs)
    funcs = {}
    for k, (start, name) in enumerate(syms):
        end = next((a for a, _ in syms[k + 1:] if a > start), float("inf"))
        if start in starts:
            part = code[bisect.bisect_left(addrs, start):bisect.bisect_left(addrs, end)]
        else:
            part = [c for c in disassembly(path, "-p", name) if start <= c[0] < end]
        funcs.setdefault(name, []).extend(x for _, x in part)
    return funcs


def differing(a, b):
    return sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))


def main():
    engine, stock, patched = sys.argv[1:4]
    ok = True
    for what, get, added in (("exports", exports, set()), ("imported symbols", imports, PATCHED_IMPORTS),
                             ("linked libraries", libraries, set())):
        e, s, p = get(engine), get(stock), get(patched)
        if e != s:
            print(f"stock rebuild vs engine: {what} differ: {sorted(set(e) ^ set(s))[:10]}")
            ok = False
        expected = sorted(set(s) | added) if added else s   # (imports() is sorted)
        if p != expected or set(s) & added:
            print(f"patched vs stock: {what} differ: {sorted(set(s) ^ set(p))[:10]} (expected added: {sorted(added)})")
            ok = False
        elif e == s:
            print(f"{what}: {len(e)}, the same in all three" + (f", the patched one with {', '.join(sorted(added))}" if added else ""))
    fe, fs, fp = functions(engine), functions(stock), functions(patched)
    d = differing(fe, fs)
    print(f"functions: engine {len(fe)}, stock {len(fs)}, patched {len(fp)}")
    if d:
        print(f"stock rebuild vs engine: {len(d)} function(s) differ in code: {d[:10]}")
        ok = False
    else:
        print("stock rebuild vs engine: every function's code the same (addresses masked)")
    d = differing(fs, fp)
    if set(d) != PATCHED_ONLY:
        print(f"patched vs stock: functions that differ: {d[:10]} (expected: {sorted(PATCHED_ONLY)})")
        ok = False
    else:
        print("patched vs stock: only these differ: " + ", ".join(
            f"{n} ({len(fs.get(n, []))} -> {len(fp.get(n, []))} instructions)" for n in d))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
