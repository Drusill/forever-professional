# UI redesign: design

Date: 2026-11-21. Status: awaiting approval.

Reference mockup: [2026-11-21-ui-redesign-mockup.html](2026-11-21-ui-redesign-mockup.html) (open it in a browser).
Emoji in it stand in for game icons and art.

## Intent

The window works, but it looks dated and wastes space. The Encounter Journal book background clashes with the
three-panel layout. The filters are red push-buttons, and you can't tell which one is on. Every row carries four
numbers plus a ✓/✗. Learned recipes are often grey (trivial), so they look disabled. The detail pane is a plain
text list that leaves half the pane empty. The user wants a modern layout that reads like a web app, in the art
style of the retail Professions window, plus collapse all / expand all for the recipe groups.

## Goals, non-goals, anti-goals

- **Goals:** the layout, rows, detail pane, profession colours and resizing described below, covered by tests and
  checked in game.
- **Non-goals:**
  - no data pipeline or baked-data changes
  - no new features beyond the redesign: no search across professions, no TomTom support, no options panel, no
    remembered character selection
  - minimap button, addon compartment, item tooltips and slash commands stay as they are (apart from what moves
    in the window)
- **Anti-goals (a failure even if it works):**
  - touching Blizzard's profession window or its filters
  - loading Blizzard's `Blizzard_Professions` / `Blizzard_ProfessionsBook` code or templates (taint risk, side
    effects on the user's own windows)
  - bundling third-party libraries
  - stutter when scrolling or resizing a 419-recipe profession (the list stays virtualized)
  - breaking the alt view

## Constraints

Everything in `AGENTS.md` applies:

- Lua 5.1, interface 16001, retail-style API.
- Client art only, no shipped textures.
- GPL-3.0.
- New Lua files go in the TOC with the camelot suffix.
- Tests run through the `lupa` harness (`tests/harness.py`, `tests/wow_mock.lua`) and must pass after each step.
- In-game checks are done by the user, with errors reported through BugSack.
- ForeverDungeonJournal (FDJ) has **no licence file**. Read it only to learn which atlases exist and how its skill
  bar works (`Interface\AddOns\ForeverDungeonJournal\Systems\RPGMode.lua` around line 900, and
  `Systems\Resize.lua`). Don't copy its code.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| **Chosen** | **A. Our own frames**: plain Frames/Textures with client atlases, a new shared widgets file, our existing virtualized list extended to two row heights and resizing | Tests keep exercising the real behaviour in our mock. Full control of the look. We keep owning the scroll code. |
| Rejected | B. Blizzard's `WowScrollBoxList` + `MinimalScrollBar` + `CreateScrollBoxListLinearView` (they exist on this client: Baganator and Auctionator use them) | Smooth scrolling, mixed row heights and resizing come for free. But the mock would need a large fake of Blizzard's ScrollBox system, so tests would check far less. It ties us to internals Forever can change. The alt-support design rejected Blizzard's dropdown for the same reason. |
| Rejected | Ace3's AceGUI | Its licence forbids bundling it stand-alone. It also looks like Ace. |
| Rejected | Blizzard's Professions window templates | Load-on-demand Blizzard code: taint and side effects. |

## Decisions made with the user

1. **Layout C, "icon rail + profession header".** From left to right:
   - a narrow rail of profession icons
   - a page header across the rest with the open profession's name and bars
   - the recipe list and the detail pane below the header

   Picked over a sidebar app (A) and top tabs (B).
2. **No book background.** Flat dark panels with thin bronze borders and gaps between them, in the colours of the
   retail Professions window.
3. **Collapse all / expand all** buttons for the recipe groups.
4. **Profession colour as an accent only.** It goes on the header's skill bar, the rail marker and icon glow, and
   a faint glow plus watermark in the header. Gold headings, difficulty colours and item quality colours stay
   as they are.
5. **Two-line rows** (picked over a difficulty bar and tidied numbers).
6. **Drops use a loot icon, not a skull.** The other source icons were approved as proposed: trainer book,
   vendor coin, quest mark.
