"""Serene's static check: every Lua file parses, every global it reads or writes is one we know, nothing is left unused.

    pip install --target ~/.cache/serene-tools/py lupa luaparser   # once
    python3 tools/check.py                 # every .lua file in the addon; exit 1 on a problem
    python3 tools/check.py Auras.lua       # some files
    python3 tools/check.py --list          # each file's globals (to read by eye)

It follows Lua's scopes (a local is seen only after its `local` line, inside its block), so it catches:
  * a typo: `Clena(x)` reads a global no one defines;
  * a local used above its definition: nil at call time;
  * a forgotten `local`: an assignment that makes a global by accident;
  * a local never read: a function no one calls, a value no one looks at (a name starting with _ is meant so);
  * on a run over every file: an ns.X set but read nowhere, neither in the addon nor in tools/test.

A global is known when it's in tools/globals.txt: Lua's own, the game's API and frames, Serene's own globals.
A new game API used on purpose goes into that file (in its section); anything else is a bug.
Writing a global is only allowed for the names under "# Serene writes" in that file.
"""
import os, re, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# (the packages live outside the addon: WoW scans everything under AddOns/)
sys.path.insert(0, os.path.expanduser("~/.cache/serene-tools/py"))
try:
    from luaparser import ast, astnodes
except ImportError:
    sys.exit("luaparser is missing: pip install --target ~/.cache/serene-tools/py lupa luaparser")

ALLOW = os.path.join(HERE, "tools", "globals.txt")


def load_allowed():
    reads, writes, section = set(), set(), None
    for raw in open(ALLOW, encoding="utf-8"):
        line = raw.strip()
        if line.startswith("#"):
            section = line.lower()
            continue
        for name in line.split():
            reads.add(name)
            if section and section.startswith("# serene writes"):
                writes.add(name)
    return reads, writes


# (luaparser 4.x keeps no line on most nodes: 0 then, and check() finds the line in the text)
def line_of(node):
    for attr in ("line", "lineno"):
        value = getattr(node, attr, None)
        if isinstance(value, int):
            return value
    token = getattr(node, "first_token", None)
    return getattr(token, "line", 0) if token is not None else 0


class Binding:
    """One local: where it is declared, whether it is reported when never read, whether it was."""

    def __init__(self, name, line, kind):
        self.name, self.line, self.kind, self.used = name, line, kind, False


def is_ns_field(node):
    """ns.X, written with a dot: one of the namespace's fields."""
    return (isinstance(node, astnodes.Index) and node.notation == astnodes.IndexNotation.DOT
            and isinstance(node.value, astnodes.Name) and node.value.id == "ns" and isinstance(node.idx, astnodes.Name))


