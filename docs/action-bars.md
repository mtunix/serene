# Action bars

Serene never builds action buttons of its own. The game's buttons keep doing placement, paging and clicks; these files change how they look and add a behaviour each on top. At the centre is Actions.lua, which every other file here asks about buttons and slots instead of reading the game itself.

| File | What it adds | Settings | Needs `actionBars` | Saved per character |
|---|---|---|---|---|
| Actions.lua | the model: buttons, slots, what's on them, cooldowns, procs | — | no | — |
| ActionBars.lua | the restyle: three looks, quiet keys, range tint, glows | `actionBars` (reload), `barKeys`, `barNames`, `barEmpty`, `barStyle`, `barStyleSame`, `barStyles` | is it | — |
| Hints.lua | a gold glow on buttons worth pressing now | `hints`, `hintFood`, `hintBuffs`, `hintBuffSoon`, `hintBuffSoonAt`, `hintReveal` | no | `hintLast` |
| Ready.lua | buttons that aren't ready fade back | `barReady`, `barReadyWhen`, `barReadyDim`, `barReadyCooldown`, `barReadyPower`, `barReadyUnusable`, `barReadyTarget`, `barReadyRange`, `barReadyHover` | no | — |
| BarCooldowns.lua | cooldowns drawn to fit the look; one global cooldown line | `barCooldown`, `barCooldownText`, `barGcd` | yes | — |
| BarKeys.lua | key labels fade once you've learned them | `barKeysLearn` (with `barKeys`) | yes | `keyLearn` |
| BarPages.lua | Action Bar 1's icons fade in on a page change; the page number | `barPages` | no | — |
| Ranks.lua | a spell's new rank put onto the bars | `barRanks`, `barRanksAuto` | no | `ranks` |
| Reagents.lua | reagent counts amber when low | `barReagents`, `barReagentLow` | no | — |
| BarPing.lua | a ring of gold when a long cooldown ends | `barPing`, `barPingMin` | yes | — |
| BarSets.lua | lost actions put back; named sets | `barSets` | no | `barSetsBy` |
| BarSupplies.lua | macros holding your best food, water, potions, bandage | `barSupplies` | no | `supplies` |
| BarUse.lua | unused buttons pointed out; easier keys suggested | `barUse`, `barUseHours` | yes | `barUseBy` |

The per-character tables all live in `SereneDB` under a `"Realm-Name"` key. "Needs `actionBars`" means the file's `init` returns early, or it only works on buttons ActionBars has dressed, when Serene's action bars are off. BarUse is the one to watch: it learns about presses only from BarKeys, so with Serene's bars off it counts nothing and `/serene review` has nothing to show.

## Actions.lua

`ns.Actions` only reads. The buttons come from `FAMILIES`, one entry per family with its name prefix, count, bar key (`main`, `bar2` to `bar8`, `pet`, `stance`), binding name and label; the first eight families hold action slots. `Buttons(all)` and `Each(fn, all)` list them whether or not ActionBars is on, and with `all` they include the pet, stance and possess buttons. The list is kept only once `IsLoggedIn()` is true, since the game may not have built every bar before then. `BarOf(button)` and `BarButtons(button)` give a button's bar key and its neighbours. That's different from `ns.BarsEach` in ActionBars, which walks only the buttons ActionBars has dressed and is what the look-dependent files use.

`Slot(button)` reads `button.action`, and for the eight slot families only falls back to the button's `GetPagedID`, `CalculateAction`, its `"action"` attribute or `ActionButton_GetPagedID`. Pet and stance buttons never get a guessed slot.

`What(slot)` describes what's on a slot as a short string, `"spell:133"` or `"macro:<name>"`. BarUse saves these strings, so their form must never change. `Cast(slot)` says what a slot casts, including through a macro, and `SpellOn(slot)` gives the spell placed there directly. `Usable(slot)` returns usable and not-enough-mana, `InRange(slot)` returns false only when the game says out of range (nil when there's no range or no target), and `Current(slot)` is true for an action in use: auto attack, a channel, a spell waiting for its target.

