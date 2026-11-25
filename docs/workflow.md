# Working on Serene

A change normally goes through three steps: the static check, the tests, and then the game itself. The first two run outside the game and catch errors and wrong logic. Neither can tell you whether something looks right, and both rely on a stub of the client, so anything visual or anything that depends on how the real client behaves is checked in game with `/reload`.

Both tools need two Python packages. Install them outside the addon folder, since WoW scans everything under `AddOns/`:

```sh
pip install --target ~/.cache/serene-tools/py lupa luaparser
```

## The static check

```sh
python3 tools/check.py             # every .lua file; exits with 1 on a problem
python3 tools/check.py Auras.lua   # one file
python3 tools/check.py --list      # each file's globals, to read through
```

`check.py` parses every file and walks it with Lua's scoping rules, so it knows which names are locals at each point. It reports parse errors, any global a file reads that isn't listed in `tools/globals.txt` (usually a typo), a local read above the line that declares it or outside the block it was declared in (it would be nil there), and any assignment that creates a global by accident, which almost always means a missing `local`. Only the names under `# Serene writes` in `globals.txt` may be assigned.

When a file starts using a game API on purpose, add the name to `globals.txt` in its section, after making sure it exists on this client ([forever-client.md](forever-client.md) describes how). Names looked up by string, `_G["X"]` or `rawget(_G, "X")`, don't need to be listed.

## The tests

```sh
python3 tools/test/run.py             # every spec in tools/test/spec
python3 tools/test/run.py loot bags   # specs whose file name contains one of these words
python3 tools/test/run.py -k roll     # only tests whose name contains this
python3 tools/test/run.py -v          # also list the globals the addon read that the stub doesn't define
```

The runner uses `lupa` to run the addon under Lua 5.1, the version the game uses. Each test gets a fresh Lua state with a fresh copy of the stub and the addon, so tests can't affect each other; a spec's top-level code (loading the addon, filling in items) runs again before every test.

`tools/test/wow.lua` is the stub. Its frames keep their state (size, points, shown, alpha, text, scripts) and report it back, but nothing is drawn and the layout is crude. Around the frames it provides events (`wow.fire`), time and timers (`wow.advance`), the mouse (`wow.hover`), bags, items, spells, auras and the merchant as plain tables a test fills in (`wow.bags`, `wow.items`...), chat filters with `wow.say`, and slash commands with `wow.slash`. `wow.load()` loads the addon's files in TOC order into one namespace and `wow.login(saved)` runs `ADDON_LOADED` and `PLAYER_LOGIN`. A global the stub doesn't define reads as nil, as it would on a client without it.

Secret values are imitated too. `wow.secret(v)` makes one: arithmetic, ordering comparisons, indexing, calling and `#` on it raise an error, concatenating gives another secret, `type()` reports the hidden type and `issecretvalue()` is true. `wow.secretFight(true)` starts a fight in which the calls the client hides behave as they do in game: the player's aura queries return nothing, other units' auras, health, power and cast info come back secret, and so do cooldowns, usability and range. What the stub can't imitate is an error on `==` or on a truth test (`if secret then`), because plain Lua won't allow it; those mistakes still only show in game.

`tools/test/harness.lua` provides what specs are written in: `test`, `eq`, `ok`, `no`, `raises`, `skip`, and `clean()`, which fails if any error was caught in the addon's scripts, timers or hooks, or if a module's `init` failed.

The specs:

| Spec | What it covers |
|---|---|
| `smoke.lua` | The whole addon: login, every module's refresh, every switch and setting, a fight, the debug commands, the mouse over every Serene frame, a long list of game events |
| `secrets.lua` | Fights with secret values, in several looks and settings |
| `settings.lua` | Settings agree across files: what files read is declared, every default is used, no setting doubles as saved state, the panel and `/serene` touch real settings, the migrations |
| `chat*.lua`, `items.lua`, `bags.lua`, `vendor.lua`, `tooltip.lua` | The logic of chat and loot lines, item sections, the bags, the merchant and the tooltips |
| `actions*.lua`, `bars_*.lua`, `fade.lua`, `modes.lua`, `hints.lua` | The action button model, the bar modules, fading, rest mode, hints |
| `client_rules.lua` | Rules of this client checked in the source, such as no `"TRILINEAR"` texture filter |
| `captured.lua` | Chat lines and tooltips recorded from the real client (below), and `Capture.lua` itself |

When a test fails because the stub is too simple, improve the stub, or stub the missing piece at the top of the spec. When it fails because of the addon, fix the addon. A test's expectation should never be changed to match a bug. While working, run only the specs for the area you touched; run the whole suite and `check.py` once at the end.

If you change a large file with a script, check that each search string occurs exactly once before replacing it; many of these files repeat similar lines.

`tools/test/globalstrings.lua` holds the game's English sentences that Serene refers to, taken from the classic-era GlobalStrings. After a file starts using a new one, regenerate it with `python3 tools/test/gen_globalstrings.py`.

### Data from the real client

`/serene capture on` (Capture.lua) records the game's own chat sentences (loot, rolls, money, experience, reputation, system messages) and the lines of item tooltips into `SereneDB.capture`, until `/serene capture off`. What players write is never stored: for player chat it keeps only the shape of the message, the channel and flags, and whether it contained a link or a web address. To turn a capture into test data, play for a while, `/reload` so the game writes the SavedVariables file, then run `python3 tools/test/import_saved.py`. That writes `tools/test/fixtures/`: your saved settings, and the captured lines and tooltips. `run.py captured` replays them; without a capture those tests are skipped. The fixtures are not committed, because they contain character names.

