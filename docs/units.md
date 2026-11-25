# Unit frames, cast bar, swing timer, regen and experience

Five files restyle frames the game already has: `Units.lua`, `CastBar.lua`, `Swing.lua`, `Regen.lua` and `Experience.lua`. None of them builds a replacement. Edit Mode still places and sizes the frames, clicks and menus still work, and the game still fills the bars and decides when they show. Serene changes the art, the colours and the positions of the frames' own child regions. The general techniques they rely on (putting art away without `Hide()`, the `holding` flag, permanent hooks) are explained in [architecture.md](architecture.md).

Health, power and cast numbers can be secret in combat, and these files never read them. The game fills its own bars; Serene only picks colours, and those come from who the unit is (class, reaction, tapped, dead), read through `Clean(Safe(...))`.

## Units.lua

Units.lua restyles the frames listed in `FRAMES`: the player, pet, target and its target, focus and its target. Each becomes a card of flat bars on glass with a round portrait at one end, the name above the bars and the level at the end of the name row. Elites and rares get a small mark and, optionally, the game's dragon fitted around the smaller portrait. The target's and focus's cast bars become slim lines under their cards, and heal prediction is flattened to match the bars.

### How it runs

`Init` returns early unless `units` is on, which is why switching it needs a reload. Otherwise it calls `DressAll`, which runs `Dress(frame, name)` for each frame that exists and keeps the result in `dressed[frame]`. That record, called `d` throughout the file, holds everything Serene knows about one card: the game's parts it found, the textures it added, and flags such as `d.reversed` (bars fill right to left), `d.dirty` (needs a relayout) and `d.later` (a move that has to wait for the end of combat).

From then on three things drive it. Events (target, focus and pet changes, faction and classification changes, vehicles, portraits, entering the world) re-dress or recolour. `Watch` hooks `SetPoint` and `SetSize` on the parts, so when the game moves something, `d.dirty` is set and a single `C_Timer.After(0)` relayouts after the game has finished. And a 0.25 s `OnUpdate` calls `ColourAll`, because a target being tapped, dying or the target of target changing doesn't always fire an event.

### Finding the parts

The frame tree differs between client versions and isn't documented, so nothing is addressed by a fixed path. `Each(frame, keys)` does `rawget` lookups and recurses into the holder keys in `HOLDERS` (`PlayerFrameContent`, `HealthBarsContainer` and so on). `HealthBar` and `PowerBar` try the modern keys first and the old `_G[name .. "HealthBar"]` globals after; portraits, name and level text work the same way.

### Putting art away

