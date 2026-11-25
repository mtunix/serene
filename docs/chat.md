# Chat

Five files make up the chat, loaded in this order: `Chat.lua` (the windows themselves), `ChatLoot.lua` (loot, rolls and gains folded into a few lines), `ChatLines.lua` (what each line says), `ChatCard.lua` (the card shown over a player's name) and `ChatShell.lua` (the window's controls under the mouse). The order matters in one place: Chat.lua's `Init` creates `ns.chat`, and ChatShell reads it in its own `Init`. When the `chat` setting is off at login, `ns.chat` is never created and the other files stay out of the way.

## How Serene changes the chat

The game's chat engine stays whole. Windows, tabs, links, history and the game's own message filters all keep working, and Serene never replaces `AddMessage`. Everything it does goes through three mechanisms.

Message-event filters (`ChatFrame_AddMessageEventFilter`, or `ChatFrameUtil.AddMessageEventFilter` where that exists) see a line before the game handles it. Returning `true` drops the line, and returning `false` followed by new arguments rewrites it. This is how channel names get shortened, loot gets folded and public channels are held during a fight.

Post-hooks on each window's `AddMessage` rewrite the newest entry in the window's `historyBuffer` before it's drawn and then call `MarkDisplayDirty`. That's how the short tags, the grey hour and grouping work. A line Serene doesn't recognise, or a secret one (the game's own lines can be secret in a fight), is left exactly as it is.

One `OnUpdate` driver in Chat.lua draws the backdrops behind the lines and runs every fade.

All of this leans on the internals of the game's ScrollingMessageFrame: `visibleLines`, `FontStringContainer`, `historyBuffer:GetEntryAtIndex`, the entries' `message` and `timestamp` fields, `MarkDisplayDirty`, `RemoveMessagesByPredicate`, `RefreshLayout` and `GetInsertMode`. Nothing documents them, so if the chat breaks after a client update, start looking there.

## Chat.lua

`Init` makes two full-screen layers. `under` sits one frame level below `ChatFrame1` and holds the dark backdrops drawn behind messages. `holder` sits above and holds everything that only appears under the mouse: the kept buttons, ChatShell's scroll bar and grip, the copy button. Its alpha follows the hover. Init then publishes `ns.chat` (the two layers, `Selected` for the window being shown, `Lines`, `Hover`, the palette), dresses every window with `DressAll`, adds the two message filters and starts the driver.

### Dressing a window

`Dress` strips a window down. The frame's background textures, its scroll bar and the side buttons go to a hidden frame through `Tuck` (see [architecture.md](architecture.md) for why Serene reparents rather than hides). Tabs become plain words (`StyleTab`, `PaintTab`): the selected one gold over a 1px line, and all of them shown only under the mouse. The input line gets a dark pane with a gold edge while you type (`StyleBox`). `Dress` also calls `ns.LinesPolish` on the window so ChatLines can hook it.

The game fades tabs on its own, which would fight Serene's fade. Init sets all six `CHAT_FRAME_TAB_*_ALPHA` constants to 1, so the game's fading changes nothing and `FadeTabs` alone decides. Tabs that are alerting ignore their parent's alpha so they stay visible.

`DressAll` runs again every 2 seconds from the driver, and on the next frame after any of `FCF_OpenNewWindow`, `FCF_OpenTemporaryWindow`, `FCF_DockFrame` and `FCF_UnDockFrame`. That catches new windows and buttons the game has moved back. `Carry` puts the kept buttons on `holder`; it never touches a protected button and never runs in combat.

### Size and alignment

Edit Mode's box for the chat still includes the room of the side button strip that Serene took away. `Box`, `Gain` and `Widen` stretch the lines and the `FontStringContainer` into that room, so the chat really is as large as Edit Mode says, and a hook on `RefreshLayout` widens it again whenever the game lays the window out. `GetWidth` can return a secret in combat, so each window's last readable width is kept in `widths[frame]`.

The game keeps re-placing the input line and the tab dock. `AlignAll` runs every 0.25 seconds and shifts both so their words start where the message words start.

### Backdrops and fades

`DrawLines` runs every frame. For each visible line it places a backdrop (`Veil`) on `under` and gives it the line's own alpha, so the backdrop fades out with the message. A backdrop reaches half the line spacing above and below its line, so two neighbours meet exactly; if they overlapped, the doubled darkness would read as a line between messages. `under` is a child of UIParent, which already applies UIParent's alpha (set by rest mode), so `DrawWindow` divides that back out to match what you actually see on the message. `TAIL` is 0, so the backdrop fills the window's width and the gradient tail code is unused. Gradients keep their opacity in their colours and ignore `SetAlpha`, which is why `Tail` rebuilds the gradient instead of fading it.

