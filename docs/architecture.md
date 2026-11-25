# Architecture

Serene is about forty Lua files that share one namespace. Most of them take a piece of the game's interface (the chat, the unit frames, the action bars) and restyle it in place; a few build windows of their own (bags, bank, merchant, the menu band, the buff frame). This page covers what all of them have in common: how they load, how settings and saved data work, the helpers in `Core.lua`, the usual shape of a module, and the handful of techniques you'll see in nearly every file. The area pages assume you've read it, and it assumes you've read [forever-client.md](forever-client.md), which explains the client these techniques work around.

## Files and the namespace

Every file starts with `local ADDON, ns = ...` (or `local _, ns = ...`). `ns` is the addon's private table and the only way files talk to each other: a file puts a function on it (`ns.Items`, `ns.ShowTip`) and others call it.

Serene creates very few globals: the saved variables (`SereneDB`); the `/serene` slash command (`SLASH_SERENE1`); for the key bindings in `Bindings.xml`, their labels (`BINDING_HEADER_SERENE` and the `BINDING_NAME_SERENE_*` strings, set in Fade, Names and Tracker) and the functions they call (`Serene_Peek`, `Serene_ToggleTracker`, `Serene_ToggleNames`); and named frames such as `SereneTopBar`, `SereneAuras` and `SereneBags`, which other files look up by name. `tools/check.py` fails on any other global a file assigns.

Most files start by copying the helpers they use into locals, e.g. `local Safe, Clean = ns.Safe, ns.Clean`. Lua resolves a name that isn't a local in scope as a global, so a local function used above the line that defines it is `nil` when it's called. `tools/check.py` catches that too.

## Loading

`Core.lua` loads first and sets up the module list. Every file that does something at login ends by registering itself:

```lua
table.insert(ns.modules, { init = Init, refresh = Refresh })
```

`Actions.lua` and `Items.lua` are the exception: they are libraries that other files call, with nothing to set up, so they don't register.

On `ADDON_LOADED`, Core lets go of every saved key that is neither a setting nor in `ns.STATE` (below), fills `SereneDB` from `ns.DEFAULTS` (the `Fill` function recurses into nested tables and never overwrites a value the player already has), runs a few migrations, and sets `ns.db = SereneDB`. The migrations either rewrite an old enum value to a valid one or flip a setting once, guarded by a flag such as `ungrouped` or `topHover` so they don't run again.

On `PLAYER_LOGIN`, Core calls each module's `init` in TOC order, each inside `pcall`. A module that fails prints its error in red and the rest carry on. `init` builds frames and installs hooks; it runs once. `refresh` is optional and re-applies settings. `ns.Refresh()` calls every module's `refresh` (also inside `pcall`) and runs after every `/serene` switch and every change in the settings panel.

## Anatomy of a module

CastBar.lua is a small, typical restyle, and most files follow its shape.

The header comment says what the player sees, which settings exist and which `/serene` words apply. Below it come constants (sizes, colours, the candidate frame names in `NAMES`) and the file's own state: `dressed`, a table mapping each game cast bar to the parts Serene made for it; `holding`, the guard described below; `hidden`, a frame that is never shown, used as a parking place for the game's art; and `active`, set once the module has started.

`Init` returns at once if the module's setting (`castBar`) is off, which is why that setting needs a reload. Otherwise it calls `DressAll`, which looks for the bars by name and through Edit Mode's registry, and registers `PLAYER_ENTERING_WORLD` so a pet's or vehicle's bar that appears later gets dressed too.

`Dress(bar)` does the real work, once per bar. It finds the bar's icon, text and fill, moves the game's art onto `hidden`, adds Serene's glass, hairline and spark, and records all of it in `dressed[bar]`. Then it hooks the game's setters on the bar (`SetStatusBarColor`, `SetStatusBarTexture`, `SetSize`, `SetWidth`...) so that whenever the game repaints or resizes the bar, Serene's `Paint` and `Layout` run straight after it. An `OnUpdate` hook moves the spark with the fill. From then on the game drives everything; Serene only reacts.

`Refresh` re-runs `Paint` and `Layout` on every dressed bar, which is how settings like the height and width apply without a reload. `ns.CastDebug` prints which bars were found for `/serene debug`, and the file ends with the `table.insert(ns.modules, ...)` line.

Larger files add more of the same pieces: an events frame that schedules a scan for the next frame, a polling ticker for changes the game doesn't announce, a `pending` flag for work that has to wait until a fight ends. The sections below explain each.

## Settings and saved data

