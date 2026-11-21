# UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the window as an icon rail, a profession header and two flat panes (two-line recipe rows, a
detail pane whose order follows the learned state), resizable, in the retail Professions art style.

**Architecture:**
- Approach A from the spec: our own frames.
- A new `UI/Widgets.lua` holds the flat panel, filter toggle, icon button, chip, item slot, progress bar, skill bar,
  the profession theme table and the source icons.
- `Window.lua` owns the rail, header, toolbar and resizing. `RecipeList.lua` owns the virtualized two-height list.
  `Detail.lua` owns the pinned header, the sections and the source cards.
- Text and ordering decisions stay frame-free in `Model.lua` / `Characters.lua`.

**Tech Stack:** Lua 5.1 (WoW Forever client, interface 16001), Python 3.12 `unittest` + `lupa` against `tests/wow_mock.lua`.

**Spec:** `docs/superpowers/specs/2026-11-21-ui-redesign-design.md` (mockup: `docs/superpowers/specs/2026-11-21-ui-redesign-mockup.html`)

## Global Constraints

- Work on `develop`, one commit per task, don't push. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- After every change run `mise exec -- python -m unittest discover tests`; the whole suite stays green.
  Single tests: `mise exec -- python -m unittest discover tests -k <name> -v`.
- New Lua files go in the TOC with ` [AllowLoadGameType camelot][ExcludeLoadGameType classic]`. A TOC change
  needs a full client restart in game.
- Never edit `ForeverProfessional/Data/`, `tools/`, or the community addons. Never call Blizzard profession filter
  setters. Never load or hook `Blizzard_Professions` / `Blizzard_ProfessionsBook` code or templates. Reading
  `ProfessionsBookFrame` regions in the throwaway probe is the only exception.
- No bundled libraries. ForeverDungeonJournal has no licence: read it for atlas names and technique, never copy
  its code.
- Client art only: textures and atlases that ship with the game.
- Every user-visible string goes through `Locale.lua` (`L.*`). Every file starts with the GPL header line and
  `local _, ns = ...`.
- Item, spell, NPC and zone names stay live or come from the baked/locale tables, as today.
- The list stays virtualized: the row pool stays under 40 rows for 400+ entries.
- Colours (hex) from the mockup:
  - window `0d0b09`, panel `15120e`, panel header `1c1813`
  - lines `2e271d` / `3d3326`
  - gold `ffd100`, muted text `9a8f7a`, dim `6d6455`
  - difficulty colours as `M.COLORS`

## Plan-level decisions (clarifications of the spec)

1. **`Learn N`:** also left out when `learn` is 0. Recipes learned with the profession (`auto`) have `learn = 0`.
2. **"+N more" counting:**
   - Objects and containers count `objectTotal` / `containerTotal` when present, as drops use `dropTotal`. This
     matches the detail pane's existing "+N more" lines.
   - A source type present only as `unverified` counts 1.
3. **Faction tag** for a row whose only entries belong to the other faction: ` · Horde` / ` · Alliance`, appended
   after the zone.
4. **Difficulty-scale tick:** shown when the shown character's skill is known and ≥ `learn`. It sits at the bar's
   end once skill ≥ `grey`.
5. **Skill bar fallback gradient:** from the spec table's 2nd to 4th stop.
6. **Quest cards:** one card per quest. The detail line lists the givers; the waypoint is the first giver with
   coordinates.
7. **List/detail split:** the list gets 44% of `width − rail − 3 gaps`, clamped to [380, 520]. The spec says about
   42%; 44% matches the mockup's 420 px at 1040.
8. **`M.SourceLines` and `M.NPCLine` are replaced by `M.SourceCards`.** Only `Detail.lua` used them.
9. **Probe results:** the probe writes `ForeverProfessionalDB.probe`. After a `/reload` they're read from the
   SavedVariables file (`C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\*\SavedVariables\ForeverProfessional.lua`,
   read-only), then cleared.
10. **Provisional accents and source icons** (Task 4) stand until Task 11 replaces them from the probe screenshot.

## Shared facts (real baked data; the logged-in mock character "Tester" is Horde, Alchemy 120/150, Herbalism 90/150)

| Recipe | Line | Facts used by tests |
|---|---|---|
| 2329 | 171 | trainer 50c, learn 15, category 2450 "Elixirs". Learned in the tests' `LEARNED` |
| 1230564 | 171 | trainer 100c + 7 quests (first 96045 "Camping 101: Alchemy", level 6; givers 1246 Vosur Brakthel A map 1455, 265813), learn 20 |
| 7255 | 171 | vendors 1685 Xandar Goodbeard (A, map 1432), 3134 Kzixx (AH, 1431), 3490 Hula'mahi (H, 1413). learn 100 |
| 1251750 | 171 | vendors 248196 Apothecary Durelle (H, 1413), 256729 Nina Surefire (A, 1433). learn 180, favor 120, rep 2586 Friendly |
| 1251753 | 171 | vendor 4610 Algernon (H, 1421) + 2 quests. learn 280 |
| 1250793 | 171 | 2 drops, first 2007 Gnarlpine Gardener (map 1438), no rates. `new`, learn 15 |
| 3230 | 171 | 12 of 547 drops (first 2064 Councilman Hartin, 0.5%, map 1421), 12 of 14 objects. teach 2553, learn 50 |
| 2335 | 171 | drop, object, container 6307 (0.27%) |
| 2365 | 171 | `unknown`, learn 100 |
| 2538 | 185 | `auto`, learn 0 |
| 1262978 | 185 | one drop: 645 Cookie, `instance = 36`, no map (mock zone "Instance 36") |
| 1319313 | 185 | one object 694054 "Recipe: Raw Plated Armorfish" |
| 24903 | 197 | primary `drop` only as `unverified`, plus containers |
| 11456 / 22704 | 171 / 202 | `crafted` / `worldObject` |

The mock's `C_Map.GetMapInfo(id).name` is `"Map <id>"`. Every category in the real data is a direct child of its
profession root (no nesting), so nested-collapse tests use a synthetic tree. Alchemy has 179 recipes.

## Review Focus

- **A character with none of the professions** (`ALTS` "Banco"): all 12 professions sit in the rail's lower group,
  the header shows "Not learned", and rows show `Learn N` uncoloured. Tests: Task 5 `test_rail_alt_without_professions`,
  Task 7 `test_learn_neutral_without_profession`.
- **Degenerate thresholds** (`learn` 0 or nil, `learn == grey`, no `grey`): no "Learn 0", and no division by zero
  or negative segment width in the scale. Tests: Task 2 `test_subtitle_auto_has_no_learn`, Task 9
  `test_scale_degenerate_thresholds`.
- **Saved window size that no longer fits** (resolution change) or was never saved: clamped to the screen, or the
  default. Test: Task 8 `test_size_restored_and_clamped`.
- **Uncached items** (output item in the header, a container name in a row): a placeholder first, then the real
  name, no error. Tests: Task 2 `test_subtitle_container_name_loads`, Task 9 `test_async_output_item`.
- **Collapse all, then search:** search still shows every match, and clearing it goes back to all collapsed.
  Test: Task 6 `test_collapse_all_then_search`.

---

### Task 1: In-game probe (throwaway, needs the user)

**Files:**
- Create (never committed): `ForeverProfessional/Probe.lua` and its TOC line (after `UI\Minimap.lua`)
- Modify: `AGENTS.md` ("Client facts": the verified atlases)

**Interfaces:**
- Produces: the probe results that Task 11 consumes. The `AGENTS.md` facts are committed.

