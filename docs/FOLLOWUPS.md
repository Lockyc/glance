---
type: roadmap
links:
  - rel: see-also
    to: ../CLAUDE.md
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
