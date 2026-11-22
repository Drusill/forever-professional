# CurseForge Logo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved CurseForge avatar as an editable SVG plus a 400×400 PNG.

**Architecture:** Clean the approved mockup (`i-cpC` in the visual companion's `hammers.html`) into one standalone SVG. Export the PNG from that SVG with headless Chrome, so the PNG matches the mockups pixel for pixel. Nothing in `ForeverProfessional/` changes.

**Tech Stack:** SVG 1.1 with filters (`feTurbulence`, `feComponentTransfer`, `feOffset`, `feGaussianBlur`, `feComposite`, `feMerge`), headless Chrome (`C:\Program Files\Google\Chrome\Application\chrome.exe`), and the Python standard library for checks.

**Spec:** `docs/superpowers/specs/2026-11-21-curseforge-logo-design.md`

## Global Constraints

- 400×400 PNG, not a single flat colour, no copyrighted art, not webp.
- Original art only: nothing from Blizzard, the WoW logo or Dungeon Journal frames.
- No curved blade crossed with a hammer.
- Full-bleed background (`#2d3549` → `#10141d` radial), no rounded corners in the file.
- Book A, single gold frame, seven tabs (red, orange, yellow, green, teal, blue, purple), red ribbon, a cross-peen hammer upright and centred, carved finish (dark recess, inner shadow, light lip, no colour).
- Files live in `docs/logo/`. The SVG has no external references.

## Review Focus

- **Small sizes:** CurseForge shrinks the 400 px file to 24–64 px. The hammer and tabs must still read at 24, 40 and 64 px (checked in Task 1, step 6).
- **Light backgrounds:** a light page around the avatar must not show transparent or faded edges, so the background must cover all 400×400 (step 6 previews it on light and dark).
- **Corner rounding:** CurseForge rounds the corners. With a 12% radius, nothing important may be clipped: the tabs reach x = 380 and the ribbon y = 396 (step 6 previews it rounded).
- **Exact size:** Chrome must not add a scrollbar or margin, or scale the image. The PNG must be exactly 400×400 (step 5 checks the header).
- **Optical centring:** the cross-peen head is lopsided (wedge on the right), so the geometric centre looks off. It's nudged until it looks centred, and step 6 compares it with the mockup.

---

### Task 1: Logo SVG and PNG

**Files:**
- Create: `docs/logo/logo.svg`
- Create: `docs/logo/logo-400.png` (generated)
- Modify: `.gitignore` (add `.superpowers/`)
- Scratch: `<scratchpad>/logo-preview.html`, `<scratchpad>/logo-preview.png` (not committed)

**Interfaces:**
- Consumes: the `bookA`, `cpHead`, `handle`, `grip`, `cpC` and `deboss` definitions in `.superpowers/brainstorm/1690-1795307159/content/hammers.html`.
- Produces: `docs/logo/logo.svg` (root `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">`) and `docs/logo/logo-400.png`.

- [ ] **Step 1: Add `.superpowers/` to `.gitignore`** under a `# Brainstorm mockups` comment. Check: `git status --short` no longer lists `.superpowers/`.

- [ ] **Step 2: Write `docs/logo/logo.svg`.** Inline `bookA` straight into the root (no `<symbol>`/`<use>` for the book). Keep only the gradients, patterns, clip path and filters it uses: `bg`, `leather`, `recess`, `gold`, `pages`, `spine`, `rib`, `bevel`, `edgeV`, `edgeH`, `coverClip`, `grain`, `soft`, `deboss`. Draw the hammer as one `<g filter="url(#deboss)" fill="url(#recess)" stroke="#1e0f05" stroke-width="2.5" stroke-linejoin="round">` holding the handle, grip and cross-peen head paths, at `transform="translate(199,193) scale(1.3)"` to start. Keep `style="mix-blend-mode:multiply"` on the grain `<rect>` (Chrome honours it in a standalone SVG). Header comment: what it is, the GPL-3.0-or-later notice ("Part of ForeverProfessional"), and the export command from step 4.

- [ ] **Step 3: Check the SVG is well formed and self-contained**

Run: `python -c "import xml.etree.ElementTree as E; E.parse('docs/logo/logo.svg'); print('ok')"` and `grep -nE 'href="(https?:|//)|<image' docs/logo/logo.svg`
Expected: `ok`, and grep prints nothing.

- [ ] **Step 4: Export the PNG**

Run (Git Bash): `"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=400,400 --user-data-dir="<scratchpad>/chrome-profile" --screenshot="C:/Users/cabez/Projectos/forever-professional/docs/logo/logo-400.png" "file:///C:/Users/cabez/Projectos/forever-professional/docs/logo/logo.svg"`
Expected: `… bytes written to file …logo-400.png`.

- [ ] **Step 5: Check the PNG header**

Run: `python -c "import struct;d=open('docs/logo/logo-400.png','rb').read(32);assert d[:8]==b'\x89PNG\r\n\x1a\n';print(struct.unpack('>II',d[16:24]))"`
Expected: `(400, 400)`.

- [ ] **Step 6: Visual check.** Write `<scratchpad>/logo-preview.html` showing `logo-400.png` at 400, 64, 40 and 24 px, twice: once on `#ffffff` and once on `#1b1f27`, all with `border-radius:12%`. Add the mockup screenshot next to it for comparison. Screenshot it with the step 4 command (window `1000,700`) and look at it. Pass when:
  - the hammer reads as a hammer and the tabs as a coloured strip at 24 px
  - no transparent or light edge shows on white
  - nothing important is clipped by the rounding
  - the hammer looks centred in the gold frame

  If it doesn't look centred, adjust the `translate` x in steps of 1–3 units, then repeat steps 4–6.

- [ ] **Step 7: Commit**

```bash
git add .gitignore docs/logo/logo.svg docs/logo/logo-400.png
git commit -m "Logo: CurseForge avatar (SVG source and 400px PNG)"
```
(The message ends with the Co-Authored-By line.)