`settings.lua` also logs in with `saved_settings.lua`, so the migrations and every module run against a real `SereneDB` rather than only the defaults.

## Testing in game

`/reload` picks up Lua changes, and the settings that need a reload. New or changed `.tga` files need a full restart of the game.

Most problems on this client only appear in a fight, because of secret values and combat lockdown, so test in and out of combat; a training dummy or any mob will do. Many of the frames Serene restyles are Edit Mode systems, so try with Edit Mode open as well. `/fstack` names the frames under the mouse. For Lua errors, use BugSack and BugGrabber or turn on the game's script errors.

## Debug commands

`/serene debug` prints one or more lines from each module. Each module defines its own `ns.XDebug` function, and Core's slash handler calls them all.

| Module | What it prints |
|---|---|
| Fade | needed, wanted and alpha per group; the frames found and those not used |
| Minimap | addon buttons in the panel, the LibDBIcon registry, queue-eye candidates |
| Chat | the selected window's rect, the Edit Mode box, widening |
| Hints | quiet state, buffs, the food check per button, the class-buff plan |
| ActionBars | dressed buttons, bars this client doesn't have |
| Ready | on/when, buttons found, how many are faint and why, which cooldown read was used |
| BarCooldowns | the cooldown look and numbers setting, the global line, buttons per look |
| BarKeys | learning on, keys bound, known, bright |
| Ranks | on/by itself, spells at top rank, old ranks waiting and on how many buttons |
| Reagents | on, the threshold, buttons low and which reagents |
| BarPing | on, the threshold, cooldowns followed, pings so far |
| BarSets | on, actions in the copy, how many left the bars, the sets |
| BarSupplies | on, the item chosen for each kind, which macros exist |
| BarUse | on, hours of play, slots followed, unused now, swaps suggested |
| Experience | bar found, last mode, last fade |
| Swing | frames found and how, the CVar, attack state, speeds |
| Units | per frame: art, badges, emblems, portrait, side |
| CastBar | bars dressed |
| Auras | buttons dressed (yours, target/focus, plates) |
| AuraFrame | Serene's buff frame or why it isn't used; counts per group; missing buffs; known short buffs; what you can dispel |
| UnitAuras | target/focus containers made, or why not |
| Bags | shown state, protected buttons, bank tab inventory slots by index and by id |
| MenuBar | micro buttons with their labels and state |
| TopBar | geometry, alpha, mouse-over now and after 3 s, Fade's view of it |
| Toasts | anchor, alert systems found, and per toast its parts, icon, masks and any game art still showing |

Some words after `debug` produce larger dumps:

| Command | What it does |
|---|---|
| `/serene debug units [frame]` | every region and child of a unit frame (size, position, alpha, art, anchor), saved to `SereneDB.unitsDump` |
| `/serene debug auras` | the same as AuraFrame's debug line |
| `/serene debug targetauras` | a walk of TargetFrame's auras, saved to `SereneDB.probeTargetAuras` |
| `/serene debug auraholder` | the game's aura holders, their methods and the AuraContainer enums, saved to `probeHolder` |
| `/serene debug plates` | which cooldown calls reached nameplate swirls, saved to `probePlates` |
| `/serene debug targeticons` | visible icon textures under TargetFrame |
| `/serene debug mouse` | the frames under the mouse with their parents, saved to `probeMouse` |
| `/serene debug menu` | MenuBar's line only |
| `/serene debug glow` | the shown parts of the action button under the mouse, naming any glow Serene doesn't know, saved to `probeGlow` |

## Getting data out of the client

Chat output is short and awkward to copy, so anything bigger is written into `SereneDB` from a debug command (`SereneDB.probeX = lines`). A `/reload` writes it to `WTF/Account/<account>/SavedVariables/Serene.lua`, where it can be read. Units clears its `unitsDump` at the next `init`; the `probe*` dumps from Auras and ActionBars stay in the file until you clear them, so remove them once read. Something that disappears before you could type a command can record itself shortly after it appears: Toasts describes each toast half a second after it shows, into a local table that `/serene debug` prints.

When something misbehaves, measure it this way before deciding on a cause. Behaviour that looks like the game's often turns out to be Serene's own, and the other way round.

## Reference sources

Blizzard's UI source for this build, other addons that run on this client, and the source of the game's strings are listed in [forever-client.md](forever-client.md#finding-out-what-the-client-does).

## Textures

`Media/*.tga` are 32-bit uncompressed TGAs with alpha, generated by the scripts in `tools/media/`. `softdisc.py` writes a white disc with a smoothly feathered edge (`AuraDisc` and the round masks); `panelmasks.py` writes `HoleMask` (an opaque square with a round hole, used by Minimap's addon panel and by Units) and `DiscMask` (which together with it draws the panel's one-pixel arc) into `Media/` (or a folder given as the argument); `copyicon.py` draws the copy icon; and `roundglow.py` turns the profile of `Glow.tga` into the round `GlowRound.tga`. The others take the output path as an argument, e.g. `python3 tools/media/softdisc.py Media/Out.tga`. Restart the game afterwards: `/reload` doesn't load changed textures.

Smooth round shapes come from soft edges baked into the texture, not from filtering; [forever-client.md](forever-client.md#textures) explains why, and which filter crashes this client.
