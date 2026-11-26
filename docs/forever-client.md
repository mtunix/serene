# The Forever client

Serene is written for the "Forever" realm client (`## Interface: 16001`). Its crash logs call the project "Camelot", and ElvUI handles it as `E.Forever`. It runs classic-era content on a retail 12.x engine that follows the Midnight (patch 12.1) rules for addons. That combination is the source of most of the odd-looking code in Serene: neither classic nor retail documentation describes this client reliably, so the code checks what exists and falls back where it can. This page collects what is known about the client; the other pages link here rather than repeating it.

## Classic content, retail engine

The content is classic era: classic quests (and Questie), the keyring, quivers and soul bags, classic spell ranks and IDs, level 60. As on classic, addons can read the combat log.

The interface underneath is retail's. Bags go through `C_Container`, the backpack is Blizzard's combined bag (`ContainerFrameCombinedBags`) and there is a reagent bag (bag 5). The character bank is the newer tabbed one (`C_Bank`, `BankFrame.BankPanel`), where each tab holds a bag in an inventory slot named by `C_Bank.BankBagTypeAndIDToInvSlot`. Whether that call expects the tab's index or its id is unclear, so Bags.lua tries both. There is Edit Mode, `TooltipDataProcessor` with typed tooltip data lines, and the settings panel API (`Settings.RegisterCanvasLayoutCategory`).

## What is secret in combat

