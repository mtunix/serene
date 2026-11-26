# Tooltips and toasts

## Tooltip.lua

Tooltip.lua restyles the game's own tooltips and changes nothing about how the game fills them: only opacities, colours, sizes and words. Every hook checks `ns.On("tooltip")` (or its own setting) when it runs, so the tooltip settings switch live.

| Setting | Effect |
|---|---|
| `tooltip` | Glass instead of the game's frame, a soft fade-in, quiet colours, how-to lines only with Shift, item comparison only with Shift |
| `tipcalm` | In a fight, tooltips of the world and of the action bars wait for Shift (or the Peek key); enemies still show |
| `tipmore` | Lines that addons add under an item wait for Shift |
| `tipvendor` | What a merchant pays for the item, for the whole stack |
| `tipcard` | A player's tooltip as a card: race and class icons, name and level, guild |

The file keeps three tables of tooltips: `styled` (the ones in `STYLED`: GameTooltip, ItemRefTooltip and the shopping tooltips), `cuttable` (the ones in `CUT`, whose addon lines can wait for Shift) and `cuts`, the cut's state per tooltip while one is applied. Everything about the fade lives in one table, `state`: the owner, the alpha, whether it's fading, how long to wait, and when the last tooltip went.

### One item tooltip, start to finish

It helps to follow GameTooltip through one hover over an item in the bags.

The game calls `SetOwner`. Serene's hook clears any old cut (`Uncut`) and, when the owner is new, calls `Fresh`, which decides how this tooltip comes in. If a tooltip was showing a moment ago (within `GRACE`, 0.3 s) the new one appears at once, so moving the mouse along a list, or a window that refreshes its tooltip constantly like the auction house, doesn't flicker. Any other tooltip starts at alpha 0. Over action, menu and bag buttons (`ACTION_NAMES`, `MENU_NAMES`) it also waits `BUTTON_WAIT` first, so running the mouse along a row of buttons doesn't flash a tooltip for each one.

The game then fills the tooltip line by line. When it reaches the "Sell Price" line, the line pre- and post-calls registered by `HookSellRow` run (`BeforeSellRow`, `AfterSellRow`); they're described below. Once all the game's lines are written, the `TooltipDataProcessor.AddTooltipPostCall` that Init registered for every data type calls `OnData`, which does the rest of the rewriting in order: `VendorPrice` settles the price line, then either `Card` turns a player's tooltip into a card or `Hushed` quietens the colours, and for an item in a cuttable tooltip with `tipmore` on, `CutItem` works out where the game's lines end and the addons' begin. On clients without the data processor the same `OnData` runs from the `OnTooltipSetItem`, `OnTooltipSetSpell` and `OnTooltipSetUnit` scripts.

Finally the game calls `Show`. The hook writes the current alpha, runs `Pass` to apply the cut, and starts `driver`, an OnUpdate frame that runs while the tooltip is visible. The driver steps the alpha toward 1 with `ns.Approach` over `FADE_IN` once the wait is over, re-applies cuts when Shift is pressed or released or a line arrives late, and after `HINT_AFTER` (1.2 s) rebuilds the tooltip with its how-to lines (`Redo`). When the tooltip hides, `OnHide` notes when it went, which is what `GRACE` measures from.

Two other things are hooked at Init. Each styled tooltip's `OnShow` calls `Dress`, which hides the NineSlice border and adds a dark pane and a faint hairline on top; old backdrop-style tooltips get their backdrop colours cleared on every show, because the game sets them again on hide. A tooltip about something shown as an icon (an item, a spell, an aura, a macro, a pet action or a totem: `ICON_KINDS`) gets a 1px hairline of `ns.LINE` all round in place of the faint line. `OnData` turns it on from the data's type (`Rim`), and it goes again when the tooltip is cleared, hidden or given a new owner, so tooltips of plain words, units and objects never keep it. And an events frame tracks the fight (`PLAYER_REGEN_DISABLED`/`ENABLED`) and the Shift key (`MODIFIER_STATE_CHANGED`), which brings back hint lines through `Redo`. `Refresh`, which Init also calls, applies the settings: it re-dresses the styled tooltips, thins the health bar under unit tooltips (`Bar`) and sets the comparison setting (`Compare`).

### Calm in a fight

With `tipcalm` on, `Held` decides in the driver whether a tooltip waits: it does in a fight when its owner is the world or an action button, unless the unit under the mouse is an enemy (`Enemy`) or Shift or Peek is held (`Peeking`). A held tooltip is still shown, at alpha 0, so the game's own tooltip logic carries on normally.

