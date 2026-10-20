---
type: roadmap
links:
  - rel: see-also
    to: CLAUDE.md
    note: architecture and conventions
---
# Follow-ups

Deliberately deferred work. Remove an entry when it ships.

- **Installer (`install.sh` + `/glance:install`).** Install is `just install` from a clone
  today. A curl-pipeable `install.sh` and the guided slash command would let someone without
  `just` install glance. Unlock: someone other than the author installing it.
- **RAW at actual size shows the embedded preview.** `ImageDecoder` takes a RAW's embedded JPEG
  when it is at least half the requested size, including for zoom upgrades, so a camera whose
  preview is under full size looks soft at 100%. Fix: skip the embedded preview for upgrades.
- **⌘-scroll zoom with a notched mouse wheel** moves about 1% per notch (`ViewerView.scrollWheel`
  scales line deltas like trackpad pixels). Fix: scale by `hasPreciseScrollingDeltas`.
- **Hover preview after a click-to-open.** The 150 ms hover timer can fire on the hidden grid,
  showing a stale preview on return; a failed preview decode leaves an empty shadowed box.
- **Unreadable folder** reads "No images in this folder" instead of saying it can't be read.
- **An explicitly opened non-image file** drops out of the list at the next folder scan.
- **Animated images keep animating** while the grid is shown or the window is minimised.
- **The thumbnail disk cache is never pruned** (`~/Library/Caches/glance/thumbnails`).
- **Turning Include Subfolders off forgets the root's exclusions**, so off-then-on brings
  `timeline/`-style folders back. Fix: an `enabled` flag on `SubfolderRoots.Root`, with Settings
  showing disabled roots. Unlock: toggling a root off and on becoming a habit.
- **Opening a subfolder before the root's first walk lands** (or an empty subfolder) shows the
  tree's oldest image: `land(at:)` finds nothing and is not retried when the walk arrives.
- **Turning Include Subfolders on, then opening a subfolder file before the walk lands**, briefly
  shows only that file: `setScope` leaves `dates` empty, so `select(_:)`'s tree insert drops the
  flat list.
- **View → Subfolders reads the key window**, so with Settings in front it shows the "turn on"
  hint instead of the browser window's folders. Fix: fall back to `NSApp.mainWindow`.
- **A deleted or moved root keeps its last list**: the failed listing is ignored rather than
  emptying the window (same as a flat folder today).
- **Comparison row labels scroll away horizontally** when many variants overflow the width; only
  the header is pinned. Fix: pin the label column like the header.
- **The empty comparison cell's placeholder has low contrast** against a cell still loading.
  Fix: a dashed outline or a glyph.
- **Possible spurious horizontal scroller with always-visible scrollbars** in both grids: the
  comparison grid sizes its cells before the scrollers appear, and `GridViewController` never
  autohides its scrollers. Fix: size cells against the content width with scrollers shown.
- **The comparison viewer prefetches in list order, not 2D**, so ↑/↓ and the row wrap may decode
  cold. Fix: focus `DecodeCache` on the cell's 2D neighbours.
- **The cold-launch Open-panel guard (`isDefaultLaunch`) is untested against a real cold launch by
  URL** or a launch that restores saved state. Fix, if it misfires: set a flag in
  `application(_:open:)` instead.