`OnCooldown(slot)` answers true, false or nil, together with how it found out (which `/serene debug` prints). It tries, in order:

1. the cooldown's duration object without the global cooldown (`Cooldown(slot)`), when it has no secret values: on cooldown unless it's zero;
2. the `isActive` and `isOnGCD` fields of `C_ActionBar.GetActionCooldown`, which are never secret: not active means false, on the global cooldown means false;
3. for an active cooldown with no word on the global cooldown, its `duration` field when readable: on cooldown if longer than `GCD_HOLD` (1.6 s);
4. when that field is secret, a hold: the slot counts as on cooldown once it has been active for more than `GCD_HOLD`, timed per slot;
5. the old `GetActionCooldown` call.

Nil means unknown, and no caller dims, pings or counts on it. `Cooldown(slot)` itself returns the duration object for handing to the game's widgets.

`Glows(button, fn)` calls `fn` for each square glow the button can wear, looked up by the keys in `GLOW_KEYS`: the game's proc glow, its spell highlight, and the LibButtonGlow and LibCustomGlow overlays. `Proc(button)` is true when the alert manager's `HasAlert` says so or any of those glows is shown. ActionBars takes those glows out of sight on its Glass and Round looks by alpha only, so `Proc` still sees them.

## ActionBars.lua

ActionBars dresses each button once, from post-hooks on the secure buttons (`UpdateButtonArt`, `UpdateHotkeys`, `Update`, `ActionButton_UpdateRangeIndicator`). What it changes:

- the bars' art is stripped (`StripBar` hides textures only, never a frame holding buttons, and leaves Edit Mode's `Selection`, the page number and anything mouse-enabled alone);
- key labels are shortened ("s-1" becomes "S1", "Mouse Button 4" becomes "M4") and set small and muted in a corner;
- macro names are optional (`barNames`);
- the highlight and pushed textures become soft washes and the checked one gold;
- out of range, the icon turns red and the key soft red, and the tint goes back to whatever colour the game had set (grey for unusable, blue for out of mana); without the game's range function, range is read from the hotkey turning red;
- empty slots are see-through, shown at half opacity while you drag something.

Nothing is dressed in a fight. `DressAll` waits for combat to end, and runs again when Edit Mode closes. Serene's own parts for each button live in `parts[button]`.

### Looks

There are three looks: `classic` (the game's own frame, with the changes above), `glass` and `round`. `barStyle` sets one look for every bar; with `barStyleSame` off each bar takes its look from `barStyles[key]`, using the same bar keys as Actions (`ns.BAR_KEYS` maps them to Edit Mode's names). Turning `barStyleSame` off copies the current look into every bar.

Glass hides the game's frame textures, crops the icon square (`CROP`) and drops the game's `IconMask`. The icon sits on a dark mat (`GLASS`, `GLASS_MAT` pixels wide) framed by a 1px gold line (`GLASS_LINE`) with a dark outline outside it; the line has to stay one pixel, so it's the mat and the contrast that make it read as a frame. Round swaps the game's mask for an `AuraDisc` mask on the icon and the washes, with a gold `AuraDisc` rim `ns.BAR_RIM` pixels wider behind it and a dark disc one pixel wider still. Those discs are drawn without a texture filter; their edges are soft in the texture itself.

The game's frame covers 3/45 of the icon's edge, so Glass and Round move the icon in by `INSET` (3/45 of the button) on each side, which keeps their icons the same size as Classic's. Classic gets the game's points back.

`Look` applies a look's masks, texture coordinates and points only out of combat; in combat it sets `waiting` and `DressAll` applies it afterwards.

### Glows

On Classic, the game's proc glow and Hints' glow stay as they are. On Glass and Round, Serene draws its own glow and keeps the square ones at alpha 0. The proc glow is caught by post-hooks on `ActionButtonSpellAlertManager:ShowAlert` and `HideAlert`. Everything else goes through a watcher, `WatchGlows`, which runs every 0.2 seconds over the dressed Glass and Round buttons and asks `HasProc`: true for a proc (`Actions.Proc`) or a Hints glow, `"faint"` for a buff running out (`ns.HintSoon`, see Hints below), false otherwise. Only a change of state calls `Proc`, which shows or hides Serene's glow; in between, `PutAwayGlows` just hides a square glow that came back. Hints' own glow breathes through its frame's alpha, so on these looks it's the glow's texture that is put away.