`ns.DEFAULTS` in `Core.lua` lists every setting with its default and a one-line comment. It's the reference for what a setting does. For a word setting the comment lists its choices in quotes (`castText = "in", -- "in" the bar, "under" it, or "none"`); the tests read those quotes, so keep that form.

Modules read booleans with `ns.On(key)`, which falls back to the default before `ns.db` exists, and everything else straight from `ns.db`. A setting that applies live is re-read in the module's `refresh`. Some settings only take effect after a `/reload`, because the module either returns early from `init` when it's off or installs `hooksecurefunc` hooks, which can't be removed. These are `chat`, `minimap`, `menuBar`, `actionBars`, `units`, `castBar`, `auras`, `auraUnits`, `auraPlates`, `auraFrame`, `bags` and `toast`.

Adding a setting means: an entry in `ns.DEFAULTS` with its comment, the module reading it, a control in `Settings.lua` (which binds controls to settings by a path string, `"fade"` or `"groups.bars"`, and marks the ones that need a reload), and optionally a word for `/serene` in Core's `SWITCHES` and `ORDER` and, when the word differs from the setting's key, `KEYS`. The `Toggle`, `Choice` and `Slider` calls in `Settings.lua`'s pages show how a control is declared; [shell.md](shell.md) describes the panel.

`SereneDB` also holds data that isn't a setting. A few of these have an empty default in `ns.DEFAULTS` so `Fill` creates them (`inv`, `bagPins`, `bagCats`, `bagKeep`, `hintLast`); the rest are created by their module when first needed and are listed in `ns.STATE` in `Core.lua`:

| Key | Kept by | What it holds |
|---|---|---|
| `inv` | Bags | every character's bags, bank, money and class, as realm → name → data |
| `gold` | TopBar | every character's money, as realm → name → `{ money, class }` |
| `bagPins`, `bagCats`, `bagKeep` | Bags, Items | sections given to items (by item id), your own sections (a list), items never suggested by "make room" |
| `hintLast`, `keyLearn`, `ranks`, `barSetsBy`, `barUseBy`, `supplies` | Hints, BarKeys, Ranks, BarSets, BarUse, BarSupplies | per character, keyed `"Realm-Name"` |
| `toastAt`, `auraAt`, `auraDebuffFree`, `topPos`, `bagsPos`, `bankPos` | Toasts, AuraFrame, TopBar, Bags | where you dragged something |
| `auraShortSpells` | AuraFrame | buffs seen to be short, by spell id |
| `settingsPage` | Settings | the panel page last open |
| `namesSaved`, `namesKeyGiven`, `tipCompare`, `tipCompareDone`, `merchantNoted`, `bagsNoted`, `ungrouped`, `topHover` | Names, Tooltip, Vendor, Bags, Core | one-time flags and values to give back |
| `unitsDump`, `probeMouse`, `probeGlow`, `capture`, `capturing` | Units, Auras, ActionBars, Capture | debug dumps and captured test data |

Saved data must never reuse a setting's key: `barUse` is BarUse's on/off switch, so its per-character data lives under `barUseBy`. A key that is neither a setting nor in `ns.STATE` is dropped at every login, so new saved state must be added there. `tools/test/spec/settings.lua` fails on anything a file reads that is neither a setting nor in `ns.STATE`, and on an `ns.STATE` key no file uses.

## Shared helpers in Core.lua

