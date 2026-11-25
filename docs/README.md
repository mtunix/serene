# Serene developer documentation

Serene is a user interface addon for the World of Warcraft Forever client, which runs classic-era content on a retail 12.x engine. It changes how the game's interface looks and behaves rather than adding features: the chat sits on glass, the minimap becomes a compass, the unit frames, cast bar, auras, swing timer and action bars are restyled, tooltips are quieter, and most of the interface fades away when it isn't needed. The bags, bank and merchant are Serene's own windows.

These pages explain how the code is organised and why it's written the way it is. A lot of it looks roundabout until you know what this client allows: values hidden in combat, frames that can't be touched during a fight, game frames whose parts have to be searched for at runtime.

## Where to start

Read [forever-client.md](forever-client.md) first. It's short and describes the client itself: which APIs it has, what it hides from addons in combat, and how it differs from both retail and classic. Then read [architecture.md](architecture.md), which covers loading, settings and saved data, the shared helpers, the usual shape of a module, and the techniques almost every file relies on. [workflow.md](workflow.md) covers the static check, the tests and debugging in game.

After that, read the page for the area you're working on:

| Page | Files |
|---|---|
| [chat.md](chat.md) | Chat, ChatLoot, ChatLines, ChatCard, ChatShell |
| [tooltips-toasts.md](tooltips-toasts.md) | Tooltip, Toasts |
| [units.md](units.md) | Units, CastBar, Swing, Regen, Experience |
| [auras.md](auras.md) | Auras, AuraFrame, UnitAuras |
| [action-bars.md](action-bars.md) | Actions, ActionBars, Hints, Ready, BarCooldowns, BarKeys, BarPages, Ranks, Reagents, BarPing, BarSets, BarSupplies, BarUse |
| [bags-merchant.md](bags-merchant.md) | Items, Bags, Vendor, Merchant |
| [shell.md](shell.md) | Fade, Modes, TopBar, MenuBar, Minimap, Tracker, Names, Settings |

## The look