`MarkOf` decides whether a line gets a coloured edge: gold with a light tint when someone else's message names you, violet for whispers. It only re-reads a line when its words change, and treats secret text as unmarked.

New lines fade in rather than pop. ChatLines owns that timing in `ns.ChatFadeIn`, and `DrawWindow` asks it for each line.

### The input line's room

The input line sits under the window, inside Edit Mode's box, which leaves an empty band at the bottom while nobody is typing. With `chatRoom` on, the messages use it. `Room` measures it, from the window's bottom down to the foot of Edit Mode's box (or the input's foot), less `ROOM_PAD`. It's 0 when the input is above the window, more than 60px away, or the window inserts at the top.

`Glide` keeps a value from 0 to 1 per window that moves with `ns.Approach` (0.22 s up, 0.34 s down) and is eased by `Ease`. `Widen` anchors `visibleLines[1]` that many pixels lower, rounded to whole pixels; the other lines hang from the first one, so they all move together. The `FontStringContainer` reaches down by the room so the lowered lines aren't clipped, and the window's hit rect reaches down by the current drop so links there stay clickable. While the window's edge cuts through a line, its backdrop fades with the part still inside. The input's own alpha is held at the eased value every frame, because the game sets the input's opacity itself when it opens and closes it.

`Writing` decides who is writing: the game's active input (`ChatEdit_GetActiveWindow`) has focus and belongs to this window, or to the dock when this window is docked. In the game's classic chat style all docked windows write into the first window's input, so that case counts too.

### Every message while you write

With `chatReveal` on, starting to write brings back the lines that had faded. `Reveal` notes each line's current opacity, keyed by its history entry (`line.messageInfo`), turns fading off with `SetFading(false)`, refreshes the window at once (`RefreshIfNecessary`) and puts each line back at the opacity it had. `Revealing`, called per line from `DrawWindow`, then eases them to full over `REVEAL` (0.3 s).

When writing stops, `Settle` turns fading back on. The game counts a line's fade from the later of its timestamp and the window's `overrideFadeTimestamp`, so setting `overrideFadeTimestamp` to "now minus the time a line stays visible" makes the revealed lines fade out over the game's normal fade duration instead of vanishing. Newer lines keep their own timing. A window that was switched away from while you wrote is settled by `DrawLines` once nobody is writing.

### Arrow keys in the input

The game's chat input has its "Alt arrow key mode" on, so plain arrow keys don't move the cursor and Ctrl+arrow doesn't jump words. With `chatArrows` on, `Arrows` turns that mode off (`SetAltArrowKeyMode(false)`); `HearKeys` applies it on every focus and `Refresh` applies it again. With the mode off, the game's own history of sent lines only answers Alt+Up/Down, so Serene keeps its own list: `Remember` records each line from a hook on the box's `AddHistoryLine` (the last `SENT_MOST`, 50), and `Recall` brings them back on plain Up/Down. Lines starting with a secure command (`IsSecureCmd`: /cast, /use, /target and so on) are left out of that list, since the game may refuse to run one an addon wrote back into the box. Alt+Up/Down still reaches them through the game's history.

### Channel names, system lines and links

`ShortChannel` is a filter on `CHAT_MSG_CHANNEL` that drops the zone from a channel name, so "2. Trade - City" shows as "2. Trade". The game routes a channel line to a window by comparing names, and the comparison uses names shorter than the one in the line, so the shortened name has to stay longer than the window's own entry for the channel or the line goes to the wrong window. `QuietSystem` is a filter on `CHAT_MSG_SYSTEM` that turns friends and guild members coming online or going offline into short grey lines (setting `quiet`).

Hovering a link shows its tooltip without a click (`OnLinkEnter`). Rolls, web addresses and player names get their own tooltips through `ns.RollTooltip` (ChatLoot), `ns.UrlTooltip` (ChatLines) and `ns.PlayerCard` (ChatCard), tried in that order.

### The chat's alerts

Friend-online and Battle.net toasts appear just above the chat tabs, 8px (`ALERT_MARGIN`) in from the screen's left edge. Left alone, the game anchors their container, `ChatAlertFrame`, to the side button column left of the window, which is off screen when the chat sits at the screen's edge.

