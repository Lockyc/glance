version := `cat VERSION`
app := ".build/glance.app"

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

# Build the release binary
[group("build")]
build:
    swift build -c release

# Assemble .build/glance.app (version from VERSION, document types from --list-types; signed with APPLE_SIGNING_IDENTITY, else ad-hoc)
[group("build")]
bundle: build
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{app}}"
    mkdir -p "{{app}}/Contents/MacOS" "{{app}}/Contents/Resources"
    cp .build/release/glance "{{app}}/Contents/MacOS/glance"
    plist="{{app}}/Contents/Info.plist"
    cp Resources/Info.plist "$plist"
    plutil -replace CFBundleShortVersionString -string "{{version}}" "$plist"
    plutil -replace CFBundleVersion -string "{{version}}" "$plist"
    for t in $(.build/release/glance --list-types); do
        plutil -insert CFBundleDocumentTypes.0.LSItemContentTypes -string "$t" -append "$plist"
    done
    if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
        codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "{{app}}"
    else
        codesign --force --sign - "{{app}}"
    fi

# Build and open glance on the given files/folders
[group("app")]
run *paths: bundle
    open -a "$PWD/{{app}}" {{paths}}

# Quit any running glance, then install to /Applications and register with Launch Services
[group("app")]
install: bundle quit
    rm -rf /Applications/glance.app
    cp -R "{{app}}" /Applications/glance.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/glance.app

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
