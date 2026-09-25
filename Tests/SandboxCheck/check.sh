#!/bin/zsh
# The sandbox check (see docs/screensaver.md, section 10): run it by hand after each macOS update
# and before a release. It isn't part of `xcodebuild test`.
#
#     Tests/SandboxCheck/check.sh
#
# The screensaver runs inside Apple's sandboxed legacyScreenSaver host, and plays the playlist that
# SGF Tools.app writes. This builds a small probe (probe.swift) twice with swiftc, signs one copy
# with the host's public file entitlements, read from the installed host so that a change shows,
# and one with App/SGFTools.entitlements, and checks the round trip the design depends on:
#
# 1. the app-like probe writes a test file in ~/Library/Application Support/SGF Tools/
# 2. the host-like probe reads it
# 3. the host-like probe may not write there
# 4. both get the same count of the screensaver's games from Spotlight, which filters its answers
#    by the sandbox: with the sandbox alone, the count is 0
# 5. the app-like probe removes the test file.
#
# It never opens an SGF file, so it can't raise a permission request. It leaves two small
# containers, com.pragmaphilia.SGFTools.SandboxCheck.Host and .App, in ~/Library/Containers.
# It prints PASS or FAIL for each step and exits 1 if any step fails.

set -u
here=${0:A:h}
repository=${here:h:h}
host=/System/Library/Frameworks/ScreenSaver.framework/PlugIns/legacyScreenSaver.appex
home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')
folder="$home/Library/Application Support/SGF Tools"
testFile="$folder/Sandbox Check $$.txt"
buddy=/usr/libexec/PlistBuddy
work=$(mktemp -d "${TMPDIR:-/tmp}/SGFToolsSandboxCheck.XXXXXX")
failures=0
folderExisted=0
[[ -d $folder ]] && folderExisted=1
trap 'rm -rf "$work"' EXIT

report() {  # report <PASS|FAIL> <message>
    print -- "$1  $2"
    [[ $1 == FAIL ]] && failures=$((failures + 1))
}

# The host's file entitlements: the sandbox and its file exceptions, without the private and
# network ones, which an ad hoc signed tool can't have.
codesign -d --entitlements - --xml "$host" > "$work/host-all.plist" 2>/dev/null \
    || { print "Can't read the entitlements of $host"; exit 1; }
for key in com.apple.security.app-sandbox com.apple.security.temporary-exception.yasb \
           com.apple.security.files.user-selected.read-only com.apple.security.files.bookmarks.app-scope; do
    if value=$($buddy -c "Print :$key" "$work/host-all.plist" 2>/dev/null); then
        $buddy -c "Add :$key bool $value" "$work/host.entitlements" >/dev/null
    fi
done
key=com.apple.security.temporary-exception.files.absolute-path.read-only
if $buddy -c "Print :$key" "$work/host-all.plist" >/dev/null 2>&1; then
    $buddy -c "Add :$key array" "$work/host.entitlements" >/dev/null
    index=0
    while value=$($buddy -c "Print :$key:$index" "$work/host-all.plist" 2>/dev/null); do
        $buddy -c "Add :$key: string $value" "$work/host.entitlements" >/dev/null
        index=$((index + 1))
    done
fi
print "The host's file entitlements:"
plutil -p "$work/host.entitlements" | sed 's/^/    /'

# A sandboxed command-line tool needs an Info.plist with a bundle identifier in its
# __TEXT,__info_plist section, or it stops with SIGTRAP before main.
build() {  # build <name> <identifier> <entitlements>
    $buddy -c "Add :CFBundleIdentifier string $2" "$work/$1-Info.plist" >/dev/null
    swiftc -O -o "$work/$1" "$here/probe.swift" \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$work/$1-Info.plist" \
        || { print "Building the $1 probe failed"; exit 1; }
    codesign -s - -f -i "$2" --entitlements "$3" "$work/$1" 2>/dev/null \
        || { print "Signing the $1 probe failed"; exit 1; }
}
build host com.pragmaphilia.SGFTools.SandboxCheck.Host "$work/host.entitlements"
build app com.pragmaphilia.SGFTools.SandboxCheck.App "$repository/App/SGFTools.entitlements"

# expect <ok|refused> <step> <probe> <arguments…>
expect() {
    local wanted=$1 step=$2 probe=$3
    shift 3
    local output
    output=$("$work/$probe" "$@" 2>&1)
    if [[ $output == "$wanted "* ]]; then
        report PASS "$step: $output"
    else
        report FAIL "$step: expected $wanted, got: $output"
    fi
}

print
expect ok "The app writes the playlist's folder" app write "$testFile"
expect ok "The host reads what the app wrote" host read "$testFile"
expect refused "The host may not write the playlist's folder" host write "$folder/Sandbox Check $$ host.txt"
hostCount=$("$work/host" count 2>&1)
appCount=$("$work/app" count 2>&1)
if [[ $hostCount == "ok "* && $hostCount == "$appCount" && $hostCount != "ok 0 games" ]]; then
    report PASS "The host and the app get the same games from Spotlight: ${hostCount#ok }"
else
    report FAIL "Spotlight: the host got \"$hostCount\", the app \"$appCount\""
fi
expect ok "The app removes its test file" app remove "$testFile"

rm -f "$testFile" "$folder/Sandbox Check $$ host.txt"
(( folderExisted )) || rmdir "$folder" 2>/dev/null
print
if (( failures )); then
    print "$failures step(s) failed. See docs/screensaver.md, section 12, for what each means."
    exit 1
fi
print "Every step passed."