`PlaceAlerts` anchors the container to UIParent from measured positions. A toast doesn't sit on the container's corner but some distance above it, so `MeasureAlerts` measures that gap one frame after a toast shows (in `OnShow` itself the game hasn't anchored the toast yet), and `PlaceAlerts` lowers the container by it. The gap is kept for the session. `HearAlerts` wires this up: `PlaceAlerts` runs again whenever a toast shows and from a `SetPoint` hook. When positions can't be read (secret in a fight) it falls back to the tabs' top left. `BNToastFrame` is also clamped to the screen.

## ChatLines.lua

Chat.lua calls `ns.LinesPolish(frame)` for each window it dresses. That adds an `AddMessage` post-hook (`OnAdded`) and an `OnMouseDown` handler to the window. `OnAdded` looks at the newest history entry and rewrites it:

- `ShortTags` turns channel tags into `[1]`, `[G]`, `[P]` and so on (setting `tags`). The tag stays the channel's own clickable link.
- The game's timestamp is shown as a grey hour. `StampPattern` builds the pattern to find it from the `showTimestamps` CVar.
- With `group` on, consecutive lines from one speaker show the name only once, indented by a blank texture as wide as the name (`Indent`). A line continues a group only when the same speaker and the same kind of message came last with nothing in between; incoming and outgoing whispers count as different kinds, and a group ends after `GROUP_TIME` (2 minutes). Each grouped line's timestamp is refreshed so the whole group fades together and the name is never the first thing to go.

`ns.ChatFadeIn(words)` gives the fade-in for a new line over `FADE_IN` (0.3 s); Chat.lua's driver asks it.

With `calm` on, `Hold` (a filter on `CHAT_MSG_CHANNEL`) keeps public channel lines back during a fight, at most `HELD_MOST` (80) per window. The module's events frame tracks the fight, and 0.5 s after it ends `Replay` plays the held lines through each window's own `OnEvent`, so they go through the game's filters and look exactly as they would have.

Copying works three ways. Alt+click copies one line into `CopyBox`; Shift+Alt+click, the copy icon (`CopyButton`) or `/serene copy` opens the window's whole history in a sheet (`CopyHistory`). `Plain` strips a line's colour codes and links for copying. Web addresses in player chat become `|Haddon:Serene:url:...|h` links (`Linkify`, applied by `UrlFilter`); a click on one opens the copy box. Clicks are heard both from `EventRegistry`'s "SetItemRef" callback and a `SetItemRef` hook, and `OnLink` de-duplicates them.

## ChatLoot.lua

ChatLoot folds three kinds of game sentence into fewer lines:

- A player's loot within `LOOT_TIME` (8 s) of their last becomes one line, "X looted [a], [b]".
- A roll becomes one line that is rewritten as choices and rolls come in, ending with the winner and their roll. Hovering its `[Roll]` link lists who chose what (`ns.RollTooltip`).
- Money, experience, reputation and quest rewards become one grey line that keeps growing while new gains arrive within 20 s, or 90 s in a fight (`GAINS_TIME`, `GAINS_FIGHT_TIME`).

The settings are `loot` and `gains`. `Init` adds `OnLootEvent` as the filter for `CHAT_MSG_LOOT` and `OnGainsEvent` for money, experience, faction and system lines.

### Reading the game's sentences

`FormatPattern` turns one of the game's format strings (`LOOT_ITEM`, "%s receives loot: %s.") into an anchored Lua pattern plus the order its arguments come in, which handles the `%2$s` form other languages use. `ns.FormatMatch` applies it, and Chat.lua and ChatCard call `ns.FormatMatch` for their own sentences.

`Read` tries every entry in `SENTENCES` against a line and returns what it says: the kind (loot, choice, roll, won, all passed), who, the item, the roll and the count. The game's own format strings are used where they exist, the `ENGLISH` copies where they don't. The order of `SENTENCES` matters, since the first match wins: longer sentences come before the shorter ones they contain, so "automatically passed on" isn't read as "passed on" and "Everyone passed on" isn't read as a player called Everyone passing. On this client every roll sentence starts with a link of its own (see [forever-client.md](forever-client.md)), which adds arguments in front; `Read` skips any leading arguments beyond the ones the sentence is about.

### Serene's own lines

ChatLoot writes its folded lines with `AddMessage` and then edits them in place. `Add` writes a line and finds the history entry it created. `Rewrite` changes that entry's text and resets its timestamp so it fades from now. `Refresh` decides between the two: if Serene's line is still the newest in the window it's rewritten where it is, otherwise it's removed (`Remove`, through `RemoveMessagesByPredicate`) and added again at the bottom, because rewriting it further up would bring it back among faded lines.

A filter runs once per chat window that shows the event, so the same sentence can arrive several times. `heard[lineID]` makes sure each sentence changes a roll's state only once. Rolls are kept in `rolls` by item and forgotten after `ROLL_KEEP` (300 s) or once a finished roll is replaced by a new one for the same item.

`Add` finds its entry by comparing `entry.message` with the text it just wrote. ChatLines' hook leaves ChatLoot's lines alone (they carry no channel tag, no player link and no raw timestamp), but an `AddMessage` hook from another addon that rewrites lines would make the lookup fail. `Add` then returns nil, the filter returns false, and the game's original sentence shows as well as Serene's line.

### A loot line from start to finish

When the game raises `CHAT_MSG_LOOT`, it runs the message filters once for each chat window that shows loot, so `OnLootEvent` sees the same sentence once per window. The first time it meets a `lineID` it calls `Read`, moves the roll's state if the sentence is about a roll (`UpdateRoll`), and stores both in `heard[lineID]`; the other windows reuse that. A plain loot sentence goes to `OnLoot`, which either rewrites the player's last loot line (same player, within `LOOT_TIME`, and still the newest line in the window) or writes a new one with `Add`. A roll sentence goes to `ShowRoll`, which writes the roll's line through `Refresh`.

`Add` calls the window's `AddMessage`, so ChatLines' post-hook `OnAdded` sees Serene's line like any other and records its arrival with `Came`. The filter then returns true and the game drops its own sentence. From the next frame on, Chat.lua's `DrawWindow` draws the line's backdrop and asks `ns.ChatFadeIn` for its opacity, so the folded line fades in over `FADE_IN` (0.3 s) rather than appearing at once.

## ChatCard.lua

`ns.PlayerCard(owner, link)` shows a small card when the mouse is over a player's name in the chat (setting `card`): level, race and class with the name in its class colour, guild and rank, where they are, and whether they're a friend, in your guild or in your group. Nothing is requested from the server on hover. The card is built from the sender's GUID on the chat line, the live group, guild roster and friends list, and `known`, a session memory keyed by `Key(name)` that a listener fills from your target, the unit under the mouse, nameplates, the group, /who answers and chat senders. A level remembered more than `OLD` (10 minutes) ago says how long ago it was seen.

The listener registers its events in `init` whether or not the chat is on. It does a little work for every message on the 14 player-chat events, where `FromGUID` reads the sender's GUID into `known`.

## ChatShell.lua

ChatShell draws the window's controls, all of which only show under the mouse: a faint glass pane behind the window, a hairline under the tabs, the menu, channel and copy buttons as small drawn icons, a slim scroll bar with a gold thumb, a pill that says "N new" (or "Latest") when you've scrolled back, and a dotted resize grip. `Reskin` clears a button's textures and lays Serene's icon over it; the button and its click are still the game's. The scroll bar can be dragged, clicked to jump and scrolled with the wheel. The grip resizes the window, or the dock's primary window when the window is docked.

The bar and the grip only take the mouse while they're visible (hover above 0.3), so invisible controls never catch clicks meant for the world. `ns.ShellOver()` tells Chat.lua the mouse is on one of them, which keeps the window shown while you drag.

## Settings

| Setting | File | What it does |
|---|---|---|
| `chat` | all | The chat in glass. Needs a reload. |
| `lineTime` | Chat | Seconds a message stays before fading |
| `quiet` | Chat | Short grey online/offline lines |
| `chatArrows` | Chat | Arrow keys move in the input; Up/Down recall sent lines |
| `chatRoom` | Chat | Messages use the input line's room while nobody writes |
| `chatReveal` | Chat | Faded messages come back while you write |
| `tags` | ChatLines | Short channel tags |
| `group` | ChatLines | One speaker's lines grouped under one name |
| `calm` | ChatLines | Public channels held during fights |
| `loot`, `gains` | ChatLoot | Loot and rolls folded; money, experience and reputation in one line |
| `card` | ChatCard | The card over a player's name |

`ns.ChatDebug` (part of `/serene debug`) prints the selected window's rect, Edit Mode's box and the widening. The other `ns.Chat*` and `ns.Loot*` names exported by these files are there for the tests.
