# Bags, bank and merchant

Eight files work together here. `Items.lua` reads the bags and the bank's containers and decides what an item is; `Inventory.lua` remembers what every character carries; `Bags.lua` draws the bags and bank windows, `BagSlots.lua` the rows of bag slots and bank tabs under their headers, `BagRoom.lua` "make room" above the bags and `BagMenu.lua` the small menu they open; `Vendor.lua` draws the merchant window and sells junk and repairs at every merchant; `Merchant.lua` buys full stacks and restyles the game's how-many popup.

The file names and their settings are crossed:

| File | Part | Switched by |
|---|---|---|
| `Vendor.lua` | Serene's merchant window | `merchant` |
| | junk selling, repairs | `sellJunk`, `autoRepair` (with or without the window) |
| `Merchant.lua` | full-stack buying, the "Alt-click" hint | `vendor` |
| | the restyled stack-split popup | `merchant` |

The bags, bank and merchant are Serene's own windows. The game's windows still exist and open and close as the game decides, only out of sight; [architecture.md](architecture.md) describes how each is put away.

## Items.lua

`ns.Items` is the one place that answers "what is in this slot and where does it belong". Bags, Vendor, Merchant and Tooltip all go through it.

`Items.Bags()` lists the player's containers: bags 0 to `NUM_BAG_SLOTS`, plus the reagent bag and the keyring where the client has them. `Items.FreeSlots(bag)` gives the room left in a bag and its family (what kind of bag it is). `Items.Room()` adds up the room for any item in the ordinary bags and lists the special ones (a quiver, a soul bag) on their own; TopBar's and MenuBar's bag words use it. `Items.BankTabs()` lists the character's purchased bank tabs, and `Items.BankBags()` every container of the bank: the tabs, or on a bank of the older kind its own slots and its bags.

`Items.Slot(bag, slot)` reads one slot through `C_Container.GetContainerItemInfo` (or the old global) and returns a plain table with `bag`, `slot`, `link`, `id`, `icon`, `count`, `quality`, `locked`, `quest` and `noValue`, or nil for an empty slot. Every value goes through `Clean`, so a secret comes back as nil rather than raising an error later.

`Items.Describe(entry)` adds the item's class, subclass, equip slot and name, and decides whether its stacks merge into one cell. Stackable items merge; gear never does, because each piece can be different. It works on saved entries of other characters too, which only carry a link, count and quality.

`Items.Section(entry)` decides the section. A pin the player set (`bagPins[itemID]`) wins as long as the section still exists, either built-in or one of the player's own in `bagCats`. Without a valid pin, `AutoSection` decides: quest items go to Quest (so a grey quest item is never junk), quality 0 goes to Junk, bags and quivers to Other, anything equippable to Equipment, and the rest by item class. `Items.IsJunk(entry)` is simply `Section(entry) == "Junk"`, which gives the one rule both windows use: what you see under Junk is what gets sold, and nothing else.