Glass's glow is `Glow.tga` over the button. Round's is `GlowRound.tga`, a round version of the same profile made by `tools/media/roundglow.py` and sized so its bright line sits on the rim. A texture added to `Media/` only exists after a full game restart, and until then `SetTexture` returns false, so Round falls back to a gold halo of `DiscSoft.tga` under the dark disc.

All of Serene's glows breathe on one shared sine wave (`Breathe`: from full to 0.7 and back over 2.4 seconds), driven by the watcher's OnUpdate and never restarted. An AnimationGroup would start again from full brightness each time a glow is shown, and with the watcher re-applying every 0.2 seconds that would look like flashing. A faint glow is drawn at `FAINT` (0.4) and kept still (the `still` set rather than `breathing`). Out of range, Glass's line and Round's rim turn soft red too (`Edge`).

The game's cast animations (`SpellCastAnimFrame`, `InterruptDisplay`, `TargetReticleAnimFrame`) are left to the game. On Glass and Round, `CastShape` gives the cast fill, the interrupt sweep and the reticle's light a mask in Serene's shape and hides the square frames the game draws around the button. Classic gets the game's masks back.

Exports: `ns.BarStyleOf(button)`; `ns.BarsEach(fn)`, called with each dressed button and its bar key; `ns.BarsKey(button)`, which BarKeys uses to re-apply a key label's colour and visibility; `ns.BarsOwnGlow(button)`. Slash: `/serene barstyle classic|glass|round`.

## Hints.lua

Hints puts a soft gold glow on action buttons worth pressing now, out of combat only. It re-evaluates every half second when something has changed (an event marks it dirty) and every 5 seconds regardless.

The glows come from `RULES`. Each rule is a function that takes the player's buffs (a table of lower-cased buff names) and returns either nil, meaning nothing to light, or a test `function(kind, id, slot)`. `Look()` collects the tests from every rule and runs them over each button from `Actions.Buttons()`, with the kind and id of what the slot casts; any test returning true lights the button. Items you don't carry are skipped before the tests run. To add a rule, add a function of that shape to `RULES`.

There are two rules. The food rule lights food that makes you Well Fed when you're neither Well Fed nor eating. Whether a food gives Well Fed is read from its tooltip (`MakesWellFed`, through `C_TooltipInfo` or a scanning tooltip) and only cached once the tooltip has really loaded; BarSupplies uses the same answer through `ns.MakesWellFed`.

The buffs rule lights whatever gives a class buff that's missing. `CLASS_BUFFS` lists them per class, as groups of spells or items; a priest's group for Power Word: Fortitude, for example, also accepts Prayer of Fortitude as already having it. Buffs are matched by localised name so any rank counts, and a spell only lights when `IsUsableAction` agrees, which keeps unlearned talents dark. Where a group offers several choices (an armor, a blessing, an aspect), only the one you cast last or are wearing now glows; `hintLast` remembers it per character.

Hints stays quiet in a fight, mounted, dead, on a taxi and in rest mode. In a fight this client returns nothing for the player's buffs anyway, and Hints reads that as "can't tell" rather than "no buffs".

A class buff or weapon enchant that's still up but has less than `hintBuffSoonAt` seconds left (with `hintBuffSoon` on) gets a fainter, still glow at `FAINT` (0.4) on whatever renews it. Only buffs whose full duration is longer than that threshold count, so a five-minute blessing isn't "running out" at a ten-minute threshold. A button that is both missing and running out gets the full glow. `ns.HintSoon(button)` reports the faint state, which ActionBars reproduces on its own looks.

