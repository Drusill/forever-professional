# Tracked Recipes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track several recipes, each with a quantity in crafts or items, account-wide; see them in a Tracked panel over the detail pane with one combined shopping list, craft steps and reagent tree; see on item tooltips which tracked recipes need an item and how much; and have each craft count its recipe down.

**Architecture:** `Characters.lua` owns the saved list (`ns.db.tracked`), its roots, a cached combined plan (`ns.TrackedPlan`, marked dirty by every input change) and the craft countdown. `Model.lua` adds `M.PlanShares(plan)` (each root's own share of every item, using the combined plan's choices) and `M.MakesSeveral(rec)`. `Tooltip.lua` adds the "Needed for" lines. `UI/Calculator.lua` draws a plan **source** (the recipe source is today's calculator), so `UI/Tracked.lua` (new) only adds the tracked source, its Recipes tab and the header button. `UI/Detail.lua` gains an action row with Track and Calculate.

**Tech Stack:** Lua 5.1 (WoW Forever client, interface 16001), Python 3.12 `unittest` + `lupa` tests against `tests/wow_mock.lua`.

**Spec:** `docs/superpowers/specs/2026-11-23-tracked-recipes-design.md` (issue #4)

## Global Constraints

- Branch `feat/4-tracked-recipes` (off `develop`), one commit per task, don't push. Conventional Commits, no `Co-Authored-By` or AI attribution (user rule). The pull request into `develop` says `Closes #4`.
- Run `mise exec -- python -m unittest discover tests` after every change; the whole suite must stay green.
- Test first: watch each new test fail before writing the code. Pin existing behaviour before refactoring shared code: `tests/test_tooltip.py` (Task 4), `tests/test_detail.py` (Task 5) and `tests/test_calculator.py` (Tasks 5–7) pass unmodified.
- One new Lua file, `UI\Tracked.lua`, listed in the TOC after `UI\Calculator.lua` with ` [AllowLoadGameType camelot][ExcludeLoadGameType classic]` (Task 8). TOC changes need a full client restart in game.
- Never edit `ForeverProfessional/Data/`, `tools/`, or the community addons. Never call Blizzard's recipe tracking (`C_TradeSkillUI.SetRecipeTracked` and friends) or profession filter setters.
- Every user-visible string goes through `Locale.lua` (`L.*`). Item and spell names stay live.
- Reuse, don't re-implement: plans only through `M.PlanMaterials` with `ns.PlanContext()`; items → crafts only through `M.CraftsFor`; who crafts only through `ns.CrafterText`; the calculator's quantity rules (1–999, revert on bad input) are shared with the Recipes rows, not copied.
- List and totals logic is frame-free and tested in `Characters.lua` / `Model.lua`; the UI only draws.
- lupa quirks: two Python wrappers of one Lua table don't compare equal (use `rawequal` through `a.lua.eval`); you can't index a Lua table with -1 from Python; two return values come back as a tuple; `t.items` is the wrapper's Python method, use `t["items"]`. Prefer the Edit tool over shell heredocs for multi-line edits.
- New UI must fit the 900×540 minimum window.

## Shared test fixture

`tests/test_tracked.py` (created in Task 1) imports `REAGENTS`, `CALC`, `MINA`, `LINES` and `seed` from
`tests/test_calculator.py`: real reagents from the client's `SpellReagents` table (build 1.60.1.71037); the
logged-in Tester knows the Engineering parts (3922, 3926, 3932), alt Mina knows the Mining smelts (2657, 2659,
3304, 3307, 3308). Helpers: `track(a, spell, qty=1, unit="crafts")` calls `ns.TrackRecipe(LINES[spell], ...)`;
`tracked(a)` returns `[(spellID, line, quantity, unit)]` from `ns.TrackedList()`; `item(p, id)` reads
`p["items"][id]`.

Two recipes sharing a reagent: **Target Dummy 3932 ×1** and **Bronze Tube 3938 ×1** (both use Bronze Bar 2841;
Weak Flux 2880 has no maker, so it's raw). Expected combined plan, default choices, nothing in bags:

| Item | Kind | Need | Crafts | Level | Notes |
|---|---|---|---|---|---|
| 4363 Copper Modulator | craft (me, 3926) | 1 | 1 | 1 | Target Dummy only |
| 4359 Handful of Copper Bolts | craft (me, 3922) | 4 | 4 | 2 | |
| 2841 Bronze Bar | craft (Mina, 2659) | 3 | 2 | 1 | Dummy 1 + Tube 2; yield 2, surplus 1 |
| 2840 Copper Bar | craft (Mina, 2657) | 7 | 7 | 3 | Modulator 1 + Bolts 4 + Bronze 2 crafts |
| 3576 Tin Bar | craft (Mina, 3304) | 2 | 2 | 2 | |
| 2589 Linen Cloth, 2592 Wool Cloth, 2880 Weak Flux | raw | 2, 1, 1 | | | |
| 2770 Copper Ore, 2771 Tin Ore | raw | 7, 2 | | | |

Shopping (by item ID): `2589 ×2, 2592 ×1, 2770 ×7, 2771 ×2, 2880 ×1`. Steps: `2840, 3576, 4359, 2841, 4363`,
then roots `4366` (3932) and `4371` (3938).

Shares (`M.PlanShares`, root 1 = 3932, root 2 = 3938, before inventory):

| Item | Root 1 | Root 2 | Combined need |
|---|---|---|---|
| 2841 Bronze Bar | 1 | 2 | 3 |
| 2840 Copper Bar | 6 | 1 | 7 |
| 2770 Copper Ore | 6 | 1 | 7 |
| 3576 Tin Bar, 2771 Tin Ore | 1 | 1 | 2 |
| 4363, 4359, 2589, 2592 | 1, 4, 2, 1 | — | |
| 2880 Weak Flux | — | 1 | 1 |

With **3932 ×2** and 3938 ×1: Copper Ore shares 11 and 1, combined need 12 (Bronze Bar: 4 needed, 2 crafts).

Tooltip strings in the mock (`C_Spell.GetSpellName` returns `"Spell <id>"`): Bronze Bar 2841 →
`Needed for: Spell 3932 (1)`, `Needed for: Spell 3938 (2)`, `Tracked total: 0 / 3`.

## Review Focus

- **A bag count is used once across tracked recipes.** Test: Task 2 `test_inventory_once`.
- **Tooltips are never stale.** The cached plan is marked dirty by list edits, craft/buy switches, bag updates, character updates, a learned recipe and a forgotten alt. Tests: Task 2 `test_dirty_*`, Task 4 `test_gone_after_untrack`.
- **A tooltip error never breaks someone else's tooltip.** Test: Task 4 `test_tracked_error_swallowed` (and the existing `test_errors_swallowed`).
- **The countdown only reacts to the player's casts of tracked spells,** in both units, and untracks at 0. Tests: Task 3.
- **Bad saved data loads** and removed recipes are pruned. Tests: Task 1 `test_bad_saved_entries_skipped`, `test_pruned_at_login`.
- **Blizzard's recipe tracking is never touched.** Test: Task 1 `test_never_blizzard_tracking`, repeated after the panel's actions in Task 8.
- **Refactors keep behaviour:** `tests/test_calculator.py`, `tests/test_tooltip.py` and `tests/test_detail.py` unmodified.
- **Fit at 900×540.** Tests: Task 5 `test_action_row_fits`, Task 7 `test_quantity_row_fits`, Task 8 `test_fits_minimum_window`.

---

### Task 1: Saved tracked list

**Files:**
- Modify: `ForeverProfessional/Core.lua` (`DEFAULTS.tracked = {}`)
- Modify: `ForeverProfessional/Characters.lua` (tracked list functions, prune at `PLAYER_LOGIN`)
- Modify: `ForeverProfessional/Model.lua` (`M.MakesSeveral`)
- Modify: `ForeverProfessional/Locale.lua` (`TRACKED_CRAFTS`, `TRACKED_CRAFT_ONE`, `TRACKED_ITEMS`, `TRACKED_ITEM_ONE`)
- Modify: `tests/wow_mock.lua` (`C_TradeSkillUI.SetRecipeTracked` / `GetRecipesTracked` set `mock.blizzardTracked = true`)
- Test: `tests/test_tracked.py` (new: fixture helpers, `TrackedListTest`)

**Interfaces:**
- Produces:
  - `M.MakesSeveral(rec) -> bool`: `rec.creates ~= nil and (M.Yield(rec) > 1 or type(rec.count) == "table")`.
  - `ns.TrackedList() -> { {spellID, line, quantity, unit}... }`: valid entries of `ns.db.tracked` in order, as normalized copies; skips non-tables, recipes missing from `ns.Data.Recipes[line]`, and quantities that aren't numbers ≥ 1; clamps to 999; `unit = "items"` only when saved so and `M.MakesSeveral(rec)`, else `"crafts"`.
  - `ns.GetTracked(spellID) -> entry | nil`.
  - `ns.TrackRecipe(line, spellID, quantity, unit)`: adds at the end or updates in place; quantity defaults to 1 and is clamped to 1–999; unit normalized as above.
  - `ns.UntrackRecipe(spellID)`; `ns.SetTrackedQuantity(spellID, n)` (n ≤ 0 untracks, else clamped); `ns.SetTrackedUnit(spellID, unit)` (keeps the number).
  - `ns.PruneTracked()`: rewrites `ns.db.tracked` with only the entries `ns.TrackedList` keeps; called at `PLAYER_LOGIN`.
  - `ns.TrackedText(entry) -> string`: `"1 craft"`, `"4 crafts"`, `"1 item"`, `"10 items"`.
  - `ns.TrackedChanged()`: the single notification every mutator calls (Task 2 makes it mark the plan dirty; here it refreshes the UI if shown).

- [x] **Step 1: Write the failing tests** (`TrackedListTest`, login with `CALC`, `seed(a)`)
  - `test_empty_by_default`: `tracked(a) == []`, `ns.db.tracked` is a table.
  - `test_track_adds_in_order`: track 3932, then 3938 ×2 → `[(3932, 202, 1, "crafts"), (3938, 202, 2, "crafts")]`.
  - `test_track_existing_updates_in_place`: track 3932, 3938, then 3932 ×5 → order kept, 3932 quantity 5.
  - `test_untrack`: untrack 3932 → only 3938; untracking a spell that isn't tracked does nothing.
  - `test_set_quantity`: 7 → 7; 1000 → 999; 0 → untracked.
  - `test_units`: 2659 ×6 `"items"` → `"items"`; 3932 ×4 `"items"` → `"crafts"` (makes 1); 3931 `"items"` (range) → `"items"`; `SetTrackedUnit(2659, "crafts")` → `(6, "crafts")`.
  - `test_makes_several`: 3932 false, 2659 true, 3931 true, the first Enchanting recipe without `creates` false.
  - `test_bad_saved_entries_skipped`: `ForeverProfessionalDB.tracked = { "junk", {spellID = 999999, line = 202, quantity = 1}, {spellID = 3932, line = 202, quantity = "x"}, {spellID = 3938, line = 202, quantity = 2, unit = "bogus"} }` → `[(3938, 202, 2, "crafts")]`.
  - `test_pruned_at_login`: same saved data → after login `ns.db.tracked` holds only the 3938 entry.
  - `test_saved_across_reload`: `CALC + "ForeverProfessionalDB.tracked = { {spellID = 2659, line = 186, quantity = 6, unit = 'items'} }"` → `[(2659, 186, 6, "items")]`.
  - `test_tracked_text`: the four strings above.
  - `test_never_blizzard_tracking`: after tracking, updating and untracking, `mock.blizzardTracked` is nil.
- [x] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_tracked -v`
- [x] **Step 3: Implement**.
- [x] **Step 4: Full suite, expect PASS**
- [x] **Step 5: Commit**: `git commit -m "feat(chars): save tracked recipes account-wide"`

---

### Task 2: Combined plan, shares and invalidation

**Files:**
- Modify: `ForeverProfessional/Model.lua` (`M.PlanShares`)
- Modify: `ForeverProfessional/Characters.lua` (`ns.TrackedRoots`, `ns.TrackedPlan`, dirty marks in `ns.TrackedChanged`, `ns.SetCraftMode`, `ns.ResetCraftModes`, `ns.UpdateCharacter`, `NEW_RECIPE_LEARNED`, `ns.ForgetChar`, and a `BAG_UPDATE_DELAYED` handler)
- Test: `tests/test_tracked.py` (`TrackedPlanTest`)

**Interfaces:**
- Consumes: Task 1's list; `M.PlanMaterials`, `ns.PlanContext`, `M.CraftsFor`; `plan.order`, `plan.items[id].reagents`, `.yield`, `.kind`.
- Produces:
  - `ns.TrackedRoots() -> { {spellID, line, crafts}... }` in list order; `crafts = M.CraftsFor(rec, quantity)` in Items mode.
  - `M.PlanShares(plan) -> { [itemID] = { {root, need}... } }` as in the spec: per root alone, before inventory, rounding crafted items per root; entries in root order; only `need > 0`.
  - `ns.TrackedPlan() -> plan, shares` (nil when nothing is tracked), cached until marked dirty; `ns.MarkTrackedDirty()`.

- [x] **Step 1: Write the failing tests**
  - `test_roots`: 3932 ×2 crafts and 2659 ×3 items → `[(3932, 202, 2), (2659, 186, 2)]`.
  - `test_combined_totals`: 3932 + 3938 → kinds, spells, need, crafts and levels as in the fixture table; shopping and steps as listed.
  - `test_inventory_once`: `mock.bags[2770] = 4` → 2770 `have` 4, `buy` 3.
  - `test_shares`: the fixture's shares table, `(root, need)` pairs per item; 4366 / 4371 (root outputs) have no entry.
  - `test_shares_scale`: 3932 ×2 + 3938 → 2770 `[(1, 11), (2, 1)]`, combined need 12.
  - `test_nothing_tracked`: `ns.TrackedPlan()` is nil.
  - `test_cached`: two calls → `rawequal` plans; `mock.schematicCalls` unchanged by the second.
  - `test_dirty_on_list_change`: after `SetTrackedQuantity(3932, 2)` → a new plan with 4363 need 2.
  - `test_dirty_on_craft_mode`: `ns.SetCraftMode(2841, "buy")` → 2841 `buy`; `ns.ResetCraftModes()` → `craft` again.
  - `test_dirty_on_bags`: `mock.bags[2770] = 7`, `fire("BAG_UPDATE_DELAYED")` → 2770 `buy` 0.
  - `test_dirty_on_character_update`: `mock.learned[2657] = true`, `ns.UpdateCharacter()` → 2840 `known.me` true.
  - `test_dirty_on_learned`: `fire("NEW_RECIPE_LEARNED", 2659)` → 2841 `known.me` true.
  - `test_dirty_on_forget`: `ns.ForgetChar("Mina")` → 2840, 2841 and 3576 `buy`.
  - `test_orphan_stays`: track 2657 (only Mina knows), forget Mina → still tracked, `plan.roots[1].known` has `me` false and no alts.
- [x] **Step 2: Run, expect failures**
- [x] **Step 3: Implement**.
- [x] **Step 4: Full suite, expect PASS** (`ContextTest` in `test_calculator.py` unmodified).
- [x] **Step 5: Commit**: `git commit -m "feat(model): combine tracked recipes into one plan with per-recipe shares"`

---

### Task 3: Craft countdown

**Files:**
- Modify: `ForeverProfessional/Characters.lua` (`ns.CountTrackedCraft`, `UNIT_SPELLCAST_SUCCEEDED` handler)
- Test: `tests/test_tracked.py` (`CountdownTest`)

**Interfaces:**
- Consumes: Task 1's mutators; `M.Yield`.
- Produces: `ns.CountTrackedCraft(spellID)`: quantity − 1 (crafts) or − `M.Yield(rec)` (items); ≤ 0 untracks. Handler: `UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)` with `unit == "player"`.

- [ ] **Step 1: Write the failing tests**
  - `test_craft_counts_down`: 3932 ×2, `fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 3932)` → 1.
  - `test_last_craft_untracks`: 3932 ×1 → after the cast, not tracked.
  - `test_items_by_yield`: 2659 ×5 items → 3 → 1 → untracked.
  - `test_other_unit_ignored`: unit `"target"` → unchanged.
  - `test_untracked_spell_ignored`: a cast of 3926 (not tracked) → list unchanged, no error.
  - `test_plan_follows_countdown`: 3932 ×2 → after one cast `ns.TrackedPlan()` has 4363 need 1.
- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "feat(chars): count tracked recipes down as they're crafted"`

---

### Task 4: Tooltip lines

**Files:**
- Modify: `ForeverProfessional/Tooltip.lua` (`ns.TrackedLines`, `ns.TRACKED_TOOLTIP_MAX = 5`, `OnItem` adds both blocks)
- Modify: `ForeverProfessional/Locale.lua` (`NEEDED_FOR`, `NEEDED_MORE`, `TRACKED_TOTAL`)
- Test: `tests/test_tracked.py` (`TrackedTooltipTest`); `tests/test_tooltip.py` unmodified

**Interfaces:**
- Consumes: `ns.TrackedPlan()`, `M.RecipeDisplayName`.
- Produces: `ns.TrackedLines(itemID) -> { text... }` as in the spec; `OnItem` shows the tooltip when recipe lines or tracked lines were added, each block after a blank line.

- [ ] **Step 1: Run the tooltip tests as the pin**: `mise exec -- python -m unittest tests.test_tooltip -v` (PASS before any change).
- [ ] **Step 2: Write the failing tests** (track 3932 and 3938; `GameTooltip:SetItemByID`)
  - `test_lines_for_shared_reagent`: 2841 → a blank line, then `Needed for: Spell 3932 (1)`, `Needed for: Spell 3938 (2)`, `Tracked total: 0 / 3`, in that order.
  - `test_raw_through_intermediates`: 2770 → `(6)`, `(1)`, `0 / 7`; `mock.bags[2770] = 4`, `fire("BAG_UPDATE_DELAYED")`, hover again → `4 / 7`.
  - `test_one_recipe`: 2880 → only `Needed for: Spell 3938 (1)` and its total.
  - `test_not_needed`: 2449 → no tracked lines, tooltip not re-shown by us.
  - `test_gone_after_untrack`: untrack both, hover 2841 again → no `Needed for` line.
  - `test_cap`: track 3922, 3926, 2659, 3932, 3938; `ns.TRACKED_TOOLTIP_MAX = 2`; hover 2770 → two `Needed for` lines, then `and 3 more`, then the total.
  - `test_tracked_error_swallowed`: make `ns.TrackedPlan` raise → hovering any item adds nothing, `mock.errors` has one entry, other post-calls still run.
- [ ] **Step 3: Run, expect failures**
- [ ] **Step 4: Implement**.
- [ ] **Step 5: Full suite, expect PASS** (`test_tooltip.py` unmodified).
- [ ] **Step 6: Commit**: `git commit -m "feat(tooltip): show which tracked recipes need an item"`

---

### Task 5: Detail action row

**Files:**
- Modify: `ForeverProfessional/UI/Detail.lua` (`DETAIL_HEADER_H` 100, action row: `h.trackButton`, `h.calcButton` moved, `h.trackedText`; `RenderHeader` sets them)
- Modify: `ForeverProfessional/Locale.lua` (`TRACK`, `UNTRACK`, `TRACKED_QTY`)
- Test: `tests/test_tracked.py` (`DetailTrackTest`, `open_addon(CALC)` as in `test_ui.py`, then `seed`, `SelectProfession(202)`, `SelectRecipe(3932)`); `tests/test_detail.py` and `tests/test_calculator.py` unmodified

**Interfaces:**
- Consumes: Task 1's `ns.TrackRecipe`, `ns.UntrackRecipe`, `ns.GetTracked`, `ns.TrackedText`.
- Produces: `detail.header.trackButton`, `detail.header.trackedText`; `UI.ToggleTracked(line, spellID)`.

- [ ] **Step 1: Run the pins**: `mise exec -- python -m unittest tests.test_detail tests.test_calculator -v` (PASS).
- [ ] **Step 2: Write the failing tests**
  - `test_action_row`: `trackButton` label `"Track"`, `calcButton` shown, `trackedText` empty.
  - `test_track_toggle`: click Track → `tracked(a) == [(3932, 202, 1, "crafts")]`, label `"Untrack"`, `trackedText` `"Tracked: 1 craft"`; click again → untracked, `"Track"`, empty text.
  - `test_tracked_text_items`: 2659 ×6 items tracked, select it on Mining → `"Tracked: 6 items"`.
  - `test_follows_countdown`: tracked 3932 ×2, cast once → `"Tracked: 1 craft"` without reselecting.
  - `test_action_row_fits`: at 900×540, Track + Calculate + `"Tracked: 999 crafts"` (mock string width) + gaps ≤ `UI.DetailContentWidth()`; `UI.DetailVisibleHeight() >= 340`.
- [ ] **Step 3: Run, expect failures**
- [ ] **Step 4: Implement**.
- [ ] **Step 5: Full suite, expect PASS**
- [ ] **Step 6: Commit**: `git commit -m "feat(ui): detail action row with Track and Calculate"`

---

### Task 6: Calculator driven by sources (no behaviour change)

**Files:**
- Modify: `ForeverProfessional/UI/Calculator.lua` (`calc.source`; renderers take the plan from it; `UI.OpenPlanPanel(source)`; the recipe source wraps today's quantity row; `M.MakesSeveral` replaces the inline multi test)
- Test: `tests/test_tracked.py` (`PlanSourceTest`); `tests/test_calculator.py` unmodified

**Interfaces:**
- Produces: `UI.OpenPlanPanel(source)` with `source = { kind, title, icon, Plan = fn() -> plan, tabs = { {key, label}... }, render = { [key] = fn(plan, y, width, pending) -> y } (optional extra tabs), showQuantity = bool, onRefresh = fn (optional) }`; `UI.calc.source`; `UI.OpenCalculator(spellID)` opens the recipe source.

- [ ] **Step 1: Run the pin**: `mise exec -- python -m unittest tests.test_calculator -v` (PASS).
- [ ] **Step 2: Write the failing tests**
  - `test_open_custom_source`: a source whose `Plan` returns the 3932 + 3938 plan, tabs Shopping / Steps / Tree, no quantity row → title shown, quantity row hidden, shopping rows equal the fixture's combined shopping.
  - `test_custom_tab`: a source with an extra `"extra"` tab and render function → selecting it calls the function and draws its rows.
  - `test_calculator_source_kind`: Calculate on 3932 → `UI.calc.source.kind == "recipe"`.
- [ ] **Step 3: Run, expect failures**
- [ ] **Step 4: Implement** the refactor; keep every `UI.*Calc*` function name the existing tests use.
- [ ] **Step 5: Full suite, expect PASS** (`test_calculator.py` unmodified).
- [ ] **Step 6: Commit**: `git commit -m "refactor(ui): draw the calculator panel from a plan source"`

---

### Task 7: Track from the calculator

**Files:**
- Modify: `ForeverProfessional/UI/Calculator.lua` (`calc.track` on the quantity row; pre-fill on open)
- Modify: `ForeverProfessional/Locale.lua` (`TRACK_UPDATE`, `TRACKED`)
- Test: `tests/test_tracked.py` (`CalcTrackTest`, the calculator opened as in `PanelBase`)

**Interfaces:**
- Consumes: Task 1's mutators; the recipe source.
- Produces: `UI.calc.track` (label `L.TRACK` / `L.TRACK_UPDATE` / disabled `L.TRACKED`).

- [ ] **Step 1: Write the failing tests**
  - `test_track_button`: Calculate on 3932, quantity 3, click Track → `[(3932, 202, 3, "crafts")]`; button disabled, `"Tracked"`.
  - `test_update`: then quantity 5 → `"Update"`, enabled; click → quantity 5.
  - `test_prefill`: 2659 tracked ×6 items; Calculate on it → `qty` `"6"`, `unitKey` `"items"`, button `"Tracked"`.
  - `test_items_unit_saved`: Calculate on 2659, Items 3, Track → `(2659, 186, 3, "items")`.
  - `test_detail_follows`: after tracking from the calculator, Back → the detail's Track button reads `"Untrack"`.
  - `test_quantity_row_fits`: at 900×540, label + box + unit switch + `"4 crafts, 2 extra"` + Track button + gaps ≤ the panel's inner width.
- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "feat(ui): track a recipe from the calculator"`

---

### Task 8: Tracked panel and header button

**Files:**
- Create: `ForeverProfessional/UI/Tracked.lua` (tracked source, Recipes tab rows, header button)
- Modify: `ForeverProfessional/ForeverProfessional_Camelot.toc` (after `UI\Calculator.lua`)
- Modify: `ForeverProfessional/UI/Window.lua` (header button placement left of the Skill stat; `UI.Refresh` updates its count)
- Modify: `ForeverProfessional/UI/Calculator.lua` (only if the quantity box needs to be shared with the Recipes rows: expose `UI.CreateQuantityBox(parent, get, set)`)
- Modify: `ForeverProfessional/Locale.lua` (`TRACKED_N`, `TRACKED_TITLE`, `TRACKED_RECIPES`, `TRACKED_EMPTY`)
- Test: `tests/test_tracked.py` (`TrackedPanelTest`, `open_addon(CALC)` then `seed`)

**Interfaces:**
- Consumes: `UI.OpenPlanPanel`, `ns.TrackedPlan`, `ns.TrackedList`, the mutators, `ns.CrafterText`, `M.MakesSeveral`.
- Produces: `UI.headerTracked`; `UI.OpenTracked()`, `UI.ToggleTrackedPanel()`; recipe rows in `UI.calc.rendered` as `{ kind = "tracked", spellID, quantity, unit, crafter, widget }`.

- [ ] **Step 1: Write the failing tests**
  - `test_header_button`: `"Tracked"` with nothing tracked; after tracking 3932 and 2659 → `"Tracked 2"`.
  - `test_opens_and_toggles`: click → panel shown, `source.kind == "tracked"`, title `"Tracked recipes"`, tab `recipes`, quantity row hidden; click again → hidden.
  - `test_recipes_rows`: 3932 ×1 and 2659 ×6 items → rows `(3932, 1, "crafts", "You")`, `(2659, 6, "items", "Mina")`; the unit switch only on 2659; tab label `"Recipes 2"`.
  - `test_edit_quantity`: type `"3"` in 3932's box → `ns.GetTracked(3932).quantity == 3`; `"abc"` then focus lost → back to `"3"`.
  - `test_unit_switch`: 2659 → Crafts → `unit == "crafts"`, quantity 6.
  - `test_untrack_row`: click 3932's untrack button → row gone, header `"Tracked 1"`.
  - `test_combined_tabs`: 3932 + 3938 → Shopping rows equal the fixture's combined shopping (`"Shopping 5"`); Steps rows `[2840, 3576, 4359, 2841, 4363, 4366, 4371]`; Tree has two depth-0 rows.
  - `test_switch_and_reset`: in Tree, switch 2841 to Buy → Shopping lists 2841; Reset → back to craft.
  - `test_empty`: untrack everything → `.message` `L.TRACKED_EMPTY` on Recipes and on Shopping, no rows.
  - `test_row_click_selects_recipe`: click 2659's name → `UI.state.line == 186`, `UI.state.selected == 2659`, panel hidden.
  - `test_live_updates`: `mock.bags[2770] = 7`, `fire("BAG_UPDATE_DELAYED")` → Copper Ore row checked; a cast of 3932 → its row quantity drops.
  - `test_closes`: `SelectRecipe(3926)` → hidden; reopen, `/fp` to close the window → hidden.
  - `test_never_blizzard_tracking_panel`: after every action above, `mock.blizzardTracked` is nil.
  - `test_fits_minimum_window`: at 900×540, the header button's right edge stays left of the Skill stat and its left edge right of the profession name (longest: Leatherworking, mock string widths); a Recipes row with the unit switch keeps `nameW >= 120`.
- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement**; add `UI\Tracked.lua` to the TOC (the tests load the TOC).
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "feat(ui): tracked recipes panel with the combined shopping list"`

---

### Task 9: Docs

**Files:**
- Modify: `README.md` (Features / How to use: tracking, the Tracked panel, tooltip lines, the countdown)
- Modify: `AGENTS.md` (Layout: `UI/Tracked`; `Characters` gains the tracked list and its plan; `Model` gains plan shares; `Tooltip` gains tracked lines; `UI/Calculator` draws plan sources; saved `ns.db.tracked`; client fact for `UNIT_SPELLCAST_SUCCEEDED` only once checked in game)

- [ ] **Step 1:** Update both files; don't touch `CHANGELOG.md` (rewritten at release time) or `docs/ideas.md`.
- [ ] **Step 2:** Full suite, expect PASS.
- [ ] **Step 3: Commit**: `git commit -m "docs: describe tracked recipes and the shopping list"`

---

## After Task 9

Run the full suite once more, then hand the user the spec's in-game checklist (new Lua file: full client
restart), on a character with an alt that knows an intermediate. Open the pull request into `develop` only
when the user asks, with `Closes #4`.

## Implementation notes

(Filled in during implementation: extra exports, deviations, commits.)