`Items.SellPrice(item)` returns what a vendor pays for one (0 if nothing), and `Items.Coins(copper, red, short)` formats money with the game's coin icons, in a quiet red for an amount you can't pay. The short form is for a word on a band (TopBar's money): the gold with its silver once there is gold, else silver and copper; the game has no short form, so it is built here.

## Inventory.lua

`ns.Inventory` keeps what every character carries in `SereneDB.inv`. Bags.lua stores every scan of the player's own bags or bank with `Remember`, keyed by realm and character name:

```lua
inv[realm][name] = {
	class = "MAGE", money = 123456,
	bags = { { link, count, quality }, ... }, bagsFree = 12, bagsSpecial = { quiver = 4 }, bagsAt = time(),
	bank = { ... }, bankFree = ..., bankSpecial = ..., bankAt = time(),
}
```

`bankAt` here is a timestamp and has nothing to do with the `bankAt` setting. The bags are remembered whenever they change, even while closed; the bank only while the player is at a banker, since that's the only time it can be read. Clicking the name in the header switches the window to another character (`CharacterMenu`, `win.viewing`), and the "bank" word opens the remembered bank from anywhere.

The same data feeds the item tooltip counts (`bagCounts`), which Inventory.lua adds itself: its module's `init` hooks the tooltips when `bags` is on. `OnItemTooltip` is a `TooltipDataProcessor` post-call (or an `OnTooltipSetItem` hook on older clients). It uses an index built lazily by `Index` and thrown away on every `Remember`, and it only adds lines for what the player wouldn't see anyway: the bank, and other characters.

## Bags.lua

### The windows

There are two windows, `SereneBags` and `SereneBank`, both made by `MakeWindow`. Along the top runs a header: the character's name (click it to look at another character's bags), then the words "bank", "bags" and "make room" on the bags window, "tabs" on the bank, and a close cross. Below it come the sections, a cell for free space at the foot, and a row of bag slots that the "bags" or "tabs" word opens. The bank opens beside the bags or where the player put it (`bankAt`); Shift-drag moves a window, and dragging the bank while it sits beside the bags moves both. Positions are saved in `bagsPos` and `bankPos`.

A window is redrawn by `Refresh(win)`. For the player's own bags it calls `Scan` over the live containers; for another character, or the bank away from a banker, it uses `Remembered`. Either way the entries go through `Sections`, which merges stacks with `Cells` and groups the cells by `Items.Section`, putting the player's own sections first in their saved order, then the built-in ones in the order of `Items.SECTIONS`. `Layout` places the cells and draws section headers. Within a section, `Earlier` sorts by quality, class, subclass, name and count.

A merged cell keeps all its stacks in `cell.slots` and shows the button of the first stack that isn't locked (`cell.live`). A stack that is in a mail or a trade is locked, so the next one answers clicks, and the cell only turns grey when every stack is locked.

Events don't redraw directly. `OnEvent` calls `Dirty(win)`, which marks the window and shows a one-frame ticker; the ticker refreshes each marked window once, however many bag events arrived in that frame. When the bags are closed, the ticker still scans and remembers them.

### Following the game's windows

`HideGameWindows` reparents `ContainerFrameCombinedBags`, `ContainerFrame1..N` and `BankFrame` into a frame that is never shown. A frame inside a hidden parent still reports `IsShown()` as true, so the game's open/closed logic keeps working unchanged. Serene follows it: the global bag functions (`OpenAllBags`, `ToggleBag` and the rest) and the game frames' `Show`/`Hide` are hooked to `Sync`, which shows Serene's bags whenever any of the game's bag frames is open. That's why B, the bag buttons, merchants and bankers open and close Serene's bags without any special handling.

The reverse also has to hold. When Serene's bags close, `OnHide` calls `CloseAllBags` (with the `syncing` flag set, so `Sync` doesn't react), because otherwise the invisible game window would stay open and the next B would close it instead of opening the bags.

The banker is the one case the game doesn't cover: its bank window is out of sight, so it no longer opens the bags itself. On `BANKFRAME_OPENED` Serene shows the bank, opens the bags if they weren't open (and remembers that in `bagsByBank` so it closes them again on `BANKFRAME_CLOSED`). Closing Serene's bank ends the banker interaction through `CloseBankInteraction`.

### Item buttons

The cells for live slots are the game's own item buttons (`ContainerFrameItemButtonTemplate`, made in `LiveButton`), so clicking, dragging, using, splitting, selling and right-click-to-bank all work without Serene calling anything protected. The template reads its bag from its parent, so each button sits in a per-bag holder frame (`Holder`) that has `SetID(bag)`, `GetBagID()` and `IsCombinedBagContainer()`. `Dress` hides the template's art (the `HIDE` list) and `Decorate` adds Serene's: a faint ground, a quality line for uncommon and better (gold for quest items), the new-item glow, a free count and the gold "keep" dot. Cells of another character's bags are plain buttons (`OfflineButton`) that show the item's tooltip by hyperlink.