The palette is a few colours used everywhere: `ns.SOFT` (warm white for text), `ns.MUTED` (grey for quiet detail), `ns.GOLD_TEXT` (the game's gold), `ns.INK` (the dark glass) and `ns.LINE` (soft gold for hairlines). The `_RGB` variants are the same colours as number triples.

`ns.Pixel(region)` returns the size of one physical screen pixel in the region's own units, so a line drawn with it stays one pixel thick at any UI scale. `ns.Hairline(frame, color, layer)` uses it to draw a 1px border just inside a frame; call `:Fit()` on the result again when the scale changes.

The rest are for reading the game safely:

| Helper | What it does |
|---|---|
| `ns.Safe(fn, ...)` | Calls `fn` in `pcall`, returns its results or nil |
| `ns.Clean(v)` | `v`, or nil if it is a secret value |
| `ns.IsSecret` | `issecretvalue`, or a stand-in that always says false |
| `ns.Over(frame, ...)` | `IsMouseOver` that can't error and is false for hidden frames |
| `ns.Approach(cur, target, elapsed, fadeIn, fadeOut)` | One step of a fade toward `target` |
| `ns.AnchoredTo(frame, other)` | Whether `frame` is anchored to `other`; used so two windows placed side by side never anchor to each other both ways |
| `ns.IsRegion(v)`, `ns.IsTexture(v)`, `ns.IsFontString(v)` | Whether a value found among a frame's keys is a region, a texture, a text |
| `ns.Silence(frame)` | Makes one of the game's frames unseen and too small to catch the mouse, again whenever the game resets it (see below) |

`/serene` on its own opens the settings panel, `/serene help` lists the switches, and `/serene debug` calls every module's `*Debug` function. The debug words are listed in [workflow.md](workflow.md).

## Working with the game's frames

### Restyle, don't rebuild

Serene finds the game's frame and changes only how it looks: textures, colours, alpha, fonts, the points of the frame's own child regions, and extra textures of its own on top. The game keeps filling, showing, hiding and placing the frame, through Edit Mode where it applies. That's what keeps Serene working in combat, in Edit Mode and through the game's own updates, and it's the default for anything new. Bags, bank, merchant, the menu band and the buff frame are Serene's own windows because they do things the game's frames can't. Replacing another game frame is a design decision, not an implementation detail.

### Finding the parts

This client's frames differ from both retail and classic in their key names, and nothing documents them. So the code searches rather than hardcodes: `rawget` over a list of candidate keys, recursing into known holder keys; the old `_G[name .. suffix]` globals as a fallback; shape tests such as "a square texture of 48px or less whose texture is secret is an aura icon"; and Edit Mode's registry (`EditModeManagerFrame.registeredSystemFrames`, matched on `system == Enum.EditModeSystem.X`), as CastBar's `DressAll` does. It uses `rawget` rather than `frame.key` because some of these frames have `__index` metatables.

### Putting the game's art away

Serene never calls `Hide()` on the game's regions, because the game calls `Show()` on them again. Depending on the region it uses one of these instead:

| Technique | Used for | Where |
|---|---|---|
| Alpha 0, held there by hooks | Regions the game keeps re-showing or re-fading | Units (`PutAway`), MenuBar (`Away`), ActionBars |
| Reparented to a frame that's never shown | Art with animations, which would restore its alpha | CastBar (`hidden`), Units, Chat and Minimap (`Tuck`), Toasts (`PutAway` into `attic`) |
| Silenced: alpha 0 and scale 0.01, re-applied from `SetAlpha`/`SetScale` hooks | Frames that must stay shown and keep working but must not catch the mouse | The game's aura containers (AuraFrame, UnitAuras), through `ns.Silence` in Core |
| The whole window reparented into a hidden frame | Bag windows: `IsShown()` still reports true, so the game's open/closed state can drive Serene's | Bags |
| Alpha 0 and moved off-screen | A window that has to stay really open, with its right-click selling, confirmations and closing | Vendor (MerchantFrame) |

The function names aren't consistent between files: `PutAway` holds alpha at 0 in Units.lua but reparents into an attic in Toasts.lua, so read the function before assuming which technique it is.

### The `holding` flag

When Serene hooks one of the game's setters to keep a region the way it wants, say `hooksecurefunc(region, "SetAlpha", ...)` to hold it at 0, its own calls to that setter would trigger the hook as well. Files that do this keep a file-local flag:

```lua
local holding = false -- (Serene's own calls, not heard by its hooks)
holding = true; region:SetAlpha(0); holding = false
-- and in the hook: if holding then return end
```

Every new `Set*` call on a hooked region needs the same wrapping, or the hook can recurse or keep re-laying out the frame. The small helpers that do the wrapping are CastBar's `Place`, `Size`, `Font` and `Paint`, Units' `Hold` and `GiveBack`, MenuBar's `Away`, and the setters in Auras.lua such as its `Font`. They all set the flag back to false rather than restoring the previous value, so they can't be nested.

### Hooks, never replacements

Serene only post-hooks the game's functions with `hooksecurefunc`. A post-hook runs after the game's code and doesn't taint it; assigning over a Blizzard function would. The exceptions are places the game leaves open to addons: `GetMinimapShape` (Minimap.lua, for the square edge), the `CHAT_FRAME_TAB_*_ALPHA` constants (Chat.lua), and the minimap's `OnMouseWheel` script, which Minimap.lua sets only when the game hasn't set one. Hooks can't be removed, so each one first checks the setting or an `active` flag before doing anything.

### Waiting a frame

The game often updates its buttons after the same event Serene is listening to. Code that needs the game's result therefore runs on the next frame, through `C_Timer.After(0, ...)` or a one-frame ticker that folds many events into a single refresh. Auras' `Request`, Bags' `Dirty`, Units' `Watch` and ActionBars' `QueueSlots` all work like that.

### Polling as a safety net

Some changes fire no event: the target of target changing, a mob being tapped, the game re-showing art, a new chat window, a button the game moved back. A few cheap periodic checks catch them:

| Module | What it checks | How often |
|---|---|---|
| Units | colours | 0.25 s |
| Chat | line alignment; re-dressing windows | 0.25 s; 2 s |
| Fade | collecting the frames it fades | 3 s |
| Minimap | gathering addon buttons | 2 s |
| MenuBar | layout | 1 s |

Each one caches the last state and returns early when nothing changed. Don't put a sweep over all frames (`EnumerateFrames`) on a timer: there are around 21,000 of them and it causes visible hitches.

## Secret values

In combat the client hands addons many values as secrets: the player's aura data, health and power in some cases, frame sizes, and more ([forever-client.md](forever-client.md) lists what is known). A secret can be passed on to a widget method, but comparing it (even `~= nil`), doing arithmetic with it or using it as a table key raises an error. The code deals with this in a few consistent ways:

- Values are read through `Clean(Safe(...))`, which turns a secret into nil, and nil means "unknown". Unknown is never taken as a fact: buffs that can't be read are not "no buffs", so nothing glows for a missing buff, and unreadable health is not "hurt".
- When the table itself might be secret, fields are read inside a closure: `Clean(Safe(function() return data.spellId end))`.
- Values that only need to be displayed are passed straight back to the game without being looked at. Auras.lua hands the game's border colour back through `SetVertexColor`; Units hands overheal to `SetAlphaFromBoolean`.
- Where possible the game does the work through its secret-safe APIs: AuraContainer filling Serene's widgets, `SetDurationCooldown`, `SetDurationText` with a colour curve, `AddDispelTypeTexture`, `SetAlphaFromBoolean`, and `UnitGetDetailedHealPrediction` with a calculator.
- Some code keeps the last clean value; Chat remembers each window's last readable width.

## Combat lockdown

While `InCombatLockdown()` is true, protected frames can't be moved, shown, hidden or have their attributes changed. That covers action buttons, secure unit frames like the target of target, secure buttons and, on this client, bag item buttons. `SetAlpha` is still allowed, which is why Fade works by changing opacity. Its one exception is the minimap: the engine can't draw the map half-transparent, so Fade hides and shows the `Minimap` frame itself.

Anything that would touch a protected frame in combat waits for the fight to end:

```lua
if InCombatLockdown() then pending = true return end
-- on PLAYER_REGEN_ENABLED: if pending then pending = false; Apply() end
```

`PLAYER_REGEN_DISABLED` fires just before lockdown starts, so it's the last chance to hide secure things; AuraFrame hides its ghost row there. A protected frame also must not be anchored to something Serene moves in combat, which is why the target of target hangs from TargetFrame itself rather than from Serene's bars.

## State on game frames, and secure actions

Taint is how the game keeps addon code away from protected actions. Anything an addon writes (a global, a field on a frame, a replaced function) is marked as tainted, and if the game's own secure code later reads tainted data during combat, it refuses the protected action, which shows up as "Interface action blocked" or a button that does nothing.

So the code is careful about where it keeps its own state for a game frame. The aura files keep it in their own tables keyed by the frame: `dressed[button]` in Auras.lua, and `made` in AuraFrame.lua and UnitAuras.lua, which is weak-keyed because the containers' icons come and go. Elsewhere it is stored on the frame itself under a `serene` prefix so it can't collide with the game's keys: `sereneColor` on unit frame bars, `sereneCell` on bag buttons, `sereneGlass` and `sereneCue` on tooltips, `sereneRoom` on chat windows. Never write an unprefixed field onto a game frame, and prefer a table of your own for frames the game treats as secure.

Secure actions go through the game's own buttons. MenuBar's words are `SecureActionButtonTemplate` buttons with `type="click"` that click the hidden micro buttons; Bags uses the game's `ContainerFrameItemButtonTemplate`; the ghost buffs are secure buttons with `type="spell"`. Purchases that need a confirmation go through the game's own dialogs: Vendor's `Proxy` stands in for a merchant button so `MerchantFrame_ConfirmExtendedItemCost` can be used, and bank tabs are bought on the game's own bank page.

## How the files depend on each other

Fade decides how visible each part of the interface is: it sorts frames into groups, works out each time it updates whether a group is needed, and moves the group's opacity toward full or toward the `rest` setting (see [shell.md](shell.md)). Nothing tells Fade to wake up; it asks other modules:

| Function | From | Answers |
|---|---|---|
| `ns.XPGained` | Experience | experience was just gained |
| `ns.HintRevealBars` | Hints | which bars a glow should bring back |
| `ns.TopNeeded` | TopBar | whether the top bar should show |
| `ns.QueueFrames`, `ns.CompassParts`, `ns.CompassOpen`, `ns.CompassDecor` | Minimap | the queue eye, the compass parts, whether the addon panel is open |

It also fades `SereneAuras`, `SereneDebuffs`, `SereneTopBar` and `SereneMenuBar`, looked up by name.

Two libraries answer questions several files need to agree on, so those files ask them instead of reading the game again:

- `ns.Actions` (Actions.lua) knows the action buttons and their slots: which buttons exist (whether or not Serene's action bars are on), the slot a button shows, what a slot holds (`What`, in a stable form that BarUse saves), what it casts, and whether it's usable, in range, in use, on cooldown or procced. ActionBars, Ready, Hints, BarCooldowns, BarPing, BarUse, BarSets, Ranks and Reagents use it. See [action-bars.md](action-bars.md).
- `ns.Items` (Items.lua) reads bag slots and decides an item's section in the bags. `IsJunk` means "shown under Junk", so the merchant sells exactly what the bags show there. It also gives sell prices and coin text. Bags, Vendor, Merchant and Tooltip use it. See [bags-merchant.md](bags-merchant.md).

Neither changes anything; they only read.

The other exports:

| Export | From | Used by |
|---|---|---|
| `ns.IsPeeking` | Fade | Modes, Ready, Tooltip |
| `ns.ModeNow` | Modes | Hints |
| `ns.HintsDirty` | Hints | Modes, Settings |
| `ns.MissingClassBuffs` | Hints | AuraFrame (ghost buffs) |
| `ns.HintSoon`, `ns.HintGlow` | Hints | ActionBars |
| `ns.MakesWellFed` | Hints | BarSupplies |
| `ns.OnBarPress` | BarKeys | BarUse |
| `ns.BarUseFaded` | BarUse | Ready |
| `ns.BarSetsMine` | BarSets | BarUse |
| `ns.ShowTip`, `ns.HideTip` | Tooltip | most files with a tooltip of their own |
| `ns.TipHint` | Tooltip | Bags, ChatCard, ChatLines, Minimap, TopBar |
| `ns.TipHints`, `ns.TipLater` | Tooltip | Merchant |
| `ns.PlayerPowerBar`, `ns.PlayerPortrait` | Units | Regen |
| `ns.CastColor` | Units | CastBar |
| `ns.AuraStyle`, `ns.SereneAuraFrame`, `ns.AuraContainers` | Auras | AuraFrame, UnitAuras |
| `ns.AURA_FONT_AUTO` | Auras | AuraFrame, Settings |
| `ns.AuraKindColors` | AuraFrame | UnitAuras |
| `ns.QueueShown`, `ns.OpenCalendar` | Minimap | TopBar |
| `ns.FormatMatch` | ChatLoot | Chat, ChatCard |
| `ns.chat` | Chat | ChatLines, ChatShell (only exists if `chat` was on at login) |
| `ns.PlaceBank` | Bags | Vendor |
| `ns.PlaceMerchant` | Vendor | Bags |
| `ns.MerchantBuyStack` | Merchant | Vendor |
| `ns.CAST_WIDTH_GAME`, `ns.CAST_FONT_AUTO` | CastBar | Settings |

Exports are defined when a file loads, and callers look them up when they need them and check for nil, so load order rarely matters. The exceptions are things created in `init`: `ns.chat`, and the named frames Fade collects (it re-collects them every 3 seconds for that reason).

Some `ns.*` names exist only so the tests can reach a file's locals (`ns.LootRead`, `ns.FadeStep`, `ns.BagsSections`, `ns.MerchantFindJunk`...). They're marked `-- (tests)`.

## Code style

Functions are named with short English verbs: `Dress`, `Place`, `Silence`, `PutAway`, `Tuck`, `Paint`, `Layout`. Indentation is tabs.

Comments describe what the player sees and why the code does what it does, in plain sentences, often in parentheses: `-- (the game sets their opacity now and then)`. They're where most of the knowledge about this client lives, so keep them when you change the code around them.

Any call into the game that might not exist on this client goes through `pcall`, and so does every event registration (`pcall(f.RegisterEvent, f, "X")`), since some events don't exist either. Where the old and new APIs differ, the code tries both: `C_Container` and the old globals, `C_Bank` tabs and `BANK_CONTAINER`, `TooltipDataProcessor` and `OnTooltipSetItem`.
