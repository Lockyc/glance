---
type: architecture
---
# glance

A native macOS (14+) image viewer: ←/→ through the current folder, a thumbnail grid with
hover-enlarge preview, zoom/pan/fullscreen, and the default handler for every image type
except PDF. One Swift package, no Xcode project, no third-party dependencies.

## Layout

```
Package.swift
VERSION                  # the one version source
justfile                 # test / bench / gate
Sources/GlanceCore/      # all logic — unit-tested
Sources/glance/          # the AppKit shell (executable)
Resources/               # Info.plist template for the bundle
Tests/GlanceCoreTests/
```

Logic lives in `GlanceCore` and is unit-tested; `Sources/glance` is the AppKit shell and stays
thin. Anything testable without a window belongs in `GlanceCore`.

## Conventions

- PDF is never listed or claimed — every type set excludes types conforming to `UTType.pdf`.
- No decoding on the main thread; failures render in place, never as a modal.

## Branches and releases

`main` + `dev`. All work commits to `dev` and is pushed immediately; `main` advances only by a
fast-forward to `dev` at release. `VERSION` is the single version source; tags are
`v<VERSION>`, each with a GitHub release carrying notes.

## Build & test

`just test` (unit tests), `just gate` (pre-merge gate), `just bench` (latency benchmarks).