`PutAway(region)` sets a region's alpha to 0 and hooks `SetAlpha`, `Show` and `SetShown` to put it back to 0 whenever the game changes it. It's applied to the keys in `ART`, the old globals in `OLD_ART` (only those starting with the frame's own name), any texture keyed Reputation or NameBackground, and any texture whose atlas ends in `-type`, the reaction-colour strip. The game re-shows the reputation band in ways the hooks don't catch, so `KeepAway` runs on the 0.25 s tick and zeroes anything that got through.

The level badge has no reliable key on this client, so `FindBadges` finds it by shape once, at the first layout: anything with "level" in its atlas, or a small, nearly square texture under the level text or on the portrait. `KEEP` lists the icons it must not touch (PvP, leader, rest, role and similar). If it takes the wrong thing, `/serene debug units <frame>` shows what each region is.

### Bars

`Paint` gives a bar a flat white fill in Serene's colour, and `Unmask` takes off the slanted mask the game's art puts on it. `HookBar` hooks `SetStatusBarTexture` and `SetStatusBarColor` on the bar so the game can't put its own look back, and `HookFill` hooks `SetAtlas`, `SetTexture` and `SetVertexColor` on the fill texture as well, because the target frame's classification update sets the atlas on the fill directly, without going through the bar (see [forever-client.md](forever-client.md)).

### Layout

`Layout(d)` anchors everything to the game's health bar. The power bar is re-anchored to the same edges, because the game's mana bar is wider than its health bar and would otherwise stick out.

With `unitBorder = "line"`, the card is a piece of glass in a 1px hairline with the round portrait sitting on its end and a gold disc one pixel larger behind the portrait as its ring. Bar-coloured stubs (`Stubs`) extend each bar to the portrait's centre, so the bars seem to come out of the portrait instead of ending in a square edge. Target and focus fill in reverse, mirroring the player's card. With `unitBorder = "none"` there's no box: the glass is a capsule made of a slab and half of `Media\Disc` meeting at the portrait's centre. Those two must not overlap, or the seam shows darker.

Fade fades a card through its frame's alpha, but the game applies that alpha to each texture separately; there's no group compositing. Halfway through a fade, everything behind the portrait (the box and its hairline, the stubs, the gold disc) would show through the face. `Carve` prevents that by putting a `Media\HoleMask` mask, centred on the portrait with a radius one pixel under half its size, on each of those parts. Only areas the face covers completely are cut, so at full opacity nothing changes. Anything new you draw behind the portrait needs the same hole in `Dress`. When portraits are off the masks are removed.

`Round(d)` swaps the portrait's masks for Serene's `Media\BadgeDisc`. It runs on every tick because the game occasionally puts its own mask back.

### Anchoring traps

The pet's health bar is anchored to the pet's portrait, so anchoring the portrait to the bar would make a loop that makes the frame disappear (see [forever-client.md](forever-client.md)). Before the portrait is moved, the health bar is therefore re-hung from the frame at the offset it had (`d.healthAt`). Look for this kind of loop whenever you anchor one of the game's regions to another.

The target of target is a secure unit frame, so it can only be moved out of combat. `MoveCompact` returns early in combat and sets `d.later`; `PLAYER_REGEN_ENABLED` marks those cards dirty and they're placed then. It's anchored to TargetFrame itself rather than to anything Serene moves, since a protected frame must never hang from something that moves in a fight.

### Elite dragon, PvP crest, heal prediction

`Dragon` and `FitDragon` keep the game's elite or rare dragon (`BossPortraitFrameTexture`) on target and focus (`CLASSIFIED`). They measure the game's portrait before anything moves, then re-centre the dragon on Serene's smaller portrait at the same relative offset and scale it by the size ratio. It's only shown on the right-hand side, and `unitElite` turns it off.

`FindEmblems` finds the PvP crest by texture name (pvp, alliance, horde, prestige, honorsystem) and runs twice after a unit change, because the game sets the crest a moment later. `PlaceEmblems` pins it to the portrait's rim at 45 degrees; left alone, it would stay where the game's larger portrait used to be.

`Segments` flattens the heal prediction parts (MyHealPrediction, OtherHealPrediction, HealAbsorb, TotalAbsorb) and strips every mask except each segment's own `FillMask`. On reversed bars the game's segments would grow the wrong way, outside the bar, so `Hang` re-anchors them to grow left and `Mirror` flips their glows and shadows.

The overheal mark is a bright line with a fade at the full end of the bar, shown while one of your heals would overflow it. `Overheal` gets that from `CreateUnitHealPredictionCalculator` and `UnitGetDetailedHealPrediction`. The answer can be secret, and a secret can't even be compared with `~= nil`, so it goes straight into `SetAlphaFromBoolean` on the mark's holder frame. The mark is shown and hidden through that frame's alpha rather than the texture's, because the game re-sets the texture's gradient on relayout, which would bring it back. A hook on `UnitFrameHealPredictionBars_Update` re-checks the mark whenever the game updates its prediction.

### The target's cast bar

`DressCast` turns the target's and focus's cast bars into a slim line under the bars, beside the target of target when that's shown. Its colour comes from `CastColor`: newer cast bars say what they show in `barType`, older ones only colour the bar, so the raw colour is classified (red for a failed cast, grey for one that can't be interrupted, green for a channel). `CastColor` is exported as `ns.CastColor` so your own cast bar matches.

### Settings and exports

| Setting | Effect |
|---|---|
| `units` | the whole file (reload) |
| `unitPortraits` | portraits on or off |
| `unitElite` | the elite and rare dragon |
| `unitBorder` | `"line"` or `"none"`; CastBar reads it too |

`ns.PlayerPowerBar()` and `ns.PlayerPortrait()` give Regen the player's power bar (even with `units` off) and portrait (nil unless dressed with portraits on). `ns.UnitsDump(frame)` backs `/serene debug units <frame>`: it writes every region and child of a frame, with size, position, alpha, art and anchor, into `SereneDB.unitsDump`, which you read from the SavedVariables file after a `/reload`. The badge, crest and cast-colour detection are all heuristics, and `d.measured` and `d.healthAt` are taken once, so a client update that renames atlases or moves parts can break them without an error.

## CastBar.lua

CastBar restyles your own cast bar (`PlayerCastingBarFrame`), the pet and vehicle bars, and any frame Edit Mode registers as a cast bar system. Each becomes a slim flat bar on glass with the spell's icon at the start, the name inside, the time on the right and a soft spark at the moving end.

All of the bar's art is reparented to `hidden`, a frame that's never shown. Reparenting matters here: the cast bar's flash and glow animations keep setting their textures' alpha, but nothing under a hidden parent is drawn whatever its alpha. Child frames go to alpha 0, except Edit Mode's `Selection`, which you need to drag the bar. The game paints the bar and its fill for each cast, so the colour is re-applied from hooks on both, using `ns.CastColor` from Units. Layout re-runs from `SetSize`, `SetHeight` and `SetLook` hooks, the last because Edit Mode's "lock to player frame" switches the bar to another look. Position and scale stay Edit Mode's; `c.gameWidth` remembers Edit Mode's width for when `castWidth` is 0. Nothing protected is touched, so it all works in combat.

