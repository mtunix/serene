# The shell: fading, the top of the screen, the compass, settings, the setup

This page covers the parts around the edges of the screen that aren't chat, unit frames, auras, bags or action bars (those have their own pages; the action bars are in [action-bars.md](action-bars.md)). Fade.lua and Modes.lua decide how visible the interface is. TopBar.lua and MenuBar.lua are the two bands of glass at the top of the screen, Minimap.lua turns the minimap into a compass, Tracker.lua and Names.lua are small toggles behind key bindings, Settings.lua is the options panel, and Setup.lua is the setup window shown on the first login and after an update.

## Fade.lua

Fade puts parts of the interface away when you don't need them and brings them back when you do. For everything except the minimap it does this through opacity alone, which is allowed on protected frames, so a faded action button still works and fading works in combat. Edit Mode, or holding the Peek key (`Serene_Peek`), shows everything.

### Groups

The frames are organised in groups. `GROUPS` lists each group's frames by global name; the lists mix retail and classic names, and names that don't exist on this client are skipped.

| Group | Frames | Comes back for |
|---|---|---|
| bars | the main and bottom action bars, stance, pet, possess | a fight, an enemy target, casting, a spell or item on the cursor |
| bar4, bar5 | MultiBarRight, MultiBarLeft | each on its own under the mouse |
| unit | PlayerFrame, PetFrame | a fight, any target, a heal or a blow on you in the last 3 s, your health or your pet's not full, mana or energy not full, any rage |
| minimap | MinimapCluster and the queue eye | the mouse or the open addon panel; with `compass = "world"`, always outside towns |
| buffs | BuffFrame, TemporaryEnchantFrame, `SereneAuras` | a fight, a target, a short debuff on you, a Welcoming Campfire |
| debuffs | DebuffFrame, `SereneDebuffs` | a fight, a target, a short debuff on you |
| xp | the status tracking bars | a fight, experience just gained (`ns.XPGained`) |
| menu | the game's micro menu and bag bar | the mouse only |
| top | `SereneTopBar` | `ns.TopNeeded`, or the mouse on the menu band |
| words | `SereneMenuBar` | the mouse on the top bar |

On top of those reasons, the mouse over any frame of a group brings that group back (the buff and debuff groups count each other's frames, and the minimap counts the compass's own parts from `ns.CompassParts`). The groups that come back for a fight stay for 3 seconds after it ends. A hint with `hintReveal = "bars"` brings back bars, bar4 and bar5 (`ns.HintRevealBars`). A short debuff means one lasting 120 seconds or less, so Resurrection Sickness and Deserter don't count.

Whether a group fades at all is its switch under `ns.db.groups`, through `SWITCH` where it shares another group's: debuffs follow `buffs`, bar4 and bar5 follow `bars`, and xp follows `menu`. The top band follows `top`, and the words band follows `menuBar` rather than `fade`. Everything needs `fade` on.

### The update loop

`Init` starts a single OnUpdate driver that does three things at different rates:

1. Every 3 seconds `Collect()` resolves the group lists into frames. It runs repeatedly because some frames, such as Serene's top bar and aura frames, are created after Fade's `init`. A frame whose parent (up to four levels) is already in a group is left out, so opacities never multiply. Bars 4 and 5 are the exception: on this client they can sit inside the main bar, so they get `SetIgnoreParentAlpha(true)` and fade on their own. When `menuBar` is on, the menu group is left empty, because MenuBar holds the game's micro buttons at alpha 0 and Fade must not bring them back.
2. Every 0.1 seconds, and at once when a fight starts or a heal or blow lands on you, `Look()` decides what each group wants. It sets `want` to 1 if the group was needed within the last 1.5 seconds (`LINGER`) and to the `rest` opacity otherwise (0 by default). The words band and the minimap go fully to 0 at rest.
3. Every frame, `Fade(elapsed)` moves each group's alpha toward its `want` with `ns.Approach`, taking 0.25 s to come in and 0.9 s to go, and applies it with `SetAlphas`, which skips frames already at that alpha. A group whose switch is off is given back at full once.