The free cell at the foot is the game's button for the first free slot, so an item dropped on it goes there. The rest of the glass takes a drop too: `Drags` gives the window, its words, its section headers and the "make room" panel an `OnReceiveDrag` and an `OnMouseUp` (for an item picked up with a click and clicked onto the glass) that call `PutDown`. That scans the live containers again and puts what the cursor holds into the first free slot that takes any item, with `C_Container.PickupContainerItem`; a merchant's item on the cursor is bought that way, as on the game's own empty slot. It does nothing on another character's window, on the bank away from a banker, or with no free slot, so the item stays on the cursor. A drop can arrive both as the end of a drag and as a mouse-up, so `PutDown` sets `win.droppedAt` and ignores a second one within 0.2 seconds; the same mark keeps a word from taking the drop as a click. Dropped on an item's cell, it is the game's button that answers (a swap, or a stack merged).

On this client the item buttons are protected. Whether they are is read from the first button made (`protectedButtons`). After that, a live window that needs a refresh in combat is only marked `pending` and refreshed on `PLAYER_REGEN_ENABLED`, and no new buttons are created in combat. The buttons that exist keep working.

### Sections and the menu

Alt-right-click on an item opens Serene's own small menu (`ns.BagMenu` in BagMenu.lua, not UIDropDownMenu; it also lists whose bags or bank to look at): the player's sections, the built-in ones, "A section of your own..." (which adds the name to `bagCats`), "Back to its own section" and "Never suggest deleting" (`bagKeep`). Picking a section writes `bagPins[itemID]`. Right-clicking the header of one of the player's own sections offers "Remove this section", which calls `RemoveSection` and drops every pin pointing at it.

### Settings

`bags` needs a reload. `bagColumns` is clamped to 4–24 in `Columns` (the panel offers 6–16). `bagCounts` turns the tooltip counts on, `bankAt` places the bank. `bagPins`, `bagCats`, `bagKeep` and `inv` are data rather than settings, as are `bagsPos`, `bankPos` and `bagsNoted`.

A few things to be aware of: `protectedButtons` is only known once the first button exists, so opening the bags for the very first time in combat can still try to create one. A refresh that arrives while a window is being dragged is dropped rather than deferred (`win.moving`). `SpecialKind` walks `FAMILY` with `pairs`, so a bag whose family has several bits set gets an arbitrary one of them as its kind.

## BagSlots.lua

The row under each window's header is drawn here: `ns.BagSlotsRow(win, live)` for the bags, `ns.BankTabsRow(win, live)` for the bank, and `ns.BagSlotsHover(win)` after each refresh so the tooltip and the faded cells follow what changed under the mouse. Bags.lua calls them from `Refresh` and shares its measures and its `Text` helper as `ns.bags`, the way Chat.lua shares `ns.chat`. Each row sets `win.rowHeight`, which `Layout` starts the sections under.


The row of bag slots lets the player put on, swap and take off bags (`PutOn` uses `PutItemInBag` and `PickupBagFromSlot`); hovering a slot highlights that bag's items with `Spotlight`. The bank comes in two kinds. An older bank has its own slots plus bag slots to buy (`BankBagSlots`). This client's bank is tabbed: `Items.BankTabs` reads the purchased tabs from `C_Bank.FetchPurchasedBankTabData`, and each tab holds a bag in an inventory slot that `C_Bank.BankBagTypeAndIDToInvSlot` names. It isn't known whether that call wants the tab's index or its id, so `TabInv` tries both; `/serene debug` prints both. Buying a tab or a bag slot never calls the purchase directly: the "buy" word calls the bank window's `Reveal` (in Bags.lua), which sets `revealing`, puts the game's `BankFrame` back under `UIParent` and hides Serene's bank, so the purchase happens on the game's own page with its own confirmation. `BANKFRAME_CLOSED` puts the frame away again.

## BagRoom.lua: make room