7. **The detail pane's order follows the state** (picked over one fixed order and tabs).
   - Not learned: Where to get it, then Characters, then Reagents.
   - Learned: Reagents, then Characters, then Where to get it folded into one line.
8. **Resizable window**, dragged from a corner, with the size remembered.
9. **Waypoints stay native** (`C_Map.SetUserWaypoint` + super-track); no TomTom.
10. **Build approach A.**

## The design

### Window

- **Size:** default 1040 × 640.
  - Resizable from a bottom-right grip, using `SetResizable(true)`, `SetResizeBounds(minW, minH, maxW, maxH)`
    when present, and `StartSizing("BOTTOMRIGHT")`.
  - Minimum about 900 × 520, so the list and detail minimums below still fit. Maximum: the UIParent size.
  - Size saved with the position in `ns.db.window` (`w`, `h`) and restored, clamped to the bounds.
  - Everything that today reads `UI.WIDTH`/`UI.HEIGHT` (`VisibleHeight`, `ContentWidth`,
    `DetailVisibleHeight`, the row pool size) must use the live size instead, and re-layout on `OnSizeChanged`.
- **Frame:** flat dark background, thin bronze border, no Encounter Journal background texture. Panels use the
  same flat style. Exact border art is the builder's choice, but it must read like the mockup, not like the old
  `UI-DialogBox-Border`.
- **Columns, left to right:**
  - Rail: 64 px, fixed.
  - Header: 54 px tall, spanning everything right of the rail.
  - List and detail below the header. The list takes about 42% of that width, clamped to [380, 520] px, and the
    detail pane takes the rest (minimum 420). *(My call; the builder may tune the split, keeping both
    minimums.)*
- Escape still closes (UISpecialFrames). Dragging still moves the window, and position and size are saved.

### Rail

- At the top, the addon icon (`Interface\Icons\INV_SideTab_Professions_c60`, the TOC icon), purely decorative.
- Then the **shown character's professions** in today's order (crafting first, then gathering, by baked
  English name), each with its skill number under the icon.
- Then a divider, then the professions the character doesn't have, smaller (about 26 px) and desaturated, no
  number.
- The grouping follows the shown character, so switching to an alt can reorder the rail. *(My call.)*
- Selected profession: a 3 px left marker and a glow around its icon, in that profession's accent colour; its
  skill number takes the accent colour too.
- Hover tooltip: the profession name plus "Skill X / Y" or "Not learned". Click selects it, like today's tabs.

### Header

- From left to right:
  - profession icon and name (`GameFontNormalLarge`-sized, gold)
  - a **skill bar**
  - a **recipes learned** bar
  - the **character selector** (moved here from the tab column, same behaviour and menu, anchored below it)
  - the close button
- **Skill bar:** "Skill" label with `X / Y`, using the game's own profession bar art:
  - `Professions-skillbar-bg`, `Professions-skillbar-frame` and `Professions-skillbar-mask`
  - the fill atlas `Skillbar_Fill_Flipbook_<Kit>`, a flipbook animated with a FlipBook animation, or its first
    frame if flipbooks fail
  - the edge flare `Skillbar_Flare_<Kit>` when present
  - When the character doesn't have the profession, the bar is replaced by "Not learned".
- **Recipes learned bar:** `learned / total` for the shown character, with a plain bronze-to-gold bar. This
  replaces today's "91 / 419 learned" counter under the list.
- **Background:** a faint glow in the accent colour at the top left, and the profession's illustration as a
  low-alpha watermark when the art exists (see Profession art).

### Toolbar (top of the list panel)

- **Search box:**
  - magnifier icon and a "Search recipes…" placeholder
  - same matching as today (recipe name, case-insensitive, ignores collapsed groups)
  - Escape/Enter clear focus
- **Filter toggle:** All / Learned / Missing as one joined control.
  - The selected segment is clearly lit (gold text on a darker gold background); the others are muted.
  - Each segment shows its count for the profession and shown character, *ignoring the search text*.
  - The filter is still saved in `ns.db.filter`.
