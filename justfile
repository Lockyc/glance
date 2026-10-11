version := `cat VERSION`
app := ".build/glance.app"

# `default` pipes `just --list` through a small stock-perl filter that clips long recipe
# docs to your terminal width (…) instead of wrapping. Self-contained — no external files;
# falls back to plain `just --list` where perl is absent. Edit the recipes below, not this.
# List available recipes
default:
    @if command -v perl >/dev/null 2>&1; then just --color always --list | perl -CS -Mutf8 -lpe 'BEGIN{($w)=`stty size 2>/dev/null </dev/tty`=~/ (\d+)/; $w||=100; $col=(-t STDOUT && !exists $ENV{NO_COLOR})} s/\e\[[0-9;]*m//g unless $col; (my $v=$_)=~s/\e\[[0-9;]*m//g; if(length($v)>$w){my($o,$n)=("",0); while(length && $n<$w-1){ if($col && s/^(\e\[[0-9;]*m)//){$o.=$1}else{s/^(.)//;$o.=$1;$n++} } $_=$o."…".($col?"\e[0m":"")}'; else just --list; fi

# Non-mutating pre-merge gate: the unit tests
gate: test

# Run the unit tests
test:
    swift test

# Run the latency benchmarks (skipped in plain `test`)
bench:
    GLANCE_BENCH=1 swift test --filter BenchmarkTests

# Build the release binary
build:
    swift build -c release

# Assemble .build/glance.app (version from VERSION, document types from --list-types)
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
    codesign --force --sign - "{{app}}"

# Build and open glance on the given files/folders
run *paths: bundle
    open -a "$PWD/{{app}}" {{paths}}

# Install to /Applications and register with Launch Services
install: bundle
    rm -rf /Applications/glance.app
    cp -R "{{app}}" /Applications/glance.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/glance.app

# Install, then make glance the default viewer for every image type except PDF
make-default: install
    /Applications/glance.app/Contents/MacOS/glance --make-default
