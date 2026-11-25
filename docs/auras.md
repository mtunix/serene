# Auras

Three files handle buffs and debuffs, and they split the work by whose auras they are and how they get at them.

| | Auras.lua | AuraFrame.lua | UnitAuras.lua |
|---|---|---|---|
| How | restyles the game's own aura buttons through hooks | Serene's own AuraContainers, filled by the game | Serene's own AuraContainers, filled by the game |
| Your buffs, debuffs, weapon enchants | only with `auraFrame = "game"` | with `auraFrame = "serene"` (the default) | |
| Target and focus | the game's holder, which UnitAuras silences | | with `auraUnits` on |
| Nameplates | with `auraPlates` on | | |

`auras` switches all three: Auras.lua's `Init` returns at once without it, AuraFrame starts only when `ns.SereneAuraFrame()` is true (`auras` on and `auraFrame = "serene"`), and UnitAuras needs both `auras` and `auraUnits`. Each of these needs a reload.

The split follows from what this client lets an addon read. In combat the player's aura data is out of reach and other units' is secret (the details are in [forever-client.md](forever-client.md)), so nothing that works by reading aura data keeps working once a fight starts. An AuraContainer avoids the problem: the addon builds the icon widgets, the container is set to a unit, and the game fills the widgets itself, in combat too. AuraFrame and UnitAuras are built on that. Auras.lua takes the other route and dresses the game's own buttons, passing on whatever the game sets on them without looking at it. None of the three reads aura data in a fight.

## The shared look

`Look()` in Auras.lua turns the aura settings into one table, exported as `ns.AuraStyle.Look`. All three files build their icons from it, so changing a setting changes every aura on screen.