Settings: `castBar` (reload), `castHeight`, `castWidth` (0 for Edit Mode's width; `ns.CAST_WIDTH_GAME` is where the panel's slider shows "Edit Mode's"), `castIcon`, `castText` (`"in"`, `"under"` or `"none"`) and `castFont` (0 for automatic, shown in the panel as `ns.CAST_FONT_AUTO`).

## Swing.lua

This client has a swing timer of its own, an Edit Mode system with a frame for each hand, driven by the `PLAYER_SWING` event (see [forever-client.md](forever-client.md)). Swing.lua restyles it rather than running a timer of its own.

The frames' names aren't documented, so `FromEditMode` looks them up in `EditModeManagerFrame.registeredSystemFrames` by `system == Enum.EditModeSystem.SwingTimer`, and if that finds nothing, `FromNames` searches `_G` for names containing "SwingTimer", at most every 5 seconds until both are found.

`HideIn` sets the game's art to alpha 0: the frames' top-level regions and children, and deeper down only regions that ignore their parent's alpha. The old alphas go into `hiddenArt` so `ShowArt` can restore them, which is why `swing` switches off without a reload. Serene's own drawing, `lines`, is a child of UIParent placed on the main-hand frame's centre, copying that frame's scale and alpha every frame. It has a row for the main hand (warm white), the off hand (fainter) and Auto Shot or a wand (gold, with the last half second tinted, where a hunter has to stand still), each with the weapon's icon at its start.

`PLAYER_SWING` starts each row's timer. `UNIT_ATTACK_SPEED` and `UNIT_RANGEDDAMAGE` rescale a swing in progress while keeping the part already done. Whether you're attacking comes from `PLAYER_ENTER_COMBAT` and `PLAYER_LEAVE_COMBAT` (melee) and `START_AUTOREPEAT_SPELL` and `STOP_AUTOREPEAT_SPELL` (Auto Shot and wands); after a `/reload` it is seeded from `IsCurrentSpell(6603)` (Attack) and `IsAutoRepeatSpell(75)` (Auto Shot).

`Paint` runs every frame. The lines are only drawn while one of the game's swing frames is visible, which is the game's `showSwingTimer` option at work, and they take on that frame's alpha. They fade in while you're attacking or a swing is running and fade out `LINGER` (1.5 s) after the last swing. While Edit Mode is open, each row shows a fixed demo position so the frames can be placed.

Settings: `swing`, `swingRanged` (the Auto Shot row) and `swingSize` (50 to 300 percent; it changes thickness, the width is Edit Mode's).

## Regen.lua

Regen draws the five-second rule: after you spend mana, a thin gold line under your mana bar grows over five seconds, with a notch at each second, until full regeneration starts again. It begins at the round portrait's rim, and `Reach` works out where the line meets the circle. The line is a child of the power bar from `ns.PlayerPowerBar()`, so it follows Units' layout and the fade.

Mana counts as spent when a `UNIT_SPELLCAST_SUCCEEDED` of yours and a drop in mana arrive within `PAIR` (0.5 s) of each other, in either order. A mana drain from someone else, or a cast made free by Clearcasting, doesn't start the line. When the mana value is secret, the spell's cost from `C_Spell.GetSpellPowerCost` decides instead. If the power type itself is secret, the bar is assumed to show mana; only a known non-mana form such as bear or cat hides the line.

The setting is `manaRegen`, and it switches live.

## Experience.lua

When you gain experience, Fade brings the experience bar back for five seconds (it asks `ns.XPGained()`), and Experience.lua animates the gain on it: a gold fill runs from the old value to the new one with a glowing tip, then the bar's own colour sweeps in over the gold.

Serene never writes to the game's bar, since setting its value from outside leaves it empty (see [forever-client.md](forever-client.md)). Everything is drawn on an overlay instead. On the first `OnUpdate` after the event, once the game has handled the same gain, it picks one of two modes. In "cover" mode the game has jumped straight to the new value, so Serene copies the fill's atlas, colour and blend mode, hides the game's fill, animates its copy and then hands the game's fill back; they're the same pixels, so nothing pops. In "follow" mode the game is animating its own bar, and the gold runs just ahead of it. The glow has a frame of its own and fades through that frame's alpha, which looks smoother than fading the texture.

The bar is found by searching the status-tracking containers (`CONTAINERS`) for a visible status bar whose maximum equals `UnitXPMax("player")`. A level-up is handled 0.2 s late, because the new level's numbers arrive after the event.

The setting is `xpGain`. `/serene debug` (`ns.XPDebug`) prints whether the bar was found, the last mode used and timing for the last fade.
