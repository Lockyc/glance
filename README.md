# glance

[![Release](https://img.shields.io/github/v/release/lockyc/glance?sort=semver&label=release)](https://github.com/lockyc/glance/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-555)
![Swift](https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/lockyc/glance)](LICENSE)

A fast, keyboard-driven image viewer for macOS. Open any image and ←/→ step instantly through
the rest of its folder; a full-window thumbnail grid, with an enlarged preview on hover, swaps
in for jumping around. It opens every image format macOS can decode, plus SVG. PDFs stay with
Preview. Turn on View → Include Subfolders for a folder and everything under it becomes one
stream, oldest first, with month headers in the grid — a whole screenshots archive browsed in
order.

![glance showing the Carina Nebula, image 5 of 24 in its folder](docs/screenshots/viewer.png)

![glance's thumbnail grid, with the hovered Hourglass Nebula enlarged](docs/screenshots/grid.png)

## Install

Needs macOS 14+ and the Xcode command-line tools (Swift 6) plus [`just`](https://github.com/casey/just).

```bash
git clone https://github.com/lockyc/glance && cd glance
just install        # builds glance.app into /Applications
just make-default   # makes glance the default viewer for every image type except PDF
```

Opening a file shows it in its folder; opening a folder (or dropping one on the Dock icon)
opens the grid. A file anywhere inside a folder with Include Subfolders on opens that whole
tree, at that file. Subfolders can be left out from View → Subfolders or glance → Settings….

## Keys

**Viewer**

| Key | Action |
|---|---|
| ← / → | Previous / next image (wraps) |
| Home / End | First / last image |
| G or Space | Thumbnail grid |
| F or ⌃⌘F | Toggle full screen |
| Esc | Leave full screen |
| 0 / 1 | Fit to window / actual size |
| + / − | Zoom in / out |
| Pinch or ⌘-scroll | Zoom about the cursor |
| Drag, or scroll when zoomed | Pan |
| Double-click | Toggle fit ↔ actual size |

**Grid**

| Key | Action |
|---|---|
| ← / → | Previous / next image (across months) |
| ↑ / ↓ | Move the selection by row |
| Return or click | Open the image |
| Esc, G or Space | Back to the viewer |
| ⌘+ / ⌘− | Larger / smaller tiles (remembered) |
| Hover | Enlarged preview |

## Formats

Everything ImageIO decodes — JPEG, PNG, HEIC/HEIF, WebP, AVIF, JPEG XL, TIFF, BMP, GIF, ICO,
ICNS, PSD, OpenEXR, TGA and camera RAW (CR2, CR3, NEF, ARW, RAF, ORF, DNG and more) — plus SVG.
Animated GIF, WebP and APNG play. A file that won't decode shows "Can't open" in place and
navigation carries on.

## Development

```bash
just test    # unit tests
just bench   # latency benchmarks
just run     # build the bundle and open it
```
