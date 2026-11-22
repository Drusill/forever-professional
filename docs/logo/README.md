# Logo

The CurseForge project avatar: a tabbed recipe book with a cross-peen hammer carved into its leather cover. Original artwork, GPL-3.0-or-later like the rest of the repo. Design: [`docs/superpowers/specs/2026-11-21-curseforge-logo-design.md`](../superpowers/specs/2026-11-21-curseforge-logo-design.md).

| File | What |
|---|---|
| `logo.svg` | The source. Edit this one |
| `logo-400.png` | The 400×400 avatar uploaded to CurseForge, exported from the SVG |

Export the PNG again after editing the SVG (Git Bash, from the repo root). Chrome renders the grain and carving filters exactly as they were designed:

```
R=$(pwd -W)   # the repo root as C:/..., which Chrome understands
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=400,400 --user-data-dir="$TEMP/fp-logo-chrome" \
  --screenshot="$R/docs/logo/logo-400.png" "file:///$R/docs/logo/logo.svg"
```