Values that can't be read never count as a reason to show something: secret or missing health isn't "hurt". The one exception is a secret `UnitCanAttack`, which counts as an enemy, since showing the bars needlessly costs less than hiding them in a fight.

### The minimap

The minimap engine can't draw the map half transparent: there's no terrain and a crosshatch, and the player arrow and the dots draw at full opacity regardless. So the minimap group switches all at once (`AT_ONCE`), and the `Minimap` frame itself is really hidden and shown (`HIDE_AWAY`, `ShowMap`), the only place Fade hides a frame. To make that look like a fade, a disc of dark glass fades in over the map, the map is switched underneath while the glass is at its darkest, and then the glass clears. MinimapCluster stays shown at alpha 0 so the mouse still finds it, and `ns.CompassDecor` fades Serene's ring, letters and band along with the glass.

### Adding a group

Add its frame names to `GROUPS` and the group to `ORDER`; give it a function in `NEEDED` that returns whether it's needed (it's called inside `pcall` ten times a second, so keep it cheap); either point it at an existing switch in `SWITCH` or add a default under `groups` in `ns.DEFAULTS` and a toggle on the General page of Settings.lua (`Toggle(left, "...", "groups.name", { depends = { "fade" } })`).

`ns.FadeDebug` prints each group's need, target and alpha, the frames found and not found, and your debuffs.

## Modes.lua

Modes is rest mode: it fades the whole interface to 0 through `UIParent`'s alpha when you've done nothing for `idleAfter` seconds (120 by default), or after 8 seconds (`AWAY_AFTER`) of nothing once the game marks you AFK. Every 0.1 seconds it checks for activity: the cursor moving, your character moving, casting or channeling, typing in the chat. Targeting, pressing a modifier, regaining control and any fight count too, through events. Activity brings everything back at once (in 0.25 s; going away takes 1.2 s). It never rests during a fight, in Edit Mode or while peeking.

Frames that ignore their parent's alpha also ignore `UIParent`'s: bars 4 and 5, and the buttons a hint reveals. Modes calls `ns.HintsDirty()` when the mode changes so Hints drops its glows, and `ns.ModeNow()` tells Hints that rest mode is on. Bars 4 and 5 stay visible in rest mode when `rest` is above 0, which doesn't happen at the default.

The settings slider goes up to 900 seconds; the slash command (`/serene idle 30-1800`) to 1800.

## TopBar.lua

`SereneTopBar` is a glass band across the top of the screen, only as wide as its contents so it doesn't cover the portraits or the compass. Its items, each switched in `topItems`, are the queue, zone, coordinates, experience in percent (blue when rested), gold, free bag slots, durability with the repair cost, the loot rule, frame rate and latency, volume (changed with the mouse wheel) and the clock. Each has a tooltip and a click action. Gold's tooltip adds up your other characters, whose money TopBar keeps in `SereneDB.gold[realm][name]`. Addon memory is shown only in the performance tooltip, and never in combat. Right-click opens the item menu, except on the queue and the clock, which keep their own right-click and use Shift-right-click instead. Shift-drag moves the band and saves `topPos`.

Fade asks `ns.TopNeeded` whether to show it, which depends on `topShow`: `always`, `calm` (away in fights) or `hover` (the default: under the mouse, or while an item has something to warn about, such as full bags, gear at 20% or less, or being in a queue). The queue warning matters because the compass's queue eye fades away with the minimap. The `top` setting switches the band live.

## MenuBar.lua

MenuBar replaces the game's micro menu with a band of words on the same glass as the top bar, just under it: Character, Spells, Talents, Quests and so on, plus "Bags" with the number of free slots. A word is gold with a line under it while its window is open, and gets a small gold dot when its button would flash. The game's micro buttons aren't restyled directly, partly because on this client a micro button's highlight texture is its icon.

Each word is a `SecureActionButtonTemplate` button. Normally it has `type = "click"` aimed at the game's own micro button, so it opens things exactly as the game does, in combat too. When the client has no backpack button, the Bags word is a macro (`/click SereneMenuBags`) instead. Because the secure clicks need them, the game's buttons are kept: `Away` holds them at alpha 0 and turns their mouse off. The bag bar's slots move into the bags window.