The glow itself is `Media/Glow` in its own frame on the button, pulsing through an AnimationGroup (bouncing between full and 0.45 over 1.1 seconds). `hintReveal` decides what a glow brings back through Fade: nothing, the button alone (it ignores its parent's alpha), its whole bar, or every bar (`ns.HintRevealBars`). Faint glows reveal nothing.

`ns.MissingClassBuffs()` gives AuraFrame its ghost buffs; it returns nil when it can't tell, and AuraFrame keeps its previous list.

## Ready.lua

Ready makes each button as present as it is ready. A button that is on cooldown, short of power, unusable, an attack with no enemy targeted, or out of range fades to `barReadyDim` percent (30 by default) and comes back the moment it's usable. The global cooldown never counts, or every button would blink with each cast. Each reason has its own setting, and `barReadyWhen` can limit the whole thing to fights.

Some buttons always stay at full: a proc, a button Hints is lighting, the action in use (`IsCurrentAction` or `IsAutoRepeatAction`), every button while something is on the cursor, and everything in Edit Mode or while peeking. With `barReadyHover` the whole bar under the mouse comes back too. A button BarUse has faded as unused gets the reason `"unused"` (`ns.BarUseFaded`).

Ready only sets opacity, on the eight slot families, and doesn't depend on ActionBars, so it works with the game's own look as well. Fade's bar opacity and Ready's multiply. The readings come from `ns.Actions`, with cooldowns from `Actions.OnCooldown`.

The target check is its own because `IsUsableAction` says yes to a harmful spell whoever you have targeted, and `IsActionInRange` gives no answer for a friend. If `IsHarmfulAction(slot, false)` is true and the target is missing, dead or not attackable, the button dims. A secret `UnitCanAttack` counts as attackable.

Events are folded into one look on the next frame. A cooldown ending fires no event per button, so a safety look also runs every 0.5 seconds, and the mouse over a bar is checked every 0.1 seconds. Buttons fade in over 0.12 s and out over 0.35 s. Turning Ready off puts every button back to 1.

## BarCooldowns.lua

BarCooldowns draws a button's cooldown to fit its look. `barCooldown` is `style` (Classic gets the sweep, Glass a line, Round a ring) or forces `sweep`, `line` or `none` everywhere.

The ring is the game's own cooldown frame stretched over Round's rim with `Ring.tga` as its swipe texture, so the ring darkens and the gold comes back as the cooldown runs. The line is a StatusBar along the icon's bottom edge, timed with `SetTimerDuration` from `C_ActionBar.GetActionCooldownDuration(slot, true)`. Pet and stance buttons have no slot, so they always get the sweep, and Classic with the sweep is left entirely to the game. The game resets the swipe colour while casting, and its texture, so hooks on those re-apply Serene's a frame later; points only move out of combat.

`barCooldownText` controls the numbers: `game` follows the `countdownForCooldowns` CVar, `always` and `never` set `SetHideCountdownNumbers`, and `soon` shows them for the last 3 seconds only. In combat the time left can't be read, so for `soon` the countdown text's alpha is set every 0.1 seconds to `duration:EvaluateRemainingDuration(curve)`, with a step curve that is 1 below 3 seconds and 0 above. The game evaluates the curve and Serene never sees the number.

With `barGcd` on, a post-hook on `ActionButton_UpdateCooldown` re-sets each button's cooldown from the duration object that leaves the global cooldown out (except while a loss-of-control cooldown shows). The global cooldown is drawn once instead, as `SereneGlobalCooldown`, a 2px line under Action Bar 1. It's parented to the main bar so Fade fades it, and timed from the GCD spell (61304), shown while that spell's cooldown `isActive`.

## BarKeys.lua

BarKeys fades a key label once you've learned the key. It hears key presses through a post-hook on `TryUseActionButton`, which both `ActionButtonDown` and `MultiActionButtonDown` call (only the down press counts), and mouse clicks through each button's `OnClick`, debounced by 0.3 seconds. Key presses don't go through `OnClick`, so nothing is counted twice. Every press is passed on to BarUse through `ns.OnBarPress`.

Each button keeps a score for its current key text. A key press moves it `GAIN` (0.07) of the way toward 1; a click halves it (`LOSS`) and marks the key as clicked. A new key starts at `START` (0.4). At `KNOWN` (0.85) and above, `ns.KeyLook` returns `"hidden"` and the label goes to alpha 0, coming back while the mouse is on the button. A clicked key at `BRIGHT` (0.35) or below is `"bright"`: drawn in warm white instead of muted grey, because you're still clicking that one. Scores are stored as `SereneDB.keyLearn[who][buttonName] = { key, score, clicked }`, and a different key text starts over.

## BarPages.lua

When the main bar's page changes (`GetActionBarPage` or `GetBonusBarOffset`, so stance and form changes count too), ActionButton1 to 12's icons come in from 0.15 to full over 0.22 seconds instead of snapping. A muted page number sits to the left of ActionButton1 whenever the page isn't 1 and no bonus bar is up.

## Ranks.lua

Ranks puts a spell's new rank onto the bars when you learn it. It reads the spellbook through `C_SpellBook` by base spell (`actionID`, so form and talent overrides don't count) and treats a spell as the highest rank when `IsSpellBookItemLowRank` is false. Each character remembers the highest id seen per spell name in `SereneDB.ranks[who].seen`. When that changes, the old id goes into `pending`, and only slots holding a pending id are upgraded, so a lower rank you placed on purpose is never touched. `C_ActionBar.IsHighestSpellRank(slot)` returning true vetoes a change.

