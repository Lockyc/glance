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
- **Notarized releases.** The release zip is ad-hoc signed, so Gatekeeper blocks it on another
  Mac until the user right-click → Opens it. Unlock: a Developer ID cert in the release
  environment, the same notary flow the sibling Tauri apps use.
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
