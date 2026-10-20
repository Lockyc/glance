---
type: architecture
links:
  - rel: see-also
    to: README.md
    note: human-facing counterpart — what glance is and how to build it
  - rel: see-also
    to: docs/FOLLOWUPS.md
    note: deferred work — what is next
---
# glance

A native macOS (14+) image viewer: ←/→ through the current folder (or, for a folder with
Include Subfolders on, its whole tree oldest-first), a thumbnail grid with
hover-enlarge preview, zoom/pan/fullscreen, image sets (`glance <files>`), a comparison grid of
labelled variants (`glance --variant …`), and the default handler for every image type
except PDF. One Swift package, no Xcode project, no third-party dependencies.

**What's next:** `docs/FOLLOWUPS.md` — deliberately deferred work.

## Layout

```
Package.swift
VERSION                  # the one version source
justfile                 # recipes: `just` lists them
Sources/GlanceCore/      # all logic — unit-tested
Sources/glance/          # the AppKit shell (executable)
Resources/Info.plist     # bundle template; `just bundle` fills its version (from VERSION)
                         # and document types (from `glance --list-types`) — never hand-edit them
Tests/GlanceCoreTests/   # unit tests for GlanceCore
Tests/glanceTests/       # the shell, driven with synthetic key and mouse events
```

Logic lives in `GlanceCore` and is unit-tested; `Sources/glance` is the AppKit shell and stays
thin. Anything testable without a window belongs in `GlanceCore`.

## Conventions

- PDF is never listed or claimed — every type set excludes types conforming to `UTType.pdf`.
- No decoding on the main thread; failures render in place, never as a modal.
- A set or comparison window (`Scope.fixed`) is never scanned, watched, or reused by an ordinary open.
- A tree's `FolderModel.files` and `dates` stay parallel (the grid's month sections index
  both): pass a tree's dates to every `replaceFiles(_:dates:)`; a flat folder has none.

## Branches and releases

`main` + `dev`. All work commits to `dev` and is pushed immediately; `main` advances only by a
fast-forward to `dev` at release. `VERSION` is the single version source; tags are
`v<VERSION>`, each with a GitHub release carrying notes.

Cutting a release: bump `VERSION` on `dev`, curate `README.md`, commit and push `dev`. The
release itself (notarize, tag, fast-forward `main`, publish `glance.zip`) is run by the
maintainer's release tooling, outside this repo. The interface it relies on: `just gate`, and
`just bundle` signing the justfile's `app` (`.build/glance.app`) with the Developer ID named by `APPLE_SIGNING_IDENTITY` and the
hardened runtime. Without that variable the bundle is ad-hoc signed, which runs locally.

## Build & test

`just test` (unit tests), `just gate` (pre-merge gate), `just bench` (latency benchmarks), `just snapshot DIR` (renders the comparison grid, viewer and hover previews off screen to PNGs in DIR).