- [ ] **Step 1: Write `Probe.lua` with a `/fpprobe` command** (`SLASH_FPPROBE1 = "/fpprobe"`). It does four things:
  - **Atlas checks:** `C_Texture.GetAtlasInfo` for `Skillbar_Fill_Flipbook_<Kit>` and `Skillbar_Flare_<Kit>`, for
    Kit in `Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, FirstAid, Fishing, Herbalism, Leatherworking,
    Mining, Skinning, Tailoring, DefaultBlue`. Also `Professions-skillbar-bg`, `Professions-skillbar-frame` and
    `Professions-skillbar-mask`.
  - **API checks:** whether `SetResizeBounds`, `CreateColor` and `Texture.SetGradient` exist.
  - **Preview frame** (`ForeverProfessionalProbe`, movable): one labelled row per kit, drawing the fill's first
    frame (via the atlas texcoords, the flipbook having 2 columns of 34 px rows) or the word MISSING. Below that,
    numbered icon candidates:
    - textures `Interface\GossipFrame\TrainerGossipIcon`, `Interface\GossipFrame\VendorGossipIcon`,
      `Interface\GossipFrame\AvailableQuestIcon`, `Interface\Minimap\Tracking\Banker`,
      `Interface\Icons\INV_Misc_Bag_10`, `Interface\Icons\INV_Misc_Bag_07`, `Interface\Icons\INV_Box_01`,
      `Interface\Icons\INV_Box_02`, `Interface\Icons\INV_Misc_Book_09`, `Interface\Icons\INV_Misc_Coin_01`,
      `Interface\Icons\INV_Misc_Gear_01`, `Interface\ChatFrame\ChatFrameExpandArrow`,
      `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up`, `Interface\Common\UI-Searchbox-Icon`
    - atlases `VignetteLoot`, `Banker`, `QuestNormal`, each marked missing when `GetAtlasInfo` is nil
  - **`/fpprobe book`:** walks `ProfessionsBookFrame`'s children and regions recursively (read only, only if the
    frame exists). For every texture wider than 100 px it records `{ path, atlas = GetAtlas(), file = GetTexture(), w, h }`.
  - Everything goes into `ForeverProfessionalDB.probe`.
- [ ] **Step 2: Hand it to the user.** Ask them to:
  1. fully restart the client
  2. run `/fpprobe` and screenshot the preview frame
  3. open the Professions book and run `/fpprobe book`
  4. `/reload`
- [ ] **Step 3: Read the results** from `WTF\Account\*\SavedVariables\ForeverProfessional.lua`, plus the
  screenshot. Write down for Task 11:
  - which kits and flares exist, per profession
  - the illustration atlas or file per profession panel seen in the book
  - the user's pick of icon numbers for trainer, vendor, drop (loot), quest, object, container, crafted, unknown
- [ ] **Step 4: Remove the probe.**
  - Delete `Probe.lua` and `git checkout ForeverProfessional/ForeverProfessional_Camelot.toc`.
  - Ask the user to run `/run ForeverProfessionalDB.probe = nil` and fully restart.
  - `git status` shows only `AGENTS.md` changed.
- [ ] **Step 5: Add the verified atlas facts to `AGENTS.md`** ("Client facts": which skill bar kits exist, the
  skillbar frame/mask/bg atlases, and whether `SetResizeBounds` exists). Run the full suite. Commit: `AGENTS.md:
  verified profession skill bar atlases`.

Tasks 2–10 don't wait for this task.

---

### Task 2: Model: primary source and row subtitle

**Files:**
- Modify: `ForeverProfessional/Model.lua` (new "Rows" section after Sources), `ForeverProfessional/Characters.lua`,
  `ForeverProfessional/Locale.lua`
- Test: `tests/test_model.py` (new `PrimarySourceTest`), `tests/test_chars.py`

**Interfaces:**
- Produces:
  - `M.PrimarySource(rec, faction) -> { type = string, text = string, more = number }`. `type` is one of
    `auto, trainer, vendor, quest, drop, object, container, crafted, worldObject, unknown`.
  - `M.RowSubtitle(rec, skill, learned, faction) -> string` (with colour codes).
  - `M.SEP = " · "`.
  - `M.Usable(npcID, faction) -> boolean`.
  - `ns.CharFaction(key) -> "Horde"|"Alliance"|nil`.

- [ ] **Step 1: Write the failing tests** (`PrimarySourceTest` in `tests/test_model.py`; `COPPER`/`SILVER` are the
  existing constants there):

```python
class PrimarySourceTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(); self.a.login()
        self.M, self.R = self.a.ns.Model, self.a.ns.Data.Recipes

    def ps(self, line, spell, faction="Horde"):
        p = self.M.PrimarySource(self.R[line][spell], faction)
        return p.type, plain(p.text), p.more

    def test_trainer_with_cost(self):
        self.assertEqual(self.ps(171, 2329), ("trainer", "Trainer · 50" + COPPER, 0))

    def test_trainer_before_quests(self):
        self.assertEqual(self.ps(171, 1230564), ("trainer", "Trainer · 1" + SILVER, 7))

    def test_vendor_usable_by_faction(self):
        self.assertEqual(self.ps(171, 7255, "Horde"), ("vendor", "Vendor · Kzixx (Map 1431)", 2))
        self.assertEqual(self.ps(171, 7255, "Alliance"), ("vendor", "Vendor · Xandar Goodbeard (Map 1432)", 2))
        self.assertEqual(self.ps(171, 7255, None)[1], "Vendor · Xandar Goodbeard (Map 1432)")

    def test_vendor_only_other_faction_tagged(self):
        self.assertEqual(self.ps(171, 1251753, "Alliance"), ("vendor", "Vendor · Algernon (Map 1421) · Horde", 2))

    def test_drop_counts_totals(self):
        self.assertEqual(self.ps(171, 3230), ("drop", "Drop · Councilman Hartin (Map 1421)", 546 + 14))

    def test_drop_in_dungeon(self):
        self.assertEqual(self.ps(185, 1262978), ("drop", "Drop · Cookie (Instance 36)", 0))

    def test_object_auto_crafted_world_unknown(self):
        self.assertEqual(self.ps(185, 1319313), ("object", "Found in Recipe: Raw Plated Armorfish", 0))
        self.assertEqual(self.ps(185, 2538), ("auto", "Learned with the profession", 0))
        self.assertEqual(self.ps(171, 11456)[:2], ("crafted", "Crafted"))
        self.assertEqual(self.ps(202, 22704)[:2], ("worldObject", "World object"))
        self.assertEqual(self.ps(171, 2365), ("unknown", "Source unknown", 0))

    def test_unverified_primary(self):
        t, text, _ = self.ps(197, 24903)
        self.assertEqual((t, text), ("drop", "Drop (location unknown)"))

    def test_subtitle_learned_is_range(self):
        rec = self.R[171][3230]
        self.assertEqual(self.M.RowSubtitle(rec, 120, True, "Horde"), self.M.RangeText(rec, 120))

    def test_subtitle_missing(self):
        self.assertEqual(self.M.RowSubtitle(self.R[171][1251750], 120, False, "Horde"),
                         "|cffff2020Learn 180|r · Vendor · Apothecary Durelle (Map 1413) · +1 more")
        self.assertEqual(plain(self.M.RowSubtitle(self.R[171][7255], 120, False, "Horde")),
                         "Learn 100 · Vendor · Kzixx (Map 1431) · +2 more")
        self.assertNotIn("|cff", self.M.RowSubtitle(self.R[171][1251750], None, False, "Horde").split("·")[0])

    def test_subtitle_auto_has_no_learn(self):
        self.assertEqual(self.M.RowSubtitle(self.R[185][2538], 50, False, "Horde"), "Learned with the profession")

    def test_subtitle_container_name_loads(self):
        rec = self.a.lua.eval('{ src = {"container"}, containers = {{6307, 0.27}}, learn = 60 }')
        self.assertEqual(plain(self.M.RowSubtitle(rec, 100, False, "Horde")), "Learn 60 · Contained in a container")
        self.a.mock.itemNames[6307] = "Box"
        self.assertEqual(plain(self.M.RowSubtitle(rec, 100, False, "Horde")), "Learn 60 · Contained in Box")
```

In `tests/test_chars.py` (with the `ALTS` fixture):
`self.assertEqual(ns.CharFaction("Player-1-0000000D"), "Alliance")`, `self.assertEqual(ns.CharFaction(None), "Horde")`,
`self.assertIsNone(ns.CharFaction("Player-9-X"))`.

- [ ] **Step 2: Run** `mise exec -- python -m unittest discover tests -k PrimarySource -v`. Expected: FAIL
  (`PrimarySource` is nil).
