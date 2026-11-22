# Small-sample drop rates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake a creature drop rate as unknown when ForeverDB computed it from fewer than 5 observed drops, so it can't outrank measured rates.

**Architecture:** The rule lives in `ForeverDB.drops()` (`tools/fpdata/foreverdb.py`), which already turns ForeverDB rows into `(npc, rate|None)`. Merge, sorting, the 12-drop cap and `dropTotal` are untouched: unknown rates already sort after known ones. The reader records which (item, NPC) pairs it set aside, and the report prints the count.

**Tech Stack:** Python 3 standard library (`unittest`), the existing `tools/` pipeline.

**Spec:** `docs/superpowers/specs/2026-11-21-small-sample-drop-rates-design.md`

## Global Constraints

- Standard library only; Python 3.9+ (`tools/README.md`).
- Never hand-edit `ForeverProfessional/Data/`; regenerate it with `tools/build_data.py`.
- The baked Lua data format and the addon code don't change.
- Threshold: `MIN_OBSERVED_DROPS = 5`.
- Commit the lock, the data and the report together.
- The pre-existing uncommitted notes in `AGENTS.md` and `tools/README.md` stay out of every commit.
- Run Python as `mise exec -- python` (in Git Bash, `python` resolves to the Windows Store stub).

## Review Focus

- A row whose rate is 0 (unknown) but has a count: stays `None` and is not counted as set aside.
- A count with 0 kills: treated as no count (no division by zero); the rate is kept.
- The same recipe item read twice (several recipes share it): the set-aside count doesn't double.
- Rounding: ForeverDB stores whole hundredths of a percent, so 7 of 121 (5.785%) is stored as 579; that has to count as "came from the count".
- Exactly 5 drops is kept; 4 is set aside.

Each line is pinned by `test_small_sample_rates` / `test_small_samples_recorded_once` in Task 1.

---

### Task 1: Set aside small-sample rates in the pipeline

**Files:**
- Modify: `tools/fpdata/foreverdb.py` (module docstring, new constant, `__init__`, `drops()` at lines 65-73)
- Modify: `tools/fpdata/report.py` (after the "NPCs: …" line, ~line 62)
- Modify: `tools/README.md` (Drops merge rule, line 45; ForeverDB row of the Sources table)
- Modify: `README.md:54` (License line)
- Test: `tools/tests/test_pipeline.py` (new class `SmallSampleTests`)

**Interfaces:**
- Produces: `foreverdb.MIN_OBSERVED_DROPS = 5`; `ForeverDB.small_samples: set[tuple[int, int]]` of `(item_id, npc_id)` pairs whose rate was set aside, filled by `drops()`; `ForeverDB.drops(item_id) -> list[tuple[int, float | None]]` keeps its signature.
- ForeverDB data read: `drop[item] = [[npc, rate×100], …]` (0 = unknown) and `seen["c<npc>"][item] = [drops, kills]`.

- [ ] **Step 1: Write the failing tests** in `tools/tests/test_pipeline.py`

```python
def sample_fdb():
    return ForeverDB({
        "drop": {"500": [[1, 909], [2, 579], [3, 388], [4, 120], [5, 1000], [6, 1000], [7, 0], [8, 300]]},
        "seen": {"c1": {"500": [1, 11]},   # rate came from 1 of 11 -> set aside
                 "c2": {"500": [7, 121]},  # 5.785% stored as 579, 7 drops -> kept
                 "c3": {"500": [1, 11]},   # 3.88% came from another source -> kept
                 "c5": {"500": [4, 40]},   # 4 drops -> set aside
                 "c6": {"500": [5, 50]},   # 5 drops -> kept
                 "c7": {"500": [1, 5]},    # already unknown, not counted
                 "c8": {"500": [0, 0]}},   # no kills: no usable count
    })


class SmallSampleTests(unittest.TestCase):
    def test_small_sample_rates(self):
        fdb = sample_fdb()
        self.assertEqual(fdb.drops(500), [(1, None), (2, 5.79), (3, 3.88), (4, 1.2),
                                          (5, None), (6, 10.0), (7, None), (8, 3.0)])
        self.assertEqual(fdb.small_samples, {(500, 1), (500, 5)})

    def test_small_samples_recorded_once(self):
        fdb = sample_fdb()
        fdb.drops(500)
        fdb.drops(500)
        self.assertEqual(len(fdb.small_samples), 2)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mise exec -- python -m unittest discover tools/tests -k SmallSample`
Expected: FAIL (`(1, 9.09)` where `(1, None)` is expected, and no attribute `small_samples`).

- [ ] **Step 3: Implement the rule in `tools/fpdata/foreverdb.py`**

