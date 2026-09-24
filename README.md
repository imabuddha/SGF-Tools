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
  - the game information that Spotlight indexes.
- **SGFRendering**, the board drawing that the thumbnails, the previews, and the screensaver share.
- **SGF Tools.app**, a small app that holds two Quick Look extensions and a Spotlight importer:
  - **thumbnails**: Finder shows the first game's board after the opening moves (50 moves on
    19x19, 30 on 13x13, 20 on smaller boards), with a stack of boards behind it for a file
    that holds several games
  - **previews**: press the Space bar on a game in Finder to see the board, with coordinates,
    beside the players, the result, the event, the date, and the rest of the game information;
    of a file over 2 MB, only the first game is read, so the preview says that the file holds
    several games rather than how many
  - **search**: Spotlight indexes the players, event, date, result, comments, and more of each
    game, so Finder, Spotlight, and `mdfind` find games (see [Searching](#searching)).

Next comes the screensaver. The plan is in [docs/plan.md](docs/plan.md).

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

The app's tests are logic tests with no host app, so running them never opens SGF Tools, and
they don't build the app. They include renderings of the preview in light and dark mode; to save
them as PNGs, set `TEST_RUNNER_SGF_PREVIEW_SAMPLES` to a folder when running `xcodebuild test`.

Every build of the app registers it with macOS, and Spotlight then uses the build's importer as
well as, or instead of, the copy in Applications. Before deleting a build (or Xcode's
DerivedData), unregister it and wait until Spotlight has dropped it. If the build is deleted
first, Spotlight keeps trying to load the missing importer and stops indexing SGF files:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "path/to/Build/Products/Release/SGF Tools.app"
mdimport -L 2>&1 | grep SGFToolsSpotlight   # repeat until the build's path is gone
```

Spotlight looks for new and removed importers a minute or so after an app is registered or
unregistered, but when that happens often it waits longer each time, up to a quarter of an hour
or more. Registering the same build again and then unregistering it removes an entry left behind.

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
5. Spotlight indexes new and changed SGF files with the importer once it has found it, usually a
   minute or so after the app is registered (see above). `mdimport -L 2>&1 | grep SGFTools`
   shows whether it has. To index the games you already have, see
   [Indexing the games you have](#indexing-the-games-you-have).

`qlmanage -t -x -s 512 -o <folder> <file.sgf>` makes a thumbnail PNG without opening a window.
(Without `-x`, `qlmanage -t` on macOS 27 doesn't use app extensions at all and waits forever.)

`mdimport -t -d2 <file.sgf>` shows what the importer finds in a file without indexing it, and
`mdls <file.sgf>` shows what Spotlight has stored for it.

## Searching

Spotlight indexes the game information of every SGF file with SGF Tools' importer:

- **Spotlight, and the search field of a Finder window**, find games by their players, teams,
  events, results, and the words in their comments. Type a name such as `Shusaku`.
- **Finder's search rows** find games by one field. In a Finder window, press Command-F, click
  the first pop-up menu of the search row (Kind), and choose Other…. Find a field such as Black
  Player, Winner, or Year Played in the list, select it, and turn on In Menu to keep it in the
  menu. Then fill in the row, for example "Winner matches Shusaku" or "Year Played equals 1846".
- **`mdfind`** does the same in Terminal, with the attribute names below:
  `mdfind 'com_breedingpinetrees_sgf_winner == "*Shusaku*"c'`.

[docs/Example SGF Search.savedSearch](docs/Example%20SGF%20Search.savedSearch) is a saved search
that finds every SGF file (by its type, `com.red-bean.sgf`) and has empty rows for Black Player,
White Player, Event, Year Played, and Result. Open it in Finder, choose Show Search Criteria
from the Action menu, fill in the rows you want, and save it under a new name.

The fields keep the names SGF Tools 1.x gave them, so searches saved with 1.x work again. A
search that picks SGF files by "Kind is SmartGoFormat" finds only files that Spotlight indexed
years ago: files indexed now have the kind SGF (or SGF game record, depending on the apps
installed). In such a search, change the Kind row's text to `SGF`, which matches both.

### The fields

The fields that SGF Tools adds describe the first game of a file, as in 1.x:

| Field | Attribute (`com_breedingpinetrees_sgf_…`) | From the SGF |
|---|---|---|
| Black Player, White Player | `black`, `white` | PB, PW |
| Black Player's Rank, White Player's Rank | `blackrank`, `whiterank` | BR, WR |
| Black Team, White Team | `blackteam`, `whiteteam` | BT, WT |
| Result | `result` | RE, as written |
| Winner, Loser | `winner`, `loser` | the players' names, only for a win (RE `B+…` or `W+…`) |
| Event | `event` | EV |
| Round Number & Type | `round` | RO |
| Date Played | `dateplayed` (date) | the first date of DT, if it has a month and day |
| Year Played | `yearplayed` (number) | the year of the first date of DT |
| Ruleset | `ruleset` | RU |
| Komi | `komi` (number) | KM |
| Handicap | `handicap` (number) | HA |
| Old Handicap | `oldhandicap` | OH, a nonstandard property of historical records |
| Overtime Method | `overtime` | OT |
| Opening | `opening` | ON |
| Board Size | `size` (number) | SZ (the width of a rectangular board), or 19 for Go without SZ |
| Game Type | `gametype` | GM as a name, such as Go |
| Moves | `moves` (number) | the moves of the main line, without passes |
| Games | `numgames` (number) | the number of games in the file |
| Collection | `iscollection` (yes or no) | whether the file holds more than one game |

Their names are in English, French, German, Japanese, Korean, Polish, Russian, Swedish, and
Simplified and Traditional Chinese, from the translations of 1.x.

Spotlight's own fields list the values of every game in the file, each once:

| Field | Attribute | From the SGF |
|---|---|---|
| Participants | `kMDItemParticipants` | PB, PW, BT, WT |
| Title | `kMDItemTitle` | GN |
| Description | `kMDItemDescription` | GC |
| Headline | `kMDItemHeadline` | RE |
| Coverage | `kMDItemCoverage` | EV |
| Authors | `kMDItemAuthors` | US |
| Contributors | `kMDItemContributors` | AN |
| Publishers | `kMDItemPublishers` | SO |
| Text content | `kMDItemTextContent` | DT, and the comments (C) and node names (N) |

And these describe the first game: Version (`kMDItemVersion`, from FF), Content Creator
(`kMDItemCreator`, AP), Copyright (`kMDItemCopyright`, CP), Location (`kMDItemNamedLocation`,
PC), and Duration (`kMDItemDurationSeconds`, TM).

Only the first 2 MB of a file are read, so that a huge file can't stall Spotlight or use too
much memory: of a larger file, only the games in its first 2 MB are indexed, and Games counts
only those. The largest SGF file found so far, 1.78 MB with 4,002 games, is read in full.

### Indexing the games you have

Spotlight uses the importer for files that are added or changed. Files it indexed before SGF
Tools was installed keep only their name, dates, and the like until they are imported again. In
Terminal, import each folder that holds SGF files, on any disk, with `mdimport -i`:

```bash
mdimport -i ~/Documents/Go
mdimport -i "/Volumes/Go Archive/Games"
```

This imports every file in the folder and in the folders inside it, whether or not it changed,
so in a folder that also holds other files, it imports those again too. Spotlight imports the
files in the background, so searches find them a little later; `mdls <file.sgf>` shows whether
a file has the fields yet.

Import folders rather than single files: on an external disk, `mdimport` given a single file
returns without storing anything, so feeding it the SGF files that `mdfind` lists, one by one,
leaves the games on such a disk unindexed.

## History

SGF Tools was started in 2009 by **Jason Foreman** ([threeve/SGF-Tools](https://github.com/threeve/SGF-Tools)),
who wrote its SGF parser and first Spotlight importer. John Mifsud joined later that year and took
it through version 1.4.5 in January 2010. That version had:
- a Spotlight importer
- a Quick Look generator that drew the board after the opening moves.

Quick Look generators stopped working on later macOS, and the importer was built for Intel Macs
and for its own file type, `com.breedingpinetrees.sgf`, which SGF files no longer have. That is
why 2.0 is a rewrite rather than an update. It shares no code with 1.x, but it keeps its ideas,
and its Spotlight fields keep their names. Version 1.x is preserved on the
[`legacy-1.x`](https://github.com/imabuddha/SGF-Tools/tree/legacy-1.x) branch, and
[docs/old-version-analysis.md](docs/old-version-analysis.md) describes what it did.

Thanks to Anders Kierulf, Kirk McElhearn, and Frank G. Sion for testing, suggestions, and the
translations of 1.x.

## License

MIT. See [LICENSE](LICENSE).