"make room" suggests the stack a vendor pays least for, in a small glass panel above the bags (`MakeRoom`, `Suggest`, `Cheapest`). Bags.lua drives it through `ns.BagRoom`: the word calls `Toggle`, each refresh calls `Suggest(win, live)`, opening the bags calls `OpenIfFull`, and the cell of `Suggested()` glows. It draws with the bags' own words and measures from `ns.bags`, so its words drag the bags and ignore the click at the end of a drag like theirs. It skips anything a vendor won't buy, quest items, locked items, the keyring and kept items. Delete, skip (for this opening only) or keep are the choices. It opens by itself when the bags open completely full (`BagsFull`, counting only bags that take any item).

`Delete` is careful because it destroys an item: it reads the slot again and gives up if the link, count or lock changed since the suggestion, picks the item up and checks that the cursor holds that item, calls `DeleteCursorItem`, and checks the cursor is empty afterwards.

## Vendor.lua: the merchant window

### The window and the game's frame

`SereneMerchant` is one scrolling list of the merchant's goods, with a search and "usable only" filter over it (`merchantSearch`, `merchantUsable`) and the buy/buyback tabs, repair cost, junk worth and money in the foot. Each row shows the icon, the name in its quality colour, the price, and a short note: how many the merchant has left, how many you have in your bags and bank (`merchantCounts`), "running low" for a reagent from Reagents.lua, or a red reason you can't use it. The window's height is set from the merchant's total number of goods (between `FEWEST` and `MOST` rows), so it doesn't change size while you search. It sits beside the bags (or beside the bank, when that is beside the bags) or where the game's window would open (`merchantAt`).

The game's `MerchantFrame` stays genuinely open the whole time, because right-click selling from the bags, the game's purchase confirmations and closing the visit all depend on it. `Aside(true)` hides it by setting its alpha to 0, moving it to x = −10000 and turning off clamp-to-screen (clamping would pull it back on screen); `Aside(false)` restores the saved points. It is re-applied from the frame's `OnShow`, from `UpdateUIPanelPositions` (which re-places the game's panels) and once more a frame after `MERCHANT_SHOW`, because the game's window can appear a moment after the event.

`Visit(true)` starts a visit on `MERCHANT_SHOW`: it clears the per-visit caches, shows the window and, a frame later, calls `Arrive`. The visit ends on `MERCHANT_CLOSED`, on `PLAYER_INTERACTION_MANAGER_FRAME_HIDE` for the merchant, or when the game's frame hides; closing Serene's window calls `CloseMerchant()`. The `merchant` setting switches live: `OnRefresh` swaps between the two windows even in the middle of a visit.

### Reading the goods

`Offer(index)` reads one item through `C_MerchantFrame.GetItemInfo` (or `GetMerchantItemInfo`) into a table with the price, lot size, supply, max stack, extended costs (tokens and items) and whether you can afford it. `Gather` builds the list for the current page and search, and `Draw` fills the rows. Merchant events go through a one-frame ticker (`Soon`) like the bags.

The red reason comes from `Reason`. It reads the item's tooltip lines (`C_TooltipInfo.GetMerchantItem`, or a hidden scanning tooltip), takes the first red line after the name and shortens it with `Short`. The patterns in `Short` are built from the game's own localized strings (`ITEM_MIN_LEVEL`, `ITEM_MIN_SKILL`, `ITEM_REQ_REPUTATION`, `ITEM_CLASSES_ALLOWED`...), so "Requires Level 40" becomes "level 40" in any language. Recipes the player already knows read "known". Reasons are cached for the visit, except when the tooltip had no lines yet, so a reason that wasn't loaded is asked for again on the next draw.

### Buying

Row clicks follow the game's own merchant buttons: right-click buys, a plain left click or a drag picks the item up, Shift opens the how-many popup (`HowMany`, using the game's `StackSplitFrame` with the row as its owner), Ctrl and other modified clicks go to `HandleModifiedItemClick`, and Alt buys a full stack through `ns.MerchantBuyStack`. Dropping an item from the bags on the window sells it (`DropSell`).

