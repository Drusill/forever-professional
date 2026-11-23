# Recipe list filters: design

Date: 2026-11-22. Issue: #2. Status: awaiting approval.

## Intent

A profession has up to a few hundred recipes, and the list can only be narrowed to All / Learned / Missing
plus a name search. Players want to see only what matters right now: recipes that still give skill, recipes
they can learn now, recipes from a given source, Forever's new recipes. A filter menu next to the
All / Learned / Missing control does that, and remembers the choices.

## Goals, non-goals, anti-goals

- Goals: a filter menu with four groups (Status, Source, New in Forever, Clear), saved across `/reload`,
  applied to the list, the category header counts, the All / Learned / Missing counts and the empty state;
  `Model.Flatten` driven by a list of predicates.
- Non-goals: per-profession or per-character filter sets; filtering by reagent, item level or category;
  a "would give skill if learned" filter (that's the skill-up planner, #5); changing the window header's
  `Recipes 12 / 179` stat.
- Anti-goals: touching Blizzard's profession window or its filters (`SetShowUnlearned` and friends);
  changing what All / Learned / Missing do today; a filter that silently hides recipes with no visible sign.

## Findings that shaped this

- `Model.Flatten(tree, opts)` (`Model.lua:195`) filters with one `opts.filter` string and `opts.search`.
  Category headers already count only matching recipes, and a search ignores collapsed categories.
- The All / Learned / Missing counts come from `Model.FilterCounts(line, isLearned)` and ignore the search;
  `tests/test_ui.py` `test_filter_counts_ignore_search` pins that.
- `ns.LearnableCount` (`Characters.lua:38`) holds the "learnable now" rule inline: not learned, the
  character has the profession, `skill >= (rec.learn or 0)`, not `rec.side` of the other faction.
- `Model.Difficulty(rec, skill)` returns `orange`, `yellow`, `green`, `grey` or `red`, and `neutral`
  when the skill is unknown.
- The client's menu API exists on 1.60.1 (`MenuUtil`, `WowStyle1DropdownTemplate`: Auctionator and Baganator
  use them), but the character selector is a hand-rolled popup (`UI/Window.lua`, `CreateCharMenu`), chosen
  in the alt-support design for the Journal look and for testing in the mock.
- Source types in the baked data, by recipe: vendor 764, drop 798, trainer 491, quest 135, object 228,
  container 213, auto 33, crafted 2, worldObject 1. 96 recipes have no `src` at all (all of them carry
  `unknown = true`). 921 recipes are `new`. Only 6 have `side`.
- The mock widget already supports `SetChecked`, `Enable`, `Disable`, `IsEnabled` and `SetEnabled`.

## Decisions (made with the user)

1. **Hand-rolled menu.** The character selector's popup becomes a reusable popup in `UI/Widgets.lua`;
   the filter menu uses it with checkbox rows.
2. **OR within a group, AND across groups.** Vendor OR Drop, AND New in Forever, AND the All / Learned /
   Missing choice, AND search. A recipe with several sources matches when any of them is checked.
3. **Skill-ups and Learnable now form one Status group, combined with OR.** Both checked shows "everything
   worth doing now".
4. **Six source entries.** Trainer (also `auto`, learned with the profession), Vendor, Drop, Quest, Other
   (container, object, crafted, worldObject) and Unknown source (no `src`).
5. **Counts.** Category header counts and the All / Learned / Missing counts follow the menu filters. The
   All / Learned / Missing counts still ignore the search, as today. The window header stat stays the
   profession's overall progress.
6. **One account-wide set** in `ns.db.filters`, like `ns.db.filter`. Switching profession or character
   keeps the same choices.
7. **Status without the profession: kept but ignored.** When the shown character lacks the profession,
   Skill-ups and Learnable now stay checked and saved, show greyed with a tooltip, and don't filter that tab.
8. **Visible and clearable.** The button reads `Filters (2)` and lights up when filters are in effect; the
   menu ends with `Clear filters`; the empty state says `No recipes match the filters.` with a Clear filters
   button.

## Approaches considered

| | Flatten input | Trade-off |
|---|---|---|
| **Chosen** | `opts.predicates`: a list of `fn(id, rec, learned) -> bool`, all must pass | One shape for the segmented choice and every menu group; each group is one OR predicate, so AND across groups is just "all pass". Search stays its own option because it also overrides collapsing. |
| Rejected | `opts.filter` plus a new `opts.filters` table | Flatten would know every filter rule; adding #5's planner filters would grow it again. |

| | Menu widget | Trade-off |
|---|---|---|
| **Chosen (user)** | Shared hand-rolled popup with checkbox rows | Journal look, same code as the character menu, fully testable in the mock. |
| Rejected | `MenuUtil.CreateContextMenu` with checkbox entries | Less drawing code, but Blizzard's look and heavy mocking. |