In combat the client hands addons secret values: values that can be passed on to the game but not compared, used in arithmetic or used as table keys (see [architecture.md](architecture.md#secret-values) for how Serene copes). What is known to be secret on this client:

- the player's aura data, and every field of the `UNIT_AURA` update info;
- other units' aura data, including the icons' textures;
- health and power in some cases, and the values behind heal prediction;
- frame sizes: `GetWidth` and `GetHeight` can return a secret, and so can an AuraContainer's size;
- `IsShown` on aura buttons.

For the player's own auras it goes further than secrecy. In combat, `GetAuraDataByIndex`, `GetAuraSlots` and `GetUnitAuras` return nothing for the player and `GetAuraDataByAuraInstanceID` raises an error; out of combat all of it reads normally. The game's own BuffFrame and DebuffFrame keep updating in combat, but their buttons' `buttonInfo` only has a readable `index` and `auraType`; the instance ID, texture, count, duration and expiration are secret. The game also folds some buttons away and slots a new aura into the middle of its list rather than at the end, so the buttons can't be used to work out which aura is which.

The secret-safe toolkit that comes with these rules is all present: `issecretvalue`, `C_Secrets`, `C_CurveUtil.CreateCurve` and `CreateColorCurve`, `Region:SetAlphaFromBoolean` and `SetVertexColorFromBoolean`, `C_UnitAuras.GetAuraDuration` returning a DurationObject, `Cooldown:SetCooldownFromDurationObject`, `GetAuraDispelTypeColor` and `CreateUnitHealPredictionCalculator`.

## AuraContainer

The supported way to show auras in combat on this client is Blizzard's AuraContainer: the addon builds the widgets and the game fills them, secret values included. AuraFrame.lua and UnitAuras.lua are built on it.

A container is created with `CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")`, then given a unit with `SetUnit` and switched on with `SetEnabled(true)`. `AddAuraGroup(key, filter, options)` adds a group of auras; the options include `initializeFrame`, `maxFrameCount`, `candidateFilters`, `sortMethod`, `sortDirection` and the layout. `SetFlowLayout*` lays the frames out, and `AddItemEnchantment` adds weapon enchants.

In `initializeFrame` the addon makes its own textures and font strings and hands them to the game with `SetIcon`, `SetApplicationCount`, `SetDurationCooldown`, `SetDurationText`, `AddDispelTypeTexture` and `SetCancelAuraButtons`. From then on the game keeps them up to date.

Filters are strings such as `HELPFUL` or `HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY`, and a `!` in front of a token negates it (`!PLAYER`). Candidate filters can include or exclude spell IDs or dispel types and set a `maxDuration`. A container only listens to `UNIT_AURA` for its own unit, so when the unit itself changes it has to be told: UnitAuras.lua calls `UpdateAllAuras()` on `PLAYER_TARGET_CHANGED` and `PLAYER_FOCUS_CHANGED`.

The target, focus and nameplate aura icons the game draws are one newer template (keys `Icon`, `Cooldown`, `CountFrame`, `useAuraDisplayTime`, plus an unnamed OVERLAY border texture). They aren't reachable from TargetFrame's tree: its "Auras" holder has no children. The square icon above the target card is one of them, the target's debuff. On nameplates, the cooldown timing calls never reach Lua at all, neither through hooks on the cooldown frame nor through the Cooldown metatable, which is why Serene reuses the game's own swirl there (see [auras.md](auras.md)).

## Things only this client has

The client has its own swing timer. It is switched by the CVar `showSwingTimer`, placed by Edit Mode as a system with two frames (`Enum.EditModeSwingTimerSystemIndices` MainHand and OffHand), exposed through `C_SwingTimer`, and announced by the event `PLAYER_SWING(swingDuration, swingType)` with `Enum.PlayerSwingType` 0 for main hand, 1 for off hand and 2 for ranged. The frames' names aren't documented anywhere, so Swing.lua finds them through Edit Mode.

Roll messages in the loot chat start with a hidden link of their own, `|HlootHistory:%d|h[Loot]|h: `, which shifts every argument of the sentence by one. ChatLoot.lua skips such leading arguments.

The sell price in item tooltips isn't a money frame. It's a typed data line (`Enum.TooltipDataLineType.SellPrice`) drawn as a plain text row, with `lineData.price` holding the price of the whole stack. Tooltip.lua rewrites that row in place rather than appending its own line.

## The game's frames

A few of the game's frames behave in ways that explain specific code:

- A micro button's highlight texture is its icon, so replacing the highlight makes the icon disappear (MenuBar.lua).
- The pet frame's health bar is anchored to its portrait. Anchoring the portrait to the bar makes an anchor loop, which the engine silently refuses, and the whole frame disappears (Units.lua).
- `TargetFrameMixin:CheckClassification` sets the health fill's atlas directly on the fill texture, bypassing `SetStatusBarTexture`, so hooking the status bar isn't enough (Units.lua).
- Heal prediction segments carry the health bar's slanted mask (Units.lua).
- The cast bar ends a cast through its own methods: `PlayFadeAnim` when the spell lands, `PlayInterruptAnims` when it's interrupted or fails, and `ApplyAlpha(1)` when the next one starts. Its way out is two animations on the bar, `FadeOutAnim` and `HoldFadeOutAnim` (a hold after an interrupt), and the bar is hidden when they finish. An interrupt can also shake it (`InterruptShakeAnim`). The time is `CastTimeText`, shown only when Edit Mode's "Show Cast Time" is on (CastBar.lua).
- The game's XP bar keeps its own animation state; calling `SetValue` on it leaves it empty, so Serene never writes to it (Experience.lua).
- The recipe toast's icon is a baked, pre-masked round texture (`mask9`) that includes the bevel (Toasts.lua).
- `GetLatestCompletedAchievements` returns nothing, so the sample achievement toast finds one by scanning categories (Toasts.lua).

## Key bindings

The key binding menu is retail's (`Blizzard_SettingsDefinitions_Frame/Keybindings.lua`). It groups bindings by their `category` attribute in `Bindings.xml`. That attribute is the name of a global string, which becomes the section's title (Serene uses `BINDING_HEADER_SERENE`). The menu is rebuilt on `ADDON_LOADED`, after the addon's Lua has run, so the string exists by then. A binding without a category goes under "Other". The classic `header` attribute adds a pseudo-binding named `HEADER_<name>`: with no category, the menu lists it as a binding row called `HEADER_SERENE`, both under "Other" and in search results. There is no "AddOns" section.

## Textures

Passing `"TRILINEAR"` as the filter argument to `SetTexture` on Serene's TGA files, for a texture or a mask, crashes the client at login with `ACCESS_VIOLATION reading 0xffffffffffffffff` and no Lua stack. `tools/test/spec/client_rules.lua` fails if any file passes it. Crash reports are written to `_forever_/errors/`.

There is no anti-aliasing setting for textures either. Small round shapes are smoothed with soft-edged textures (`Media/AuraDisc.tga` and the other discs), baked near the size they are shown, with `SetSnapToPixelGrid(false)` and `SetTexelSnappingBias(0)` on the region. [workflow.md](workflow.md) describes the scripts that make them. Changed textures are only loaded when the game restarts.

## Finding out what the client does

Since nothing documents this client completely, these are the ways to find out:

1. Look at other addons that run on it. TradeSkillMaster's `LibTSMWoW` treats `IsForever` like retail. ElvUI handles it as `E.Forever`, and oUF's aura element shows how to use AuraContainer, for example its `ForceUpdate` when the unit changes. Wanderer's merchant window (`MerchantWindow.lua`, `Swap.lua`, `Util.HideOffScreen`) has the off-screen pattern Vendor.lua uses. VendorPricePlus and AutoBiographer are useful too.
2. Search the client binary for names: `grep -aoE 'C_SwingTimer[A-Za-z_.]*' Wow.exe`, or the same for any enum or API name. The swing timer's two Edit Mode frames, the AuraContainer enums and the secret-safe toolkit can all be found this way.
3. Read Blizzard's UI source for this build: Gethe/wow-ui-source, `forever` branch, version 12.1.5.70961, in particular `BuffFrame.lua`, `UnitAuraDoc` and the AuraContainer templates. Clone it outside the `AddOns` folder, since the game scans everything in there. (`tree.json` in the addon folder is a listing of that repository's files, kept locally for searching and ignored by git.)
4. The game's English strings (GlobalStrings) come from Ketho's BlizzardInterfaceResources, `classic_era` branch; `tools/test/gen_globalstrings.py` downloads them for the tests.
5. Probe in game and read the result back from SavedVariables. A debug command writes what it finds into `SereneDB`, a `/reload` writes the file, and the file can then be read outside the game. This is the most reliable of these; [workflow.md](workflow.md) describes how.
