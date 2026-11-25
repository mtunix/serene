"""Serene's static check: every Lua file parses, and every global it reads or writes is one we know.

    pip install --target ~/.cache/serene-tools/py lupa luaparser   # once
    python3 tools/check.py                 # every .lua file in the addon; exit 1 on a problem
    python3 tools/check.py Auras.lua       # some files
    python3 tools/check.py --list          # each file's globals, as before (to read by eye)

It follows Lua's scopes (a local is seen only after its `local` line, inside its block), so it catches:
  * a typo: `Clena(x)` reads a global no one defines;
  * a local used above its definition: nil at call time (FightProbe was);
  * a forgotten `local`: an assignment that makes a global by accident.

A global is known when it's in tools/globals.txt: Lua's own, the game's API and frames, Serene's own globals.
A new game API used on purpose goes into that file (in its section); anything else is a bug.
Writing a global is only allowed for the names under "# Serene writes" in that file.
"""
import os, re, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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


def line_of(node):
    for attr in ("line", "lineno"):
        value = getattr(node, attr, None)
        if isinstance(value, int):
            return value
    token = getattr(node, "first_token", None)
    return getattr(token, "line", 0) if token is not None else 0


class Scopes:
    """Walks a chunk with Lua's scoping; records globals read and written, with their lines."""

    def __init__(self):
        self.stack = [set()]
        self.reads, self.writes = {}, {}
        self.declared_anywhere = {}  # local name -> first line it is declared (for "used above its definition")

    def known(self, name):
        return any(name in scope for scope in self.stack)

    def declare(self, node):
        if isinstance(node, astnodes.Name):
            self.stack[-1].add(node.id)
            self.declared_anywhere.setdefault(node.id, line_of(node))

    def push(self):
        self.stack.append(set())

    def pop(self):
        self.stack.pop()

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
        if not self.known(node.id):
            self.reads.setdefault(node.id, line_of(node))

    def visit_Index(self, node):
        self.visit(node.value)
        if node.notation == astnodes.IndexNotation.SQUARE:
            self.visit(node.idx)

    def visit_Invoke(self, node):
        self.visit(node.source)
        self.visit(node.args)

    def visit_Field(self, node):
        if getattr(node, "between_brackets", False):
            self.visit(node.key)
        self.visit(node.value)

    def visit_LocalAssign(self, node):
        self.visit(node.values)
        for target in node.targets:
            self.declare(target)

    def visit_Assign(self, node):
        self.visit(node.values)
        for target in node.targets:
            if isinstance(target, astnodes.Name):
                if not self.known(target.id):
                    self.writes.setdefault(target.id, line_of(target))
            else:
                self.visit(target)

    def function(self, args, body, extra=()):
        self.push()
        for name in extra:
            self.stack[-1].add(name)
        for arg in args:
            self.declare(arg)
        self.visit(body)
        self.pop()

    def visit_LocalFunction(self, node):
        self.declare(node.name)
        self.function(node.args, node.body)

    def visit_Function(self, node):
        name = node.name
        if isinstance(name, astnodes.Name):
            if not self.known(name.id):
                self.writes.setdefault(name.id, line_of(name))
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
        return [f"PARSE ERROR: {problem}"], []
    walker = Scopes()
    walker.visit(tree)
    if listing:
        return [], sorted(set(walker.reads) | set(walker.writes))
    problems = []
    for name, line in sorted(walker.reads.items(), key=lambda kv: kv[1]):
        if name in allowed_reads or name == "...":
            continue
        line = line or find_line(text, r"(?<![\w.:])" + re.escape(name) + r"\b")
        local_at = walker.declared_anywhere.get(name)
        if local_at is not None:
            local_at = local_at or find_line(text, r"\blocal\s+(function\s+)?[\w,\s]*\b" + re.escape(name) + r"\b")
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
    return problems, []


def main(argv):
    listing = "--list" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        paths = sorted(p for p in os.listdir(HERE) if p.endswith(".lua"))
    allowed_reads, allowed_writes = load_allowed()
    failed = False
    for path in paths:
        full = path if os.path.isabs(path) else os.path.join(HERE, path)
        problems, names = check(full, allowed_reads, allowed_writes, listing)
        if listing:
            print(f"{path}: {', '.join(names)}")
            continue
        if problems:
            failed = True
            for problem in problems:
                print(f"{path}: {problem}")
    if not listing:
        print("check: problems found" if failed else f"check: {len(paths)} files ok")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