- [ ] **Step 3: Implement**:
  - `M.Usable`: the NPC faction is nil or `"AH"`, or `faction` is nil, or the NPC faction is `"A"` for
    `"Alliance"` / `"H"` for `"Horde"`.
  - `M.PrimarySource`, using the type order and texts in the spec's table:
    - Zone via `M.ZoneName`, formatted `"%s (%s)"` and left out when nil.
    - Container names via `C_Item.GetItemNameByID`, else `L.A_CONTAINER`.
    - `more` per plan decisions 2 and 3.
  - `M.RowSubtitle`, joining with `M.SEP` per the spec ("Line 2") and plan decision 1. `Learn N` is red
    (`M.COLORS.red`) only when `skill` is known and below `learn`.
  - `ns.CharFaction(key)`: `ns.GetChar(key)`'s faction, nil when there's no record.
  - New strings: `L.LEARN = "Learn %d"`, `L.ROW_TRAINER = "Trainer · %s"`, `L.ROW_VENDOR = "Vendor · %s"`,
    `L.ROW_DROP = "Drop · %s"`, `L.ROW_QUEST = "Quest · %s"`, `L.ROW_OBJECT = "Found in %s"`,
    `L.ROW_CONTAINER = "Contained in %s"`, `L.A_CONTAINER = "a container"`,
    `L.SRC_AUTO_SHORT = "Learned with the profession"`.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Commit** `Model: primary source and two-line row subtitle`.

---

### Task 3: Model: source cards

**Files:**
- Modify: `ForeverProfessional/Model.lua` (replace `M.NPCLine` / `M.SourceLines` with `M.SourceCards`)
- Test: `tests/test_model.py` (replace the `test_sources_*` tests that call `SourceLines`)

**Interfaces:**
- Consumes: `M.Usable`, `M.SEP` (Task 2).
- Produces:
  - `M.SourceCards(rec, faction) -> { teach = {itemID...}, cards = {card...}, requirements = {string...}, notes = {string...} }`.
  - A card is `{ type, title, detail, waypoint = {map,x,y,name}|nil, item = itemID|nil, instance = boolean }`, with
    `type` one of `auto, trainer, vendor, drop, object, container, quest, crafted, worldObject, more`.

- [ ] **Step 1: Write the failing tests** (helper `cards(line, spell, faction="Horde")` returns `lua_list(...cards)`):

```python
    def test_cards_trainer(self):
        c = self.cards(171, 2329)[0]
        self.assertEqual((c.type, c.title, c.detail), ("trainer", "Trainer", "50" + COPPER))

    def test_cards_vendors_own_faction_first(self):
        names = lambda f: [c.title.split(" <")[0] for c in self.cards(171, 7255, f)]
        self.assertEqual(names("Horde"), ["Kzixx", "Hula'mahi", "Xandar Goodbeard"])
        self.assertEqual(names("Alliance"), ["Xandar Goodbeard", "Kzixx", "Hula'mahi"])
        self.assertEqual(self.cards(171, 7255, "Horde")[0].title, "Kzixx <Rare Goods>")

    def test_cards_gated_vendor(self):
        s = self.M.SourceCards(self.R[171][1251750], "Horde")
        v = lua_list(s.cards)[0]
        self.assertIn("Map 1413", v.detail)
        self.assertEqual(v.waypoint.map, self.a.ns.Data.NPCs[248196].map)
        self.assertEqual(sorted(lua_list(s.requirements)), ["120 Merchant's Favor", "Faction 2586: Friendly"])

    def test_cards_drops_rates_more_and_objects(self):
        cards = self.cards(171, 3230)
        self.assertIn("0.5%", cards[0].detail)
        self.assertIn(("more", "+535 more"), [(c.type, c.title) for c in cards])
        self.assertTrue(any(c.type == "object" for c in cards))
        self.assertEqual(lua_list(self.M.SourceCards(self.R[171][3230], "Horde").teach), [2553])

    def test_cards_dungeon_drop(self):
        c = self.cards(185, 1262978)[0]
        self.assertTrue(c.instance)
        self.assertIsNone(c.waypoint)

    def test_cards_container_is_item(self):
        c = next(c for c in self.cards(171, 2335) if c.type == "container")
        self.assertEqual(c.item, 6307)

    def test_cards_quest(self):
        c = next(c for c in self.cards(171, 1230564) if c.type == "quest")
        self.assertEqual(c.title, "[6] Camping 101: Alchemy")
        self.assertTrue(c.detail.startswith("Given by Vosur Brakthel"))
        self.assertIsNotNone(c.waypoint)

    def test_cards_notes(self):
        self.assertEqual(lua_list(self.M.SourceCards(self.R[171][2365], "Horde").notes), ["Source unknown"])
        notes = lua_list(self.M.SourceCards(self.R[197][24903], "Horde").notes)
        self.assertTrue(any("(location unknown)" in n for n in notes))

    def test_every_recipe_has_cards_or_notes(self):
        for line in self.R.keys():
            for spell, rec in self.R[line].items():
                s = self.M.SourceCards(rec, "Horde")
                self.assertTrue(lua_list(s.cards) or lua_list(s.notes), (line, spell))
```

- [ ] **Step 2: Run** `-k test_cards`. Expected: FAIL.
- [ ] **Step 3: Implement `M.SourceCards`** from today's `M.SourceLines` logic:
  - **NPC title:** name plus ` <sub>`.
  - **NPC detail:** rate, faction tag and zone + coords, joined with `M.SEP`. The waypoint comes from the NPC
    record, as today.
  - **Faction order:** vendors and drops put the entries usable by `faction` first, keeping data order.
  - **"+N more"** becomes a `more` card after its type.
  - **Quests:** one card per quest (plan decision 6).
  - **Trainer:** `title = L.SRC_TRAINER`, `detail = M.Money(cost)` or nil.
  - **Requirements and notes:** the same strings as today.
  - Delete `M.NPCLine` and `M.SourceLines`. `Detail.lua` still calls `SourceLines` until Task 10, so keep a
    temporary `M.SourceLines` adapter that flattens the cards into today's line shape, and delete it in Task 10.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Commit** `Model: source cards with faction-ordered NPCs`.

---

### Task 4: Widgets, theme and skill bar

**Files:**
- Create: `ForeverProfessional/UI/Widgets.lua` (TOC: before `UI\Window.lua`)
- Modify: `ForeverProfessional/UI/Window.lua` (move `UI.Panel` out, start with `local UI = ns.UI`), `tests/wow_mock.lua`
- Test: `tests/test_widgets.py` (new)

**Interfaces:**
- Produces, all on `ns.UI` (Widgets.lua creates `ns.UI = ns.UI or {}`):
  - `UI.HexColor(hex) -> r, g, b`, and `UI.COLORS` (the hex values in Global Constraints).
  - `UI.THEME[line] = { kit, accent, bar = {fromHex, toHex}, watermark = nil }` and `UI.Theme(line) -> entry`
    (a neutral default for unknown lines).
  - `UI.SOURCE_ICONS[type] -> texture path`, for every Task 2/3 type plus `check`.
  - `UI.Panel(parent) -> Frame`: flat backdrop, `bgFile` and `edgeFile` `Interface\Buttons\WHITE8X8`,
    `edgeSize` 1.
  - `UI.CreateSegmented(parent, items, onSelect) -> control`, with `control.buttons[key]`, `control.order`,
    `control:SetSelected(key)` and `control:SetCount(key, n)`. Each button has `.key`, `.label`, `.count` and
    `.selected`. A click calls `onSelect(key)`.
  - `UI.CreateIconButton(parent, texture, tooltip, onClick) -> Button`.
  - `UI.CreateChip(parent) -> chip`, with `chip:SetChip(text, style)` (style `"good"|"bad"|"neutral"`),
    `chip.text` and `chip.style`.
  - `UI.CreateSlot(parent, size) -> Button`, with `slot:SetItem(itemID, count)`, `.icon`, `.count`, `.border`
    and an item tooltip on enter.
  - `UI.CreateProgressBar(parent, width, height) -> bar`, with `bar:SetProgress(value, max)` and `bar.fill`.
  - `UI.CreateSkillBar(parent, width, height) -> bar`, with `bar:SetTheme(line)`, `bar:SetProgress(value, max)`,
    `bar.fill`, `bar.clip`, `bar.innerWidth` and `bar.usesFallback`.

- [ ] **Step 1: Extend the mock**:
  - `mock.missingAtlases = {}`: `C_Texture.GetAtlasInfo(n)` returns nil for those names.
  - `Widget:CreateAnimationGroup()` returns an object whose `CreateAnimation()` returns a table of no-op setters,
    plus `Play`/`Stop`/`IsPlaying`.
  - `Widget:SetRotation(r)` stores `self.rotation`.
  - `Widget:SetGradient(o, a, b)` stores `self.gradient`.
  - `CreateColor(r, g, b, a)` returns `{ r = r, g = g, b = b, a = a }`.