The band is placed under the top bar but not anchored to it. It holds secure buttons, which can't be re-laid out in combat, and the top bar must stay free to move, so out of combat the band checks once a second where the top bar is and follows it. The words' states are refreshed every 0.25 seconds. `/serene debug menu` prints the buttons, their labels and state.

## Minimap.lua

Minimap turns the game's minimap into the compass: a thin gold ring with tick marks and a shadow, N/E/S/W letters that turn with "Rotate Minimap", an info band underneath with zone, coordinates and clock, round badges on the ring for the calendar, the addon panel and tracking, zooming with the mouse wheel, and an optional square edge. Mail, queue and difficulty indicators stay where the game puts them.

The game's clutter around the minimap is reparented into a hidden frame (`Tuck`). The game shows some of it again by itself, so `Gather()` repeats every 2 seconds. The game's coordinate and clock texts have no known names on this client, so they're found by their text pattern. `Layout` runs every frame but returns at once unless the width, the shape, the rounded facing, or the side of the screen the compass is on has changed.

The tracking badge is the game's own tracking button, scaled down and laid invisibly over Serene's badge, so its menu is the game's; that's arranged out of combat only. Its tooltip is rewritten from OnUpdate, because the game rewrites it while it's shown.

The addon panel collects every addon's minimap button: LibDBIcon buttons, the AddonCompartment, and frames named like minimap buttons, but not Questie's or HereBeDragons' map pins. Its badge sits on the lower part of the ring on the side facing the middle of the screen (225° when the compass is on the right half, 135° on the left), and the panel grows upward beside the compass. It slides out from under the ring with its icons rising one after another, stays for 2 seconds after the mouse leaves, and the badge's icon becomes a gold diamond while it's open.

On a round compass the panel's edge toward the ring is a concave arc. `Media/HoleMask.tga` cuts the arc out of the panel's glass and `Media/DiscMask.tga` draws its hairline, both generated by `tools/media/panelmasks.py`; each row of icons sits as close to the arc as it fits. A square compass gets a straight edge.

The square edge sets the minimap's mask and overrides the global `GetMinimapShape`, which LibDBIcon and HereBeDragons read to place buttons. The round edge is the game's own and isn't touched at login; the round mask is only restored when switching back from square. `minimap` needs a reload, `edge` applies live through `ns.MinimapEdge`, and Fade reads `compass`. `ns.MinimapDebug` lists the addon buttons in the panel, the LibDBIcon registry and the queue-eye candidates.

## Tracker.lua and Names.lua

Tracker hides `ObjectiveTrackerFrame` and Questie's tracker, and hides them again whenever they reappear. The `Serene_ToggleTracker` key binding or the `tracker` setting brings them back. In combat the game may refuse to hide the tracker because its quest item buttons are protected, so during a fight it's only made invisible and is properly hidden once combat ends. It looks again 3 and 10 seconds after login, because Questie builds its tracker late.

