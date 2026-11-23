# Recipe List Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A filter menu next to All / Learned / Missing narrows the recipe list by status (skill-ups, learnable now), source type and New in Forever, saved across `/reload`, with counts and the empty state following it.

**Architecture:** `Model.Flatten` takes a list of predicates; the segmented choice and each menu group become one predicate each (OR inside a group, AND across). `Model.lua` owns the rules (`LearnedPredicate`, `SourceKeys`, `FILTER_GROUPS`, `FilterPredicates`, `ActiveFilterCount`); `Characters.lua` shares the learnable rule (`ns.CanLearnNow`) with `ns.LearnableCount`. The window keeps the choices in `ns.db.filters`. The character selector's popup moves to `UI/Widgets.lua` as `UI.CreatePopup`, and the filter menu reuses it with checkbox rows.

**Tech Stack:** Lua 5.1 (WoW Forever client, interface 16001), Python 3.12 `unittest` + `lupa` tests against `tests/wow_mock.lua`.

**Spec:** `docs/superpowers/specs/2026-11-22-recipe-filters-design.md` (issue #2)

## Global Constraints

- Branch `feat/2-recipe-filters` (off `develop`), one commit per task, don't push. Conventional Commits, no `Co-Authored-By` or AI attribution (user rule). The pull request into `develop` says `Closes #2`.
- Run `mise exec -- python -m unittest discover tests` after every change; the whole suite must stay green.
- No new Lua file, so no TOC change. If one becomes necessary, it goes in the TOC with ` [AllowLoadGameType camelot][ExcludeLoadGameType classic]`.
- Never edit `ForeverProfessional/Data/`, `tools/`, or the community addons. Never call Blizzard profession filter setters (`SetShowUnlearned` etc.).
- Every user-visible string goes through `Locale.lua` (`L.*`).
- Item/spell names stay live (not baked).
- Reuse, don't re-implement: the learnable rule lives only in `ns.CanLearnNow`; the colour rule only in `Model.Difficulty`; the menu order only in `Model.FILTER_GROUPS`.

## Shared test fixture

`tests/test_filters.py` (created in Task 1) uses the mock Tester (`Player-1-0000000A`, Horde, Alchemy 120/150,
Herbalism 90/150) and:

```python
FILTERS = "mock.learned = { [2329] = true, [3171] = true, [6617] = true }"
```

| Recipe | Line | Data | At skill 120 | Used for |
|---|---|---|---|---|
| 2329 | 171 | learn 15, grey 95, `trainer` | grey, learned | not a skill-up |
| 3171 | 171 | learn 90, yellow 120, green 140, grey 160, `trainer` | yellow, learned | skill-up |
| 6617 | 171 | learn 60, green 110, grey 130, `vendor` | green, learned | skill-up, vendor |
| 3173 | 171 | learn 120, `trainer` | not learned | learnable now (edge: skill == learn) |
| 11452 | 171 | learn 215, no `src` (`unknown`) | not learned | not learnable; Unknown source |
| 7183 | 171 | `auto` | — | counts as Trainer |
| 3230 | 171 | `drop`, `object` | — | Drop and Other |
| 1251744 | 171 | `quest`, `new` | — | Quest, New |
| 2795 | 185 | learn 25, `side = "Alliance"` | — | faction rule with `ALTS` (Paly can, Dru (Druid) can't) |

Expected sets are computed in Python from `a.ns.Data.Recipes[171]` (as `test_chars.py` does for
`LearnableCount`), so the tests survive data rebuilds. Helpers in the file:

```python
DIFFICULTY_OK = {"orange", "yellow", "green"}

def recipes(a, line):
    return {k: v for k, v in a.ns.Data.Recipes[line].items()}

def srcs(rec):
    return list(rec.src.values()) if rec.src else []
```

## Review Focus

- **All / Learned / Missing unchanged.** Task 1 pins today's results and counts before touching `Flatten`; `test_ui.py` `test_filter_buttons` and `test_filter_counts_ignore_search` must pass unmodified.
- **Status filter on a profession the shown character lacks:** no error, status ignored, checks kept. Test: Task 3 `test_status_ignored_without_profession`.
- **Saved filters with unknown keys** (old or future saves): load and are ignored. Test: Task 3 `test_unknown_saved_keys_ignored`.
- **Learnable rule drift:** `ns.LearnableCount` and the Learnable now filter agree on every profession. Test: Task 2 `test_learnable_matches_learnable_count`.
- **Two popups open at once:** opening one closes the other. Test: Task 5 `test_one_popup_at_a_time`.
- **Collapsed categories with filters on:** filters never expand them (only search does, as today). Test: Task 3 `test_filters_keep_collapsed`.

---

### Task 1: Predicate-driven Flatten, shared learnable rule

**Files:**
- Modify: `ForeverProfessional/Model.lua` (`Flatten`, `FilterCounts`, new `LearnedPredicate`)
- Modify: `ForeverProfessional/Characters.lua` (`CanLearnNow`, `LearnableCount`)
- Modify: `ForeverProfessional/UI/RecipeList.lua` (`RefreshList`), `ForeverProfessional/UI/Window.lua` (`RefreshFilterButtons`)
- Modify: `tests/test_model.py` (`flat()` helper builds predicates)
- Test: `tests/test_filters.py` (new)

**Interfaces:**
- Produces:
  - `ns.CanLearnNow(rec, skill, faction) -> bool`: `skill ~= nil and skill >= (rec.learn or 0) and not (rec.side and rec.side ~= faction)`.
  - `M.LearnedPredicate(filter) -> fn|nil`: nil for `"all"` (or unknown), `function(id, rec, learned) return learned end` for `"learned"`, `not learned` for `"missing"`.
  - `M.Flatten(tree, opts)`: `opts.predicates` (list of `fn(id, rec, learned) -> bool`, may be nil or empty); `opts.filter` removed. `rec` is `ns.Data.Recipes[tree.line][id]`. Returns and entries unchanged.
  - `M.FilterCounts(line, isLearned, predicates)`: counts recipes passing every predicate; nil = all.

- [ ] **Step 1: Write the pinning tests** (they pass before the change)

`tests/test_filters.py` `PinTest` (login with `LEARNED` from `test_ui.py`, `mock.learned = { [2329], [3170], [7183] }`):
- `test_segmented_pinned`: through `UI.SetFilter`: `"learned"` → recipe ids `[2329, 3170, 7183]` sorted; `"missing"` → total − 3, without 2329; `"all"` → total. `UI.matchCount` matches each.
- `test_learnable_count_pinned`: `ns.LearnableCount(171)` equals the Python count of not-learned recipes with `(rec.learn or 0) <= 120` and no other-faction `side`.

- [ ] **Step 2: Run, expect PASS**: `mise exec -- python -m unittest tests.test_filters -v`

- [ ] **Step 3: Write the failing tests** (`PredicateTest` in `tests/test_filters.py`)
- `test_learned_predicate`: `M.LearnedPredicate("all")` is nil; `"learned"` returns true for `learned=true`, false otherwise; `"missing"` the reverse.
- `test_flatten_with_predicates`: `Flatten(BuildTree(171), { predicates = { LearnedPredicate("learned") }, isLearned = … })` gives the same ids and `(count, learned) == (3, 3)`.
- `test_flatten_and_of_predicates`: two predicates, `learned` and `id == 2329` → only `[2329]`.
- `test_flatten_empty_predicates`: `predicates = {}` and `predicates = nil` both give every recipe.
- `test_filter_counts_predicates`: `FilterCounts(171, isLearned, { fn returning id == 2329 })` → `(1, 1)`; without predicates → `(total, 3)`.
- `test_can_learn_now`: `CanLearnNow({ learn = 120 }, 120, "Horde")` true; `({ learn = 121 }, 120, …)` false; `({}, 0, …)` true; `({ learn = 1 }, nil, …)` false; `({ learn = 1, side = "Alliance" }, 300, "Horde")` false; same with `"Alliance"` true.

Update `tests/test_model.py` `flat()` to pass `predicates` built from `LearnedPredicate(filter)` instead of `filter`; its tests stay as they are.

- [ ] **Step 4: Run, expect failures** (nil function / unknown option): `mise exec -- python -m unittest tests.test_filters tests.test_model -v`

- [ ] **Step 5: Implement**
- `ns.CanLearnNow` in `Characters.lua`; `LearnableCount` calls it (`not learned and ns.CanLearnNow(rec, prof.skill or 0, c.faction)`).
- `M.LearnedPredicate`, the new `Flatten` (`Match` runs every predicate, then the search), `FilterCounts` with `predicates`.
- `UI.RefreshList` passes `predicates = { M.LearnedPredicate(s.filter) }` (skip nil); `RefreshFilterButtons` calls `FilterCounts` as before (no menu yet). Update the comment above `Flatten`.

- [ ] **Step 6: Full suite, expect PASS** (including `test_ui.py` filter tests unmodified): `mise exec -- python -m unittest discover tests`
- [ ] **Step 7: Commit**: `git commit -m "refactor(model): filter the recipe list with predicates"`

---

### Task 2: Menu filter predicates

**Files:**
- Modify: `ForeverProfessional/Model.lua`
- Test: `tests/test_filters.py`

**Interfaces:**
- Consumes: `LearnedPredicate`, predicate `Flatten`, `ns.CanLearnNow` (Task 1); `M.Difficulty`.
- Produces:
  - `M.SourceKeys(rec) -> {[key]=true}`: `trainer` ← `trainer`, `auto`; `vendor`; `drop`; `quest`; `other` ← `container`, `object`, `crafted`, `worldObject`; `unknown` when `rec.src` is nil or empty. Unlisted future types go to `other`.
  - `M.FILTER_GROUPS` exactly as in the spec (status with `needsProfession = true`, source, new).
  - `M.FilterPredicates(filters, ctx) -> list`: one predicate per group with a checked item, OR inside the group; status group skipped when `ctx.skill` is nil. `skillups`: `learned and DIFFICULTY_OK[M.Difficulty(rec, ctx.skill)]`. `learnable`: `not learned and ns.CanLearnNow(rec, ctx.skill, ctx.faction)`.
  - `M.ActiveFilterCount(filters, hasProfession) -> number`: checked items of `FILTER_GROUPS`, minus status items when `hasProfession` is false. Keys not in `FILTER_GROUPS` never count.

- [ ] **Step 1: Write the failing tests** (`MenuModelTest`, login with `FILTERS`; `flat(filters, segmented="all", search="")` builds `{ LearnedPredicate(segmented), unpack(FilterPredicates(filters, { skill = 120, faction = "Horde" })) }`)
- `test_source_keys`: `SourceKeys` of 7183 → `{trainer}`; 6617 → `{vendor}`; 3230 → `{drop, other}`; 1251744 → `{quest}`; 11452 → `{unknown}`.
- `test_skillups`: ids == `[3171, 6617]` (2329 is grey).
- `test_learnable`: ids == Python set (not learned, `learn <= 120`); contains 3173; excludes 11452 and 2329.
- `test_learnable_matches_learnable_count`: for every line the Tester has, `len(learnable ids) == ns.LearnableCount(line)`.
- `test_status_or`: `skillups` + `learnable` → union of the two previous sets.
- `test_each_source`: for each source key, ids == Python set of recipes whose mapped keys contain it.
- `test_sources_or`: `vendor` + `drop` → recipes with either.
- `test_new`: ids == Python set of `rec.new`.
- `test_and_across_groups`: `vendor` + `new` → recipes with vendor AND new; `skillups` + `vendor` → `[6617]`.
- `test_with_search`: `vendor` with a search for 6617's mock name (`"Spell 6617"`) → `[6617]`; with `"Spell 3171"` → empty.
- `test_with_segmented`: `learnable` + `"learned"` → empty; `skillups` + `"missing"` → empty; `learnable` + `"missing"` → same as `learnable`.
- `test_status_skipped_without_skill`: `FilterPredicates({ skillups = true, vendor = true }, { skill = nil })` has one predicate (source only).
- `test_active_filter_count`: `{ skillups, vendor, drop, new }` → 4 with profession, 3 without; `{ bogus = true }` → 0; `{}` → 0.

- [ ] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_filters -v`
- [ ] **Step 3: Implement** the four model functions and `FILTER_GROUPS`.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "feat(model): skill-up, learnable, source and new filters"`

---

### Task 3: Saved filters applied in the window

**Files:**
- Modify: `ForeverProfessional/Core.lua` (`DEFAULTS.filters`)
- Modify: `ForeverProfessional/UI/Window.lua` (`UI.Create`, `UI.MenuPredicates`, `UI.SetFilterOption`, `UI.ClearFilters`, `RefreshFilterButtons`)
- Modify: `ForeverProfessional/UI/RecipeList.lua` (`RefreshList`, empty state)
- Modify: `ForeverProfessional/Locale.lua` (`NO_RESULTS_FILTERED`, `CLEAR_FILTERS`)
- Test: `tests/test_filters.py`, `tests/test_addon.py` (`ns.db.filters` default)

**Interfaces:**
- Consumes: Task 2 model functions.
- Produces:
  - `ns.db.filters` (default `{}`), `UI.state.filters` (same table).
  - `UI.MenuPredicates() -> list` for the shown character and profession.
  - `UI.SetFilterOption(key, on)`, `UI.ClearFilters()` (leaves `UI.state.filter` alone). Both refresh the list (scroll to top), the segmented counts and, from Task 5, the filter button and menu (guard with `if UI.RefreshFilterMenu then …`).
  - `UI.list.empty` text switches between `L.NO_RESULTS` and `L.NO_RESULTS_FILTERED`; `UI.list.clearButton` shown only with active filters and no entries, its click calls `UI.ClearFilters()`.

- [ ] **Step 1: Write the failing tests** (`WindowFilterTest`, `open_addon(FILTERS)` as in `test_ui.py`)
- `test_default_filters`: fresh DB → `ns.db.filters` is an empty table (`test_addon.py`).
- `test_set_option_filters_list`: `SetFilterOption("skillups", true)` → recipe ids `[3171, 6617]`; `ns.db.filters.skillups == true`; `SetFilterOption("skillups", false)` → every recipe again.
- `test_saved_across_reload`: setup `ForeverProfessionalDB = { version = 2, filters = { vendor = true } }` + `FILTERS` → every listed recipe has `vendor` in `src`.
- `test_unknown_saved_keys_ignored`: setup `filters = { bogus = true, vendor = true }` → same as vendor alone, no error.
- `test_segmented_counts_follow_menu_not_search`: `SetFilterOption("vendor", true)` → All count == vendor recipe total, Learned == learned vendor recipes (`1`, 6617), Missing == the rest; then a search text → counts unchanged.
- `test_header_stat_unchanged`: with `vendor` on, `UI.header.recipesText.text == "3 / <total>"`.
- `test_category_counts_follow_filters`: with `vendor` on, every header entry's `count` sums to the vendor total.
- `test_status_ignored_without_profession`: `SetFilterOption("skillups", true)`, `UI.SelectProfession(185)` (Tester has no Cooking) → every Cooking recipe listed; `ns.db.filters.skillups` still true; back to 171 → `[3171, 6617]`.
- `test_faction_rule_with_alts`: setup `ALTS` + `FILTERS`; `SetFilterOption("learnable", true)`, `SelectProfession(185)`; `UI.SetChar("Player-1-0000000D")` (Paly) → 2795 listed; `UI.SetChar("Player-1-0000000C")` (Dru (Druid)) → 2795 not listed.
- `test_filters_keep_collapsed`: collapse a category, turn on `vendor` → that header is still `collapsed` (when it has vendor recipes).
- `test_empty_state_filtered`: `skillups` + `SetFilter("missing")` → no entries, `UI.list.empty.text == L.NO_RESULTS_FILTERED`, `clearButton.shown`; click it → entries back, `ns.db.filters` empty, `UI.state.filter == "missing"` still.
- `test_empty_state_plain`: no menu filters, search `"zzzz"` → `L.NO_RESULTS`, `clearButton` hidden.

- [ ] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_filters tests.test_addon -v`
- [ ] **Step 3: Implement** as listed. `RefreshList` builds `{ LearnedPredicate(s.filter), unpack(UI.MenuPredicates()) }`; `RefreshFilterButtons` passes `UI.MenuPredicates()` to `FilterCounts`. `UI.Refresh` (profession or character change) already calls both.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "feat(ui): apply saved recipe filters to the list"`

---

### Task 4: Shared popup, character menu on it

**Files:**
- Modify: `ForeverProfessional/UI/Widgets.lua` (`UI.CreatePopup`, `UI.CreateCheckRow`, `UI.CreateToggleButton`)
- Modify: `ForeverProfessional/UI/Window.lua` (`CreateCharMenu`, `OpenCharMenu` use the popup)
- Test: `tests/test_widgets.py`; `tests/test_ui.py` `SelectorTest` unchanged

**Interfaces:**
- Produces:
  - `UI.CreatePopup(parent, width) -> frame`: `UI.Panel` at 0.97 alpha, `DIALOG` strata, mouse enabled, hidden, `rows = {}`, `:Fit(rowCount, rowH)` sets height `12 + rowCount * rowH` (separators may add their own height through `:Fit(n, h, extra)`).
  - `UI.CreateCheckRow(parent) -> button`: `.check` texture, `.label`; `:SetChecked(v)` shows/hides the check; `:SetEnabled(v)` greys label and check, and `OnClick` does nothing while disabled; `.disabledTooltip` shown on `OnEnter` while disabled.
  - `UI.CreateToggleButton(parent, label) -> button`: flat backdrop like the segmented control, `.label`; `:SetText(s)` resizes to fit; `:SetActive(v)` gold label and border when true, muted when false; `.active`.

- [ ] **Step 1: Write the failing tests** (`tests/test_widgets.py`)
- `test_popup`: hidden, strata `DIALOG`, `Fit(5, 22)` → height `12 + 110`.
- `test_check_row`: `SetChecked(true)` shows `.check`; `SetEnabled(false)` → clicking doesn't call the handler; `OnEnter` with `disabledTooltip` set shows it in `GameTooltip`; enabled → no tooltip.
- `test_toggle_button`: `SetActive(true)` → `.active` and gold label colour; `SetActive(false)` → muted.

- [ ] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_widgets -v`
- [ ] **Step 3: Implement** the three widgets; `CreateCharMenu` returns `UI.CreatePopup(parent, MENU_W)` anchored as today; `OpenCharMenu` ends with `m:Fit(#list, MENU_ROW_H)`.
- [ ] **Step 4: Full suite, expect PASS** (`SelectorTest` untouched)
- [ ] **Step 5: Commit**: `git commit -m "refactor(ui): shared popup and checkbox row widgets"`

---

### Task 5: Filter button and menu

**Files:**
- Modify: `ForeverProfessional/UI/Window.lua` (toolbar, `UI.filterMenu`, `UI.OpenFilterMenu`, `UI.CloseFilterMenu`, `UI.ToggleFilterMenu`, `UI.RefreshFilterMenu`, char menu closes the filter menu)
- Modify: `ForeverProfessional/Locale.lua` (the remaining strings in the spec)
- Test: `tests/test_filters.py`

**Interfaces:**
- Consumes: `UI.CreatePopup`, `UI.CreateCheckRow`, `UI.CreateToggleButton` (Task 4); `UI.SetFilterOption`, `UI.ClearFilters` (Task 3); `M.FILTER_GROUPS`, `M.ActiveFilterCount` (Task 2).
- Produces:
  - `UI.filterButton` between the search box and the segmented control (search box `RIGHT` anchors to it).
  - `UI.filterMenu` with `UI.filterMenu.rows` keyed by item key (`rows.skillups`, `rows.vendor`, …), group headings, separators and `UI.filterMenu.clearRow`, built once from `M.FILTER_GROUPS`. Labels: `L["FILTER_" .. key:upper()]`, headings `L["FILTER_" .. group.key:upper()]` (the `new` group has no heading, only a separator).
  - `UI.RefreshFilterMenu()`: checks from `ns.db.filters`; status rows disabled with `disabledTooltip = L.FILTER_NEEDS_PROFESSION` when `ns.CharSkill(line, UI.state.char)` is nil; button text `L.FILTERS` or `L.FILTERS_COUNT:format(n)` and `SetActive(n > 0)` with `n = M.ActiveFilterCount(...)`. Called by `UI.Refresh`, `SetFilterOption` and `ClearFilters`.

- [ ] **Step 1: Write the failing tests** (`FilterMenuTest`, `open_addon(FILTERS)`)
- `test_button_in_toolbar`: `UI.filterButton.label.text == "Filters"`, not active; search box's `RIGHT` point is relative to `UI.filterButton`.
- `test_toggle_menu`: click button → `UI.filterMenu.shown`; click again → hidden.
- `test_menu_rows_follow_groups`: `rows` has exactly the ten item keys; `clearRow` exists; labels match the spec strings.
- `test_click_row_filters`: click `rows.vendor` → `ns.db.filters.vendor`, row checked, menu still open, button `"Filters (1)"` and active, list = vendor recipes; click again → unchecked, `"Filters"`.
- `test_disabled_status_rows`: `SelectProfession(185)` → `rows.skillups` and `rows.learnable` disabled with `disabledTooltip == L.FILTER_NEEDS_PROFESSION`; source rows enabled; with `skillups` saved, button reads `"Filters"` (not in effect).
- `test_clear_row`: `vendor` + `new` + `SetFilter("learned")`, click `clearRow` → `ns.db.filters` empty, every row unchecked, button `"Filters"`, `UI.state.filter == "learned"`.
- `test_one_popup_at_a_time`: open filter menu, click `UI.charButton` → char menu shown, filter menu hidden; click filter button → filter menu shown, char menu hidden.
- `test_menu_hides_with_window`: open, `/fp` to close → filter menu hidden.

- [ ] **Step 2: Run, expect failures**: `mise exec -- python -m unittest tests.test_filters -v`
- [ ] **Step 3: Implement** the button, menu and refresh; window `OnHide` closes both popups.
- [ ] **Step 4: Full suite, expect PASS**
- [ ] **Step 5: Commit**: `git commit -m "feat(ui): recipe filter menu in the toolbar"`

---

### Task 6: Docs

**Files:**
- Modify: `README.md` (Features / How to use: the filter menu)
- Modify: `AGENTS.md` (Layout row for `UI/Widgets`: popup, checkbox row, toggle button; Data format untouched)

- [ ] **Step 1:** Update both files; don't touch `CHANGELOG.md` (it's rewritten at release time) or `docs/ideas.md` (the issue tracks this).
- [ ] **Step 2:** Full suite, expect PASS.
- [ ] **Step 3: Commit**: `git commit -m "docs: describe the recipe filters"`

---

## After Task 6

Run the full suite once more, then hand the user the spec's in-game checklist (no TOC change: `/reload` is enough), on one character with Alchemy and one without. Open the pull request into `develop` only when the user asks, with `Closes #2`.