- [ ] **Step 2: Write the failing tests** (`self.a.g._ns = self.a.ns`, parent from
  `self.a.run('return CreateFrame("Frame", nil, UIParent)')`):

```python
    def test_theme_for_every_profession(self):
        for line in self.a.ns.Data.Professions.keys():
            t = self.UI.Theme(line)
            self.assertTrue(t.kit); self.assertEqual(len(t.accent), 6); self.assertEqual(len(lua_list(t.bar)), 2)
        self.assertEqual(self.UI.Theme(164).accent, "ff8a1f")
        self.assertEqual(lua_list(self.UI.Theme(164).bar), ["d4400c", "ffe680"])

    def test_hex_color(self):
        self.assertEqual(self.UI.HexColor("ff8000"), (1.0, 128 / 255, 0.0))

    def test_skill_bar_game_art_and_fallback(self):
        bar = self.UI.CreateSkillBar(self.parent, 150, 8)
        Addon.call(bar, "SetTheme", 164)
        self.assertEqual(bar.fill.atlas, "Skillbar_Fill_Flipbook_Blacksmithing")
        self.assertFalse(bar.usesFallback)
        self.a.run('mock.missingAtlases["Skillbar_Fill_Flipbook_Blacksmithing"] = true')
        Addon.call(bar, "SetTheme", 164)
        self.assertTrue(bar.usesFallback)

    def test_skill_bar_progress_clamps(self):
        bar = self.UI.CreateSkillBar(self.parent, 150, 8)
        Addon.call(bar, "SetProgress", 215, 225)
        self.assertAlmostEqual(bar.clip.width, bar.innerWidth * 215 / 225, places=3)
        Addon.call(bar, "SetProgress", 300, 225)
        self.assertAlmostEqual(bar.clip.width, bar.innerWidth, places=3)
        Addon.call(bar, "SetProgress", 0, 0)   # no error, empty
        self.assertLess(bar.clip.width, 1)

    def test_segmented(self):
        picked, sel, count = self.a.run('''
            local picked
            local c = _ns.UI.CreateSegmented(UIParent, {{key="all",label="All"},{key="learned",label="Learned"}},
                function(k) picked = k end)
            c:SetSelected("all"); c:SetCount("learned", 3); c.buttons.learned:Click()
            return picked, c.buttons.all.selected, c.buttons.learned.count:GetText()''')
        self.assertEqual((picked, sel, count), ("learned", True, "3"))

    def test_chip_slot_icon_button_panel(self):
        chip = self.UI.CreateChip(self.parent); Addon.call(chip, "SetChip", "Learned", "good")
        self.assertEqual((chip.text.text, chip.style), ("Learned", "good"))
        slot = self.UI.CreateSlot(self.parent, 28); Addon.call(slot, "SetItem", 2447, 4)
        self.assertEqual(slot.count.text, "4")
        slot.scripts.OnEnter(slot); self.assertEqual(self.a.g.GameTooltip.item, 2447)
        Addon.call(slot, "SetItem", 2447, 1); self.assertEqual(slot.count.text, "")
        self.assertEqual(self.UI.Panel(self.parent).backdrop.edgeSize, 1)
```

- [ ] **Step 3: Run** `-k Widgets`. Expected: FAIL (no `UI.Theme`).
- [ ] **Step 4: Implement `Widgets.lua`.**
  - **The theme table, exact values** (the first five from the spec; the last seven provisional per plan
    decision 10):

```lua
UI.THEME = {
    [164] = { kit = "Blacksmithing",  accent = "ff8a1f", bar = { "d4400c", "ffe680" } },
    [186] = { kit = "Mining",         accent = "d9a441", bar = { "6a4a22", "ffd970" } },
    [185] = { kit = "Cooking",        accent = "c9d3de", bar = { "7d8b9a", "ffffff" } },
    [356] = { kit = "Fishing",        accent = "6aa0ff", bar = { "2f5aa8", "cfe2ff" } },
    [129] = { kit = "FirstAid",       accent = "6fdc2a", bar = { "3fae12", "d8ffb0" } },
    [171] = { kit = "Alchemy",        accent = "4fd1c5", bar = { "1f8a80", "a8fff5" } },
    [333] = { kit = "Enchanting",     accent = "b36bff", bar = { "6a2fb0", "e6ccff" } },
    [202] = { kit = "Engineering",    accent = "e0b040", bar = { "8a6a1a", "ffe9a0" } },
    [165] = { kit = "Leatherworking", accent = "c08850", bar = { "7a4a20", "f0d0a8" } },
    [197] = { kit = "Tailoring",      accent = "d070b0", bar = { "8a2f6a", "ffd0f0" } },
    [182] = { kit = "Herbalism",      accent = "6fcf4a", bar = { "2f7a1a", "d0ffb0" } },
    [393] = { kit = "Skinning",       accent = "c0a080", bar = { "6a5030", "f0e0c8" } },
}
```

  - **Provisional `UI.SOURCE_ICONS`:**
    - trainer and auto: `Interface\GossipFrame\TrainerGossipIcon`
    - vendor: `Interface\GossipFrame\VendorGossipIcon`
    - quest: `Interface\GossipFrame\AvailableQuestIcon`
    - drop: `Interface\Icons\INV_Misc_Bag_10`
    - object: `Interface\Icons\INV_Box_01`
    - container: `Interface\Icons\INV_Box_02`
    - crafted and worldObject: `Interface\Icons\INV_Misc_Gear_01`
    - unknown: `M.QUESTION_ICON`
    - check: `Interface\RaidFrame\ReadyCheck-Ready`
  - **Skill bar:**
    - It's built from `Professions-skillbar-bg/frame/mask`, a clipping frame (`SetClipsChildren`), the
      `Skillbar_Fill_Flipbook_<kit>` fill (flipbook animated inside a `pcall`, else first frame) and
      `Skillbar_Flare_<kit>` when the atlas exists.
    - Without the fill atlas: a `WHITE8X8` fill with `SetGradient("HORIZONTAL", CreateColor(from), CreateColor(to))`
      inside a `pcall`, else `SetVertexColor(accent)`. `usesFallback` is true.
    - `SetProgress` sets `clip` width to `max(0.01, innerWidth * clamp(value / max, 0, 1))`, and 0.01 when
      `max` is 0 or nil.
  - **Window.lua:** remove its `UI.Panel`, use `local UI = ns.UI`, keep all behaviour.
- [ ] **Step 5: Run** the full suite. Expected: PASS.
- [ ] **Step 6: Commit** `Widgets: flat panel, filter toggle, chips, slots, bars and profession theme`.

---

### Task 5: Window shell: rail, header, flat frame

**Files:**
- Modify: `ForeverProfessional/UI/Window.lua`, `ForeverProfessional/Locale.lua`, `ForeverProfessional/UI/RecipeList.lua`
  and `ForeverProfessional/UI/Detail.lua` (anchoring only)
- Test: `tests/test_ui.py` (rewrite the tab, counter and selector-position tests)

**Interfaces:**
- Consumes: Task 4 widgets and theme.
- Produces:
  - `UI.RAIL_W = 64`, `UI.HEADER_H = 54`, `UI.GAP = 8`, `UI.DEFAULT_W, UI.DEFAULT_H = 1040, 640`.
  - `UI.RailOrder(key) -> knownLines, otherLines`: both in `UI.ProfessionOrder()` order. "Known" means
    `ns.CharSkill(line, key)` is non-nil.
  - `UI.railButtons`: buttons with `.line`, `.group` (`"known"|"other"`), `.icon`, `.skill` (FontString),
    `.marker` and `.glow`.
  - `UI.header`, with `.icon`, `.name`, `.skillBar`, `.skillText`, `.notLearned`, `.recipesBar`, `.recipesText`
    and `.watermark`.
  - `UI.RefreshRail()`, `UI.RefreshHeader()`.
  - `UI.frame.listPanel` and `UI.frame.detailPanel` stay.
  - Gone: `UI.tabs`, `UI.RefreshTabs`, `UI.frame.counter`, `UI.RefreshCounter`, `UI.frame.title`, the Encounter
    Journal background. Their callers are updated.