`Buy` checks with `Still` that the merchant still sells the same item at that index, then buys whole lots. Items with extended costs or that can't be returned, and purchases above the game's `MERCHANT_HIGH_PRICE_COST`, go through the game's own confirmations: `MerchantFrame_ConfirmExtendedItemCost` and `MerchantFrame_ConfirmHighCostItem` expect one of the game's merchant buttons, so `Proxy` builds a hidden button carrying the same fields (`price`, `extendedCost`, `link`, `count`...). Where the game has no confirmation for a case, `Ask` shows Serene's own popup.

### Junk and repairs

`Arrive` runs at the start of every visit, whether the player uses Serene's window or the game's, and does nothing if Shift is held. With `sellJunk` on it sells the junk, then with `autoRepair` on it repairs.

`FindJunk` collects every slot `Items.IsJunk` says is junk and that sells for something, skipping locked items and items without value, up to `MAX_SELL` (120) slots, each a whole stack. Selling is refused in combat and when the merchant doesn't buy, which the game shows by whether `MerchantSellAllJunkButton` is shown; that's why `Arrive` runs a frame after the window appears. `Sell` puts the items in a queue that an `OnUpdate` works through one item every 0.15 seconds (`SellNext`), reading each slot again first so an item that moved or changed isn't sold by mistake. After the last sale it waits half a second for the money to arrive, prints one line with the total and only then calls the repair.

With `repairGuild` on, `Repair` uses the guild's money when the guild allows repairs and the player's withdrawal allowance covers the whole cost (−1 means no limit). Otherwise the player's own gold pays for all of it; the cost is never split up front. The server answers a guild repair asynchronously, so `JudgeGuild` looks again after 1.5 seconds and pays whatever is still damaged with the player's gold. Without enough money, nothing is repaired and a line says so.

`merchantNoted` records that the one-time note about another merchant window (Wanderer's) has been checked; Bags.lua does the same for other bag addons with `bagsNoted`.

## Merchant.lua: full stacks

`Plan(index)` works out what "a full stack" of a merchant item means: the item's max stack size, limited by what the player can pay and by the merchant's supply, rounded down to whole lots. It returns nil for items paid with tokens or other items, and for items that don't stack; those keep the game's normal buying. `Purchase` then buys the count in parts of `GetMerchantItemMaxStack`, because a merchant sells at most that many in one call, and says so when money or supply cut the stack short. A stack that costs `MERCHANT_HIGH_PRICE_COST` or more goes through `Confirm`, Serene's popup `SERENE_MERCHANT_STACK`. On accept it checks the merchant still offers the same item at that index and plans the stack again before buying.

There are three ways in: Alt-click on the game's merchant buttons (hooked in `HookButtons`, on the buy tab only), Alt-click on Vendor's rows (`ns.MerchantBuyStack`), and a "Stack" button added to the game's `StackSplitFrame` when the popup's owner is a merchant item. The owner check in `Owner` accepts the game's `MerchantItem%dItemButton` buttons and Vendor's rows, which mark themselves with `sereneMerchantRow` and carry `SetID(index)` and a `SplitStack` method like the game's buttons do. The merchant item tooltip gets an "Alt-click: buy N for X" hint, deferred through `ns.TipLater` when calm tooltips hold how-to lines back.

With `merchant` on, the stack-split popup itself is restyled in glass wherever it opens, the bags' split included. `Dress` and `LayoutSerene` move the popup's own regions; `Hold` records each region's original points and size the first time it moves, and `LetGo` restores them, so switching the setting off gives back exactly the game's layout. The popup frame's own position is never touched, because the game anchors it to each item it opens for.

## How the windows sit together

Bags, bank and merchant window place themselves beside each other, bottom edges level. Each anchors to another only if that one isn't already anchored to it (`ns.AnchoredTo`), so two windows never anchor to each other in a loop. When one hides, the other re-places itself: the bank calls `ns.PlaceMerchant` from its `OnHide`, and Vendor's window calls `ns.PlaceBank`.