### Quiet colours

`Hush` recolours an item or spell tooltip's lines: the first line keeps its colour (quality, class, friend or foe), other white lines become warm white and the game's yellow becomes a muted gold. `HushUnit` does the same for units and also greys the faction and PvP lines and drops "(Player)". Lines are only recoloured, never removed. Addons such as Questie add their own lines afterwards at fixed positions, and removing a game line would leave gaps among them.

### The cut

With `tipmore` on, everything addons add under an item waits for Shift, and a small "Shift" cue sits in the tooltip's corner. `GameLines` works out how many lines are the game's own by matching the tooltip's font strings against `data.lines`. `Pass` then sets every line after that point to alpha 0, and `Fit` shrinks the tooltip so it ends at the last line kept. Lines are never removed here either: pressing Shift makes the driver call `Show()`, the game lays the whole tooltip out again, and `Pass` keeps everything.

Addons sometimes add a line after the tooltip is already shown. `AddLine`, `AddDoubleLine` and the global `SetTooltipMoney` are hooked (`Late`, `LateMoney`) so such a line is hidden straight away rather than one frame later. `Uncut` clears the cut when the tooltip is cleared or hidden. `Fit` keeps the old width when words would overflow or when coins or an icon sit beside them.

`Fit` can only measure an anchored tooltip. The comparison tooltips are filled and shown while unanchored and only placed afterwards, so Init also hooks their own `SetPoint` to lay them out again at that point; when `Fit` still can't measure, `Pass` keeps no height and the cut is retried on the next frame. A quest reward's comparison is rebuilt every 0.2 s, twice each time, the second time through the game's C comparison call. Hooks on `TooltipComparisonManager` don't see that second call, but hooks on the tooltip frames' own methods do, which is why everything is hooked on the frames.

### The vendor price

On this client the sell price is a typed data line drawn as a plain text row, and an item merchants won't buy has no such line at all (see [forever-client.md](forever-client.md)). With `tipvendor` on, Serene writes "Vendor" and the stack's price into that row.

Finding the row is the job of the two line calls. `BeforeSellRow` notes, in `sereneSellAt` on the tooltip, the index the row is about to get; `AfterSellRow` then rewrites that row with `PriceWords` and the coins, taking the stack's total from the line's `price` or working it out from `EachPrice` and `StackOf`, and records the index in `sereneVendorRow`. When the pre-call didn't run, `SellRowNear` looks for the row among the last two lines by its words, or as a blank line, because VendorPricePlus blanks the game's row when Auctionator is loaded. A row the game drew with real coins is left alone.

The row is rewritten in place rather than a line being added because the game's row sits among the game's own lines, above the Shift cut. A line Serene appended would land below the lines of addons that wrote earlier (AuctionDB, Auctionator) and so behind the cut.

`VendorPrice`, called from `OnData`, only adds a line of Serene's own when no row was rewritten, the game drew no coins (`shownMoneyFrames`), and the data doesn't say the item is unsellable (`Sellable`). That covers clients without typed line calls and tooltips built without data lines. It only does this for GameTooltip and ItemRefTooltip.

### Hints and comparison

`ns.TipHint(tip, text)` adds one of Serene's how-to lines ("Click: ..."). They show when Shift is held, or on their own after `HINT_AFTER`. A tooltip built with `ns.ShowTip` remembers how it was built, so it can be rebuilt with its hints when that moment comes; `ns.TipLater(redo)` does the same for tooltips the game builds itself, such as `SetMerchantItem`.

`Compare` turns the game's `alwaysCompareItems` setting off while `tooltip` is on, remembering the old value in `tipCompare` (and that it did so in `tipCompareDone`), and gives it back when `tooltip` is switched off. Comparison then only appears with Shift. The comparison tooltips (`COMPARE`) are placed by the game edge to edge beside the tooltip they compare against; a hook on their `SetPoint` (`Apart`) sets those side anchors again `COMPARE_GAP` apart, under the `holding` flag. Their "Equipped" tab (`CompareHeader`) is dressed by `Header`, called from `Dress`, into a band of the tooltip's glass along its top: its art away, anchored to both of the tooltip's top corners (so the width the game sets to fit the words gives way), and sitting on the edge rather than reaching into the tooltip, so the two panes meet without a darker seam. On it are the worn item's icon, round in a gold ring (masked by `Media/WornDisc`, a soft disc baked for its 14px, with the same disc in gold a pixel wider behind it), and the words, small and in a soft gold, in line with the tooltip's own, with a faint line under them from that margin to the end of the words. `Worn` takes the icon from the comparison's data in `OnData` and `Lay` places icon, words and line. Band and tooltip read as one frame: `Join` moves the tooltip's gold hairline up to the band's top. The tab stays the game's own frame; its words alone, without glass, were lost on bright ground. Switched off, the tab is given back as the game made it.