## Design

### Learnable rule, shared (`Characters.lua`)

- `ns.CanLearnNow(rec, skill, faction) -> bool`: `skill ~= nil`, `skill >= (rec.learn or 0)`, and not
  (`rec.side` set and `rec.side ~= faction`). Learned status is checked by the caller.
- `ns.LearnableCount` uses it, so the count on the rail and the filter can't drift apart.

### Predicates (`Model.lua`)

- `M.LearnedPredicate(filter)`: `nil` for `"all"`, `learned` for `"learned"`, `not learned` for `"missing"`.
- `M.SourceKeys(rec) -> {[key]=true}`: `trainer` for `trainer` or `auto`; `vendor`; `drop`; `quest`;
  `other` for `container`, `object`, `crafted`, `worldObject`; `unknown` when `rec.src` is missing or empty.
  `rec.src` is used as is: source types listed in `unverified` still count, as the row subtitle shows them.
- `M.FILTER_GROUPS`: the menu's order and grouping, used by the model and the UI:

  ```lua
  M.FILTER_GROUPS = {
      { key = "status", items = { "skillups", "learnable" }, needsProfession = true },
      { key = "source", items = { "trainer", "vendor", "drop", "quest", "other", "unknown" } },
      { key = "new",    items = { "new" } },
  }
  ```

- `M.FilterPredicates(filters, ctx) -> list`: one predicate per group with at least one checked item;
  items in a group combine with OR. `ctx = { skill, faction }` for the shown character.
  - `skillups`: learned and `M.Difficulty(rec, skill)` is `orange`, `yellow` or `green`.
  - `learnable`: not learned and `ns.CanLearnNow(rec, skill, faction)`.
  - source keys: `M.SourceKeys(rec)` holds a checked key.
  - `new`: `rec.new`.
  - The status group is left out when `ctx.skill` is nil (decision 7).
