# Serene

A calm interface for World of Warcraft's **Forever** client: a retail 12.x engine running classic-era content. The
game's own frames are restyled in place (chat, minimap, action bars, unit frames, auras, tooltips), plus Serene's own
bags, bank and merchant windows, and a fade that puts everything away when it isn't needed. Lua, one shared
namespace (`ns`), no libraries.

| Path | What |
|---|---|
| `*.lua`, `Serene.toc` | The addon. TOC order is load and init order. |
| `docs/` | Developer docs: architecture, the client, the workflow, one page per area |
| `tools/check.py`, `tools/globals.txt` | Static check |
| `tools/test/` | Tests: the addon run under Lua 5.1 against a stub of the client |
| `.github/workflows/check.yml` | CI: the check and the tests on every push to `main` and every pull request |
| `Media/`, `tools/media/` | TGA textures and the scripts that generate them |

## Read the docs before working — always

The docs are the authority on how Serene works and *why*. Much of the code looks odd until you know what this client
allows and what it does behind the addon's back. **Never start implementing, reviewing or planning without
reading them.** Don't infer patterns from surrounding code alone.

At the start of any task touching code:

1. Read [docs/README.md](docs/README.md) (the design brief, the glossary and the file map),
   [docs/forever-client.md](docs/forever-client.md) and [docs/architecture.md](docs/architecture.md).
2. Read the doc for each area you touch, in parallel:

   | Touching | Read |
   |---|---|
   | Chat, ChatLoot, ChatLines, ChatCard, ChatShell | [docs/chat.md](docs/chat.md) |
   | Tooltip, Toasts | [docs/tooltips-toasts.md](docs/tooltips-toasts.md) |
   | Units, UnitHeals, CastBar, Swing, Regen, Experience | [docs/units.md](docs/units.md) |
   | Auras, AuraFrame, UnitAuras | [docs/auras.md](docs/auras.md) |
   | Items, Inventory, Bags, BagSlots, Vendor, Merchant | [docs/bags-merchant.md](docs/bags-merchant.md) |
   | Actions, ActionBars, Hints, Ready, BarCooldowns, BarKeys, BarPages, Ranks, Reagents, BarPing, BarSets, BarSupplies, BarUse | [docs/action-bars.md](docs/action-bars.md) |
   | Fade, Modes, TopBar, MenuBar, Minimap, Tracker, Names, Settings | [docs/shell.md](docs/shell.md) |
   | A game API, a frame of the game's, what is secret, textures | [docs/forever-client.md](docs/forever-client.md) |
   | Secret values and combat lockdown in code, hooks, the module shape, settings and saved data | [docs/architecture.md](docs/architecture.md) |
   | Checking, testing, debugging, probes, textures | [docs/workflow.md](docs/workflow.md) |

When unsure whether a doc is relevant, read it.

**Docs are part of the deliverable.** If a change alters behaviour the docs describe, update the doc in the same
change. Something learnt about the client goes into `forever-client.md`, a technique into `architecture.md`; other
pages link to them instead of repeating them. The docs describe the code as it is: no
dates, no account of how it came about, no "was tried" or "used to".

## Commits

**Subject only, by default.** One short line saying what changed: `Fix rolls where everyone passed`,
`Add the merchant's buyback page`. Most commits have no body.

**A body, when the subject can't carry it, is one comma-separated line of short labels**: the areas or items
touched, a few words each. No sentences, no rationale, no before/after narrative.

```
Tests and static check

Client stub, specs per area, secret fights, settings checks, capture and fixtures
```

**Never add a `Co-Authored-By:` trailer**, or any other authorship or tool attribution.

`main` is the branch; upstream is `github.com/mtunix/serene`.

## Commands

Run from the addon folder. Both tools need `lupa` and `luaparser`, kept outside the addon (WoW scans `AddOns/`):

```bash
pip install --target ~/.cache/serene-tools/py lupa luaparser   # once

python3 tools/check.py                    # parse errors, unknown globals, locals used early, accidental globals, dead code
python3 tools/test/run.py                 # every spec
python3 tools/test/run.py loot bags       # specs whose file name has one of these words
python3 tools/test/run.py -k roll         # tests whose name has this
python3 tools/test/import_saved.py        # SavedVariables -> tools/test/fixtures (after /serene capture in game)
```

## Verify what you changed, then in game

`python3 tools/check.py` plus a bare `python3 tools/test/run.py` is the **final gate**: run it once when the change
is finished. While iterating, run only what covers the files you touched.

| Changed | Loop with |
|---|---|
| One addon file | `tools/check.py <File>.lua`, then the specs of its area (`run.py chat`, `run.py bags vendor items`...) |
| Settings, `DEFAULTS`, the panel, `/serene` | `run.py settings smoke` |
| Anything read in a fight | its specs, then `run.py secrets` |
| `tools/test/wow.lua` (the stub) | the whole suite: every spec leans on it |

- **Narrowest first.** One spec before the suite. Never run the suite to find out whether one new test passes.
- **A test failing because the stub is too simple:** fix the stub (or stub the part in the spec). **Because of the
  addon:** fix the addon. Never change an expectation to match a bug.
- **New game API used on purpose:** check it exists on this client, then add it to `tools/globals.txt`.
- **The tests can't see the screen.** Anything visual, and real client behaviour (secret values with `==` or in an
  `if`, the game's own frames' insides), is verified in game by the user: `/reload`, `/serene debug`, `/fstack`.
  New or changed textures need a full game restart.
- **Report honestly:** "check and tests pass; untested in game" until the user confirms it in game.

## Writing comments

Serene's comments are part of its record of what was learnt. Follow the house style in
[docs/architecture.md](docs/architecture.md#code-style):

- Say **what the player sees and why**, in plain prose, often as a parenthetical:
  `-- (the game sets their opacity now and then)`.
- **Keep the "why" comments** when you edit code. Never delete one because it looks long.
- Never restate what a line does, and never narrate your own edit (`-- changed to fix X`, `-- new`).
- A file's header says what it shows and the switches it adds; keep it current.

## Conventions

- **Function names are short English verbs:** `Dress`, `Place`, `Silence`, `Tuck`, `Paint`, `Layout`.
- **pcall around every game call** that might not exist on this client, and around every event registration.
- **Secret values:** in a fight the client hides some values. Read through `ns.Clean`/`ns.Safe`; never compare,
  do arithmetic on, or index a value that may be secret. "Unknown" is never a fact: don't dim, glow or count on nil.
- **Locals before use.** A local used above its definition is nil at call time; `tools/check.py` reports it.
- **Settings** live in `ns.DEFAULTS` in `Core.lua`, each with a one-line comment (a word setting's comment lists its
  quoted choices). Saved state that isn't a setting goes in `ns.STATE` (any other saved key is dropped at login) and
  never reuses a setting's key; `spec/settings.lua` checks both.
- **Restyle the game's frames, don't replace them.** Ask the user before replacing another game frame.
- **Never pass the `"TRILINEAR"` filter to `SetTexture`**: it crashes this client on login.
- **The user likes to be interviewed** with a few concrete questions before a big feature.