- **Collapse all / Expand all:** two icon buttons with tooltips.
  - *Collapse all* marks every category of the current profession's tree, at any depth, as collapsed in
    `ns.db.collapsed`. *Expand all* clears them.
  - The "Other" node shares the key `M.OTHER` across professions. Collapse all may set it; that's accepted.
  - While a search is active the list ignores collapse state (as today). The buttons still update the saved
    state. *(My call.)*

### Recipe list

The list is virtualized as today, but with **two row heights**:

- **Group headers, 24 px:**
  - chevron (right when collapsed, down when open), indented by depth
  - category name in gold
  - a small learned/total progress bar and the `learned/total` text on the right
  - Click toggles, as today.
- **Recipe rows, 34 px:**
  - 26 px recipe icon (`M.RecipeIcon`).
  - **Line 1:** the recipe name in its difficulty colour (`M.Difficulty`, as today). On the right, a green ✓ if the
    shown character knows it, otherwise the icon of its *primary source* (below).
  - **Line 2, small and muted:**
    - Not learned: `Learn <learn>`, then ` · `, then the primary source text, then ` · +N more` when there are
      other sources.
      - `Learn N` is red when the shown character has the profession and its skill is below N.
      - It's neutral when the skill is unknown.
      - When the recipe has no `learn` value, `Learn N · ` is left out.
    - Learned: the four thresholds in their colours (today's `M.RangeText`).
  - Selected row: a gold left edge and a light gold tint. Hover shows the spell tooltip, as today.

**Primary source.** It's the first match in this order: `auto`, trainer, vendor, quest, drop, object, container,
crafted, worldObject. If none matches, it's "Source unknown". *(My call: easiest-to-get first.)*

| Source | Text | Icon |
|---|---|---|
| auto | "Learned with the profession" | trainer icon |
| trainer | "Trainer · <cost>" (cost when known) | trainer book |
| vendor | "Vendor · <NPC> (<zone>)" | vendor coin |
| quest | "Quest · <quest name>" | quest mark |
| drop | "Drop · <NPC> (<zone, or dungeon name for instance bosses>)" | **loot icon** |
| object | "Found in <object>" | builder picks |
| container | "Contained in <item name, or 'a container' until it loads>" | builder picks |
| crafted / worldObject | today's `L.SRC_CRAFTED` / `L.SRC_WORLDOBJECT` | builder picks |
| unknown | "Source unknown" | question mark |

**Which NPC a row names** *(my call, following the alt-support design's vendor-faction hint)*:

- Within the primary source type, the row names the first entry the **shown character's faction** can use: NPC
  faction `"AH"`, or the character's own side. The character's faction comes from its cached record
  (`ns.GetChar(key).faction`, "Horde" or "Alliance").
- If no entry is usable, it names the first one, followed by its faction tag ("Alliance").
- An unknown faction counts as usable.
- So `M.PrimarySource` takes the faction too, e.g. `M.PrimarySource(rec, faction)`.
- This matters: 415 of the 742 vendor-first recipes mix factions with a one-faction vendor listed first.

- Unverified source types (`rec.unverified`) count as that type, without a name: "Vendor (location unknown)".
- **+N more** counts the other source entries in the record:
  - vendors, quests, objects and containers count each entry
  - drops count `dropTotal` (or the number of `drops`)
  - trainer and auto count 1 each
  - entries of both factions count
- Item names (containers) and quest/NPC names come from the same sources as today: live item API, baked
  names, and `ns.Data.Locale` when present.

The empty list ("No recipes match.") stays.

### Detail pane

- **Pinned header**, outside the scroll frame:
  - the output item's icon with a border in its quality colour
  - the recipe name in its difficulty colour
  - "Creates `[count×]` <item name in quality colour>", plus the item's subtype when the client gives it cheaply
    (e.g. `C_Item.GetItemInfoInstant`); otherwise the item name alone
  - chips: "✓ Learned" (green) or "Not learned" (red), the category name, and "New in Forever" when `rec.new`
  - on the right, a **difficulty scale**: a bar running orange → yellow → green → grey from `learn` to `grey`,
    the four numbers under it, and a white tick at the shown character's skill when it falls in or near the
    range
- **Scroll area** below the header, scrollbar only when needed (as today).
- **Sections:** gold title with a rule. Order depends on the state.
  - **Not learned:**
    1. **Where to get it**, opening with "Get <recipe item> from:" (item icon, name in quality colour,
       tooltip) when `rec.teach` exists. Several items mean one line each.
    2. **Characters**
    3. **Reagents**
  - **Learned:**
    1. **Reagents**
    2. **Characters**
    3. **Where to get it**, folded: one line with a right chevron and the primary source text. Clicking it
       expands the full section in place. The expanded or folded choice lasts for the session, across
       recipes, and isn't saved. *(My call.)*
- **Reagents:** a grid of slots: icon in a bordered slot with the count overlaid, name in quality colour, item
  tooltip on hover. Two columns when the pane is at least about 440 px wide, one otherwise. Items load async
  exactly as today.
- **Characters:** one row per group (known by / learnable by / skill too low) from `ns.RecipeOwners`, each with
  a coloured dot (green / yellow / grey). The names and hints are the same as today's `ns.OwnerLines`. "No
  character has this profession" when empty.
- **Where to get it:** each source is a **card**:
  - round type icon
  - title line (NPC <sub>, object, quest `[level] name`, or container item)
  - muted detail line (drop rate, faction tag, zone + coords, cost, "Given by …" for quests)
  - a **Waypoint** button on the right when there are coordinates; a muted "Dungeon" label for instance NPCs
    without an outdoor map

  Around the cards:
  - Within each source type, entries the shown character's faction can use come first (data order kept),
    then the other faction's. *(My call.)*
  - Trainer and auto are a single card or line.
  - "+N more" lines stay.
  - Requirements (rep, Merchant's Favor, faction-only) become chips or a line at the top of the section.
  - Unverified and unknown notes keep their orange warning style.
  - The content is what `M.SourceLines` produces today, restructured into cards (see Code shape).
- **Nothing selected** *(my call)*:
  - the profession's illustration as a large faint watermark (when the art exists)
  - "Select a recipe."
  - three small stat boxes: **Learned**, **Learnable now** (not learned, the shown character has the profession,
    skill ≥ `learn`, not locked to the other faction), **Missing**
  - no clicks on them

### Profession art and colours

Each profession gets a theme entry: the skill bar kit name, an accent colour, a fallback bar gradient and
(optionally) the watermark atlas.

- **Skill bar kits:** `Skillbar_Fill_Flipbook_<Kit>` exists on this client for at least FirstAid, Herbalism,
  Alchemy, Engineering and DefaultBlue, the kits FDJ probes. The kits for the other professions must be checked
  in game (`C_Texture.GetAtlasInfo`). If a profession has no kit, its bar is a plain colour texture with the
  fallback gradient, drawn with the same frame and mask.
- **Colours from the user's screenshot** (the Professions book bars), used for the accent and fallback:

  | Profession | Bar gradient | Accent |
  |---|---|---|
  | Blacksmithing | `#7a1205 → #d4400c → #ff9a1f → #ffe680` | `#ff8a1f` |
  | Mining | `#2a1e12 → #6a4a22 → #c8902e → #ffd970` | `#d9a441` |
  | Cooking | `#2a3440 → #7d8b9a → #dfe6ee → #ffffff` | `#c9d3de` |
  | Fishing | `#14203a → #2f5aa8 → #7fb0ff → #cfe2ff` | `#6aa0ff` |
  | First Aid | `#1d5a08 → #3fae12 → #8af040 → #d8ffb0` | `#6fdc2a` |

  The builder picks accents for Alchemy, Enchanting, Engineering, Leatherworking, Tailoring, Herbalism and
  Skinning from their game bar art once it's seen in game.
- **Watermark illustrations** (the anvil, pot and fishing gear behind the Professions book panels): atlas or
  texture names unknown. Find them in game by reading the regions of `ProfessionsBookFrame` while the user has
  it open, without hooking or modifying it. If they can't be found, drop the watermark: no substitute art.
- **Source icons**, including the loot icon for drops: client textures or atlases picked and checked in game.

### In-game probe (first step of the plan)

Before building the art, one throwaway check in game. It can be a `/run` snippet for the user, or a temporary
debug command that is not committed. It reports:

1. which `Skillbar_Fill_Flipbook_<Kit>` and `Skillbar_Flare_<Kit>` atlases exist for each of the 12 professions,
   with `Professions-skillbar-bg/frame/mask`
2. the atlas or texture of the illustration behind each profession panel in `ProfessionsBookFrame`
3. candidate textures for the source icons, especially the loot icon
4. that `SetResizeBounds` exists (FDJ's Resize.lua suggests it does)

Blizzard's Professions book only shows the logged-in character's own professions, so the probe can't rely on it
to *see* the other bars.

- It also opens a **throwaway preview frame** that draws all 12 skill bars (kit art or fallback) and the source
  icon candidates side by side.
- The user takes a screenshot of it and sends it back, as they have throughout.
- Accents for the seven unseen professions and the source icons get picked from that screenshot. Expect a
  round or two.
- The same screenshot routine is used to check the finished window against the mockup.

The results fill in the theme table. Nothing waits on the probe except the art.

## Code shape

- **New `UI/Widgets.lua`** (in the TOC, before the other UI files): factories for the flat panel, filter
  toggle, icon button, chip, source card, item slot and skill bar. It also holds the theme table and the
  helpers to apply a profession's accent. The widgets don't read addon state.
- **`UI/Window.lua`:**
  - rail, header, toolbar, character selector placement
  - resizing and layout on size change
  - size and position save and restore
  - collapse all / expand all
- **`UI/RecipeList.lua`:**
  - two row heights, with entry offsets computed from heights
  - the first visible entry found by offset, so scrolling stays O(visible rows)
  - the row pool sized from the live height and the smaller row height, grown on resize
- **`UI/Detail.lua`:** pinned header, scroll area, state-dependent section order, folded sources, reagent grid,
  source cards, empty state.
- **`Model.lua`**, frame-free and tested:
  - `M.PrimarySource(rec)` → `{ type, text, more }`
  - the row's second-line text
  - a card-shaped version of the source lines (or `M.SourceLines` extended so each line says which card it
    belongs to)
  - the section order for a state
  - the "learnable now" count
  - the filter counts

  The exact function names are the builder's call.
- **`Locale.lua`:** new enUS strings (Learn %d, Where to get it, Learnable now, Collapse all, Expand all, Search
  recipes…, Get %s from:, Learned with the profession, etc.). Old strings that are no longer used are removed.
- **`ns.db`:** `window.w`, `window.h` added. No other saved-variable changes and no version bump: missing size
  means the default.

## Tests

Existing tests in `tests/test_ui.py` and `tests/test_detail.py` that depend on the old structure (tabs, filter
buttons, counter, check textures, row heights, detail line order) are rewritten for the new one, not deleted.
New tests cover:

- rail grouping for the logged-in character and for an alt
- collapse all / expand all, including nested categories and the search override
- filter counts
- row second lines for each source type, "+N more", red vs neutral "Learn N", and the faction rule (Horde and
  Alliance characters see different vendors on a mixed-faction recipe)
- virtualized list with mixed heights: the right rows at a given scroll offset, a small pool, a pool that grows
  on resize
- resize: layout recomputed, size saved and restored, bounds respected
- detail order for learned vs not learned, folded sources toggle, reagent columns by width, empty-state counts
- skill bar fallback when the kit atlas is missing (the mock's `C_Texture.GetAtlasInfo` returns nil for unknown
  atlases)

The mock (`tests/wow_mock.lua`) gains what the new code needs: `SetResizable`, `SetResizeBounds`,
`StartSizing`, `OnSizeChanged`, `CreateMaskTexture`, animation groups, and so on, kept minimal.

## Left to the builder

- Exact sizes, paddings and font objects, within the mockup's look.
- The panel border art, scrollbar styling, chip and card textures.
- The list/detail width split, within the stated minimums.
- Function and file-internal structure. The order of the work, as long as each step leaves the addon working and
  the tests green.
- Source icon textures and accent colours for the seven unseen professions, after the probe.
- Whether the flipbook animates or shows a still frame, if animation proves fiddly.