The upgrade is `PickupSpellBookItem`, `PutActionInSlot` and `ClearCursor`, done only out of combat with nothing on the cursor, followed by one chat line. With `barRanksAuto` off nothing changes by itself: each button that could be upgraded gets a small gold dot (`Mark`), and `SereneRankButton` above Action Bar 1 ("New ranks for N spells") does it on click; the button hides in combat. The first look happens 3 seconds after entering the world, so a half-read spellbook doesn't look like a set of new ranks.

## Reagents.lua

Reagents colours the count on spells that use up a reagent once you're running low. It goes over every action button with `ns.Actions.Each`, picks the slots whose spell consumes something (`IsConsumableAction` or `C_Spell.IsConsumableSpell`), and reads how many casts are left with `GetActionUseCount`. That value is secret in combat, so the check runs only outside it. At or below `barReagentLow` the game's count turns amber, and soft red at 0; a count it never coloured is left to the game.

The reagent's name is read once per spell from the tooltip line that starts with `SPELL_REAGENTS` (`C_TooltipInfo.GetAction`). At a merchant (`MERCHANT_SHOW`) one chat line lists what the merchant sells that you're low on, and Serene's merchant window marks those rows through `ns.ReagentLow(name)`.

## BarPing.lua

When a button's own cooldown that ran for at least `barPingMin` seconds (30 by default) ends, a single ring of gold goes out from it: `Glow.tga` on Classic and Glass, `GlowRound.tga` on Round, growing from 0.85 to 1.25 and fading over about a second. The ping frame ignores its parent's alpha so it shows on a faded bar, and when the button itself is faint (effective alpha under `FAINT_BELOW`, 0.6) a copy of the icon shows with the ring.

The cooldown's length is measured rather than read, since it can be secret. Every 0.1 seconds each visible slot is asked `ns.Actions.OnCooldown(slot)`, and the time it was first seen running is kept. A slot that changes action, or isn't seen on any button for more than `SEEN_GAP` (0.5 s, as when you page away), is forgotten, so paging never causes a ping. `/serene ping` shows one on ActionButton1.

## BarSets.lua

BarSets keeps a copy of your bars so it can put back what leaves them on its own, and lets you save and load named sets.

The copy covers all 180 slots: what `GetActionInfo` reports, with macros and equipment sets recorded by name. `Snapshot` takes it one second (`SETTLE`) after the last `ACTIONBAR_SLOT_CHANGED`, only out of combat and with nothing on the cursor, and stores it in `SereneDB.barSetsBy[who]`. The first copy waits 3 seconds after login, and a read that comes back completely empty is ignored.

