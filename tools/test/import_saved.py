"""Turn Serene's SavedVariables into test fixtures (tools/test/fixtures/), so the tests replay this client's real data.

    python3 tools/test/import_saved.py            # the account's file under WTF (the only one, or the newest)
    python3 tools/test/import_saved.py <path/to/SavedVariables/Serene.lua>

Writes:
  fixtures/saved_settings.lua   your settings as saved (without remembered bags, probes and captures): the tests log
                                in with them, so the migrations and every module meet a real, lived-in SereneDB.
  fixtures/capture_chat.lua     the game's chat lines kept by /serene capture (see Capture.lua), by event.
  fixtures/capture_tooltip.lua  item tooltips' lines kept by /serene capture, by item id.

In game first: /serene capture on, play a while (loot, roll, sell, gain experience and reputation, hover items),
then /reload (that writes the file). /serene capture off when you have enough.
"""
import glob, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.expanduser("~/.cache/serene-tools/py"))
from lupa import lua51

# Kept out of saved_settings.lua: big, or not settings.
NOT_SETTINGS = {"inv", "capture", "capturing", "unitsDump"}


def find_saved():
    # (the addon sits in _forever_/Interface/AddOns/Serene; WTF is beside Interface)
    wtf = os.path.normpath(os.path.join(ROOT, "..", "..", "..", "WTF", "Account"))
    found = glob.glob(os.path.join(wtf, "*", "SavedVariables", "Serene.lua"))
    if not found:
        sys.exit(f"no Serene.lua under {wtf}/*/SavedVariables: give its path")
    return max(found, key=os.path.getmtime)


def lua_value(value, indent=""):
    """A Lua value (from lupa) as Lua source, keys sorted so the file only changes when the data does."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    if isinstance(value, str):
        out = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
        return '"' + out + '"'
    # a table
    items = list(value.items())
    if not items:
        return "{}"
    keys = [k for k, _ in items]
    is_list = all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1))
    inner = indent + "\t"
    lines = []
    if is_list:
        for k in range(1, len(keys) + 1):
            lines.append(inner + lua_value(value[k], inner) + ",")
    else:
        def order(k):
            return (0, k) if isinstance(k, (int, float)) else (1, str(k))
        for k in sorted(keys, key=order):
            if isinstance(k, str) and k.isidentifier():
                key = k
            else:
                key = "[" + lua_value(k) + "]"
            lines.append(f"{inner}{key} = {lua_value(value[k], inner)},")
    return "{\n" + "\n".join(lines) + "\n" + indent + "}"


def write(name, header, value):
    folder = os.path.join(HERE, "fixtures")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"-- {header}\n-- Written by tools/test/import_saved.py; run it again to refresh.\n")
        f.write("return " + lua_value(value) + "\n")
    print(f"wrote {os.path.relpath(path, ROOT)}")


def main(argv):
    path = argv[1] if len(argv) > 1 else find_saved()
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(path, encoding="utf-8", errors="replace").read())
    db = lua.globals().SereneDB
    if db is None:
        sys.exit(f"{path}: no SereneDB in it")
    settings = lua.table()
    for key, value in db.items():
        if key in NOT_SETTINGS or str(key).startswith("probe"):
            continue
        settings[key] = value
    write("saved_settings.lua", "SereneDB as saved in game, without remembered bags, probes and captures.", settings)
    capture = db.capture
    if capture is None or capture.chat is None:
        print("no capture in it yet: in game, /serene capture on, play a while, /reload, then run this again")
        return 0
    write("capture_chat.lua", "Chat lines this client printed, by event (each: the event's arguments).", capture.chat)
    if capture.tooltip is not None:
        write("capture_tooltip.lua", "Item tooltips' lines as this client gave them, by item id.", capture.tooltip)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
