# CurseForge logo: design

Small change: a new image for the CurseForge project page. No addon code changes. Approach: hand-written SVG, with the PNG exported by headless Chrome.

## Why

The CurseForge project needs an avatar. At a glance it should say **"every recipe in one book"**, the idea the addon is built on.

CurseForge's avatar rules: 400×400, not a single flat colour, no copyrighted art, no webp. That rules out the addon's in-game icon (`Interface\Icons\INV_SideTab_Professions_c60`, the crossed hammer and pick), which is Blizzard art. Lists show the avatar at about 24–64 px, so it has to read at that size.

## Goals

- At 24–64 px it reads as a book about professions, and at 400 px it looks finished.
- Original art only.

## Non-goals

- The in-game icon (the TOC `IconTexture`, the minimap button), banners, or other sizes. Using the logo there is separate work with its own constraints.

## Anti-goals

- Anything that looks like Blizzard art, the WoW logo or Dungeon Journal frames.
- A curved blade crossed with a hammer, which reads as a hammer and sickle.
- Detail that turns to mush below 40 px.

## The design (chosen with mockups)

- **Canvas:** 400×400, a full-bleed dark navy radial background (`#2d3549` → `#10141d`) with no rounded corners, since CurseForge rounds them itself.
- **Book:** a squarer closed book that fills most of the canvas. It has:
  - a brown leather cover with a grain texture, a bevelled edge and dark outlines
  - a rounded spine with four raised bands
  - a thick block of pages with visible page edges
  - a soft shadow under the book
  - a red bookmark ribbon at the bottom
- **Tabs:** seven coloured index tabs on the fore edge (red, orange, yellow, green, teal, blue, purple). They stand for every profession being in here.
- **Frame:** one gold frame on the cover. The double frame was dropped.
- **Emblem:** one **cross-peen hammer**, upright and centred, **carved into the leather**: a dark recess with an inner shadow and a light lip, no colour.
- **Reference:** the mockup "1 · Cross-peen", Carved finish (symbol `i-cpC` in the visual companion's `hammers.html`).

How we got there: a book with an emblem, an open book and a tabbed index were compared, and the tabbed index was picked. Then came crossed tools, a medallion and several carving finishes. The crossed tools were too busy for CurseForge's sizes, so the user chose a single hammer, then a bigger, more defined book, then this hammer and finish.

## Approaches

- **Hand-written SVG, PNG exported by headless Chrome (picked).** The mockups are already SVG, and Chrome renders the PNG exactly as the mockups looked. The SVG stays in the repo as the editable source.
- **Redraw in Inkscape or Figma.** Dropped: the work would be done twice for no gain.
- **A Python rasteriser such as cairosvg.** Dropped: it handles the grain (`feTurbulence`) and carving filters differently from Chrome, and it would add a dependency.

## Build

1. `docs/logo/logo.svg`: a standalone SVG (`viewBox="0 0 400 400"`), cleaned up from the mockup. It keeps only the definitions it uses, with readable ids and short comments, and has no external references. A header comment gives the export command.
2. `docs/logo/logo-400.png`: exported from the SVG at exactly 400×400 with headless Chrome.
3. Nudge the hammer a few pixels so the lopsided head looks centred (my call).
4. Check the PNG at 400, 64, 40 and 24 px before handing it over.
5. `.gitignore`: add `.superpowers/` (the mockup folder).

Location (my call): `docs/` is already on the packager's ignore list in the planned `.pkgmeta`, so the logo can never end up inside the addon zip.

## Left to the builder

Exact pixel nudges, ids and comment wording.

## Commits

1. This design.
2. The logo (SVG and PNG) and the `.gitignore` line.
