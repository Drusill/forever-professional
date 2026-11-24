# Tracked recipes and shopping list: design

Date: 2026-11-23. Issue: #4. Status: draft, waiting for approval.

## Intent

The calculator (#3) plans one recipe at a time. A crafter planning a session wants several recipes, each with
a quantity, and one combined shopping list: Copper Ore counted once for everything that needs it, have / need
from the bags of whoever is playing. Item tooltips say which tracked recipe needs an item, so a stack in the
bags or on the Auction House can be matched to the plan. The list counts down as recipes are crafted.

## Goals, non-goals, anti-goals

- Goals: an account-wide tracked list with a quantity and unit per recipe; tracking from the detail pane and
  from the calculator; a Tracked panel over the detail pane with the tracked recipes and the combined
  Shopping / Steps / Tree views; "Needed for" lines on item tooltips; a countdown on each craft; per-recipe
  shares of a combined plan in `Model`, reusable by #5 ("which step needs this").
- Non-goals: alt inventories in have / need (still the logged-in character); prices; a frame outside the main
  window; a reverse "used in" index (#6); sorting or grouping the tracked list.
- Anti-goals: Blizzard's recipe tracking (`C_TradeSkillUI.SetRecipeTracked` and friends) or any other change
  to the user's profession window; a tooltip that breaks someone else's tooltip; a stale tooltip after the
  list, the bags or a craft/buy choice changed.

## Findings that shaped this

- `M.PlanMaterials(roots, ctx)` (`Model.lua:818`) already takes several roots. Pass 2 sums every root's needs
  per item, then subtracts `ctx.have(item)` once per item (`n.net = max(0, need − have)`), so a bag count is
  used once across all roots. Multi-output items round on the combined total.
- The plan keeps totals only: `plan.items[id]` has no record of which root asked for how much. A per-recipe
  "(n)" needs that split.
- The roots' own output is never subtracted (#3 decision 9), but reagents are, live on `BAG_UPDATE_DELAYED`.
  After crafting 2 of 4 tracked crafts the used reagents leave the bags while the quantity still says 4, so
  without a countdown the shopping list grows.
- The calculator's Shopping, Steps and Tree renderers (`UI/Calculator.lua:145–209`) already loop over
  `plan.shopping`, `plan.steps` and `plan.tree` for every root; only `UI.RefreshCalculator` builds a
  one-root plan from the quantity row.
- `ns.PlanContext()` (`Characters.lua:189`): reagents, have (`C_Item.GetItemCount(id, true)`), knownBy from
  `ns.RecipeOwners`, mode from `ns.db.craftModes`. "Me" is always the logged-in character.
- `ns.db` is account-wide; characters live in `ns.db.chars[GUID]`, and `/fp forget` deletes that record only.
  New optional fields need no `db.version` bump (`InitDB` fills missing defaults).
- A data rebuild can remove a recipe (Disorienting Smog Potion, #16), leaving a saved spell ID with no
  `ns.Data.Recipes` entry.
- `Tooltip.lua` adds lines through `TooltipDataProcessor.AddTooltipPostCall(Item)` (fallback
  `OnTooltipSetItem`), guarded by `tooltip.fpItem` per tooltip, wrapped in `pcall` with `geterrorhandler`.
  Today it only adds lines for recipe items (`ns.AddRecipeLines`).
- Layout at the 900×540 minimum: the rail is full (logo 52 + five known × 52 + divider 11 + seven others × 30
  = 533 of 538px), so a rail entry doesn't fit. The window header has about 150px free left of the Skill
  stat. The detail pane is 432px wide (396px of scroll content); its pinned header is 76px
  (`DETAIL_HEADER_H`), with Calculate on the chip row, which is tight with a long category chip.
- The mock already has per-spell schematics (`mock.schematics`, `mock.onlySchematics`), `mock.bags` /
  `mock.bank`, tooltip post-calls (`mock.postCalls`, `SetItemByID`) and `fire(event, ...)`. It has no
  `C_TradeSkillUI.SetRecipeTracked` to guard against.

## Decisions (made with the user)

1. **Account-wide list,** `ns.db.tracked`. Any character sees the same list with its own have / need; tooltips
   show it on every character.
2. **Tracked panel over the detail pane,** opened by a `Tracked n` button in the window header. Built on the
   calculator panel: tabs `Recipes | Shopping | Steps | Tree`.
3. **Track from both places.** A Track / Untrack toggle in the detail pane (Track adds 1 craft), and a Track
   button in the calculator that tracks with the panel's quantity and unit. Opening the calculator on a tracked
   recipe pre-fills its tracked quantity and unit. Quantities are also edited in the Tracked panel.
4. **Detail header gets an action row** (+24px, header 100px): Track and Calculate on the left, the tracked
   quantity on the right.
5. **Quantity saved with its unit,** `crafts` or `items`, like the calculator's `Crafts | Items` switch (shown
   only for recipes that make more than one or a range). Items round up to whole crafts.
6. **Count down on each craft.** The player's successful cast of a tracked recipe lowers its quantity by one
   craft (by the yield in Items mode); at 0 the recipe leaves the list.
7. **Tooltip: one line per recipe, plus a total.** `Needed for: <recipe> (n)`, n being that recipe's own share
   at its tracked quantity before bags; then `Tracked total: have / need` from the combined plan. At most five
   recipe lines, then `and N more`. When the total need is 0 (what you carry, often an intermediate, covers
   it), only the total is shown, since the recipe lines would contradict it (decided in game, 2026-11-24).
8. **Orphans stay; removed recipes go.** A tracked recipe nobody knows (alt forgotten, never learned) stays and
   shows "Nobody". Entries whose recipe is gone from the data are skipped by the plan and pruned at login.

## Approaches considered

| | Per-recipe shares | Trade-off |
|---|---|---|
| **Chosen** | `M.PlanShares(plan)`: walk the combined plan's decided items once per root, summing that root's needs alone, before inventory | Uses the same craft/buy choices the panel shows; one cheap pass per root over items already decided. Shares can add up to a little more than the combined need where a multi-output item rounds per root (the total line shows the real need). |
| Rejected | One `M.PlanMaterials` per tracked recipe | Choices could differ from the combined plan (cycle paths, first-reached decisions), and N full plans per refresh. |

| | Panel | Trade-off |
|---|---|---|
| **Chosen** | The calculator panel draws a **source**: the recipe source (one root from the quantity row, today's behaviour) or the tracked source (roots from the list, plus a Recipes tab). New `UI/Tracked.lua` holds the tracked source, its Recipes tab and the header button | Shopping / Steps / Tree are drawn by the same code for both; #5 adds a third source. The refactor is pinned by the existing panel tests. |
| Rejected | A separate Tracked panel copying the renderers | Two copies of the row pool and three renderers to keep in step. |

| | Freshness | Trade-off |
|---|---|---|
| **Chosen** | `ns.TrackedPlan()` caches the combined plan and its shares; every input change marks it dirty (list edits, craft/buy switches, `BAG_UPDATE_DELAYED`, character updates, a forgotten alt) | Tooltip hovers stay cheap; each invalidation is tested. |
| Rejected | Recompute on every tooltip | No staleness risk, but a full plan per hover and per tooltip refresh. |

| | Countdown | Trade-off |
|---|---|---|
| **Chosen** | `UNIT_SPELLCAST_SUCCEEDED` for `"player"` with a tracked spell ID | Works for enchants (no item); one event per craft, also with "Create All". Needs an in-game check that Forever fires it with the recipe's spell ID. |
| Rejected | Watch the output's bag count | Enchants make no item; moving, mailing or selling the output would undo the countdown. |

## Design

### Saved list (`Core.lua`, `Characters.lua`)

- `DEFAULTS.tracked = {}`: an ordered list `{ {spellID, line, quantity, unit}... }`, tracking order. New
  optional field, no `db.version` bump.
- Read through `ns.TrackedList()`, which skips bad entries (not a table, unknown recipe, quantity not a number
  ≥ 1). `quantity` is clamped to 1–999 and `unit` read as `"items"` only when the recipe makes more than one
  per craft or a range, else `"crafts"`. That test becomes `M.MakesSeveral(rec)` in `Model.lua`, shared with
  the calculator's `Crafts | Items` switch (today inline in `UI.RefreshCalculator`).
- `ns.GetTracked(spellID) -> entry | nil`.
- `ns.TrackRecipe(line, spellID, quantity, unit)`: adds at the end, or updates the existing entry in place.
- `ns.UntrackRecipe(spellID)`, `ns.SetTrackedQuantity(spellID, n)` (n ≤ 0 untracks),
  `ns.SetTrackedUnit(spellID, unit)` (keeps the number, switches its meaning, like the calculator).
- `ns.PruneTracked()` at `PLAYER_LOGIN`: drops the entries `ns.TrackedList` would skip.
- `ns.TrackedText(entry) -> "4 crafts" | "1 craft" | "10 items" | "1 item"`.
- Every change calls `ns.TrackedChanged()`: marks the plan dirty and calls `UI.Refresh` when the window is
  shown.

### Combined plan and shares (`Model.lua`, `Characters.lua`)

- `ns.TrackedRoots() -> { {spellID, line, crafts}... }`: `crafts = M.CraftsFor(rec, quantity)` in Items mode,
  else `quantity`; in list order.
- `M.PlanShares(plan) -> { [itemID] = { {root = i, need = n}... } }`: for each root alone, add
  `root.crafts × count` to its reagents, walk `plan.order` (shallow first) and, for crafted items, add
  `ceil(share / yield) × count` to their reagents. No inventory. Entries per item in root order, only `need > 0`.
- `ns.TrackedPlan() -> plan, shares | nil`: `M.PlanMaterials(ns.TrackedRoots(), ns.PlanContext())` and its
  shares, cached until dirty; nil when nothing is tracked. Marked dirty by `ns.TrackedChanged`,
  `ns.SetCraftMode`, `ns.ResetCraftModes`, `BAG_UPDATE_DELAYED`, `ns.UpdateCharacter`, `NEW_RECIPE_LEARNED`
  and `ns.ForgetChar`.

### Countdown (`Characters.lua`)

`UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)`: when `unit == "player"` and `spellID` is tracked,
`ns.CountTrackedCraft(spellID)` lowers the quantity by 1 (crafts) or by `M.Yield(rec)` (items); at 0 or below
the recipe is untracked. Other units and untracked spells are ignored.

### Tooltip (`Tooltip.lua`)

- `ns.TrackedLines(itemID) -> { text... }`: empty when nothing is tracked or the item isn't in the plan with a
  share. Otherwise one `L.NEEDED_FOR` line per share (`M.RecipeDisplayName(root.spellID)`, n), at most
  `TOOLTIP_MAX_RECIPES` (5), then `L.NEEDED_MORE` with the rest, then `L.TRACKED_TOTAL` with
  `plan.items[id].have` and `need`. Covers raw, bought and crafted items alike; a root's own output only when
  another tracked recipe uses it.
- `OnItem` adds the recipe lines (as today) and then the tracked lines, each block after a blank line, and
  shows the tooltip when either added something.

### Detail action row (`UI/Detail.lua`)

```
[icon] Target Dummy                 Skill
       Creates Target Dummy         [org|yel|grn|g]
       [Learned] [Engineering Supplies] [New]
------------------------------------------------
[Track] [Calculate]                 Tracked: 4 crafts
------------------------------------------------
```

- `DETAIL_HEADER_H` 76 → 100. `h.trackButton` (`UI.CreateToggleButton`): `L.TRACK` when untracked (tracks 1
  craft), `L.UNTRACK` when tracked; `h.calcButton` moves next to it; `h.trackedText` shows
  `L.TRACKED_QTY:format(ns.TrackedText(entry))`, empty when untracked. Both buttons act on the selected recipe
  and line.
- At 900×540 the scroll area drops from about 374px to about 350px.

### Calculator: sources and Track (`UI/Calculator.lua`)

- `calc.source` is `{ kind, title, icon, Plan(), tabs, render[tab] }`. The recipe source keeps today's header
  (Who), quantity row and `Shopping | Steps | Tree` tabs; `UI.OpenCalculator(spellID)` opens it as before.
  `UI.OpenPlanPanel(source)` opens any source. The shared renderers take the plan from the source.
- Recipe source: a `calc.track` button right-aligned on the quantity row, `L.TRACK` when the recipe isn't
  tracked, `L.TRACK_UPDATE` when it is and the panel's quantity or unit differs, disabled `L.TRACKED` when they
  match. Click: `ns.TrackRecipe(line, spellID, calc.quantity, calc.unitKey)`. On open, a tracked recipe
  pre-fills the quantity and unit from its entry. The summary keeps the space between the unit switch and the
  button (no wrap).

### Tracked panel (`UI/Tracked.lua`, new)

```
[<] Tracked recipes
[Recipes 2] [Shopping 5] [Steps 7] [Tree]        [Reset choices]
-----------------------------------------------------------------
[i] Target Dummy           [  1 ]                 You      [x]
[i] Bronze Bar             [  6 ] [Crafts|Items]  Mina     [x]
```

- `UI.headerTracked` in the window header, left of the Skill stat: `L.TRACKED_N` with the count (`L.TRACKED`
  alone when empty). Click opens the tracked source with `UI.OpenPlanPanel`, or closes it when it's shown.
- Tracked source: title `L.TRACKED_TITLE`, no Who and no quantity row (the tab row moves up), tabs `Recipes n`
  (tracked recipes), `Shopping n`, `Steps n`, `Tree`; plan from `ns.TrackedPlan()`. Opens on Recipes.
- Recipes rows: recipe icon and name (click selects that profession and recipe, closing the panel), a quantity
  box (1–999, same rules as the calculator's), the `Crafts | Items` switch for multi-output recipes, the
  crafter (`ns.CrafterText` of the root), and an untrack button (`L.UNTRACK` tooltip).
- Empty list: `L.TRACKED_EMPTY` on every tab.
- Closes like the calculator (Back, another recipe or profession, window hidden). Redraws on
  `BAG_UPDATE_DELAYED`, `ns.TrackedChanged` and `UI.Refresh` while shown.
- At 900×540: the Recipes row's name keeps at least 120px with the unit switch shown.

### Strings (`Locale.lua`)

`TRACK = "Track"`, `UNTRACK = "Untrack"`, `TRACK_UPDATE = "Update"`, `TRACKED = "Tracked"`,
`TRACKED_N = "Tracked %d"`, `TRACKED_TITLE = "Tracked recipes"`, `TRACKED_QTY = "Tracked: %s"`,
`TRACKED_CRAFTS = "%d crafts"`, `TRACKED_CRAFT_ONE = "1 craft"`, `TRACKED_ITEMS = "%d items"`,
`TRACKED_ITEM_ONE = "1 item"`, `TRACKED_RECIPES = "Recipes"`,
`TRACKED_EMPTY = "Nothing tracked yet. Track a recipe from its detail or the calculator."`,
`NEEDED_FOR = "Needed for: %s (%d)"`, `NEEDED_MORE = "and %d more"`, `TRACKED_TOTAL = "Tracked total: %d / %d"`
(reuse existing `L.*` where one already says the same).

## Testing

Test first, one step at a time, `mise exec -- python -m unittest discover tests` after each.

- New `tests/test_tracked.py`, importing `REAGENTS`, `CALC`, `MINA` and `seed` from `tests/test_calculator.py`.
- Pins: `tests/test_calculator.py` (panel source refactor), `tests/test_tooltip.py` (tooltip additions) and
  `tests/test_detail.py` (action row) pass unmodified.
- Mock: `C_TradeSkillUI.SetRecipeTracked` / `GetRecipesTracked` record calls in `mock.blizzardTracked`, so a
  test can assert they're never used.
- Covered: adding, updating, removing and changing quantity and unit; bad saved entries and pruning; the
  combined totals of two recipes sharing a reagent (Bronze Bar for Target Dummy and Bronze Tube); shares;
  each invalidation; the countdown in both units and its removal at 0; tooltip lines, the cap, the total, and
  the line disappearing once untracked; the action row, the calculator's Track and pre-fill; the Tracked panel's
  tabs, quantity edits, untrack, empty state, live updates and fit at 900×540.

## Steps

On `feat/4-tracked-recipes`, one Conventional Commit each, no push:

1. Saved tracked list.
2. Combined plan, shares and invalidation.
3. Craft countdown.
4. Tooltip lines.
5. Detail action row.
6. Calculator driven by sources (no behaviour change).
7. Track from the calculator.
8. Tracked panel and header button.
9. README and AGENTS updates.

## Left to the builder

Exact pixel layout of the action row, the header button and the Recipes rows; the untrack icon; the colours of
the tooltip lines (reuse the owner-line colours); whether a Recipes row shows its output count for Items mode.

## In-game checklist (after implementation)

New Lua file in the TOC: **restart the client fully** (`/reload` doesn't load it).

1. `/fp`, Engineering, Target Dummy (3932): the detail header has an action row with Track and Calculate.
   Click Track: it reads Untrack, the row says "Tracked: 1 craft", the window header says "Tracked 1".
2. Mining, Bronze Bar: Calculate, switch to Items, type 6, click Track: "Tracked 2"; reopen Calculate: 6 Items
   pre-filled and the button reads Tracked.
3. Click "Tracked 2": the panel lists both recipes; Shopping lists Copper Ore once with the summed need; Steps
   and Tree show both roots. Change Target Dummy to 3: totals scale. Untrack with the row's button: it leaves.
4. Hover a needed reagent in the bags (e.g. Copper Ore): "Needed for:" lines with each recipe's amount and
   "Tracked total: have / need". Untrack everything: the lines are gone on the next hover.
5. Craft one tracked recipe once: its quantity drops by one craft (checks `UNIT_SPELLCAST_SUCCEEDED` on
   Forever); craft the last one: it leaves the list.
6. Log in on an alt: the same list, with that character's have / need; "You" now names the alt's recipes.
7. `/fp forget` an alt who knew a tracked recipe: it stays tracked and shows "Nobody". `/reload`: the list is
   kept.
8. Open Blizzard's profession window: no recipe is tracked there by the addon.
9. At the minimum window size (900×540): the action row, the header button and the Recipes rows fit; the
   detail sections still scroll.