- [ ] **Step 1: Write the failing tests** (replacing `test_tabs_one_per_profession`, `test_every_profession_tab`,
  `test_counter` and `test_tabs_below_selector`; `AltViewTest` reads rail buttons and `UI.header.recipesText`
  instead of tabs and the counter):

```python
    def rail(self, line): return next(b for b in lua_list(self.UI.railButtons) if b.line == line)

    def test_rail_groups_shown_character(self):
        known, other = self.UI.RailOrder(None)
        self.assertEqual(lua_list(known), [171, 182])
        self.assertEqual(lua_list(other), [164, 185, 333, 202, 129, 165, 197, 356, 186, 393])
        self.assertEqual(self.rail(171).skill.text, "120")
        self.assertEqual(self.rail(164).group, "other")
        self.assertFalse(self.rail(164).skill.shown)
        self.assertLess(Addon.call(self.rail(182), "GetPoint")[-1], 0)   # stacked below the logo

    def test_rail_click_selects(self):
        Addon.call(self.rail(185), "Click")
        self.assertEqual(self.UI.state.line, 185)
        self.assertTrue(self.rail(185).marker.shown); self.assertFalse(self.rail(171).marker.shown)

    def test_rail_tooltip(self):
        self.a.g.enter(self.rail(171))
        self.assertEqual(lua_list(self.a.g.GameTooltip.lines)[:2], ["Alchemy", "Skill 120 / 150"])

    def test_header(self):
        h = self.UI.header
        self.assertEqual((h.name.text, h.skillText.text, h.recipesText.text), ("Alchemy", "120 / 150", "3 / 179"))
        self.assertTrue(h.skillBar.shown); self.assertFalse(h.notLearned.shown)
        self.UI.SelectProfession(185)
        self.assertFalse(h.skillBar.shown); self.assertTrue(h.notLearned.shown)

    def test_no_journal_background_and_selector_in_header(self):
        textures = [r.texture for r in lua_list(self.a.g.ForeverProfessionalFrame.regions)]
        self.assertNotIn(r"Interface\EncounterJournal\UI-EJ-JournalBG", textures)
        self.assertTrue(self.a.lua.eval("rawequal")(self.UI.charButton.parent, self.UI.header))
```

