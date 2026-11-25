"""Serene's tests: the addon's Lua run outside the game, under Lua 5.1 (the game's), against a stub of the client.

    pip install --target ~/.cache/serene-tools/py lupa luaparser   # once
    python3 tools/test/run.py                  # every spec in tools/test/spec
    python3 tools/test/run.py loot bags        # specs whose file name has one of these words
    python3 tools/test/run.py -k "roll"        # only tests whose name has this
    python3 tools/test/run.py -v               # every test's name, and the globals the addon read that the stub lacks

Each test runs in a fresh Lua (see harness.lua). Exit code 1 when a test fails.
What a spec can use: tools/test/harness.lua (test, eq, ok...) and tools/test/wow.lua (the stub; wow.load, wow.fire...).
"""
import os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# (the packages live outside the addon: WoW scans everything under AddOns/)
sys.path.insert(0, os.path.expanduser("~/.cache/serene-tools/py"))
try:
    from lupa import lua51
except ImportError:
    sys.exit("lupa is missing: pip install --target ~/.cache/serene-tools/py lupa luaparser")


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fresh(spec):
    # (a Lua function's several results come back as a tuple: __run's verdict and message)
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    boot = lua.eval("function(code, name) local f, e = loadstring(code, name) if not f then error(e, 0) end return f() end")
    lua.execute("SERENE_ROOT = " + lua_string(ROOT))  # (wow.lua reads it as it loads)
    # (a chunk named @path makes errors and tracebacks name the file)
    for part in ("wow.lua", "globalstrings.lua", "harness.lua"):
        path = os.path.join(HERE, part)
        boot(open(path, encoding="utf-8").read(), "@" + os.path.relpath(path, ROOT))
    boot(open(spec, encoding="utf-8").read(), "@" + os.path.relpath(spec, ROOT))
    return lua


def main(argv):
    verbose = "-v" in argv
    argv = [a for a in argv if a != "-v"]
    only = None
    if "-k" in argv:
        at = argv.index("-k")
        only = argv[at + 1].lower()
        del argv[at:at + 2]
    folder = os.path.join(HERE, "spec")
    # (the folder's own files only: spec/lib holds helpers the specs dofile)
    specs = sorted(os.path.join(folder, f) for f in os.listdir(folder) if f.endswith(".lua"))
    if argv:
        specs = [s for s in specs if any(word.lower() in os.path.basename(s).lower() for word in argv)]
    passed, skipped, failed, missing = 0, [], [], {}
    started = time.time()
    for spec in specs:
        name = os.path.relpath(spec, ROOT)
        # (loaded once to count its tests; each test then gets a Lua of its own, the spec's top level run again)
        try:
            count = len(fresh(spec).globals().__tests)
        except Exception as problem:
            failed.append((name, "(loading the spec)", str(problem)))
            print(f"{name}: LOAD ERROR\n  {problem}")
            continue
        for index in range(1, count + 1):
            lua = fresh(spec)
            test_name = lua.globals().__tests[index].name
            if only and only not in test_name.lower():
                continue
            good, message = lua.globals().__run(index)
            for key, n in (lua.globals().wow.missing or {}).items():
                missing[key] = missing.get(key, 0) + n
            if good == "skip":
                skipped.append((name, test_name, message))
                print(f"  skip  {name}: {test_name} ({message})")
            elif good:
                passed += 1
                if verbose:
                    print(f"  ok    {name}: {test_name}")
            else:
                failed.append((name, test_name, message))
                print(f"  FAIL  {name}: {test_name}\n" + "\n".join("        " + l for l in str(message).splitlines()))
    if verbose and missing:
        # (numbered families once: ActionButton#Border, TargetFrameBuff#)
        names = sorted({re.sub(r"\d+", "#", key) for key in missing})
        print("\nGlobals the addon read that the stub doesn't define (nil, as on a client without them):")
        print("  " + ", ".join(names))
    print(f"\n{passed} passed, {len(failed)} failed, {len(skipped)} skipped ({time.time() - started:.1f}s)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