Each new copy is compared with the previous one. If at least `WIPE_AT` (3) slots emptied at once, or a spell disappeared that you no longer know (a talent reset), the missing records go into `store.lost`, and `SereneBarSetsButton`, over ActionButton12, says how many. Clicking it calls `Restore`, which puts each one back with pickup, `PutActionInSlot` and `ClearCursor`, but only into a slot that is still empty; a slot you've used since drops its entry. After that first click (`armed`), spells you haven't relearned yet come back by themselves on `SPELLS_CHANGED` and the `LEARNED_SPELL_*` events. Right-clicking forgets them.

Named sets live in `store.sets`. Loading one saves the current bars as `undo`, then makes every slot match the set, clearing slots that are empty in it and skipping anything that can't be picked up. Serene's own changes mustn't look like losses, so they run inside `Placing`, which mutes `Queue` while placing and then marks the copy `stale`. A stale copy is simply replaced by the bars as they are, without comparing; the same happens when the feature has been switched off for a while. `ns.BarSetsMine(fn)` gives BarUse the same protection for its Clear and Swap. Slash: `/serene sets [save|load|delete <name>]` and `/serene sets back`.

## BarSupplies.lua

BarSupplies makes per-character macros (`Serene Food`, `Serene Water`, `Serene Heal`, `Serene Mana`, `Serene Bandage`) that always hold the best item of their kind in your bags. They're only created when asked for: `/serene supply food|water|health|mana|bandage` calls `ns.SupplyPickup(kind)`, which puts the macro on the cursor so you can drop it on a bar. After that, `EditMacro` rewrites each one out of combat to `#showtooltip` and `/use item:ID`.

An item's kind comes from the name of the spell it casts, localised from known spell ids (Food 433, Drink 430, Healing Potion 441, Restore Mana 2023, First Aid 746); bandages are also recognised by consumable subclass, and healthstones by item id. Only items you can use now, at or under your level, are considered. Among those the best scores highest: food that doesn't give Well Fed before food that does (the Well Fed food is kept for when you want the buff, `ns.MakesWellFed`), healthstones before potions, higher item level, conjured items (sell price 0) before bought ones, and a smaller stack before a bigger one. When you run out, the macro keeps the last item (`store.last` in `SereneDB.supplies[who]`), so the button shows it at a count of 0 rather than going blank.

## BarUse.lua

BarUse watches how you use your bars and points out what you don't. Its data is in `SereneDB.barUseBy[who]` (not under `barUse`, which is the on/off setting): `played`, the seconds logged in and not AFK, counted in 10-second ticks, and for each slot `{ what, since, last, n }`, where `what` is `Actions.What(slot)` and `n` counts presses reported by BarKeys. A different action in a slot starts its record over.

A visible button counts as unused when its last press (or the moment it was placed) is more than `barUseHours` of play ago (10 by default) and it isn't in `keep`. About a minute into a session one chat line says how many there are, but only when that set differs from the one it last mentioned. `/serene review` opens `SereneBarReview`, which lists them with three choices: Keep (never mention it again), Fade (stored in `faded[what]`, after which Ready dims it with the reason `"unused"`, so this needs Ready on) and Clear (empties the slot).

The same window suggests easier keys. `Ease(key)` scores a binding: 1 to 4 score 6; 5, Q, E, R, F and mouse buttons 4 and 5 score 5; T, G, Z, X, C, V and the mouse wheel 4; other keys 3; 7 to 0, minus and equals 2; function keys 1. Shift takes off 1, Ctrl and Alt 2 each, and a bound key never scores below 1, while an unbound button scores 0. An action counts as busy when it has been pressed at least 5 times an hour over at least an hour of play; it's a candidate for a swap when it's busy and on a hard key (ease 2 or less). `Swaps` sorts those by rate, busiest first, and the actions on easy keys (ease 4 or more) quietest first, and pairs them in order, first with first, up to three pairs. A pair is suggested when the busy action's rate is at least three times the quiet one's, plus one press an hour (`busy ≥ 3 × quiet + 1`). Swap trades the two slots, and their counts move with them.