- `M.ActiveFilterCount(filters, hasProfession) -> number`: checked items that are in effect (status items
  don't count when `hasProfession` is false). Drives the button label and the empty state.
- `M.Flatten(tree, opts)`: `opts.filter` is replaced by `opts.predicates`. Each recipe passes when every
  predicate returns true for `(id, ns.Data.Recipes[tree.line][id], learned)` and the search matches.
  Return values and header entries are unchanged.
- `M.FilterCounts(line, isLearned, predicates)`: counts only recipes passing `predicates` (the menu ones,
  never the segmented one). `nil` means all, as today.

### Saved state (`Core.lua`)

- `DEFAULTS.filters = {}`: a flat set, `{ skillups = true, vendor = true, … }`. Unknown keys are ignored,
  so old or future saves load cleanly. No `db.version` bump: the field is new and optional.

### Window state and flow (`UI/Window.lua`, `UI/RecipeList.lua`)

- `UI.state.filters` points at `ns.db.filters` (set in `UI.Create`).
- `UI.MenuPredicates()` builds `M.FilterPredicates(UI.state.filters, ctx)` with the shown character's skill
  (`ns.CharSkill(line, UI.state.char)`) and faction (`ns.CharFaction(UI.state.char)`).
- `UI.RefreshList` passes `{ M.LearnedPredicate(s.filter), unpack(UI.MenuPredicates()) }` (minus the nil)
  to `Flatten`. `UI.RefreshFilterButtons` passes `UI.MenuPredicates()` to `FilterCounts`.
- `UI.SetFilterOption(key, on)` and `UI.ClearFilters()` write `ns.db.filters`, then refresh the list, the
  All / Learned / Missing counts, the filter button and the open menu. Clear filters leaves the
  All / Learned / Missing choice alone.
- Switching profession or character re-evaluates which status items are in effect (the menu greys them,
  the button count changes).

### Filter button and menu (`UI/Widgets.lua`, `UI/Window.lua`)

Toolbar, right to left: expand all, collapse all, All / Learned / Missing, **Filters**, search (takes the rest).

```
[Search…                  ] [Filters (2)] [All 179][Learned 3][Missing 176] [>][v]
                            +---------------------------+
                            | Status                    |
                            | [x] Skill-ups             |
                            | [ ] Learnable now         |
                            | Source                    |
                            | [ ] Trainer               |
                            | [x] Vendor                |
                            | [ ] Drop                  |
                            | [ ] Quest                 |
                            | [ ] Other                 |
                            | [ ] Unknown source        |
                            | ------------------------- |
                            | [ ] New in Forever        |
                            | ------------------------- |
                            |     Clear filters         |
                            +---------------------------+
```

- `UI.CreatePopup(parent, width)` (Widgets): the panel the character menu uses today, dialog strata, mouse
  enabled, hidden, with a row pool and `:Fit(rowCount, rowH)`. The character menu moves onto it unchanged.
- `UI.CreateCheckRow(parent)` (Widgets): a row button with a checkbox texture and a label;
  `:SetChecked(v)`, `:SetEnabled(v)` (greyed label and check when disabled, clicks ignored), and an optional
  tooltip shown on hover while disabled.
- `UI.CreateToggleButton(parent, label)` (Widgets): a flat text button like the segmented control's;
  `:SetText`, `:SetActive(v)` (gold label and border when filters are in effect).
- The menu stays open while toggling; it closes on a second click of the button, when the window hides,
  and when the character menu opens (and opening the character menu closes it). Only one popup at a time.
- Disabled status rows show the tooltip `L.FILTER_NEEDS_PROFESSION`.

### Empty state (`UI/RecipeList.lua`)

- With no entries and `M.ActiveFilterCount(...) > 0`: text `L.NO_RESULTS_FILTERED` and a `Clear filters`
  button under it that calls `UI.ClearFilters()`.
- Otherwise today's `L.NO_RESULTS` and no button.

### Strings (`Locale.lua`)

`FILTERS = "Filters"`, `FILTERS_COUNT = "Filters (%d)"`, `FILTER_STATUS = "Status"`,
`FILTER_SKILLUPS = "Skill-ups"`, `FILTER_LEARNABLE = "Learnable now"`, `FILTER_SOURCE = "Source"`,
`FILTER_TRAINER = "Trainer"`, `FILTER_VENDOR = "Vendor"`, `FILTER_DROP = "Drop"`, `FILTER_QUEST = "Quest"`,
`FILTER_OTHER = "Other"`, `FILTER_UNKNOWN = "Unknown source"`, `FILTER_NEW = "New in Forever"`,
`CLEAR_FILTERS = "Clear filters"`, `NO_RESULTS_FILTERED = "No recipes match the filters."`,
`FILTER_NEEDS_PROFESSION = "The shown character doesn't have this profession."`
(reuse existing `L.*` where one already says the same).

## Testing

Test first, one step at a time, `mise exec -- python -m unittest discover tests` after each.

- New `tests/test_filters.py` for the model and the window; the character menu tests in `tests/test_ui.py`
  (`SelectorTest`) must stay green through the popup refactor.
- Fixture: the mock Tester (Horde, Alchemy 120/150) with learned `2329` (grey at 120), `3171` (yellow) and
  `6617` (green); `ALTS` for the faction rule (Paly, Alliance, Cooking 30, can learn Alliance-only `2795`;
  Dru (Druid), Horde, Cooking 50, can't).
- Expected sets are computed in Python from `ns.Data.Recipes` so the tests survive data rebuilds.
- Covered: All / Learned / Missing pinned before the refactor; each status, source and New filter; OR inside
  a group; AND across groups; menu filters plus search; menu filters plus Learned / Missing; status ignored
  without the profession (and kept saved); the faction rule; `ns.LearnableCount` unchanged; saved choices
  surviving a reload of the addon; button label and active state; disabled rows and their tooltip; Clear
  filters (menu and empty state) keeping the segmented choice; All / Learned / Missing counts following the
  menu but not the search; the window header stat unchanged.

## Steps

On `feat/2-recipe-filters`, one Conventional Commit each, no push:

1. Shared learnable rule and predicate-driven `Flatten` / `FilterCounts`; All / Learned / Missing unchanged.
2. Menu filter predicates in the model.
3. Saved filters applied in the window: list, counts, empty state.
4. Shared popup in `Widgets.lua`; the character menu moves onto it.
5. Filter button and menu.
6. README and AGENTS updates.

## Left to the builder

Exact pixel layout of the button, menu rows and separators; checkbox textures (client art by name, e.g.
`Interface\Buttons\UI-CheckBox-Check`); whether a click outside closes the menu; final wording of the
tooltip; which extra real recipes the tests use.

## In-game checklist (after implementation)

No TOC change, so `/reload` is enough.

1. On a character with Alchemy: open `/fp`, open Filters. Check Skill-ups: only learned recipes in orange,
   yellow or green remain; the button reads `Filters (1)` and lights up; All / Learned / Missing counts change.
2. Add Learnable now: unlearned recipes at or under your skill appear too. Uncheck Skill-ups.
3. Check Vendor and Drop: recipes from either source; add New in Forever: only Forever's new ones among them.
4. Type in the search box: the list narrows further; All / Learned / Missing counts don't move.
5. Pick a combination that matches nothing: `No recipes match the filters.` with Clear filters; click it:
   everything is back and the All / Learned / Missing choice is unchanged.
6. `/reload` with filters on: they're still on.
7. Switch to a profession the character doesn't have (or to an alt without it): Skill-ups and Learnable now
   are greyed with the tooltip and don't filter; switch back: they apply again.
8. Open the character menu while the filter menu is open: only one stays open. Close the window: both close.
9. Check the toolbar at the minimum window width (900px): the search box still has room.
