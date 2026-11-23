# Learned Recipe Difficulty Implementation Plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax for tracking. One commit per task.

**Goal:** A learned recipe is never shown red, the Skill-ups filter keeps learned recipes that still give skill, and the data report lists recipes whose baked learn level is above their yellow threshold.

**Architecture:** `Model.Difficulty` and `Model.RangeText` take an optional `learned` argument; every caller already has it in scope. The data side stays in the pipeline: `tools/fpdata/report.py` flags `learn > yellow`, and learn levels checked in game go in `tools/overrides.json`.

**Tech Stack:** Lua 5.1 (WoW Forever client, interface 16001), Python 3.12 `unittest` + `lupa` tests against `tests/wow_mock.lua`; stdlib Python pipeline.

**Spec:** `docs/superpowers/specs/2026-11-23-learned-recipe-difficulty-design.md` (issue #11)

## Global Constraints

- Branch `fix/11-learned-recipe-difficulty` (off `develop`), one commit per task, don't push. Conventional Commits, no `Co-Authored-By` or AI attribution (user rule). The pull request into `develop` says `Closes #11`.
- Run `mise exec -- python -m unittest discover tests` after every Lua change, and `mise exec -- python -m unittest discover tools/tests` after every pipeline change. Each suite stays green.
- Observe each new test fail (RED) before the fix.
- Never hand-edit `ForeverProfessional/Data/` or the community addons. Changes under `tools/` (Tasks 2 and 3) were approved with issue #11.
- Reuse, don't re-implement: the colour rule lives only in `Model.Difficulty`; the learnable rule only in `ns.CanLearnNow`.
- Unlearned behaviour must not change: the existing `test_difficulty`, `test_range_text`, `test_learnable` and `test_skillups` cases stay as they are.

## Task 1: learned recipes are never red

**Files:** `ForeverProfessional/Model.lua`, `ForeverProfessional/UI/RecipeList.lua`, `ForeverProfessional/UI/Detail.lua`, `tests/test_model.py`, `tests/test_filters.py`, `tests/test_ui.py`

- [x] **RED, model.** In `tests/test_model.py` add:

```python
    def test_difficulty_learned_ignores_learn_level(self):
        D = self.M.Difficulty
        rec = self.recipes171[3230]  # 50 / 80 / 100 / 120
        self.assertEqual(D(rec, 40), "red")              # unlearned: unchanged
        self.assertEqual(D(rec, 40, False), "red")
        self.assertEqual(D(rec, 40, True), "orange")     # learned: thresholds only
        self.assertEqual(D(rec, 120, True), "grey")
        helm = self.a.ns.Data.Recipes[164][9980]         # Ornate Mithril Helm, issue #11
        self.assertEqual(D(helm, 241, True), "yellow")

    def test_range_text_learned_learn_value_not_red(self):
        rec = self.recipes171[3230]
        self.assertTrue(self.M.RangeText(rec, 10, True).startswith("|cffff804050|r"))
        self.assertTrue(self.M.RangeText(rec, 10).startswith("|cffff202050|r"))
```

- [x] **RED, filter.** In `tests/test_filters.py` add a case: pick from `self.recs` the first recipe with `learn > 120` and `grey > 120` (computed in Python, so it survives rebuilds), add it to `mock.learned`, and assert `self.ids(["skillups"])` contains it, while `{3171, 6617}` stay in and 2329 stays out.
- [x] **RED, UI.** In `tests/test_ui.py` add a case: with that same recipe learned, its list row label does not start with `|cffff2020`, and its sub text equals `RangeText(rec, 120, True)`. After selecting it, the detail header title does not start with `|cffff2020`.
- [x] Run `mise exec -- python -m unittest discover tests`: the new tests fail.
- [x] **GREEN.** In `Model.lua`:

```lua
-- Colour of a recipe for the given skill; "neutral" when the skill is unknown. A learned recipe is
-- always craftable, so the learn level only makes an unlearned recipe red.
function M.Difficulty(rec, skill, learned)
    if not skill then return "neutral" end
    if not learned and rec.learn and skill < rec.learn then return "red" end
    ...
```

  `RangeText(rec, skill, learned)` colours the learn value red only when `not learned and skill and skill < rec.learn`. `RowSubtitle` calls `M.RangeText(rec, skill, true)` on its learned branch. The Skill-ups predicate calls `M.Difficulty(rec, ctx.skill, learned)`. `UI/RecipeList.lua:251` and `UI/Detail.lua:293` pass `learned`.
- [x] Run the addon suite: all green.
- [x] Commit: `fix(ui): never show a learned recipe as red`.

## Task 2: report recipes whose learn level is above yellow

**Files:** `tools/fpdata/report.py`, `tools/tests/test_pipeline.py`, `tools/REPORT.md` (regenerated)

- [ ] **RED.** In `tools/tests/test_pipeline.py`, build a report over a catalog with one recipe `learn 245 / yellow 240` and one `learn 240 / yellow 240`; assert a section `## Learn level above the yellow threshold (1)` and a line with the first recipe's spell and `learn 245, yellow 240`, and no line for the second.
- [ ] Run `mise exec -- python -m unittest discover tools/tests`: the new test fails.
- [ ] **GREEN.** In `build_report`, after "No known source", add the section using `recipe_label`, sorted like the others (`not new`, skill line, spell) and capped at `list_limit`, with the line "Learned recipes ignore the learn level in game; check the recipe item's tooltip and fix confirmed values in `tools/overrides.json`."
- [ ] Run `python tools/build_data.py` (pinned sources, no `update`): `ForeverProfessional/Data/` has no diff, `tools/REPORT.md` gains the section with 30 entries.
- [ ] Commit: `feat(tools): report learn levels above the yellow threshold`.

## Task 3: fix confirmed learn levels (needs the in-game check)

**Files:** `tools/overrides.json`, `ForeverProfessional/Data/Recipes/*.lua` (regenerated), `tools/REPORT.md` (regenerated)

- [ ] In game: for each listed recipe you can reach (start with the Blacksmithing plans), read "Requires <Profession> (N)" on the recipe item's tooltip. 9980 is already known to be at most 241.
- [ ] For each confirmed value, add to `tools/overrides.json` under `recipes`: `"9980": { "learn": N, "_evidence": "Plans: Ornate Mithril Helm tooltip, <date>, client 1.60.1" }`. Leave unconfirmed recipes alone.
- [ ] Run `python tools/build_data.py` and both suites. Check the diff in `Data/` touches only the overridden `learn` values, and the report section shrinks by the same number.
- [ ] Commit: `fix(data): correct learn levels confirmed in game`.

## Task 4: in-game check and wrap-up

- [ ] In game, as the Blacksmith at 241: Ornate Mithril Helm row and detail title are yellow, the learn value in the range text is not red, and Skill-ups shows the helm.
- [ ] An unlearned recipe above your skill is still red.
- [ ] Add a line for the fix to `CHANGELOG.md` only when the next release's notes are written (Releasing, step 1).
- [ ] Open the pull request into `develop` with `Closes #11` when the user asks.