Add `MIN_OBSERVED_DROPS = 5` next to the other constants, `self.small_samples = set()` in `__init__`, and `seen["c<npc>"]  {item: [drops, kills]}` to the docstring's table list. In `drops()`, after the vendor check: a rate is set aside (yielded as `None`, `(item, npc)` added to `small_samples`) when the rate is non-zero, the count exists with kills > 0, `abs(rate×100 − 10000 × drops / kills) <= 1`, and `drops < MIN_OBSERVED_DROPS`. Every other row keeps today's behaviour. Object and container drops are unchanged (ForeverDB has no counts for them).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mise exec -- python -m unittest discover tools/tests`
Expected: all OK (17 existing + 2 new).

- [ ] **Step 5: Report line** in `tools/fpdata/report.py`, right after the "NPCs: …" line:

```python
lines.append("Drop rates set aside for a small sample (fewer than %d drops seen): %d." % (
    MIN_OBSERVED_DROPS, len(fdb.small_samples)))
```

(import `MIN_OBSERVED_DROPS` from `fpdata.foreverdb`). The report is built after the merge, so the set is complete by then.

- [ ] **Step 6: Docs**

`tools/README.md` line 45 becomes:

```
- **Drops, objects, containers:** ForeverDB. The 12 best rates are kept, plus a total. Rate `nil` means unknown, which is still true of most new Forever drops. A creature drop rate that ForeverDB worked out from fewer than 5 observed drops (its `seen` counts) is baked as unknown, so it can't outrank measured rates; the NPC stays listed.
```

In the Sources table, the ForeverDB row's licence cell `GPL-3.0` becomes `GPL-3.0; its loot counts include Drop Tables (valcheffnet/DropTables), data CC BY-SA 4.0`.

`README.md` line 54: `ForeverDB (GPL-3.0)` becomes `ForeverDB (GPL-3.0, including Drop Tables loot counts under CC BY-SA 4.0)`.

- [ ] **Step 7: Commit, staging only this task's lines of `tools/README.md`**

`tools/README.md` also holds the pre-existing provenance note, which must not be staged. Build the staged version from HEAD instead of the working file: write `git show HEAD:tools/README.md` to a scratch file, apply the two Step 6 replacements to it, then `git update-index --cacheinfo 100644,$(git hash-object -w <scratch file>),tools/README.md`. Check with `git diff --cached tools/README.md` (only the two lines) and `git diff tools/README.md` (only the provenance note left).

```bash
git add tools/fpdata/foreverdb.py tools/fpdata/report.py tools/tests/test_pipeline.py README.md
git commit -m "Pipeline: set aside drop rates seen fewer than 5 times"
```

### Task 2: Rebuild the data with the rule

**Files:**
- Regenerate: `ForeverProfessional/Data/**`, `tools/REPORT.md`
- Modify: `tests/test_model.py:179` and `:254-255` (two counts)
- Commit: `tools/sources.lock.json` (already moved: client 1.60.1.71037, ForeverDB 2026-11-21)

**Interfaces:**
- Consumes: Task 1's rule and report line. The cache already holds the pinned downloads.

- [ ] **Step 1: Rebuild offline**

Run: `mise exec -- python tools/build_data.py build`
Expected: "Built 2159 recipes (921 new) …", no network fetch of ForeverDB.

- [ ] **Step 2: Check the report**

Run: `grep -n "set aside\|drop rate is known" tools/REPORT.md`
Expected: the set-aside line with a count near 129 (it counts every recipe item's rows, including those past the 12 kept), and "a drop rate is known" for new recipes at 2 / 363.

- [ ] **Step 3: Check Alchemy 3230's order**

Run: `grep -n "\[3230\] " ForeverProfessional/Data/Recipes/Alchemy.lua`
Expected: the `drops` list starts with Councilman Hartin's NPC at 0.5; Kolkar Packhound (4316) isn't ahead of any rated NPC.

- [ ] **Step 4: Run both test suites**

Run: `mise exec -- python -m unittest discover tools/tests` and `mise exec -- python -m unittest discover tests`
Expected: the pipeline suite is OK. In the addon suite, Councilman Hartin is back on top, so the "0.5%" and title assertions pass, but Kolkar Packhound stays listed (with an unknown rate), so Alchemy 3230 has one more drop NPC than before the update and two count assertions in `tests/test_model.py` still fail on that alone.

- [ ] **Step 5: Update the two counts in `tests/test_model.py`**

`test_drop_counts_totals`: `546 + 14` becomes `547 + 14`. `test_cards_drops_rates_more_and_objects`: `"+535 more"` becomes `"+536 more"`. Change nothing else; if any other assertion fails, stop and report it.

Run: `mise exec -- python -m unittest discover tests`
Expected: OK, 219 tests.

- [ ] **Step 6: Commit the data update**

```bash
git add tools/sources.lock.json tools/REPORT.md ForeverProfessional/Data tests/test_model.py
git commit -m "Data: client 1.60.1.71037, ForeverDB 2026-11-21"
```

Check `git status` afterwards: only `AGENTS.md` and `tools/README.md` (the pre-existing notes) stay modified.
