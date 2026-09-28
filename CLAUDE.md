# SGF Tools: notes for agents

SGF Tools is a **public** repo under the MIT license: a Mac app holding Quick Look extensions
(thumbnails and previews of SGF Go game files), a Spotlight importer, and a screensaver. It began
as Jason Foreman's threeve/SGF-Tools (2009); 2.0 is a rewrite that shares no code with 1.x.
John Mifsud maintains it.

## Because it's public
- Everything committed here is visible to the world. Never add code, data, images, or text from
  John's private projects, and never mention private clients, prices, or agreements.
- **Update README.md to match reality before every push**, and fix stale comments and docs in the
  areas you changed.
- Never publish a GitHub release, or turn a draft release into a public one, without John's
  explicit OK. Draft releases are fine for his testing.
- Keep the credits (Jason Foreman, and the 1.x contributors named in the README).

## Building and testing
- `project.yml` is the source of truth; regenerate the Xcode project with xcodegen, and never
  hand-edit the `.xcodeproj`.
- Tests: `cd SGFKit && swift test` (the package) and `xcodebuild -project SGFTools.xcodeproj
  -scheme "SGF Tools" test` (the app's logic tests; no host app, so no window opens). Build with
  `-jobs 6` at most. The `fastEnough()` timing tests can fail under heavy load; rerun on an idle
  Mac before treating that as a regression.
- **No GUI:** don't launch the app, or anything that opens a window, while John may be using
  the Mac. Don't register test builds with LaunchServices or leave them where Spotlight or Quick
  Look would pick them up instead of the installed app.
- Delete build trees you create.

## Versions and releases
- The app and the screensaver share one version: `MARKETING_VERSION` in `project.yml`
  (John is fine with that).
- A release is `scripts/build-release.sh`: Developer ID signing, notarization, and stapling of the
  app, the saver, and the DMG. Check the README's install steps against the release.

## Writing
American spelling and the serial comma.