(Compare Lua tables with `rawequal`; two Python wrappers of the same table aren't `==`.)

`AltViewTest` additions:

```python
    def test_rail_follows_alt(self):
        self.UI.SetChar("Player-1-0000000D")   # Paly: Alchemy, Cooking
        self.assertEqual(lua_list(self.UI.RailOrder("Player-1-0000000D")[0]), [171, 185])
        self.assertEqual(next(b for b in lua_list(self.UI.railButtons) if b.line == 185).group, "known")

    def test_rail_alt_without_professions(self):
        self.UI.SetChar("Player-1-0000000E")   # Banco
        self.assertTrue(all(b.group == "other" for b in lua_list(self.UI.railButtons)))
        self.assertTrue(self.UI.header.notLearned.shown)
```

- [ ] **Step 2: Run** `-k rail`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **Frame:** flat `UI.Panel` look, keep the name `ForeverProfessionalFrame`, size `DEFAULT_W × DEFAULT_H`. Drop
    the Encounter Journal texture and the title text.
  - **Rail:** 64 px panel on the left.
    - Logo: the TOC icon, with tooltip `L.TITLE`.
    - Known buttons at 34 px with a skill number underneath, then a 1 px divider, then other buttons at 26 px,
      desaturated (`SetDesaturated(true)`).
    - `UI.RefreshRail()` re-anchors the buttons on each refresh, because the groups change with the shown
      character.
    - The selected button shows `.marker` (3 px, accent colour) and `.glow`; its skill number takes the accent.
    - Tooltip: the profession name, then `L.SKILL` or `L.NOT_LEARNED_PROF`.
  - **Header:** spans the area right of the rail, `HEADER_H` tall.
    - `skillBar` from `UI.CreateSkillBar(…, 150, 8)` with `SetTheme(line)`; `recipesBar` from
      `UI.CreateProgressBar`. Each has a "Skill" / `L.RECIPES` label and an `"%d / %d"` value.
    - The char button is re-parented into the header (right side, left of the close button). The menu anchors
      `TOPRIGHT` to the button's `BOTTOMRIGHT`.
    - The accent glow is a gradient texture at the top left.
  - **Toolbar and panes:** the toolbar row sits inside the list panel top, unchanged (Task 6 restyles it). The list
    and detail panels sit below the header at fixed widths for now: list 418, detail the rest. Their visible
    heights are computed from the frame height (`UI.ListVisibleHeight()` and `UI.DetailVisibleHeight()`, both
    read `UI.frame:GetHeight()`).
  - **Strings:** `L.RECIPES = "Recipes"`. Remove `L.COUNT`.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Commit** `Window: icon rail and profession header replace the tabs`.

---

### Task 6: Toolbar: search, filter toggle with counts, collapse all / expand all

**Files:**
- Modify: `ForeverProfessional/UI/Window.lua`, `ForeverProfessional/Model.lua`, `ForeverProfessional/Locale.lua`
- Test: `tests/test_ui.py`, `tests/test_model.py`

**Interfaces:**
- Consumes: `UI.CreateSegmented`, `UI.CreateIconButton` (Task 4).
- Produces:
  - `M.FilterCounts(line, isLearned) -> total, learned`.
  - `M.CategoryIDs(tree) -> {id...}`: every node id at every depth, in tree order, `M.OTHER` included when
    present.
  - `UI.CollapseAll()`, `UI.ExpandAll()`, `UI.collapseAllButton`, `UI.expandAllButton`, `UI.filterControl`.
  - `UI.filterButtons` = `UI.filterControl.order` (buttons with `.key` and `.selected`).
  - `UI.searchBox.placeholder`, `UI.searchBox.icon`.

- [ ] **Step 1: Write the failing tests**:

```python
    def test_filter_counts_ignore_search(self):
        b = {x.key: x for x in lua_list(self.UI.filterButtons)}
        self.assertEqual([b[k].count.text for k in ("all", "learned", "missing")], ["179", "3", "176"])
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "spell 3230")
        self.assertEqual(b["all"].count.text, "179")
        self.a.call(b["learned"], "Click")
        self.assertTrue(b["learned"].selected); self.assertFalse(b["all"].selected)

    def test_collapse_all_and_expand_all(self):
        before = len(self.entries())
        self.a.call(self.UI.collapseAllButton, "Click")
        self.assertTrue(all(e.kind == "header" and e.collapsed for e in self.entries()))
        self.assertTrue(all(self.a.g.ForeverProfessionalDB.collapsed[e.cat] for e in self.entries()))
        self.a.call(self.UI.expandAllButton, "Click")
        self.assertEqual(len(self.entries()), before)

    def test_collapse_all_then_search(self):
        self.UI.CollapseAll()
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "spell 3230")
        self.assertEqual(self.recipe_ids(), [3230])
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "")
        self.assertEqual(self.recipe_ids(), [])

    def test_search_placeholder(self):
        self.assertEqual(self.a.g.ForeverProfessionalSearchBox.placeholder.text, "Search recipes…")
```

In `tests/test_model.py`:

```python
    def test_category_ids_nested(self):
        tree = self.a.lua.eval('{ children = { { id = 1, recipes = {}, children = { { id = 2, recipes = {}, '
                               'children = {} } } }, { id = "other", recipes = {}, children = {} } }, recipes = {} }')
        self.assertEqual(lua_list(self.M.CategoryIDs(tree)), [1, 2, "other"])

    def test_filter_counts(self):
        self.assertEqual(self.M.FilterCounts(171, self.a.lua.eval("function(id) return id == 2329 end")), (179, 1))
```

- [ ] **Step 2: Run** `-k "collapse or filter_counts or category_ids or placeholder"`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **Toolbar row** at the top of the list panel: search box (keep the name `ForeverProfessionalSearchBox`,
    `Interface\Common\UI-Searchbox-Icon` on the left, placeholder `L.SEARCH_RECIPES`), then the filter control
    (`L.FILTER_ALL/LEARNED/MISSING`), then the collapse and expand buttons (tooltips `L.COLLAPSE_ALL` /
    `L.EXPAND_ALL`).
  - **Counts** are refreshed in `UI.Refresh` from `M.FilterCounts` for the shown character. Missing = total −
    learned.
  - **`CollapseAll` / `ExpandAll`** set or clear `ns.db.collapsed[id]` for `M.CategoryIDs(M.BuildTree(line))`,
    then `UI.RefreshList()`.
  - **Strings:** `L.SEARCH_RECIPES = "Search recipes…"`, `L.COLLAPSE_ALL = "Collapse all"`,
    `L.EXPAND_ALL = "Expand all"`. Remove `L.SEARCH`.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Commit** `Toolbar: filter toggle with counts, collapse all and expand all`.

---

### Task 7: Two-line rows in a two-height virtualized list

**Files:**
- Modify: `ForeverProfessional/UI/RecipeList.lua`
- Test: `tests/test_ui.py` (rewrite `test_list_rows_rendered`, `test_learned_check_marks`, `test_header_click_collapses`,
  `test_scrolling_moves_rows`; keep `test_row_pool_is_small`)

**Interfaces:**
- Consumes: `M.RowSubtitle`, `M.PrimarySource`, `ns.CharFaction` (Task 2); `UI.SOURCE_ICONS`, `UI.CreateProgressBar` (Task 4).
- Produces:
  - `UI.HEADER_ROW_H = 24`, `UI.RECIPE_ROW_H = 34` (replace `UI.ROW_H`).
  - `UI.entryTop[i]`: the y offset of entry i. `UI.contentHeight`.
  - `UI.FirstVisible(offset) -> index` (binary search over `entryTop`).
  - `UI.EnsureRowPool()`: grows `UI.list.rows` to `ceil(UI.ListVisibleHeight() / HEADER_ROW_H) + 2`.
  - Row fields:
    - all rows: `.entry`, `.entryIndex`, `.label`
    - header rows: `.expand` (texture, `rotation` 0 collapsed / `-math.pi/2` open), `.progress`, `.count`
    - recipe rows: `.icon`, `.sub`, `.status`, `.selectedTex`

- [ ] **Step 1: Write the failing tests**:

```python
    def search(self, spell):   # test_ui.py now imports math
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", f"spell {spell}")
        return next(r for r in self.visible_rows() if r.entry.kind == "recipe" and r.entry.id == spell)

    def test_row_heights_and_content_height(self):
        rows = self.visible_rows()
        self.assertEqual(rows[0].height, 24)
        self.assertEqual(next(r for r in rows if r.entry.kind == "recipe").height, 34)
        e = self.entries()
        self.assertEqual(self.UI.list.child.height, sum(24 if x.kind == "header" else 34 for x in e))

    def test_missing_row(self):
        row = self.search(7255)
        self.assertEqual(plain(row.label.text), "Spell 7255")
        self.assertEqual(plain(row.sub.text), "Learn 100 · Vendor · Kzixx (Map 1431) · +2 more")
        self.assertEqual(row.status.texture, self.UI.SOURCE_ICONS.vendor)

    def test_learned_row(self):
        row = self.search(2329)
        rec = self.a.ns.Data.Recipes[171][2329]
        self.assertEqual(row.sub.text, self.a.ns.Model.RangeText(rec, 120))
        self.assertEqual(row.status.texture, self.UI.SOURCE_ICONS.check)

    def test_header_row(self):
        h = self.visible_rows()[0]
        self.assertEqual((h.label.text, h.expand.rotation), ("Camping", -math.pi / 2))
        self.assertRegex(h.count.text, r"^\d+/\d+$")
        self.a.call(h, "Click")
        self.assertEqual(self.visible_rows()[0].expand.rotation, 0)

    def test_scroll_with_mixed_heights(self):
        top = lua_list(self.UI.entryTop)
        for offset, expected in ((top[10], 11), (top[10] + 5, 11)):
            self.a.call(self.UI.list.scroll, "SetVerticalScroll", offset)
            self.UI.RenderList()
            self.assertEqual(self.visible_rows()[0].entryIndex, expected)
```

`AltViewTest` addition:

```python
    def test_learn_neutral_without_profession(self):
        self.UI.SetChar("Player-1-0000000E")
        self.a.call(self.a.g.ForeverProfessionalSearchBox, "SetText", "spell 1251750")
        row = next(r for r in lua_list(self.UI.list.rows) if r.shown and r.entry.kind == "recipe" and r.entry.id == 1251750)
        self.assertTrue(row.sub.text.startswith("Learn 180"))
```

- [ ] **Step 2: Run** `-k "row or scroll"`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `UI.RefreshList` fills `entryTop` and `contentHeight` (headers 24, recipes 34) and sets the scroll child height.
    `RenderList` starts at `UI.FirstVisible(scroll)` and positions each row at `-entryTop[i]`.
  - **Header rows:** chevron `Interface\ChatFrame\ChatFrameExpandArrow` with the rotation above, the name in
    `GameFontNormal`, a 34 px progress bar, and `"%d/%d"` in muted text.
  - **Recipe rows:** 26 px icon; line 1 `label` in `GameFontHighlight` coloured by `M.Difficulty`; line 2 `sub` in
    `GameFontHighlightSmall` in muted colour (its colour codes stay). `status` is 14 px, `SOURCE_ICONS.check` if
    learned, else `SOURCE_ICONS[M.PrimarySource(rec, faction).type]`.
  - **Selection:** a gold 2 px left edge plus `ffd100` at 0.11 alpha.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Commit** `List: two-line rows with source icons, mixed-height virtualization`.

---

### Task 8: Resizable window

**Files:**
- Modify: `ForeverProfessional/UI/Window.lua`, `ForeverProfessional/UI/RecipeList.lua`, `ForeverProfessional/UI/Detail.lua`,
  `tests/wow_mock.lua`
- Test: `tests/test_ui.py` (new `ResizeTest`)

**Interfaces:**
- Consumes: `UI.EnsureRowPool` (Task 7).
- Produces:
  - `UI.MIN_W, UI.MIN_H = 900, 520`.
  - `UI.ListWidth(frameWidth) -> number` (plan decision 7).
  - `UI.Layout()`.
  - `UI.resizeGrip`.
  - `ns.db.window.w` / `.h`.
  - `UI.DetailContentWidth()`: live, from the detail panel width.

- [ ] **Step 1: Extend the mock**:
  - `UIParent` is 1920 × 1080.
  - `SetSize`/`SetWidth`/`SetHeight` call `scripts.OnSizeChanged(self, w, h)` when the size changes and a handler
    is set.
  - `SetResizable(v)` stores `self.resizable`; `SetResizeBounds(...)` stores `self.resizeBounds = {...}`;
    `StartSizing(p)` stores `self.sizing = p`; `StopMovingOrSizing()` clears it.
- [ ] **Step 2: Write the failing tests**:

```python
class ResizeTest(unittest.TestCase):
    def setUp(self, setup=LEARNED):
        self.a = open_addon(setup); self.UI = self.a.ns.UI; self.f = self.a.g.ForeverProfessionalFrame

    def test_resizable_with_grip(self):
        self.assertTrue(self.f.resizable)
        self.assertEqual(lua_list(self.f.resizeBounds)[:2], [900, 520])
        g = self.UI.resizeGrip
        g.scripts.OnMouseDown(g, "LeftButton"); self.assertEqual(self.f.sizing, "BOTTOMRIGHT")
        Addon.call(self.f, "SetSize", 1200, 700)
        g.scripts.OnMouseUp(g, "LeftButton")
        self.assertEqual((self.a.g.ForeverProfessionalDB.window.w, self.a.g.ForeverProfessionalDB.window.h), (1200, 700))

    def test_list_width_split(self):
        self.assertEqual([self.UI.ListWidth(w) for w in (900, 1040, 1400)], [380, 418, 520])

    def test_layout_on_resize(self):
        Addon.call(self.f, "SetSize", 1400, 900)
        self.assertEqual(self.f.listPanel.width, 520)
        self.assertEqual(self.f.detailPanel.width, 1400 - 64 - 3 * 8 - 520)

    def test_pool_grows_on_taller_window(self):
        before = len(lua_list(self.UI.list.rows))
        Addon.call(self.f, "SetSize", 1040, 1060)
        self.assertGreater(len(lua_list(self.UI.list.rows)), before)

    def test_size_restored_and_clamped(self):
        def size(win):
            a = open_addon(f"ForeverProfessionalDB = {{ window = {win} }}; " + LEARNED)
            f = a.g.ForeverProfessionalFrame
            return f.width, f.height
        self.assertEqual(size("{ point='CENTER', x=0, y=0, w=1200, h=700 }"), (1200, 700))
        self.assertEqual(size("{ point='CENTER', x=0, y=0, w=5000, h=5000 }"), (1920, 1080))
        self.assertEqual(size("{ point='CENTER', x=0, y=0, w=100, h=100 }"), (900, 520))
        self.assertEqual(size("{}"), (1040, 640))
```

- [ ] **Step 3: Run** `-k Resize`. Expected: FAIL.
- [ ] **Step 4: Implement.**
  - **Resizing:** `SetResizable(true)`; `SetResizeBounds(MIN_W, MIN_H, UIParent:GetWidth(), UIParent:GetHeight())`
    when the method exists.
  - **Grip:** a 16 px button at `BOTTOMRIGHT` with `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up/-Highlight/-Down`.
    `OnMouseDown` → `StartSizing("BOTTOMRIGHT")`; `OnMouseUp` → `StopMovingOrSizing()` and `UI.SavePosition()`,
    which now also stores `w`/`h`.
  - **Restore:** `RestorePosition` restores the size, clamped to `[MIN, UIParent size]`; the default size when
    missing.
  - **`OnSizeChanged` → `UI.Layout()`:**
    - list panel width `ListWidth(w)`; detail panel from list right + `GAP` to `w − GAP`
    - `UI.EnsureRowPool()`, `UI.RefreshList()`, and `UI.RefreshDetail()` when shown
  - **Live sizes:** `Detail.lua`'s `ContentWidth` becomes `UI.DetailContentWidth()`. Everything else that read
    `UI.WIDTH`/`UI.HEIGHT`/`UI.LIST_W` reads the live size; remove those constants.
- [ ] **Step 5: Run** the full suite. Expected: PASS.
- [ ] **Step 6: Commit** `Window: resizable from a corner grip, size remembered`.

---

### Task 9: Detail pane: pinned header and empty state

**Files:**
- Modify: `ForeverProfessional/UI/Detail.lua`, `ForeverProfessional/Characters.lua`, `ForeverProfessional/Locale.lua`
- Test: `tests/test_detail.py` (rewrite `test_header_and_schematic`, `test_not_learned_and_drop_sources`'s status part,
  `test_count_range_without_schematic`, `test_empty_until_selected`, `test_header_divider`), `tests/test_chars.py`,
  `tests/test_ui.py` (`test_alt_detail_status` reads `detail.stateChip`)

**Interfaces:**
- Consumes: `UI.CreateChip` (Task 4), `UI.DetailContentWidth` (Task 8).
- Produces:
  - `ns.LearnableCount(line, key) -> number`: not learned, the character has the profession, skill ≥
    `learn or 0`, and `rec.side` is nil or the character's faction.
  - `detail.header`, a child of `UI.frame.detailPanel` (not of the scroll child), with `.icon`, `.iconBorder`,
    `.title`, `.creates`, `.stateChip`, `.catChip`, `.newChip`, and `.scale` (with `.segments`, `.tick` and
    `.nums[1..4]`).
  - `detail.empty`: a frame with `.hint`, `.watermark` and `.stats.learned/.learnable/.missing` (each with
    `.value`, `.label`).

- [ ] **Step 1: Write the failing tests**:

```python
    def test_empty_state_stats(self):
        e = self.d.empty
        self.assertTrue(e.shown)
        recs = self.a.ns.Data.Recipes[171]
        learnable = sum(1 for i, r in recs.items() if i != 2329 and (r.learn or 0) <= 120 and r.side in (None, "Horde"))
        self.assertEqual([e.stats[k].value.text for k in ("learned", "learnable", "missing")],
                         ["1", str(learnable), "178"])

    def test_header_learned(self):
        self.select(2329)
        h, rec = self.d.header, self.a.ns.Data.Recipes[171][2329]
        self.assertTrue(self.a.lua.eval("rawequal")(h.parent, self.UI.frame.detailPanel))
        self.assertEqual(plain(h.title.text), "Spell 2329")
        self.assertEqual(plain(h.creates.text), "Creates Item 2454 · Herb")
        self.assertEqual((h.stateChip.text.text, h.stateChip.style), ("Learned", "good"))
        self.assertEqual(h.catChip.text.text, "Elixirs")
        self.assertFalse(h.newChip.shown)
        self.assertEqual([n.text for n in lua_list(h.scale.nums)], [str(rec.learn), str(rec.yellow), str(rec.green), str(rec.grey)])
        self.assertTrue(h.scale.tick.shown)

    def test_header_not_learned_new_and_tick_hidden(self):
        self.select(1250793)
        self.assertEqual(self.d.header.stateChip.style, "bad")
        self.assertEqual(self.d.header.newChip.text.text, "New in Forever")
        self.select(1251750)                       # learn 180 > skill 120
        self.assertFalse(self.d.header.scale.tick.shown)

    def test_scale_degenerate_thresholds(self):
        for line in self.a.ns.Data.Recipes.keys():
            for spell, r in self.a.ns.Data.Recipes[line].items():
                if (r.learn or 0) == (r.grey or 0) or r.grey is None:
                    self.select(spell, line)
                    self.assertTrue(all(s.width >= 0 for s in lua_list(self.d.header.scale.segments)))

    def test_async_output_item(self):
        self.a.run("mock.asyncItems[2454] = true")
        self.UI.SelectRecipe(2329)
        self.assertIn("Item #2454", self.d.header.creates.text)
        self.a.run("flush()")
        self.assertIn("Item 2454", plain(self.d.header.creates.text))
```

Also, in `test_count_range_without_schematic`, the creates text starts with `f"Creates {lo}-{hi}x "`. In
`tests/test_chars.py`, `ns.LearnableCount(171, "Player-1-0000000B")` equals the same Python count for skill 290,
faction Horde, learned `{7255}`, and `ns.LearnableCount(171, "Player-1-0000000E") == 0`.

- [ ] **Step 2: Run** `-k "header or empty_state or scale or async_output or Learnable"`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **Header** (about 76 px):
    - 46 px icon with a 2 px border in `ITEM_QUALITY_COLORS[q]` of the output item.
    - Title in `GameFontNormalLarge` coloured by difficulty.
    - Creates line `L.CREATES_LINE:format(text)`, where text is `[count× ]` plus the coloured item name plus
      ` · subtype`. The subtype is the 3rd return of `C_Item.GetItemInfoInstant`; it's left out when nil.
    - The chips.
    - A 150 px scale on the right: segments orange/yellow/green proportional over `learn → grey` with a 6 px grey
      cap, widths `max(0, …)`; the four numbers; the tick per plan decision 4.
    - Output item loading reuses the existing pending/requested logic.
  - **Scroll frame:** anchored below the header; `UI.DetailVisibleHeight()` subtracts it. Remove `detail.divider`
    and `detail.status`.
  - **Empty state:**
    - `detail.empty.watermark` from `UI.Theme(line).watermark`, hidden when nil.
    - Hint `L.SELECT_RECIPE`.
    - Three stat boxes: `L.LEARNED`, `L.LEARNABLE_NOW`, `L.FILTER_MISSING`.
  - **Strings:** `L.CREATES_LINE = "Creates %s"`, `L.LEARNABLE_NOW = "Learnable now"`.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Commit** `Detail: pinned recipe header with difficulty scale, profession summary when empty`.

---

### Task 10: Detail pane: sections in state order, reagent grid, characters, source cards

**Files:**
- Modify: `ForeverProfessional/UI/Detail.lua`, `ForeverProfessional/Characters.lua`, `ForeverProfessional/Model.lua`
  (drop the temporary `SourceLines` adapter), `ForeverProfessional/Locale.lua`
- Test: `tests/test_detail.py` (rewrite the rest onto `detail.rendered`), `tests/test_chars.py`

**Interfaces:**
- Consumes: `M.SourceCards` (Task 3), `M.PrimarySource` (Task 2), `UI.CreateSlot` (Task 4), `UI.DetailContentWidth` (Task 8).
- Produces:
  - `M.DetailOrder(learned) -> {"reagents","characters","sources"}` or `{"sources","characters","reagents"}`.
  - `ns.OwnerGroups(line, spellID) -> { {group = "known"|"learnable"|"low", text} ... }`. `ns.OwnerLines` is
    rebuilt on top of it, with output unchanged.
  - `UI.ReagentColumns(width) -> 2 if width >= 440 else 1`.
  - `UI.state.sourcesOpen` (session only) and `UI.ToggleSources()`.
  - `UI.DetailBlocks(spellID, rec) -> blocks`, stored as `detail.rendered`. Block kinds: `section` (text),
    `reagents` (items = `{{item, count}}`), `owner` (group, text), `get` (item), `card` (card), `req` (text),
    `note` (text), `folded` (text).
  - Rendered widgets: `detail.cardWidgets` (with `.icon`, `.title`, `.detail`, `.waypoint`, `.dungeon`, `.card`),
    `detail.slots`, `detail.ownerRows` (with `.dot`, `.text`), `detail.folded`.

- [ ] **Step 1: Write the failing tests** (`blocks()` returns `[(b.kind, plain(b.text or ""))
  for b in lua_list(self.d.rendered)]`; `sections()` returns only the section texts):

```python
    def test_order_not_learned(self):
        self.select(1251753)
        self.assertEqual(self.sections(), ["Where to get it", "Characters", "Reagents"])
        self.assertEqual(lua_list(self.d.rendered)[1].kind, "get")      # Get <recipe item> from:

    def test_order_learned_with_folded_sources(self):
        self.select(2329)
        self.assertEqual(self.sections(), ["Reagents", "Characters"])
        self.assertEqual(self.blocks()[-1], ("folded", "Where to get it · Trainer · 50" + COPPER))
        self.a.call(self.d.folded, "Click")
        self.assertIn("Where to get it", self.sections())
        self.select(2329)          # stays open for the session
        self.assertTrue(self.UI.state.sourcesOpen)

    def test_vendor_cards_and_waypoint(self):
        self.select(1251750)
        card = next(w for w in lua_list(self.d.cardWidgets) if w.shown and w.card.type == "vendor")
        self.assertEqual(card.title.text, "Apothecary Durelle <Alchemist>")
        self.a.call(card.waypoint, "Click")
        self.assertEqual(lua_list(self.a.mock.waypoints)[0].uiMapID, self.a.ns.Data.NPCs[248196].map)
        self.assertIn(("req", "120 Merchant's Favor"), self.blocks())

    def test_dungeon_card(self):
        self.select(1262978, 185)
        w = next(w for w in lua_list(self.d.cardWidgets) if w.shown)
        self.assertFalse(w.waypoint.shown); self.assertTrue(w.dungeon.shown)
        self.assertEqual(w.dungeon.text, "Dungeon")

    def test_reagent_grid_columns(self):
        self.assertEqual((self.UI.ReagentColumns(440), self.UI.ReagentColumns(439)), (2, 1))
        self.select(1251753)
        slots = [s for s in lua_list(self.d.slots) if s.shown]
        self.assertGreater(Addon.call(slots[1], "GetPoint")[3], Addon.call(slots[0], "GetPoint")[3])  # 2nd column

    def test_unknown_note_and_quest_card(self):
        self.select(2365)
        self.assertIn(("note", "Source unknown"), self.blocks())
        self.select(1230564)
        titles = [w.title.text for w in lua_list(self.d.cardWidgets) if w.shown]
        self.assertIn("[6] Camping 101: Alchemy", titles)
```

Define `COPPER = r"|TInterface\MoneyFrame\UI-CopperIcon:0:0:2:0|t"` at the top of `tests/test_detail.py`. Slots
are anchored with the 5-argument `SetPoint("TOPLEFT", child, "TOPLEFT", x, y)`, so `GetPoint()[3]` is x.

`OwnersDetailTest.test_characters_section_order` now asserts the owner blocks after the "Characters" section,
each with its text and group:

```python
        i = r.index(("section", "Characters"))
        self.assertEqual([(b.group, plain(b.text)) for b in lua_list(self.d.rendered)[i + 1:i + 3]],
                         [("learnable", "Learnable by: Dru (Rogue), Paly (Horde vendors only)"),
                          ("low", "Skill too low: Tester 120 / 280, Dru (Druid) 150 / 280")])
```

Keep `test_every_recipe_renders`, `test_async_item_rerenders` (reagent slot names), `test_item_tooltip` (slot) and
`test_waypoint_refused_on_bad_map`, adapted to slots, cards and blocks.

- [ ] **Step 2: Run** `-k "order or cards or dungeon or reagent or note or characters"`. Expected: FAIL.
- [ ] **Step 3: Implement `UI.DetailBlocks`** per the spec's "Sections":
  - **"Where to get it":** `get` blocks for `teach` (with `L.GET_FROM`), then `req` blocks, then `card` blocks,
    then `note` blocks.
  - **Learned and folded:** one `folded` block, `L.WHERE .. M.SEP .. M.PrimarySource(rec, faction).text`, which
    calls `UI.ToggleSources()` when clicked.
  - **Rendering:** pooled widgets per kind, positioned top to bottom.
    - **Reagents:** grid of `UI.CreateSlot(…, 28)` with the item name in quality colour next to each slot, in
      `UI.ReagentColumns(UI.DetailContentWidth())` columns.
    - **Owner rows:** an 8 px dot coloured `40c040` (known), `ffd100` (learnable) or `909090` (low). When there
      are no owners, a single `owner` block with `L.NO_CHARACTER`.
    - **Cards:** a round type icon from `UI.SOURCE_ICONS`, title, muted detail, and a `L.WAYPOINT` button when
      `card.waypoint`. A muted `L.DUNGEON` label when `card.instance` and no waypoint. Container cards show an
      item tooltip.
  - **Model and strings:**
    - Delete the `M.SourceLines` adapter.
    - Add `L.WHERE = "Where to get it"`, `L.GET_FROM = "Get %s from:"`, `L.DUNGEON = "Dungeon"`.
    - Remove the strings nothing uses any more (`L.SOURCES`, `L.RECIPE_ITEM`, `L.CREATES`, `L.SRC_VENDORS`,
      `L.SRC_DROPS`, `L.SRC_QUESTS`, `L.SRC_CONTAINERS`, `L.SRC_OBJECTS`, `L.SKILL_RANGE`, …). Check with grep.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Commit** `Detail: sections follow the learned state, reagent grid, character rows, source cards`.

---

### Task 11: Profession art from the probe, docs, in-game check

**Files:**
- Modify: `ForeverProfessional/UI/Widgets.lua` (`UI.THEME` kits, accents and watermarks; `UI.SOURCE_ICONS`),
  `ForeverProfessional/UI/Window.lua` (header watermark), `README.md` (Usage), `AGENTS.md` (Layout table: `UI/Widgets`)
- Test: `tests/test_widgets.py`, `tests/test_ui.py`

**Interfaces:**
- Consumes: the Task 1 results; `UI.header.watermark` (Task 5); `detail.empty.watermark` (Task 9).

- [ ] **Step 1: Write the failing tests:**
  - `UI.SOURCE_ICONS` has a non-nil entry for each type in Task 2's list plus `check`.
  - With a theme that has `watermark` set, the header watermark shows that art at alpha ≤ 0.1. With
    `watermark = nil`, it's hidden.
  - Set `self.a.ns.UI.THEME[171].watermark = "test-atlas"` in the test to cover the first case.
- [ ] **Step 2: Run** `-k watermark`. Expected: FAIL.
- [ ] **Step 3: Apply the probe results:**
  - kits that don't exist are set to nil (that profession uses the fallback)
  - accents and fallbacks for Alchemy, Enchanting, Engineering, Leatherworking, Tailoring, Herbalism and Skinning
    are picked from the preview screenshot's bars
  - `watermark` per profession from the book dump, nil where none was found
  - `UI.SOURCE_ICONS` from the user's numbered picks

  Then show the header watermark (`SetAlpha(0.07)`) when the theme has one.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Update `README.md` Usage** (rail, header, toolbar with collapse/expand all, two-line rows, detail
  order, resizing) and the `AGENTS.md` Layout table.
- [ ] **Step 6: In-game check with the user** (`/reload` is enough; no TOC change since Task 4). Ask for
  screenshots of:
  - Blacksmithing with Heartseeker selected (compare with the mockup)
  - a learned recipe
  - the empty pane
  - the window resized small and large
  - an alt with no professions

  Fix what they report, with BugSack clean.
- [ ] **Step 7: Commit** `Profession art, source icons and docs for the redesigned window`.