| Setting | Choices |
|---|---|
| `auraShape` | `"round"` or `"square"` |
| `auraRing`, `auraRingSize` | ring on `"all"`, `"debuffs"` or `"none"`; 1 to 3 px |
| `auraColors` | debuff colours `"quiet"` (Serene's shades) or `"game"` |
| `auraEdge` | a dark hairline outside the ring |
| `auraDim` | darken the elapsed part of the icon |
| `auraDrain` | on the game's buttons, the ring drains as the aura runs out |
| `auraTime`, `auraTimeAt`, `auraTimeSize` | time text `"outline"`, `"plate"` or `"none"`; `"under"` or `"on"` the icon; font size (0 for automatic) |

Every round part, whether mask, ring, edge or swirl, is the same texture, `Media/AuraDisc.tga`, so the parts line up exactly and stay smooth at small sizes. Its edge is soft in the file itself, and `Smooth()` sets CLAMP wrapping and turns pixel snapping off. The quiet debuff colours are in `KINDS`: magic blue, curse violet, disease ochre, poison green, anything else soft red.

## Auras.lua: the game's buttons

### Finding them

The game's aura buttons use different key names from build to build, so no part is read from a fixed key. `IconOf(button)`, for example, first tries the keys `Icon` and `icon`, then the old global `<button name>Icon`, and finally any key containing the word "Icon" that holds a texture and isn't a border, highlight or similar (`NOT_ICON`). `CountOf`, `DurationOf` and `CooldownOf` follow the same pattern through the shared helpers `Part` and `KeyWith`.

When a button has no useful keys at all, two shape tests take over. `LooseIcon` picks the largest square texture. `SecretIcon` picks a square texture of 48 px or less whose texture is secret; this works because the game sets aura icons as secret textures and none of its frame art.

`ScanPlayer` walks `BuffFrame`, `DebuffFrame` and `TemporaryEnchantFrame` (their `auraFrames` lists first, then their children), falling back to the old `BuffButtonN` globals. `ScanUnits` does the same for TargetFrame and FocusFrame through their pools, the holders `ns.AuraContainers` finds, and the secret-icon walk. `ScanPlates` goes through `C_NamePlate.GetNamePlates()` to each plate's `UnitFrame.AurasFrame`, and `PlateExtras` tucks away the unkeyed square border art there. `Walk` skips any frame flagged `sereneOwn`, which is how UnitAuras marks its own containers; their icons are secret textures too and would otherwise be dressed a second time.

Scans are driven by hooks on the holders' update methods and by events: target and focus changes, `UNIT_AURA` for player, target and focus, Edit Mode and scale changes. `Request()` sets `pending` and folds everything that arrives in the same frame into one `C_Timer.After(0, Scan)`, so the scan runs once, after the game has filled its buttons for the same event. The focus needs a second event frame because `RegisterUnitEvent` takes at most two units. Nameplates are also rescanned on a 0.5 s ticker while any are shown.

### Dressing a button

`Dress(button, kind)` builds the parts and keeps them in `dressed[button]`, a plain table in the file:

- `a.face` is a frame two levels above the button. The game's icon is reparented onto it, its masks swapped for the round `AuraDisc` mask, and its baked-in edge trimmed by `TRIM`.
- `a.dim` is a Cooldown of Serene's over the icon, reversed and black at `DIM` (0.55), which darkens the part of the aura's time that has passed.
- `a.top` holds the game's count and duration text above everything else.
- `a.rim` and `a.edge` are slightly larger discs behind the icon, so only a hairline of each shows: the ring colour, then a dark edge.
- The game's own border (debuff kind, weapon enchant) is flattened into that hairline and recoloured.
- The game's own cooldown becomes a ring around the icon (`Ring`), its swipe in the ring's colour. While it runs, `Track` dims the static rim to 0.22, so the ring reads as draining over a quiet track.

There are two swirls because one Cooldown can't be both a ring around the icon and a shade over it. The game's swirl becomes the ring, and `a.dim` has to be driven with the same timing. At file load Auras.lua hooks every timing method on the shared Cooldown metatable (`IsTimingCall` decides which) and records each call's arguments in `lastTiming[swirl]`, secrets included. `Replay(from, to)` repeats those calls on `a.dim` without reading the values. It hooks every timing-like method rather than a fixed list because the 12.x Cooldown API has several ways to set a time, and it does so at load because an aura's swirl can be set before Serene gets to dress it.

### Nameplates

Cooldown timing on nameplates never passes through Lua, so neither the hooks nor `Replay` see anything there. For plates (`a.gameDims`) the game's own cooldown is turned into the darkening instead: reversed, black at `DIM`, covering the icon and ring. `SwipeColor`, `Ring`, `Dim` and `Track` all step aside for plate icons, so plate icons have no draining ring.

### Colours and time text

`HookBorder` catches the game's `SetVertexColor` on a debuff border. If the colour can be read, `Quieter` matches it against `DebuffTypeColor` (within 0.02) and the border gets Serene's quieter shade for that kind. If it's secret, the game's values are handed on unread. When the game swaps the border's art rather than its colour, the kind comes from the atlas name (`KindOfName`), which is never secret.

The time text is shrunk and muted. Serene can't read the remaining time, but the game switches the text to near-white when an aura is running low, so `HookDuration` watches for that colour and turns it into Serene's soft white. `TimeLook` places the text on or under the icon, outlined or on a small `Media\Pill`.

`QuietArrow` shows the game's buff-collapse arrow only under the mouse while `auraArrow` is on. `Font`, `Tint` and `SwipeColor` wrap their calls in the `holding` flag described in [architecture.md](architecture.md).

### Exports

Auras.lua also provides what the other two files build on: `ns.AuraStyle` (`Look`, `KINDS`, `Quieter`...), `ns.SereneAuraFrame()` (whether AuraFrame takes over the player's auras), `ns.AuraContainers(frame)` (the game's aura holders under a frame) and `ns.AURA_FONT_AUTO`. `/serene debug mouse`, which describes the frames under the mouse and dresses one that looks like an aura, lives here as well.

## AuraFrame.lua: your buffs and debuffs

With `auraFrame = "serene"`, the player's auras are drawn on two containers, `SereneAuras` and `SereneDebuffs`. They have global names because Fade looks them up by name. The game's own frame stays available as `auraFrame = "game"`, where Auras.lua restyles it instead.

On screen the buffs are split into rows. Short buffs, the ones worth watching, are shown at full size; long, steady buffs such as an armor or a blessing step back into a row of small rings; world buffs get a shelf of their own, and weapon enchants come first.

`Init` creates both containers (if either fails, `problem` says why and the game's frame is left alone), works out what the class can dispel (`LearnDispels`) and which buffs are known to be short (`LearnShort`), places the containers (`PlaceHolders`), adds the aura groups and the weapon-enchant slots, puts the game's frames away (`PutGameAway`) and builds the ghost row (`Ghosts`). After that it listens for a handful of events. `PLAYER_REGEN_DISABLED` hides the ghost row before lockdown; spell and pet changes re-learn dispels; Edit Mode, scale and world changes put the game's frames away again. Everything else is batched into one pass 0.3 s later, and only out of combat: it re-learns short buffs and either re-applies the layout (`Apply`) or just refreshes the ghosts. A layout change asked for during a fight sets `pending` and waits for `PLAYER_REGEN_ENABLED`.

### Settings

| Setting | Effect |
|---|---|
| `auraFrame` | `"serene"` for this frame, `"game"` for the game's restyled one (reload) |
| `auraSize` | icon size of the full row and world shelf (16 to 64) |
| `auraPerRow` | icons in a row |
| `auraTiers` | long buffs go into the small row; off, every buff is full size |
| `auraShort` | a buff lasting less than this many seconds stays full size (needs `auraTiers`) |
| `auraSmall` | icon size of the small row (8 to 32) |
| `auraTimeWhen` | the time text `"always"`, `"soon"` (only in the last stretch) or `"never"` |
| `auraSoon` | the last stretch, in seconds |
| `auraWorld` | world buffs on their own shelf |
| `auraGhosts` | missing class buffs as ghosts |
| `auraDispel` | debuffs you can remove in their kind's colour, the rest grey |
| `auraDebuffSize` | debuff icon size |
| `auraDebuffAt` | debuffs `"buffs"` (under them), `"portrait"` (by yours) or `"free"` (where you dragged them) |

### Groups

The game applies the filters itself, so they work on secret data. Which groups exist depends on the settings (`Enabled`, `Filters`):

| Container | Group | Exists when | Filter |
|---|---|---|---|
| buffs (`HELPFUL`) | world | `auraWorld` | `includeSpellIDs` = `WORLD` (Rallying Cry, Warchief's Blessing, Spirit of Zandalar, Songflower, the Dire Maul tributes, Sayge, Chronoboon) |
| | full | always | excludes `WORLD` when `auraWorld` is on; with `auraTiers`, `maxDuration = auraShort` |
| | small | `auraTiers` | excludes the spells in `ns.db.auraShortSpells`, and `WORLD` when `auraWorld` is on |
| debuffs (`HARMFUL`) | removable | `auraDispel` and you can remove something | `includeDispelTypes` = what you can remove |
| | other | always | `excludeDispelTypes` = the same, under the same condition; otherwise every debuff |

Weapon enchants are added with `AddItemEnchantment` and laid out before the buff groups.

The small row needs the learned list because a container can't keep an aura out of one group just because another group shows it. "Full" can use the game's `maxDuration` filter, which works in combat, but there is no minimum-duration filter for "small". So "small" excludes every spell Serene has seen to be short, and `LearnShort` adds to that list out of combat. A short buff Serene has never seen can therefore show in both rows the first time. For the same reason a long buff stays in the small row as it runs out: the groups are decided by filters, not by reading durations.

What you can remove comes from `DISPELS`, a hand-kept table of each class's cleansing spells (classic spell IDs, any rank, plus the warlock's felhunter) checked with `IsPlayerSpell`. The result is kept in `canRemove`.

### Icons

The game calls each group's `initializeFrame`, which is `Maker(kind)`. It builds the parts of one icon (edge, ring, picture, mask, swirl, count and time text), keeps them in the weak table `made[button]`, and hands the picture and count to the game with `SetIcon` and `SetApplicationCount`. `Dress` then sizes everything from `Measure(kind)` and hands over the swirl and the time text with `SetDurationCooldown` and `SetDurationText`. `Apply` runs `Dress` again on every made button when a setting changes.

| Kind | Size | Differences |
|---|---|---|
| full | `auraSize` | |
| small | `auraSmall` | 1 px ring, no time, no count, no darkening |
| world | `auraSize` | gold ring one pixel thicker, time always shown |
| enchant | `auraSize` | violet ring |
| removable, other | `auraDebuffSize` | ring coloured by the debuff's kind |

Debuff rings are coloured by the game through `AddDispelTypeTexture` with the colour map from `KindColors(look)`, because the kind may be secret. With `auraDispel` on, debuffs you can't remove get a grey ring. The darkening is the game's own swirl through `SetDurationCooldown`. The time text is coloured by a curve (`TimeCurve`) over the remaining duration: soft white in the last 10 seconds, muted before that, and with `auraTimeWhen = "soon"` fully transparent until the last `auraSoon` seconds. Hiding the time until it matters has to happen inside the curve, because Lua can't read the time.

### Placement

`PlaceHolders` anchors the buffs by their top-right corner at `auraAt` if you've moved them, otherwise at the game's `BuffFrame`, which Edit Mode positions. They grow left, `auraPerRow` to a row. Debuffs go under the buffs, beside your portrait, or wherever you dragged them (`auraDebuffFree`). `/serene aurasmove` (`ns.AuraMove`) shows two movers to drag; they have a fixed size because the containers' own size can be secret. `ns.AuraReset` returns both to the default place.

`PutGameAway` doesn't touch `BuffFrame`, `DebuffFrame` or `TemporaryEnchantFrame` themselves. It silences the `AuraContainer` inside each (`ns.Silence`: alpha 0 and scale 0.01, re-applied from `SetAlpha` and `SetScale` hooks) and makes the collapse arrow invisible and unclickable. The outer frames stay shown and in place, which is what lets Edit Mode keep positioning `BuffFrame`, and Serene's buffs follow it. Only a frame with no inner container is reparented to a hidden frame instead.

### Ghost buffs

`ns.MissingClassBuffs()` from Hints.lua lists the class buffs you're missing. Each is drawn as a faint grey copy of its icon to the left of the top row, and each is its own `SecureActionButtonTemplate` button with `type1 = "spell"`, so a click casts it. They can't share one button laid over the container, because Serene can't read where the container put its icons. Ghosts are only built out of combat and are hidden on `PLAYER_REGEN_DISABLED`.

Placing the ghost row is the fiddly part. `PlaceGhostRow` needs the width of the top row, but the container's width is that of its widest row, and it may be secret anyway. `TopRowWidth` therefore re-runs the flow layout by hand from the number of icons in each group, and it has to agree with `Layout`, which starts every group after the first on a new line (the game's flow layout does that whenever anything was placed before it, enchants included). If you change one, change the other; both also copy the game's flow-layout rules and would need to follow any change there. The counts come from `Shown()`, which counts the made buttons that are shown. Some effects make even `IsShown` secret, and then `Counted()` works the counts out from your buffs and weapon enchants instead, which can be read out of combat.

`/serene debug` prints a "buff frame" line: each group's count and where it came from, how many ghosts and known short buffs there are, and the kinds you can dispel.

## UnitAuras.lua: target and focus

The target's and focus's aura icons live in frames addons can't usefully reach, and their aura data is secret in combat, so UnitAuras gives each unit an AuraContainer of its own: `SereneTargetAuras` and `SereneFocusAuras`. Each is parented to its unit frame, flagged `sereneOwn` so Auras.lua leaves its icons alone, anchored above the card at the name's top-left, and grows right and up, eight icons to a row.

It has three groups, in this order:

| Group | Filter |
|---|---|
| mine (23 px) | `HARMFUL\|PLAYER\|INCLUDE_NAME_PLATE_ONLY` |
| debuffs (18 px) | `HARMFUL\|!PLAYER\|INCLUDE_NAME_PLATE_ONLY` |
| buffs (18 px) | `HELPFUL` |

`INCLUDE_NAME_PLATE_ONLY` matches what the game itself shows on the target. If the client refuses the `!PLAYER` filter, `AddGroups` falls back to all debuffs, and your own then appear twice. Debuff rings are coloured by kind through `AddDispelTypeTexture` with `ns.AuraKindColors` from AuraFrame, icons are darkened by `SetDurationCooldown`, and there is no time text. Like AuraFrame, a layout change in a fight waits for `PLAYER_REGEN_ENABLED`.

A container only hears `UNIT_AURA` for its unit, so on `PLAYER_TARGET_CHANGED` and `PLAYER_FOCUS_CHANGED` the file calls `UpdateAllAuras()`. The game's own holder (`TargetFrameContent.TargetFrameContentContextual.Auras`, or the first holder `ns.AuraContainers` finds) is silenced the same way as the player's frames. Auras.lua still dresses that silenced holder and runs its secret-icon walk there, which costs a little and shows nothing.

Because nameplates use the game's swirl and target and focus use UnitAuras, the draining ring (`auraDrain`) only appears on the player's buttons with `auraFrame = "game"`.
