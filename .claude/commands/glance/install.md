You are installing or updating **glance** — a fast, keyboard-driven image viewer for macOS.

## 1. Check the Mac

```bash
sw_vers -productVersion
```

glance needs macOS 14 or later. On an older Mac, say so and stop.

## 2. Install

From a glance checkout (`[ -f install.sh ] && [ -f Package.swift ]`), ask with AskUserQuestion:
- **Latest release** (recommended): `bash install.sh`
- **This checkout's code**: `just install`

Outside a checkout, run `curl -fsSL https://raw.githubusercontent.com/lockyc/glance/main/install.sh | bash`.

If the installer needs `sudo`, the user types their password in this session: suggest `! <the command>`.

## 3. Check it from a new shell

```bash
"$SHELL" -lc 'command -v glance && glance --list-types | head -3'
```

Expect the link's path and three type identifiers. If `glance` isn't found, `~/.local/bin` is missing from `PATH`: show the line for the user's shell (fish: `fish_add_path ~/.local/bin`; zsh/bash: `export PATH="$HOME/.local/bin:$PATH"` in `~/.zprofile` / `~/.bash_profile`) and offer to add it.

## 4. Default viewer

Ask with AskUserQuestion whether glance should be the default viewer for every image type except PDF. On yes, run `glance --make-default` and report the count it prints.

## 5. Done

Report the installed version (`/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/glance.app/Contents/Info.plist`) and that `glance <file or folder>` opens it.
