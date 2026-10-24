#!/usr/bin/env bash
# install.sh — install or update glance from its latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/lockyc/glance/main/install.sh | bash
# Installs /Applications/glance.app and links `glance` into ~/.local/bin. Re-run to update.
# GLANCE_ZIP_URL, GLANCE_APP_DIR and GLANCE_BIN_DIR override the download and the two places.
set -euo pipefail

main() {
    zip_url=${GLANCE_ZIP_URL:-https://github.com/lockyc/glance/releases/latest/download/glance.zip}
    app_dir=${GLANCE_APP_DIR:-/Applications}
    bin_dir=${GLANCE_BIN_DIR:-$HOME/.local/bin}
    team=G9V8U6ZU5E
    lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

    fail() { echo "glance: $*" >&2; exit 1; }

    [ "$(uname)" = Darwin ] || fail "glance runs on macOS only."
    major=$(sw_vers -productVersion | cut -d. -f1)
    [ "$major" -ge 14 ] || fail "glance needs macOS 14 or later; this Mac runs $(sw_vers -productVersion)."

    # Runs a command as the user, or with sudo when $1 (a directory) isn't writable.
    in_dir() {
        local dir=$1
        shift
        if [ -w "$dir" ]; then "$@"; else sudo "$@"; fi
    }

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    echo "→ downloading glance"
    curl -fsSL "$zip_url" -o "$work/glance.zip" || fail "couldn't download $zip_url"
    ditto -x -k "$work/glance.zip" "$work/unzipped" || fail "the download isn't a zip."
    new="$work/unzipped/glance.app"
    [ -d "$new" ] || fail "the download holds no glance.app."
    [ -z "$(find "$work/unzipped" -maxdepth 1 -type l)" ] && [ ! -L "$new" ] \
        || fail "the download's glance.app is a link."
    codesign --verify --strict --deep "$new" 2>/dev/null || fail "the download's signature doesn't verify."
    info=$(codesign -dv "$new" 2>&1) || fail "the download's signature can't be read."
    printf '%s\n' "$info" | grep -qx "TeamIdentifier=$team" \
        || fail "the download isn't signed by glance's developer."
    spctl --assess --type execute "$new" 2>/dev/null || fail "macOS won't open the download: it isn't notarized."
    version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$new/Contents/Info.plist")

    if pgrep -U "$(id -u)" -x glance >/dev/null; then
        echo "→ quitting the running glance"
        pkill -U "$(id -u)" -x glance || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -U "$(id -u)" -x glance >/dev/null || break; sleep 0.5; done
        ! pgrep -U "$(id -u)" -x glance >/dev/null || fail "glance didn't quit; quit it from its menu and re-run."
    fi

    target="$app_dir/glance.app"
    echo "→ installing glance $version to $target"
    [ -d "$app_dir" ] || in_dir "$(dirname "$app_dir")" mkdir -p "$app_dir"
    staged="$app_dir/.glance.app.new"
    in_dir "$app_dir" rm -rf "$staged"
    in_dir "$app_dir" ditto "$new" "$staged" || fail "couldn't copy glance into $app_dir."
    old="$app_dir/.glance.app.old"
    in_dir "$app_dir" rm -rf "$old"
    if [ -e "$target" ]; then
        in_dir "$app_dir" mv "$target" "$old" \
            || fail "couldn't move the old $target aside. Allow your terminal in System Settings > Privacy & Security > App Management, or drag the old app to the Trash, then re-run."
    fi
    if ! in_dir "$app_dir" mv "$staged" "$target"; then
        [ ! -e "$old" ] || in_dir "$app_dir" mv "$old" "$target" || true
        fail "couldn't move glance into place at $target."
    fi
    in_dir "$app_dir" rm -rf "$old"
    "$lsregister" -f "$target" || fail "Launch Services wouldn't register $target."

    echo "→ linking $bin_dir/glance"
    [ -d "$bin_dir" ] || in_dir "$(dirname "$bin_dir")" mkdir -p "$bin_dir"
    in_dir "$bin_dir" ln -sfn "$target/Contents/MacOS/glance" "$bin_dir/glance"
    "$bin_dir/glance" --list-types >/dev/null || fail "$bin_dir/glance doesn't run."

    echo "✓ glance $version is in $target."
    echo "  \`glance --make-default\` makes it the default viewer for every image type except PDF."
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) echo "  $bin_dir isn't on your PATH; add it to run \`glance\` by name." ;;
    esac
}

main "$@"
