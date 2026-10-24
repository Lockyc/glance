version := `cat VERSION`
app := ".build/glance.app"
info_plist := "Resources/Info.plist"

# `default` pipes `just --list` through a small stock-perl filter that clips long recipe
# docs to your terminal width (…) instead of wrapping. Self-contained — no external files;
# falls back to plain `just --list` where perl is absent. Edit the recipes below, not this.
# List available recipes
default:
    @if command -v perl >/dev/null 2>&1; then just --color always --list | perl -CS -Mutf8 -lpe 'BEGIN{($w)=`stty size 2>/dev/null </dev/tty`=~/ (\d+)/; $w||=100; $col=(-t STDOUT && !exists $ENV{NO_COLOR})} s/\e\[[0-9;]*m//g unless $col; (my $v=$_)=~s/\e\[[0-9;]*m//g; if(length($v)>$w){my($o,$n)=("",0); while(length && $n<$w-1){ if($col && s/^(\e\[[0-9;]*m)//){$o.=$1}else{s/^(.)//;$o.=$1;$n++} } $_=$o."…".($col?"\e[0m":"")}'; else just --list; fi

# Non-mutating pre-merge gate: the unit tests
[group("check")]
gate: test

# Run the unit tests
[group("check")]
test:
    swift test

# Run the latency benchmarks (skipped in plain `test`)
[group("check")]
bench:
    GLANCE_BENCH=1 swift test --filter BenchmarkTests

# Render the comparison grid, viewer and hover previews off screen to PNGs in DIR
[group("check")]
snapshot dir:
    GLANCE_SNAPSHOT_DIR={{dir}} swift test --filter SnapshotTests

# Build the release binary
[group("build")]
build:
    swift build -c release

# Assemble .build/glance.app (version from VERSION, document types from --list-types, Sparkle embedded; signed with APPLE_SIGNING_IDENTITY, else ad-hoc)
[group("build")]
bundle: build
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{app}}"
    mkdir -p "{{app}}/Contents/MacOS" "{{app}}/Contents/Resources" "{{app}}/Contents/Frameworks"
    cp .build/release/glance "{{app}}/Contents/MacOS/glance"
    install_name_tool -add_rpath @executable_path/../Frameworks "{{app}}/Contents/MacOS/glance"
    ditto .build/release/Sparkle.framework "{{app}}/Contents/Frameworks/Sparkle.framework"
    plist="{{app}}/Contents/Info.plist"
    cp "{{info_plist}}" "$plist"
    plutil -replace CFBundleShortVersionString -string "{{version}}" "$plist"
    plutil -replace CFBundleVersion -string "{{version}}" "$plist"
    for t in $(.build/release/glance --list-types); do
        plutil -insert CFBundleDocumentTypes.0.LSItemContentTypes -string "$t" -append "$plist"
    done
    # Inside-out: each nested Sparkle helper before the framework, the framework before the app.
    if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
        sign=(codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY")
    else
        sign=(codesign --force --sign -)
    fi
    sparkle="{{app}}/Contents/Frameworks/Sparkle.framework"
    "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
    "${sign[@]}" "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"
    "${sign[@]}" "{{app}}"

# Print the directory holding Sparkle's sign_update and generate_keys (resolving packages first)
[group("build")]
sparkle-bin:
    @swift package resolve >/dev/null
    @echo "{{justfile_directory()}}/.build/artifacts/sparkle/Sparkle/bin"

# Build and open glance on the given files/folders
[group("app")]
run *paths: bundle
    open -a "$PWD/{{app}}" {{paths}}

# Quit any running glance, install to /Applications, register with Launch Services, and link `glance` onto the PATH
[group("app")]
install: bundle quit
    rm -rf /Applications/glance.app
    cp -R "{{app}}" /Applications/glance.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/glance.app
    mkdir -p ~/.local/bin && ln -sf /Applications/glance.app/Contents/MacOS/glance ~/.local/bin/glance

# Quits any running glance, force-killing one still alive after 3s.
[private]
quit:
    #!/usr/bin/env bash
    killall glance 2>/dev/null || exit 0
    for _ in {1..30}; do pgrep -x glance >/dev/null || exit 0; sleep 0.1; done
    killall -9 glance 2>/dev/null
    while pgrep -x glance >/dev/null; do sleep 0.1; done

# Install, then make glance the default viewer for every image type except PDF
[group("app")]
make-default: install
    /Applications/glance.app/Contents/MacOS/glance --make-default