Serene aims to keep the feel of the original World of Warcraft interface while making it calm and minimal. The game's character shows in a few accents: 1px hairlines in a soft version of its gold, round portraits, and gold for what matters. Everything else is Serene's: dark glass, flat colours with no gradients, quiet text, space around things, and fading out when not needed. The game's ornate borders at their full thickness are too heavy for this, and so are its glossy bars. The game's frames are restyled rather than replaced; [architecture.md](architecture.md#restyle-dont-rebuild) explains what that means for the code and which windows are Serene's own.

The design notes are also at the top of `Core.lua`, and each file's header describes what it shows.

## Words used in the code and these pages

| Word | Meaning |
|---|---|
| dress | To restyle one of the game's frames: find its parts, put its art away, add Serene's own pieces and hook its setters. Most files have a `Dress` function and a `dressed` table. |
| glass | The dark, slightly see-through backdrop (`ns.INK`) Serene draws behind things in place of the game's borders. |
| hairline | A 1px line, usually in soft gold (`ns.LINE`), around a piece of glass (`ns.Hairline`). |
| card | A unit frame as Serene draws it: portrait and bars on one piece of glass. Also the player card shown in chat and tooltips. |
| band | A strip of glass across the top of the screen: the top bar (TopBar.lua) and the menu band of words under it (MenuBar.lua). |
| compass | The minimap as Serene draws it, with its ring, letters and degree ticks. |
| fade, rest | Fading a part of the interface away when it isn't needed. A faded part rests at the opacity set by `rest` (0 by default). |
| rest mode | Everything faded at once while you're away or idle (Modes.lua). |
| peek | Holding the Peek key, which shows the whole interface for as long as it's held (`Serene_Peek`). |
| hint | A gold glow on an action button worth pressing now, such as food when you're not Well Fed or a missing class buff (Hints.lua). |
| tiers | AuraFrame's split of your buffs: short ones at full size, long steady ones in a small row. |
| ghost buffs | Your class's buffs that you're missing, shown greyed out in AuraFrame; clicking one casts it. |
| world shelf | AuraFrame's own row for world buffs. |

## Files

Modules initialise in TOC order, which is the order of this table.

| File | What it does |
|---|---|
| `Core.lua` | Holds the defaults, the palette and the shared helpers, loads the modules and handles `/serene`. |
| `Capture.lua` | Records the game's chat sentences and item tooltips as test data, but only after `/serene capture on`. |
| `Actions.lua` | Answers questions about the action buttons and their slots (`ns.Actions`) for every bar file. |
| `Items.lua` | Reads bag slots and decides each item's section, and so what counts as junk (`ns.Items`), for the bags, merchant and tooltips. |
| `Tooltip.lua` | Puts tooltips on glass, quietens their colours and fades them; its `ns.ShowTip` and `ns.HideTip` are used by most files. |
| `Chat.lua` | Puts each chat message on its own glass, shows the tabs as words and widens the window as Edit Mode allows. |
| `ChatLoot.lua` | Folds loot, rolls, money, experience and reputation messages into a few short lines. |
| `ChatLines.lua` | Shortens channel tags, adds the hour, groups a speaker's lines, fades new lines in, holds public channels during fights, and handles copying and links. |
| `ChatCard.lua` | Shows a card about a player when the mouse is over their name in the chat. |
| `ChatShell.lua` | Draws the chat window's controls that appear on hover: the pane, the icons, the scroll bar, the "new messages" pill and the resize grip. |
| `Minimap.lua` | Turns the minimap into the compass, with the zone and time under it and a panel for addon buttons. |
| `Hints.lua` | Lights action buttons worth pressing: food when you're not Well Fed, missing or expiring class buffs. |
| `ActionBars.lua` | Restyles the game's action bars: art away, keys small and quiet, empty slots see-through. |
| `Ready.lua` | Dims action buttons that can't be used right now (cooldown, power, range, no target) until they can. |
| `BarCooldowns.lua` | Draws cooldowns in the bars' look and puts the global cooldown on a single line under Action Bar 1. |
| `BarKeys.lua` | Shows a button's key brightly while you still click it, and hides it once you use the key. |
| `BarPages.lua` | Fades Action Bar 1's icons in when its page or form changes, and shows the page number. |
| `Ranks.lua` | Puts a spell's new rank onto the buttons that hold the old one, by itself or after a click. |
| `Reagents.lua` | Colours a reagent count amber when it runs low, and mentions it at merchants who sell it. |
| `BarPing.lua` | Sends a soft ring out from a button when a long cooldown comes back. |
| `BarSets.lua` | Keeps a copy of your bars, puts back what left them by itself (a talent reset), and saves named sets. |
| `BarSupplies.lua` | Keeps macros pointing at the best food, water, potions and bandages you carry. |
| `BarUse.lua` | Notices buttons you never press and suggests easier keys for the ones you press most (`/serene review`). |
| `MenuBar.lua` | Replaces the micro menu and bag buttons with a band of words under the top bar. |
| `Experience.lua` | Shows the experience bar for a moment when you gain experience, with the new part lit gold. |
| `Toasts.lua` | Restyles the recipe and achievement toasts and lets you move them. |
| `Fade.lua` | Fades groups of frames to the rest opacity and brings them back when they're needed. |
| `Swing.lua` | Restyles the client's built-in swing timer as thin lines of glass. |
| `Units.lua` | Restyles the player, pet, target, focus and target-of-target frames as cards. |
| `CastBar.lua` | Restyles your cast bar as a slim line on glass. |
| `Auras.lua` | Restyles the game's aura buttons (nameplates, and yours when `auraFrame` is `"game"`) and holds the aura look shared by the other aura files. |
| `UnitAuras.lua` | Draws the target's and focus's auras on Serene's own AuraContainers. |
| `AuraFrame.lua` | Draws your buffs and debuffs on Serene's own AuraContainers, with tiers, ghost buffs and the world shelf. |
| `Regen.lua` | Draws the five-second rule as a gold line under your mana bar. |
| `TopBar.lua` | Draws the band at the top: zone, experience, money, bags, durability, performance and the clock. |
| `Tracker.lua` | Hides the quest tracker and brings it back with a key. |
| `Names.lua` | Hides or shows the names over heads with one key. |
| `Merchant.lua` | Buys full stacks (Alt-click or the Stack button) and restyles the game's stack-split popup. |
| `Vendor.lua` | Draws Serene's merchant window, sells junk and repairs at every merchant. |
| `Bags.lua` | Draws Serene's bags and bank windows, remembers your other characters' items, and offers "make room". |
| `Modes.lua` | Puts the interface into rest mode when you're idle or away. |
| `Settings.lua` | Builds the settings panel: Serene's own controls on eight pages. |
| `Bindings.xml` | Declares the key bindings for Peek, the tracker and names. |
| `Media/` | Holds Serene's textures; the scripts that make them are in `tools/media/`. |
| `tools/check.py` | Checks every file for parse errors, unknown globals, locals used too early and accidental globals. |
| `tools/test/` | Runs the addon's logic outside the game against a stub of the client ([workflow.md](workflow.md)). |

Two names are easy to mix up. `Vendor.lua` is the merchant window and is switched by the setting `merchant`; `Merchant.lua` buys full stacks and is switched by the setting `vendor`.

## Writing these docs

Refer to code by function name rather than line number; names can be searched for and don't go stale. Facts about the client go in [forever-client.md](forever-client.md) and techniques in [architecture.md](architecture.md); other pages link to them rather than repeating them. When a change alters something a page describes, update the page in the same change.
