#!/bin/sh
# Builds a release of SGF Tools: the app and the screensaver, each signed with a Developer ID, with
# the hardened runtime and a secure timestamp, notarized by Apple, and stapled, and a disk image
# holding both, an Applications link, and Distribution/Read Me.txt, itself signed, notarized, and
# stapled. So all three open on any Mac without a warning.
#
#   scripts/build-release.sh [output-folder]     (default: build/release)
#
# The folder gets "SGF Tools.app", "SGF Tools.saver", and SGF-Tools-<version>.dmg. Never launches
# anything. It needs the Developer ID identity in the login keychain, the notary credentials in a
# keychain profile (`xcrun notarytool store-credentials`), and the network; each of the three
# notarizations takes a few minutes. To use your own:
#
#   SGF_SIGNING_IDENTITY  default "Developer ID Application: FrissonTouch (2FCB9FTC4W)"
#   SGF_TEAM              default 2FCB9FTC4W, the identity's team
#   SGF_NOTARY_PROFILE    default notary-frissontouch
#
# The binaries are built as an archive would build them (DEPLOYMENT_POSTPROCESSING), so they carry
# neither the build's paths nor the debugging entitlement, which notarization refuses. The build
# registers the app with macOS, and with it its Spotlight importer: when you're done with the build
# folder, unregister the app before deleting it (see "Building from source" in the README).
set -eu

identity="${SGF_SIGNING_IDENTITY:-Developer ID Application: FrissonTouch (2FCB9FTC4W)}"
team="${SGF_TEAM:-2FCB9FTC4W}"
profile="${SGF_NOTARY_PROFILE:-notary-frissontouch}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
out="${1:-$repo/build/release}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
derived="$repo/build/release-derived"
version=$(sed -n 's/^    MARKETING_VERSION: *//p' project.yml | head -1)
products="$derived/Build/Products/Release"
app="$products/SGF Tools.app"
saver="$products/SGF Tools.saver"

# notarize <app, saver, or dmg>: sends it to Apple (a bundle as a zip), waits for the verdict, and
# staples the ticket to it. Fails, naming the command that fetches Apple's log, unless the verdict
# is Accepted.
notarize() {
    target="$1"
    work=$(mktemp -d)
    case "$target" in
    *.dmg) submission="$target" ;;
    *)
        submission="$work/$(basename "$target").zip"
        ditto -c -k --sequesterRsrc --keepParent "$target" "$submission"
        ;;
    esac
    result=$(xcrun notarytool submit "$submission" --keychain-profile "$profile" --wait 2>&1) || true
    rm -rf "$work"
    echo "$result"
    if ! echo "$result" | grep -q 'status: Accepted'; then
        id=$(echo "$result" | sed -n 's/^ *id: //p' | head -1)
        echo "error: notarization failed; its log: xcrun notarytool log ${id:-<id>} --keychain-profile $profile" >&2
        exit 1
    fi
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
}

echo "== Building SGF Tools $version"
xcodegen generate --quiet
log=$(mktemp)
for scheme in "SGF Tools" "SGF Tools Screensaver"; do
    xcodebuild -project SGFTools.xcodeproj -scheme "$scheme" -configuration Release \
        -derivedDataPath "$derived" \
        DEPLOYMENT_POSTPROCESSING=YES STRIP_STYLE=debugging \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp \
        build > "$log" 2>&1 || { tail -30 "$log" >&2; exit 1; }
done
rm -f "$log"

echo "== Checking the signatures"
# Every piece of code: the app, its two Quick Look extensions and Spotlight importer, and the saver.
for code in "$app" "$app"/Contents/PlugIns/*.appex "$app"/Contents/Library/Spotlight/*.mdimporter "$saver"; do
    codesign --verify --strict "$code"
    details=$(codesign -dvv "$code" 2>&1)
    echo "$details" | grep -q "^Authority=$identity\$" || { echo "error: $code isn't signed with $identity" >&2; exit 1; }
    echo "$details" | grep -q 'flags=.*runtime' || { echo "error: $code lacks the hardened runtime" >&2; exit 1; }
    echo "$details" | grep -q '^Timestamp=' || { echo "error: $code lacks a secure timestamp" >&2; exit 1; }
    if codesign -d --entitlements - --xml "$code" 2>/dev/null | grep -q get-task-allow; then
        echo "error: $code carries the debugging entitlement" >&2
        exit 1
    fi
done
codesign --verify --deep --strict "$app"
codesign --verify --deep --strict "$saver"

echo "== Notarizing the app and the screensaver"
notarize "$app"
notarize "$saver"
rm -rf "$out/SGF Tools.app" "$out/SGF Tools.saver"
ditto "$app" "$out/SGF Tools.app"
ditto "$saver" "$out/SGF Tools.saver"

echo "== Making the disk image"
stage=$(mktemp -d)
ditto "$app" "$stage/SGF Tools.app"
ditto "$saver" "$stage/SGF Tools.saver"
cp "Distribution/Read Me.txt" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="$out/SGF-Tools-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "SGF Tools $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg" > /dev/null
rm -rf "$stage"
codesign --force --timestamp --sign "$identity" "$dmg"
notarize "$dmg"

echo "== Gatekeeper"
spctl -a -vv -t exec "$out/SGF Tools.app"
spctl -a -vv -t install "$out/SGF Tools.saver"
spctl -a -vv -t install --context context:primary-signature "$dmg"
echo "wrote $out"
