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

A native macOS (14+) image viewer: ←/→ through the current folder, a thumbnail grid with
hover-enlarge preview, zoom/pan/fullscreen, and the default handler for every image type
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

Cutting a release: bump `VERSION` on `dev`, curate `README.md`, `just gate`, fast-forward `main`
to `dev` and push, tag `v<VERSION>` and push the tag, then `just bundle`, zip `.build/glance.app`
with `ditto -c -k --keepParent`, and `gh release create` with the zip and notes.

## Build & test

`just test` (unit tests), `just gate` (pre-merge gate), `just bench` (latency benchmarks).
