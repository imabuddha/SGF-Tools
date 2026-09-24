# SGF Tools

Tools for SGF (Smart Game Format) Go game files on the Mac: board thumbnails and previews in
Finder and Quick Look, Spotlight search on players, events, dates, and results, and a screensaver
that replays games.

## Status

**Version 2.0 is being written from scratch** for Apple Silicon Macs running macOS 26 or later.
There is no release yet, but it can be built and tried. So far:

- **SGFKit**, a Swift package with no dependencies:
  - a tolerant SGF parser: every SGF version, collections, any charset (with detection for
    files that claim UTF-8 but aren't), and damaged or mislabeled files
  - the game model, with captures
  - the game information that Spotlight will index.
- **SGFRendering**, the board drawing that the thumbnails, the previews, and the screensaver share.
- **SGF Tools.app**, a small app that holds two Quick Look extensions:
  - **thumbnails**: Finder shows the first game's board after the opening moves (50 moves on
    19x19, 30 on 13x13, 20 on smaller boards), with a stack of boards behind it for a file
    that holds several games
  - **previews**: press the Space bar on a game in Finder to see the board, with coordinates,
    beside the players, the result, the event, the date, and the rest of the game information.

Next come Spotlight search, then the screensaver. The plan is in [docs/plan.md](docs/plan.md).

## Building

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The Xcode project is generated from `project.yml` and isn't in the repository:

```bash
xcodegen generate
open SGFTools.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project SGFTools.xcodeproj -scheme "SGF Tools" -configuration Release build
xcodebuild -project SGFTools.xcodeproj -scheme "SGF Tools" test   # the app's tests
cd SGFKit && swift test                                            # the package's tests
```

The app's tests are logic tests with no host app, so running them never opens SGF Tools. They
include renderings of the preview in light and dark mode; to save them as PNGs, set
`TEST_RUNNER_SGF_PREVIEW_SAMPLES` to a folder when running `xcodebuild test`.

The app icon, `App/AppIcon.icon`, is an Icon Composer document, so macOS lights it and shows it
in the dark, tinted, and clear icon styles. Its two layers, the board and the stones, are drawn by
SGFRendering: a corner of the position that the thumbnail of John Mifsud's 2009 game against
GNU Go shows. After a change to the renderer, draw them again with
`TEST_RUNNER_SGF_APP_ICON_ASSETS="$PWD/App/AppIcon.icon/Assets"` set when running
`xcodebuild test` (see `Tests/AppIconArtwork.swift`).

The app is signed to run locally (ad hoc), which needs no Apple account, and macOS loads its
Quick Look extensions that way. To sign with your own team instead, see
`Config/Signing.xcconfig`.

## Trying it out

1. Build the Release configuration, as above.
2. Copy `SGF Tools.app` from the build products into `/Applications` (in Xcode: Product > Show
   Build Folder in Finder, then `Products/Release`). The extensions work only while macOS knows
   where the app is; opening it once, or copying it into Applications, registers it.
3. In Finder, SGF files get board thumbnails. Select one and press the Space bar for the preview.
4. If nothing changes, check that SGF Tools is on in System Settings > General > Login Items &
   Extensions, under Quick Look, and run `qlmanage -r` and `qlmanage -r cache` in Terminal to
   reset Quick Look.

`qlmanage -t -x -s 512 -o <folder> <file.sgf>` makes a thumbnail PNG without opening a window.
(Without `-x`, `qlmanage -t` on macOS 27 doesn't use app extensions at all and waits forever.)

## History

SGF Tools was started in 2009 by **Jason Foreman** ([threeve/SGF-Tools](https://github.com/threeve/SGF-Tools)),
who wrote its SGF parser and first Spotlight importer. John Mifsud joined later that year and took
it through version 1.4.5 in January 2010. That version had:
- a Spotlight importer
- a Quick Look generator that drew the board after the opening moves.

Both plug-in types stopped working on later macOS, which is why 2.0 is a rewrite rather than an
update. It shares no code with 1.x, but it keeps its ideas. Version 1.x is preserved on the
[`legacy-1.x`](https://github.com/imabuddha/SGF-Tools/tree/legacy-1.x) branch, and
[docs/old-version-analysis.md](docs/old-version-analysis.md) describes what it did.

Thanks to Anders Kierulf, Kirk McElhearn, and Frank G. Sion for testing, suggestions, and the
translations of 1.x.

## License

MIT. See [LICENSE](LICENSE).