class Scopes:
    """Walks a chunk with Lua's scoping; records globals read and written, locals never read, and ns fields set and
    read, with their lines."""

    def __init__(self):
        self.stack = [{}]
        self.reads, self.writes = {}, {}
        self.declared_anywhere = {}  # local name -> first line it is declared (for "used above its definition")
        self.unused = []             # Bindings never read
        self.ns_writes, self.ns_reads = {}, set()

    def known(self, name):
        return any(name in scope for scope in self.stack)

    def lookup(self, name):
        for scope in reversed(self.stack):
            if name in scope:
                return scope[name]
        return None

    # (kind: "function" or "local" for what is reported when never read; None for parameters and loop variables)
    def declare(self, node, line=0, kind=None):
        if isinstance(node, astnodes.Name):
            self.retire(self.stack[-1].get(node.id))
            self.stack[-1][node.id] = Binding(node.id, line, kind)
            self.declared_anywhere.setdefault(node.id, line_of(node))

    def retire(self, binding):
        if binding and binding.kind and not binding.used and not binding.name.startswith("_"):
            self.unused.append(binding)

    def push(self):
        self.stack.append({})

    def pop(self):
        for binding in self.stack.pop().values():
            self.retire(binding)

    # expressions and statements ----------------------------------------------------------------
    def visit(self, node):
        if node is None:
            return
        if isinstance(node, list):
            for item in node:
                self.visit(item)
            return
        if not isinstance(node, astnodes.Node):
            return
        method = getattr(self, "visit_" + type(node).__name__, None)
        if method:
            return method(node)
        # (anything else: its child nodes, in order)
        for key, value in getattr(node, "__dict__", {}).items():
            if key.startswith("_") or key in ("comments", "first_token", "last_token"):
                continue
            if isinstance(value, (astnodes.Node, list)):
                self.visit(value)

    def visit_Chunk(self, node):
        self.visit(node.body)

    def visit_Block(self, node):
        self.push()
        for statement in node.body:
            self.visit(statement)
        self.pop()

    def visit_Name(self, node):
        binding = self.lookup(node.id)
        if binding:
            binding.used = True
        else:
            self.reads.setdefault(node.id, line_of(node))

    def visit_Index(self, node):
        if is_ns_field(node):
            self.ns_reads.add(node.idx.id)
        # (in a.b the b is a key, not a name; only a[b] reads b)
        self.visit(node.value)
        if node.notation == astnodes.IndexNotation.SQUARE:
            self.visit(node.idx)

    def visit_Invoke(self, node):
        self.visit(node.source)
        self.visit(node.args)

    def visit_Field(self, node):
        # (likewise { key = v }: only { [key] = v } reads key)
        if getattr(node, "between_brackets", False):
            self.visit(node.key)
        self.visit(node.value)

    def visit_LocalAssign(self, node):
        # (the values first: in `local x = x` the x on the right is still the outer one)
        self.visit(node.values)
        for target in node.targets:
            self.declare(target, line_of(node), "local")

    def visit_Assign(self, node):
        self.visit(node.values)
        for target in node.targets:
            if isinstance(target, astnodes.Name):
                # (a local given a new value is not read by it)
                if not self.known(target.id):
                    self.writes.setdefault(target.id, line_of(target))
            elif is_ns_field(target):
                self.ns_writes.setdefault(target.idx.id, line_of(node))
            else:
                self.visit(target)

    def function(self, args, body, extra=()):
        self.push()
        for name in extra:
            self.stack[-1][name] = Binding(name, 0, None)
        for arg in args:
            self.declare(arg)
        self.visit(body)
        self.pop()

    def visit_LocalFunction(self, node):
        # (declared before its body, so it can call itself; `local f = function` can't)
        self.declare(node.name, line_of(node), "function")
        self.function(node.args, node.body)

    def visit_Function(self, node):
        # (`function Name()` assigns a global; `function a.b()` only reads a)
        name = node.name
        if isinstance(name, astnodes.Name):
            if not self.known(name.id):
                self.writes.setdefault(name.id, line_of(name))
        elif is_ns_field(name):
            self.ns_writes.setdefault(name.idx.id, line_of(node))
        else:
            self.visit(name)
        self.function(node.args, node.body)

    def visit_Method(self, node):
        self.visit(node.source)
        self.function(node.args, node.body, extra=("self",))

    def visit_AnonymousFunction(self, node):
        self.function(node.args, node.body)

    def visit_Fornum(self, node):
        self.visit([node.start, node.stop, node.step])
        self.push()
        self.declare(node.target)
        self.visit(node.body)
        self.pop()

    def visit_Forin(self, node):
        self.visit(node.iter)
        self.push()
        for target in node.targets:
            self.declare(target)
        self.visit(node.body)
        self.pop()

    def visit_Repeat(self, node):
        # (the condition sees the body's locals)
        self.push()
        for statement in node.body.body:
            self.visit(statement)
        self.visit(node.test)
        self.pop()


def find_line(text, pattern, after=0):
    """The first line (after a given one) where a pattern matches: for nodes the parser gives no line."""
    for number, line in enumerate(text.splitlines(), 1):
        if number > after and re.search(pattern, line):
            return number
    return 0


