"""Compares three builds of ntdll.so: the engine's (reference), our stock rebuild and our
patched rebuild (scripts/build-ntdll.sh runs it before signing).

    python3 -I scripts/ntdll-compare.py ENGINE_SO STOCK_SO PATCHED_SO

Each pair is compared in its exports, imported symbols, linked libraries, and every function
(from the local symbols all three have): its code, disassembled, with addresses, offsets and
immediates masked (they move with the layout), so what is left is the instructions, registers
and the symbols called.
Engine vs stock (is the toolchain right?): all of that the same. (The files differ in layout:
athei's engine was linked by Xcode 26's ld, ours by a newer one, which orders a section
differently and sizes the stubs differently.)
Stock vs patched (does the patch change only what it should?): exports, imports and libraries
the same, and only the functions in PATCHED_ONLY differ.
Exits non-zero otherwise.
"""
import re
import subprocess
import sys

# what patches/ntdll-msync-alert-fd.patch may change
PATCHED_ONLY = {"_pthread_exit_wrapper"}


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def exports(path):
    return sorted(line.split()[2] for line in run("nm", "-gU", path).splitlines() if len(line.split()) == 3)


def imports(path):
    return sorted(run("nm", "-u", path).split())


def libraries(path):
    return [re.sub(r" \(compatibility version.*\)$", "", line.strip()) for line in run("otool", "-L", path).splitlines()[1:]]


def functions(path):
    """{name: [normalized instructions]} from otool's disassembly of __text"""
    funcs, name = {}, None
    for line in run("otool", "-tV", path).splitlines()[1:]:
        if re.match(r"^[_A-Za-z.$][\w.$]*:$", line):
            name = line[:-1]
            funcs.setdefault(name, [])
            continue
        if name is None or not line.strip():
            continue
        fields = line.split("\t", 1)
        insn = fields[1] if len(fields) > 1 else fields[0]
        insn = re.sub(r"0x[0-9a-f]+", "X", insn)        # addresses, offsets, immediates
        insn = re.sub(r"\b\d+\b", "N", insn)
        insn = re.sub(r"## literal pool.*", "## literal", insn)
        funcs[name].append(insn.strip())
    return funcs


def differing(a, b):
    return sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))


def main():
    engine, stock, patched = sys.argv[1:4]
    ok = True
    for what, get in (("exports", exports), ("imported symbols", imports), ("linked libraries", libraries)):
        e, s, p = get(engine), get(stock), get(patched)
        if e != s:
            print(f"stock rebuild vs engine: {what} differ: {sorted(set(e) ^ set(s))[:10]}")
            ok = False
        if s != p:
            print(f"patched vs stock: {what} differ: {sorted(set(s) ^ set(p))[:10]}")
            ok = False
        print(f"{what}: {len(e)}, the same in all three" if e == s == p else f"{what}: DIFFER")
    fe, fs, fp = functions(engine), functions(stock), functions(patched)
    d = differing(fe, fs)
    print(f"functions: engine {len(fe)}, stock {len(fs)}, patched {len(fp)}")
    if d:
        print(f"stock rebuild vs engine: {len(d)} function(s) differ in code: {d[:10]}")
        ok = False
    else:
        print("stock rebuild vs engine: every function's code the same (addresses masked)")
    d = differing(fs, fp)
    if set(d) - PATCHED_ONLY or not d:
        print(f"patched vs stock: functions that differ: {d[:10]} (allowed: {sorted(PATCHED_ONLY)})")
        ok = False
    else:
        print(f"patched vs stock: only {', '.join(d)} differs "
              f"({len(fs[d[0]])} -> {len(fp[d[0]])} instructions)")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
