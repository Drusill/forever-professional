# Small-sample drop rates: design

Small change to the data pipeline (`tools/`). Approved approach: A, minimum sample.

## Why

ForeverDB build 2026-11-21 added Drop Tables (observed loot counts) as a source. Some of its drop rates rest on one drop in a few kills. Our baked drop rows are `{npc, rate}` and sort by rate, so these outrank rates measured over thousands of kills. Example: Alchemy 3230's top source became "Kolkar Packhound 9.09%" (1 drop in 11 kills) instead of Councilman Hartin at 0.5%. The addon trusts the pipeline's order: the first drop is the recipe's main source in the list, and cards follow data order. Players would be sent to farm the wrong mob.

## Goals

- A drop rate that rests on fewer than 5 observed drops doesn't rank, and doesn't show a number.
- The NPC stays listed: an observed drop is real evidence of a source.
- Rates from other sources are untouched.

## Non-goals

- Showing sample sizes in the UI ("1 of 25 kills"). That was approach B, possibly later.
- Changing the data format or any addon code.

## Anti-goals

- Losing a rate that didn't come from the small sample.
- Hiding an NPC that really drops the item.

## Facts the design rests on

- ForeverDB `drop[item] = [[npc, rate×100], …]` (909 = 9.09%; 0 = unknown).
- ForeverDB `seen["c<npc>"][item] = [drops, kills]`. Only creature keys (`c`) exist: object and container drops have no counts.
- A count doesn't mean the rate came from it: item 6211 from NPC 2373 has 3.88% (also in the previous data) but a count of 1 of 11 (9.09%). Another source supplied that rate.
- In this build, 131 drop rows on recipe items have counts: 118 rest on 1 drop, 11 on 2, 2 on 5 or more (the two new Cooking recipes: 7 of 121, 6 of 124). 91 of the 131 are on classic recipes.

## Approaches

- **A. Minimum sample in the pipeline (picked).** A rate computed from fewer than 5 drops is baked as unknown. Cheapest fix for the misleading order; no format or UI change.
- **B. Bake the counts and show them.** Cards say "1 of 25 kills", small samples sort after measured rates. More useful on new Forever drops, but touches the format, the docs, the Model, the cards and their tests. Deferred.
- **C. Rank by a statistical lower bound.** Dropped: 1 of 11 kills still has a 1.6% lower bound, above a well-measured 0.5%, and with many small samples some are lucky.

## Design

1. `tools/fpdata/foreverdb.py`, `drops()`: a rate becomes unknown (`None`) when ForeverDB has a count for that NPC and item, the rate equals drops ÷ kills (to ForeverDB's 0.01% precision), and drops is below a named constant `MIN_OBSERVED_DROPS = 5`. Rows with no count, or a rate that doesn't match the count, keep their rate.
2. Merge, sorting, the 12-drop cap and `dropTotal` stay as they are. Unknown rates already sort after known ones, so on classic world-drop recipes a set-aside NPC usually falls outside the 12 kept, but is still counted.
3. `tools/REPORT.md`: one line with how many rates were set aside for a small sample.
4. `tools/README.md`: update the Drops merge rule. Credit Drop Tables (CC BY-SA 4.0, via ForeverDB), since its NPC lists still end up in the data (my call).
5. Tests: pipeline unit tests for the three cases (small sample matching the rate → unknown; 5 or more drops → kept; rate not matching its count → kept). Rebuild the data; the two addon tests that failed on Alchemy 3230 pass again with Councilman Hartin back on top.

## Known limit

If ForeverDB replaced an older rate with a small-sample one, the older number isn't in the file any more; that NPC shows "rate unknown". Worth raising with the ForeverDB maintainers if it matters.

## Left to the builder

Function and test names, where the constant lives, the report wording.

## Commits

1. This design.
2. Pipeline fix, tests, README rule and credit.
3. Data update: lock (client build 1.60.1.71037, ForeverDB 2026-11-21), data and report together.

The uncommitted notes in `AGENTS.md` and `tools/README.md` that predate this work stay out of these commits; only this change's README lines get staged.