def check(path, allowed_reads, allowed_writes, listing):
    text = open(path, encoding="utf-8").read()
    try:
        tree = ast.parse(text)
    except Exception as problem:  # luaparser raises its own error types
        return [f"PARSE ERROR: {problem}"], [], None
    walker = Scopes()
    walker.visit(tree)
    walker.pop()
    if listing:
        return [], sorted(set(walker.reads) | set(walker.writes)), walker
    problems = []
    for name, line in sorted(walker.reads.items(), key=lambda kv: kv[1]):
        if name in allowed_reads or name == "...":
            continue
        # (no line from the parser: the name's first use as a word, not after . or :; it may be in a comment, so roughly)
        line = line or find_line(text, r"(?<![\w.:])" + re.escape(name) + r"\b")
        local_at = walker.declared_anywhere.get(name)
        if local_at is not None:
            local_at = local_at or find_line(text, r"\blocal\s+(function\s+)?[\w,\s]*\b" + re.escape(name) + r"\b")
        # (a local of that name exists somewhere: declared further down, or in a block already closed)
        if local_at and local_at > line:
            problems.append(f"line {line}: '{name}' is read here, but its local is declared only at line {local_at} "
                            "(nil at this point)")
        elif local_at and local_at < line:
            problems.append(f"line {line}: '{name}' is read here, outside the block of its local (line {local_at})")
        else:
            problems.append(f"line {line}: unknown global '{name}' (a typo? a new game API goes in tools/globals.txt)")
    for name, line in sorted(walker.writes.items(), key=lambda kv: kv[1]):
        if name not in allowed_writes:
            line = line or find_line(text, r"(^|[^\w.:])" + re.escape(name) + r"\s*=[^=]")
            problems.append(f"line {line}: assigns the global '{name}' (a forgotten 'local'?)")
    for binding in sorted(walker.unused, key=lambda b: b.line):
        what = "local function" if binding.kind == "function" else "local"
        problems.append(f"line {binding.line}: {what} '{binding.name}' is never read (dead code? '_' if meant)")
    return sorted(problems, key=lambda p: int(p.split()[1].rstrip(":")) if p.startswith("line ") else 0), [], walker


def spec_reads():
    """Every ns.X the tests read (specs, stub, harness): an export there only for them is still used."""
    names = set()
    for folder, _, files in os.walk(os.path.join(HERE, "tools", "test")):
        for name in files:
            if name.endswith(".lua"):
                names |= set(re.findall(r"\bns\.(\w+)", open(os.path.join(folder, name), encoding="utf-8").read()))
    return names


def main(argv):
    listing = "--list" in argv
    paths = [a for a in argv if not a.startswith("--")]
    # (ns fields are set in one file and read in another: weighed only when every file is read)
    everything = not paths
    if everything:
        # (the addon's own files only: the tests' Lua under tools/ defines its own globals)
        paths = sorted(p for p in os.listdir(HERE) if p.endswith(".lua"))
    allowed_reads, allowed_writes = load_allowed()
    failed = False
    walkers = {}
    for path in paths:
        full = path if os.path.isabs(path) else os.path.join(HERE, path)
        problems, names, walkers[path] = check(full, allowed_reads, allowed_writes, listing)
        if listing:
            print(f"{path}: {', '.join(names)}")
            continue
        if problems:
            failed = True
            for problem in problems:
                print(f"{path}: {problem}")
    if everything and not listing:
        read = spec_reads()
        for walker in walkers.values():
            if walker:
                read |= walker.ns_reads
        for path, walker in walkers.items():
            for name, line in sorted((walker.ns_writes if walker else {}).items(), key=lambda kv: kv[1]):
                if name not in read:
                    failed = True
                    print(f"{path}: line {line}: ns.{name} is set but read nowhere (the addon, tools/test)")
    if not listing:
        print("check: problems found" if failed else f"check: {len(paths)} files ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