### The player card

With `tipcard` on, `Card` turns a player's tooltip into a card. It rewrites lines 1 to 3 into the card's layout, empties the game's other lines, moves late addon lines up under the card (`Move`), and draws a round race icon ringed in faction colour with a small class badge on it (atlases, falling back to the character creation sheets). If anything it needs is secret, which is common in fights, `Card` returns false and the tooltip stays a normal quiet one.

### Exports

| Function | Use |
|---|---|
| `ns.ShowTip(owner, build, anchor)` | Show a tooltip whose lines come from `build(tooltip)`; it can be rebuilt with hints |
| `ns.HideTip()` | Fade it out |
| `ns.TipHint(tip, text)` | Add a how-to line |
| `ns.TipHints()` | Whether hints show right now |
| `ns.TipLater(redo)` | Rebuild a tooltip the game built (e.g. `SetMerchantItem`) when hints come |

### What it depends on

Tooltip.lua relies on the `<Tooltip>TextLeftN`/`TextRightN` globals and on the game's private `shownMoneyFrames` and `numMoneyFrames` fields. It keeps its own parts on the tooltips under `serene*` keys (`sereneGlass`, `sereneHair`, `sereneRim`, `sereneCue`, `sereneTab` and `sereneWorn` on the comparisons' band, `sereneCard`, and the two price-row fields above). `Move` puts addon lines' text on other line indices for the card, which would confuse an addon that later edits "its" line by index. `ACTION_NAMES` lists the button names of the game, Bartender, Dominos and ElvUI.

## Toasts.lua

Toasts.lua restyles the game's toasts for a new recipe, an achievement (on this client "Legacy Challenge Earned") and a criteria. Each becomes a slim glass card, 270 by 40, with a gold hairline, a round icon with its own ring at the left, the title muted, the name in gold and the points quiet. The game's toast frames stay, so their clicks and fades keep working.

### Dressing

`Init` hooks `AlertFrame:AddAlertFrame` and every alert system's `AddAlert` and `ShowAlert`. Those hooks call `Dress` (directly, or through `Sweep` over a system's pool) on each frame the game serves. Toast frames come from pools and are reused, so `Layout` runs again on every `OnShow`. `PutAway` moves every texture except the icon to a hidden `attic` frame; it skips children that take the mouse, so the toast's click areas stay. `dressed` holds Serene's parts per frame.

The recipe toast's icon is a baked, pre-masked copy with a light bevel (see [forever-client.md](forever-client.md)), which would show as a pale ring inside Serene's rim. The hook on the recipe system's `AddAlert` therefore calls `Unbake`, which puts the plain profession icon back (`RecipeIcon`) and crops and masks it.

### Drawing round things

The glass under the round icon is cut round by `Media/ToastNotch`, and the ring is a separate hollow texture (`Media/Ring`), so no layer shows through another while the toast fades. The ring and icon stay inside the toast's height because the game clips anything that reaches outside it. Masks come from `CreateMaskTexture` on the icon's own parent, the way the game masks portraits, rather than `SetMask`. Circles stay smooth through textures baked near the size they're shown (64px) and pixel snapping turned off (`Smooth`), as described in [workflow.md](workflow.md).

### Placement

The game stacks all toasts upward from one anchor, `AlertFrame`. Serene moves only that anchor (`Place`), to the position saved in `toastAt`, and a hook on the anchor's `SetPoint` puts it back whenever the game moves it. The toasts then stack from there as usual.

`/serene toasts move` shows a sample toast you can drag (`ns.ToastMove`) and saves where you leave it. `/serene toasts reset` (`ns.ToastReset`) forgets `toastAt` and gives the game its place back. `/serene toasts test` (`ns.ToastTest`) fires a real recipe toast and a real achievement toast. It loads the achievement UI first, because the toast borrows its code, and finds an earned achievement by scanning the categories (`EarnedAchievement`), since the client's list of recent achievements is empty.

The setting is `toast`; switching it off needs a reload to undo toasts already dressed. `ns.ToastsDebug` reports each toast's parts and any of the game's art still showing. Toasts vanish before you can type a command, so it keeps a snapshot taken 0.5 s after each one appeared.