Names gives one key (`` ` `` by default, `Serene_ToggleNames`) that hides every name-over-heads CVar at once. It saves the previous values in `namesSaved` and restores exactly those. The default key is bound once per account (`namesKeyGiven`), and only if nothing else holds it; leftover `WANDERER*` bindings from another addon don't count as taken. It never binds in combat.

## Settings.lua

The settings panel is built from Serene's own widgets on one canvas and registers with `Settings.RegisterCanvasLayoutCategory` under AddOns, falling back to `InterfaceOptions_AddCategory`, or failing both, a standalone window. `ns.OpenSettings(page)` opens it, which is what `/serene` with no word does. It has eight pages chosen by words across the top, and remembers the last one in `settingsPage`.

The pages are declared in `PAGES`, each entry `{ key, title, build }`, where `build(left, right)` adds rows to the page's two columns:

```lua
{ "general", "General", function(left, right)
	Header(left, "Fading")
	Toggle(left, "Fade the interface when calm", "fade")
	Toggle(left, "Action bars", "groups.bars", { depends = { "fade" } })
	...
end },
```

The row builders are `Header(column, text)`, `Toggle(column, text, path, opts)`, `Choice(column, text, path, options, opts)` with options as `{ value, label }` pairs shown as pills, `Slider(column, text, path, low, high, step, show, opts)` where `show(value)` formats the number, `Actions(column, text, actions, opts)` for buttons that run a function, and `Note(column, text, opts)`. A path names a setting, `"fade"` or `"groups.bars"`, and the file's `Get` and `Set` read and write it.

The options the rows take (`reload` only on toggles):

| Option | Effect |
|---|---|
| `depends` | settings the row needs: `"key"` on, `"!key"` off, or `"key=value"`; unmet, the row dims to 40% but stays clickable |
| `after` | a function run after the value changes |
| `note` | a short muted word beside the label, such as `"reload"` |
| `reload` | changing it shows the gold "Reload to apply" button, which stays up until a reload even if you switch back (`needsReload`) |

Toggles and choices apply at once through `Apply`, which calls `ns.Refresh()` and then every control's `Update()`; sliders call `ns.Refresh()` as they move. `tools/test/spec/settings.lua` checks that every control names a real setting of the right type, and that a choice only offers values its setting's comment in `ns.DEFAULTS` lists.

## Setup.lua

The setup is a window of glass in the middle of the screen (`SereneSetup`, Escape closes it), only as wide as its column of rows and as tall as its tallest page, so the buttons stay put from page to page. It opens two seconds after login when there is something to show:

- On the account's first login (Core sets `ns.fresh` when `SereneDB` didn't exist yet), the setup's pages: a welcome, the presets, then Fading, Compass and top bar, Bars and frames, Chat and tooltips, Bags and merchants, and a last page. Dots under the page show where you are; Back and Next move between pages. "Keep the defaults" on the welcome page closes it with nothing changed, and "Skip to the end" on the others goes to the last page.
- After an update, if `NEWS` has an entry newer than `setupSeen`, only what's new: one page with each newer version's rows under a header. Players who had Serene before the setup existed get this too, never the welcome.

Either way `setupSeen` is set to the newest version in `NEWS` at login, so neither opens again by itself. `/serene setup` and `/serene news`, and the two buttons under Setup on the panel's General page, open them again; with nothing new since, the news page shows the latest version's.

The pages' rows are the settings panel's own controls, built through `ns.SettingsRows(frame, width, build)` with the builders from `ns.SettingsKit`, so they look the same, apply at once and keep the panel's rows in step (`ns.SettingsApply`). `spec/settings.lua` holds Setup.lua's rows to the same rules as the panel's.

The presets are three cards, one under the other: **Serene** (the defaults), **Always in view** (nothing fades or rests, the quest tracker shown) and **A light touch** (the game's own bars, unit frames, cast bar, buffs, bags, merchant, menu, swing timer and toasts; no top bar, readiness or hints). Picking one sets every key any preset names, to that preset's value or else the default, so picking one after another never leaves a mix; settings no preset names stay as they are. The card whose keys match the settings now is gold, so a fresh install opens with Serene chosen.

The setup keeps the values of the settings read only at login (`RELOAD`, the same ones the panel marks "reload") as they were at login. If any differs on the last page, its button is "Reload" and reloads the interface; closed any other way, a line in the chat says a `/reload` is owed.

A version that brings settings worth showing gets an entry at the end of `NEWS`: `{ version, header, build }`, where `build(column)` adds the rows. Its version is never newer than the TOC's `## Version`, which `spec/setup.lua` checks; a version with nothing to switch needs no entry.

## Bindings.xml

Three key bindings, under AddOns > Serene: `SERENE_PEEK` shows everything while held (it uses `runOnUp`, so it hears the key going down and coming up), `SERENE_TRACKER` toggles the quest tracker and `SERENE_NAMES` the names over heads. Their names in the key binding menu are the `BINDING_*` globals set in Fade.lua, Tracker.lua and Names.lua.
