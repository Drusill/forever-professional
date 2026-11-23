# Learned recipe difficulty: design

Date: 2026-11-23. Issue: #11. Status: draft, waiting for approval.

## Intent

A Blacksmith at 241 who learned Ornate Mithril Helm (spell 9980) from its quest sees the recipe in red, the
colour for "you can't make this". Blizzard's profession window shows it craftable. A known recipe is always
craftable: the learn level only limits learning it. The addon must never show a learned recipe as red, and
the baked learn levels that contradict the client's own colour ranges must be found and fixed.

## Goals, non-goals, anti-goals

- Goals: learned recipes are never red (list row name, detail header title, learn value in the range text);
  the Skill-ups filter includes learned recipes that still give skill; `tools/REPORT.md` lists the recipes
  whose learn level is above their yellow threshold; confirmed learn levels go in `tools/overrides.json`.
- Non-goals: changing the colour of unlearned recipes; re-deriving learn levels from a new data source;
  harvesting learn levels in game automatically.
- Anti-goals: hand-editing `ForeverProfessional/Data/`; clamping learn levels by a rule without checking them
  in game (a wrong learn level makes "Learnable now" lie in the other direction); calling Blizzard's
  profession filter setters.

## Findings that shaped this

- `Model.Difficulty(rec, skill)` (`Model.lua:368`) returns `red` when `skill < rec.learn`, with no notion of
  learned. Callers: the list row (`UI/RecipeList.lua:251`), the detail header (`UI/Detail.lua:293`) and the
  Skill-ups predicate (`Model.lua:315`), which keeps learned recipes whose colour is orange, yellow or green,
  so a learned "red" recipe drops out of it. All three callers already have `learned` in scope.
- `Model.RangeText(rec, skill)` (`Model.lua:384`) colours the learn value red when `skill < rec.learn`.
  `RowSubtitle` uses it for learned recipes only (`Model.lua:706`).
- `learn` comes from WhatsTraining's `skill` (Classic values, `tools/fpdata/whatstraining.py:26`).
  yellow / grey come from Forever's `SkillLineAbility` (`TrivialSkillLineRankLow/High`), green is their
  midpoint (`tools/fpdata/merge.py:43`). The client's `MinSkillLineRank` is 1 for these spells, so the client
  table can't give the learn level.
- 30 baked recipes have `learn > yellow`: Blacksmithing 9957, 9972, 9979, 9980, 16991, 22757, 23650, 23652,
  23653; Leatherworking 10619, 10630, 10632, 10650, 19048, 24655, 1255000-1255003; Tailoring 19435, 26086,
  1257426-1257431; Engineering 9273; Mining 3304; Cooking 1229737. Example: 9980 is learn 245 / yellow 240 /
  grey 260, learned in game at 241, so Forever's real requirement is at most 241.
- No item table (`RequiredSkillRank`) is in the pipeline's sources, so the plans' real requirement can only be
  read from the recipe item's tooltip in game ("Requires Blacksmithing (N)").

## Design

1. `Model.Difficulty(rec, skill, learned)`: when `learned` is true, skip the learn check. The colour then
   comes from the yellow / green / grey thresholds only. 9980 at 241 becomes yellow (yellow 240, green 250),
   matching the client's ranges. Without `learned` (nil or false) the behaviour is unchanged.
2. `Model.RangeText(rec, skill, learned)`: the learn value is orange when learned, red only when not learned
   and out of reach. `RowSubtitle` passes `learned`.
3. Callers pass `learned`: the list row, the detail header, the Skill-ups predicate.
4. `tools/fpdata/report.py` gets a section "Learn level above the yellow threshold (N)", listing each recipe
   with its learn and yellow values, so new cases show up on every rebuild.
5. After the in-game check, each confirmed learn level goes in `tools/overrides.json` with `_evidence`
   (character, skill, tooltip text), then the data is rebuilt.

## Tests

- `tests/test_model.py`: a learned recipe below its learn level is never red, and takes its colour from the
  thresholds; unlearned behaviour stays as today (existing `test_difficulty` and `test_range_text` unchanged).
- `tests/test_filters.py`: Skill-ups includes a learned recipe below its learn level that is still orange,
  yellow or green.
- `tests/test_ui.py`: the list row and detail header title of such a recipe are not red.
- `tools/tests/test_pipeline.py`: the report lists a recipe with `learn > yellow` and leaves out one with
  `learn <= yellow`.

## Open question

- Which learn levels are confirmed in game. Only those go in `tools/overrides.json`; the rest stay as baked
  and stay listed in the report.
