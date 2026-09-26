# The screensaver

The design of the screensaver's first draft, step 5 of [plan.md](plan.md), decided on 2026-09-25
against 2.0.6 (7) on macOS 27.0 (26A428). It answers the plan's open question, how the
screensaver gets at the files, and is meant to be built from.

Claims about macOS are marked **verified** (a command run on the test Mac, listed in the
[appendix](#appendix-what-was-checked)), **reported** (with a source), or **untested** (open until
the first real run, which the logging in section 9 is designed to answer).

## The decision in short

- **SGF Tools.app chooses the games.** When John clicks Update Screensaver Games, or when the app
  opens and its list is more than a week old, it asks Spotlight for every qualifying game, reads
  them in a random order until 10,000 qualify, and writes each one's details and first 50 moves,
  as a small SGF game, to one playlist file in `~/Library/Application Support/SGF Tools/`. On the
  click, and only then, it first asks macOS for access to Documents and the other disks, since
  Spotlight hides from it the files it may not read (1.2, 1.5).
- **The screensaver plays from that file.** No privacy setting guards it, and the screensaver's
  host can read it (verified with probes signed with the host's entitlements).
- **If there's no playlist, the screensaver asks Spotlight and reads the files itself** ("direct
  mode", the plan's first idea), and treats every read as a test. **If that fails too, it plays
  John's own 2009 game against GNU Go**, which it carries, with one line saying to open SGF Tools.
  The screen is never black with nothing to explain it.
- **Why the app, not the screensaver, reads the files:** on the test Mac every qualifying game is
  in a place that macOS's privacy layer (TCC) guards: 99.3% on an external volume, the rest in
  Documents. The screensaver's host can't ask John for access while it runs, and granting it
  access grants it to every screensaver. The app can ask, while John is at the Mac, with its own
  name on the request.

## 1. Where the games come from

### 1.1 The host

Third-party `.saver` bundles run inside Apple's `legacyScreenSaver.appex`
(`/System/Library/Frameworks/ScreenSaver.framework/PlugIns/`, bundle ID
`com.apple.ScreenSaver.Engine.legacyScreenSaver`), which `WallpaperLegacyExtension.appex` starts
for the wallpaper system. `WallpaperLegacyExtension` finds savers in `~/Library/Screen Savers` and
`/Library/Screen Savers`, the two folders its sandbox exceptions name. The saver's code runs with
the host's entitlements (verified, `codesign -d --entitlements -`):

| Entitlement | Value | For the saver |
|---|---|---|
| `com.apple.security.app-sandbox` | true | Sandboxed, in the host's container |
| `…temporary-exception.files.absolute-path.read-only` | `/` | Reads the whole file system, as far as the sandbox goes |
| `…temporary-exception.yasb` | true | Writes outside `~/Library` (not needed) |
| `…files.user-selected.read-only`, `…files.bookmarks.app-scope` | true | Open panels and bookmarks (useless in a saver) |
| `…assets.pictures.read-only`, `…network.client`, `…network.server` | true | Not needed |
| `…cs.disable-library-validation` | true | Loads ad hoc signed bundles, such as this one |
| `…temporary-exception.mach-lookup.global-name` | CARenderServer, CoreDisplay.master, nsurlstorage-cache, ViewBridgeAuxiliary | Drawing; no services of our own |
| `com.apple.private.xpc.launchd.per-user-lookup` | true | Apple-private |

Also verified:
- **The sandbox profile** (`/System/Library/Sandbox/Profiles/application.sb`): `yasb` grants read
  and write on `/` and then denies `~/Library`; the `/` read-only exception comes later in the
  profile and wins, so the host **reads everything, and writes inside `~/Library` only in its
  own container**. Every sandboxed process may look up Spotlight's server,
  `com.apple.metadata.mds`.
- **The container** is `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/`.
  Inside the sandbox, `NSHomeDirectory()` is the container's `Data` folder, so both the saver
  and the app find the real home folder with `getpwuid(getuid())`.
- **No third-party saver has run on the test Mac under macOS 27**: the container's metadata was
  last written on 2025-05-30, and the log has no entries from the host. That metadata lists a
  blanket `(allow mach-lookup mach-register)` exception that the macOS 27 host no longer has.
- **The host is `x86_64 arm64e`**, and the saver is `arm64` only, like the rest of SGF Tools. An
  arm64e system process loading our arm64 code already works for the importer, which runs in
  the arm64e `mdworker_shared`.
- `~/Library/Screen Savers` and `/Library/Screen Savers` are empty.
- `loginwindow` still names `com.apple.screensaver.willstop`, `didstart`, `didstop`,
  `didlaunch`, and `previewdidstop`.

### 1.2 What the probes showed

Small command-line probes, signed ad hoc with sandbox entitlements and run headlessly, stood in
for the host and the app (verified):

| | The host's file entitlements | The app today (App Sandbox only) | The app as proposed (1.5) |
|---|---|---|---|
| Spotlight: qualifying games | **64,020** in 0.8 s | **0** | (the host's case without `yasb`: 64,020) |
| Read files on the external volume and in Documents | 5 of 5 each (see below) | not run | not run |
| List `~`, `~/Library/Application Support`, `/Users/Shared` | yes | **no** (EPERM) | not run |
| Write `~/Library/Application Support/<folder>/` | **no** (EPERM) | not run | **yes**, creating the folder |
| Write elsewhere in `~/Library` | no | not run | no |
| Read the file the app-like probe wrote | **yes** | | |

So **Spotlight filters its results by the client's sandbox**: the `/` read-only exception lifts
the filter completely, and the app as it is today sees nothing. And **the playlist's round trip,
the app writes it and the host reads it, works under the host's sandbox rules**.

What no probe can show is TCC as the real host meets it. A probe's file access is checked for
the app that launched it, which already has access to Documents and the external volume, so the
five reads of each above say nothing about the host. Testing that headlessly would risk a
permission dialog on John's screen, so it wasn't done.

**John's test of 2.1.0 (8), on 2026-09-26, showed that Spotlight also filters by TCC** (verified).
The app, installed in `/Applications` with the entitlements of 1.5, got no games at all from the
query that finds 64,020 in Terminal: "Wrote 0 games of 0 found". Every qualifying game is in a
place TCC guards (1.3), the app had never read any of them, so it held no grant, and no
permission request appeared. So:
- Spotlight leaves out of a client's results the files that the client's TCC access doesn't
  cover, as well as those its sandbox doesn't, and **a Spotlight query never makes macOS ask**.
- The probes' 64,020 came from Terminal's access, which they inherited, as they did for reads.
  The row "Spotlight: qualifying games" above holds only for a process with that access.
- The app has to read each place itself, once, for macOS to ask; then Spotlight answers with
  what it may read (1.5). There's no API that asks ahead of time (1.3).

### 1.3 TCC, and where the games are

Where the qualifying games are on the test Mac (verified, `mdfind`):

| Where | SGF files | Qualifying games |
|---|---:|---:|
| One external volume (PCI Express; "External", "Fixed") | 64,812 | 63,555 |
| `~/Documents` | 19,719 | 441 |
| `~/Library`, all in other apps' containers | 7,574 | 24 |
| **Total** | **92,105** | **64,020** |

Every one of them is behind TCC: removable volumes, the Documents folder, or "data from other
apps". Reported:
- Screensavers can't read Documents, Desktop, or Downloads since macOS 10.15; the rest of the
  home folder is fine (WebViewScreenSaver's README; Aerial's troubleshooting page).
- An external disk gives a saver a permission error (Aerial issue #879; Aerial's FAQ). The
  workaround was adding `legacyScreenSaver.appex` to Full Disk Access, which then applies to
  every third-party saver.
- There's no API to ask for access to a removable volume in advance; the request comes only
  from a file operation on it (Apple DTS, forum thread 686498).
- Since macOS 14, reading another app's container asks about "data from other apps" (forum
  threads 739602 and 766275).

Untested: whether TCC counts a fixed PCI Express disk as removable, whether `tccd` can put up a
prompt for the host while a screensaver runs or denies silently, and whether the host already
holds a grant on the test Mac (the TCC database can't be read without Full Disk Access).

The external volume can also be unmounted or asleep. Its Spotlight index is on the volume, so a
query then finds only what's in Documents; a playlist keeps playing, and an update keeps it
(1.5).

### 1.4 Why the playlist comes first

Direct mode alone, the plan's first idea, needs no change to the app, keeps up with the index by
itself, and reads the actual file while it runs, as the plan says. But on the test Mac, the
most likely outcome of its first run is that TCC refuses every read, and the saver plays only
its own game until John grants the host access that every screensaver would share. The
playlist avoids TCC in the host altogether, works when the volume isn't mounted, starts at once,
and does no slow work in a host that is known to leak instances (section 8). Its costs:

- **The saver doesn't read the actual file while it runs.** The app read it when it made the
  playlist, so the moves are the file's, not a copy from Spotlight. (Question 1 for John.)
- **The app must be opened** before the saver has games, and again to pick new ones.
- **The app needs two sandbox exceptions** (section 1.5).
- **More code:** the builder, the format, and a row in the app's window.

Direct mode stays as the fallback, so a saver without a playlist still tries the plan's first
idea, and John's manual test (section 11, step 7) runs it on purpose to learn what the real host
is allowed.

### 1.5 The app's side

**Entitlements.** `App/SGFTools.entitlements` gains two temporary exceptions:

```xml
<key>com.apple.security.temporary-exception.files.absolute-path.read-only</key>
<array><string>/</string></array>
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array><string>/Library/Application Support/SGF Tools/</string></array>
```

The first is the host's own; it lets Spotlight return results to the app and lets the app read
the files, with TCC still asking for the places it guards. The second makes the playlist's folder,
and nothing else in `~/Library`, writable (verified with the probe). As `application.sb` grants
them, the first also lets the app run programs and issue read extensions anywhere, and the
second lets programs in the playlist's folder run. The host has the same `/` exception, so this
adds little, but the app parses thousands of SGF files it didn't write with these rights; the
read exception could be narrowed to `/Users/` and `/Volumes/`, where the games are (question 2).
Temporary exceptions keep an app out of the Mac App Store, which SGF Tools isn't in. The Quick
Look extensions and the importer keep their own entitlements.

**Reasons for the permission requests**, in `App/Info.plist`: `NSDocumentsFolderUsageDescription`,
`NSDesktopFolderUsageDescription`, `NSDownloadsFolderUsageDescription`,
`NSRemovableVolumesUsageDescription`, and `NSNetworkVolumesUsageDescription`, each "SGF Tools
reads your SGF files to choose games for its screensaver."

**When it writes the playlist:**
- when the app opens, if the saver is installed (`SGF Tools.saver` in `~/Library/Screen Savers`
  or `/Library/Screen Savers`) and the playlist is missing or more than 7 days old; so someone
  who never installs the saver never sees a permission request. This update never asks for
  access, so it chooses only from the places the app may already read.
- when John clicks **Update Screensaver Games** in the app's window, which first asks for access.

**Asking for access** (`App/AccessCheck.swift`), on the click only, since Spotlight never asks
(1.2): before the query, the app reads the top level of each place in turn, off the main thread,
with `opendir` and one `readdir`. macOS should ask once for a place it hasn't decided on, with
the reason above, while the read waits for the answer, and not again for a place already allowed
or refused (untested: John's next test). The status line says "Asking macOS for access to
Documents…" meanwhile. The places:
- `~/Documents`;
- each volume under `/Volumes` that `mountedVolumeURLs(… .skipHiddenVolumes)` lists, is local
  (`volumeIsLocal`), is shown in Finder (`volumeIsBrowsable`), and isn't the startup disk
  (`volumeIsRootFileSystem`), by name. That leaves out Recovery, the `/System/Volumes` ones, and
  network volumes, which the query's scope, `kMDQueryScopeComputer`, doesn't search ("all locally
  mounted volumes, plus the user's home directory", `MDQuery.h`), so their request would gain
  nothing. An internal volume that TCC doesn't guard costs a read and no request.
- **not** Desktop or Downloads, where collections are rarely kept, so that everyone isn't asked
  about them; their games are chosen only with Full Disk Access. A place that was never asked
  about has no switch under Files & Folders.

Each read's outcome, `allowed`, `denied` (`EPERM`), or `failed` with its `errno`, and how long it
waited are logged; a read that took over half a second most likely waited on a request. When
places were refused, the window names them and the switches to turn on under Privacy & Security
> Files & Folders, with a button that opens that pane
(`x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders`; the anchor
is in the Privacy & Security extension's `TCCServiceList.plist` and binary on macOS 27, and its
`legacyBundleIdentifier` is `com.apple.preference.security`, verified). When an update by itself
found nothing, or kept the playlist because places came up empty, the window says to click the
button.

**The window** gets a fourth row under the three features, "Screensaver", with a sentence on
what it does, a status line, and the button (with a tooltip). The status reads, for example,
"10,000 games of 64,020, chosen today at 10:32", "Choosing games… 2,345 of 10,000", or what went
wrong ("441 games in Documents couldn't be read: access not allowed"). The closing paragraph's
"There is nothing to set up" is reworded to match.

**How it builds the playlist** (`App/PlaylistBuilder.swift`, off the main thread):
1. On the click, ask for access (above). Then ask Spotlight for the qualifying files
   (`GameCandidates`, 1.7), and drop the paths it must never open (1.7).
2. Shuffle them, and read files until 10,000 games qualify or the list runs out, four at a time,
   with `GameFileReader` (1.7). There's no time limit: a read that waits on a permission request
   waits for John's answer.
3. Turn each game into a playlist line (1.6).
4. Write the file with `Data.write(to:options: .atomic)`, so the saver sees the old playlist or the
   new one, never part of one (verified: the app-like probe did exactly this). A file the saver
   has open keeps its old contents. **Unless the old playlist is kept:** when the new one would
   have fewer games than it, and has none, or macOS refused some reads, or a volume that holds
   some of the old playlist's games isn't mounted, or a place TCC guards (Documents, Desktop,
   Downloads, a volume) holds some of the old games and Spotlight found none there. That place
   may be hidden rather than empty; the games count as gone only when the update asked for
   access to it, got it, and none of the first 20 old games there still exists (`stat`). An
   update by itself never looks there. Then the window shows the old playlist and a line saying
   why, and the next update tries again. **So no update replaces a playlist with an empty one,
   or with a smaller one for want of access** (`PlaylistBuilder.playlistToKeep`, tested).
5. Tally everything by location (1.7): found, left out and why, read, refused by error, missing,
   not a game, the time, and the size written. The tallies go to the log and the status line.

The app quits when its window closes, but waits for an update under way to finish, since the
playlist is written only at the end.

At about 1 ms to parse a game (`spotlight-notes.md`) and a fast disk, 10,000 games take seconds,
not minutes (untested). A new random 10,000 each time means the saver works through the whole
collection over the weeks: at about 40 seconds a game (section 4), 10,000 games are almost five
days of screensaver time on each display.

### 1.6 The playlist

`~/Library/Application Support/SGF Tools/Screensaver Games.sgfplaylist`, found by the real home
folder. The extension has no declared type, so Spotlight indexes the file's name but not its text,
and a search for a player doesn't turn up the playlist (untested).

UTF-8 text, one game per line. Header lines start with `#`; every other line is a file URL, a
tab, and a game in SGF:

```
# SGF Tools screensaver games
# format: 1
# made: 2026-09-25T10:32:00Z
# found: 64020
# games: 10000
file:///Volumes/Go%20Archive/Games/example.sgf	(;GM[1]FF[4]CA[UTF-8]SZ[19]PB[Black Tester]BR[3d]PW[White Tester]WR[5d]RE[W+R]EV[An Event]DT[2009-05-01]AB[dd][pp];W[pd];B[dp]…)
```

- **The URL** (`URL.absoluteString`, so it holds no tab or line break) is for the log and for
  later features; the saver never opens it. It copies the names and folders of files in places
  TCC guards to one it doesn't, where the user's other processes, including other screensavers
  in the host, may read them; the README says the playlist holds the paths. An opaque identity,
  such as a hash of the path, would do for telling games apart.
- **The root** gets `GM[1]`, `FF[4]`, `CA[UTF-8]`, `SZ` as written, and PB, BR, PW, WR, RE, EV, and
  DT from the first game's `GameInfo`, each escaped (`\` and `]`), with tabs and line breaks
  turned into spaces.
- **Every main-line node**, from the root up to and including the node of the 50th move (passes
  count, as SGF numbers moves), keeps its B, W, AB, AW, and AE with their values as written,
  minus any tab or line break, and nothing else. Nodes left empty are dropped. Handicap stones,
  setup in the middle of a game, passes (including `tt`), and compressed point lists come through
  unchanged, so **replaying the line gives the same positions as replaying the file**, which the
  tests check move by move.
- A line is about 600 bytes, so 10,000 games take about 6 MB.
- A reader refuses a file whose `format` isn't 1, and skips a line that doesn't parse or a last
  line cut short.

SGF rather than a compact string of its own: the saver already has SGFKit's parser, `GameInfo`,
and `GameSummary`, so there's no second decoder, and any line can be pasted into an SGF program.

**What counts as a game**, in the app, in direct mode, and again in the saver for every line:
the game type is Go (GM 1, or no GM), PB and PW aren't empty or blank, and
`GameInfo.moveCountWithoutPasses` is at least 20, the count Spotlight's Moves field holds.
Only a file's first game is used, as Spotlight and the thumbnails see it.

### 1.7 Shared code for finding and reading games

Both the app's builder and the saver's direct mode use the same two files in `Shared/`:

**`GameCandidates`** runs one synchronous `MDQuery`, scoped to the computer, on a background
thread, and copies the paths into a Swift array (0.9 s and about 6 MB for 64,020 paths,
verified). The results leave out whatever the calling process may not read (1.2):

    kMDItemContentType == "com.red-bean.sgf" && com_breedingpinetrees_sgf_black == "*" &&
    com_breedingpinetrees_sgf_white == "*" && com_breedingpinetrees_sgf_moves >= 20

It leaves out anything under the real `~/Library` (other apps' containers, where a read asks
about "data from other apps", and iCloud Drive), the Trash (`~/.Trash` and each volume's
`.Trashes`), `.Spotlight-V100`, and `.DocumentRevisions-V100`. It sorts the rest into
**location classes** by path: Documents, Desktop, Downloads, home (the rest of the home folder),
startup disk (the rest of `/`), and one class for each volume under `/Volumes`.

**`GameFileReader`** reads one candidate:
1. `stat` it (allowed everywhere by the sandbox profile): skip a missing file (a stale index) and
   a dataless one (`SF_DATALESS`, which a read would download).
2. Read at most the first 2 MB with a plain read, **never a memory map**: a mapped file on a
   volume that goes away raises SIGBUS and would crash the host (code review, L7).
3. Parse with `SGFParser.parse(_:options:)` and `stopAfterFirstGame`, and check that it's a game.
4. Report one outcome, which callers tally by location class:

| Outcome | Signal | What it means |
|---|---|---|
| game | data that parses and qualifies | Play it, or write its line |
| missing | `ENOENT`, or `stat` fails | The index is stale |
| dataless | `SF_DATALESS` | A cloud file; never read |
| not a game | parses, doesn't qualify | The file changed since it was indexed |
| denied | `EPERM` (Cocoa error 257 over POSIX 1) | TCC, since the sandbox allows `/` |
| unreadable | `EACCES` (POSIX 13), or another error | The file's own permissions |

A read that doesn't answer in time is the caller's to handle: the builder waits, and direct mode
abandons it (1.8).

### 1.8 How the saver picks a game

A process-wide **game library** serves every screen. For each new game it goes down this list,
logging every step:

1. **The playlist.** Read once per process, on a background queue: the whole file (refused over
   64 MB), with the start of each line noted (about 10 ms for 6 MB), and the bytes kept. A pick
   chooses a line at random, parses only that line, and checks it again. Before each pick, the
   library compares the file's inode, size, and modification date with what it read, and reads
   it again if the app has replaced it. Twenty bad lines in a row count as no playlist.
   *Failure is detected* by the read itself: no file (`ENOENT`), refused (`EPERM`, which would
   mean the real host differs from the probes; see section 12), a wrong format, or no playable
   line.
2. **Direct mode**, never in the preview. `GameCandidates` runs once per process, with a 10-second
   limit, and again when its list is an hour old at the start of a later session. Reads run on a
   dedicated queue, never the main thread or Swift's cooperative pool, one at a time, with a
   limit of 3 seconds each. A read that times out is abandoned (its thread stays blocked until
   macOS answers) and counts against its class.
   - A class is **denied** after 2 `denied` outcomes, or 3 time-outs in a row; the library stops
     picking from it, until a late read from it succeeds.
   - A class is skipped after 5 `unreadable` outcomes.
   - `missing`, `dataless`, and `not a game` just pick again.
   - Direct mode gives up for the process after 20 failed picks in a row, when 6 abandoned reads
     (two classes' worth) haven't come back, after a query that fails or times out, or when every
     class is denied or skipped. An abandoned read that comes back no longer counts.
3. **The saver's own game:** `johnVsGnu.sgf`, John Mifsud's 2009 game against GNU Go (already in
   the repository, and drawn by the app icon), from the saver's bundle, which the view hands the
   library as `Bundle(for: ScreensaverView.self)`, never `Bundle.main`, which is the host. Under
   the details, one more line: "Open SGF Tools to choose games for this screensaver."

For every screen, a pick avoids the games on the screens and the last 200 shown. When a small
collection can't, it avoids fewer recent games, half as many each time, then only the games on
the screens, then only those on the other screens, so that no game is on two screens at once and
no screen shows a game twice in a row while there's another. The next game is picked, read, and
parsed while the current one plays, so a game never waits on a read.

## 2. Targets and files

**A new target and scheme** in `project.yml`, beside the importer's. The saver isn't embedded in
the app, so building it never builds the app or registers its Spotlight importer.

```yaml
  # The screensaver: a .saver bundle that macOS loads into its sandboxed legacyScreenSaver host.
  # It plays games from the playlist the app writes (see docs/screensaver.md). It isn't embedded
  # in the app, so building it doesn't build the app or register its Spotlight importer.
  SGFToolsScreensaver:
    type: bundle
    platform: macOS
    sources:
      - Screensaver
      - Shared/Look.swift
      - Shared/GameSummary.swift
      - Shared/Playlist.swift
      - Shared/GameCandidates.swift
      - Shared/GameFileReader.swift
      - path: SGFKit/Tests/SGFRenderingTests/Fixtures/johnVsGnu.sgf
        buildPhase: resources
    dependencies:
      - package: SGFKit
        product: SGFKit
      - package: SGFKit
        product: SGFRendering
      - sdk: ScreenSaver.framework
    settings:
      base:
        PRODUCT_NAME: SGF Tools
        PRODUCT_MODULE_NAME: SGFToolsScreensaver
        PRODUCT_BUNDLE_IDENTIFIER: com.pragmaphilia.SGFTools.Screensaver
        WRAPPER_EXTENSION: saver
        INFOPLIST_FILE: Screensaver/Info.plist
        SKIP_INSTALL: YES
```

```yaml
  SGF Tools Screensaver:
    build:
      targets:
        SGFToolsScreensaver: all
```

`SGFToolsTests` also compiles `App/PlaylistBuilder.swift` and everything in `Screensaver/` except
the view, so the view's Objective-C class exists only in the bundle. It already compiles all of
`Shared/`:

```yaml
    sources:
      - path: Tests
        excludes:
          - SandboxCheck
      - Shared
      - App/AccessCheck.swift
      - App/ContentView.swift
      - App/PlaylistBuilder.swift
      - Spotlight/SpotlightAttributes.swift
      - path: Screensaver
        excludes:
          - ScreensaverView.swift
          - Info.plist
          - "*.png"
      - path: SGFKit/Tests/SGFRenderingTests/Fixtures/johnVsGnu.sgf
        buildPhase: resources
```

- `Screensaver/Info.plist`, written like `Spotlight/Info.plist`: the `$(…)` build settings,
  package type `BNDL`, `NSPrincipalClass` `SGFToolsScreenSaverView`, the shared version numbers,
  `LSMinimumSystemVersion`, and the copyright line. No configure sheet.
- No entitlements: a plug-in runs with its host's. Signed ad hoc like every target; the host
  loads it because it has `disable-library-validation`. arm64 only, macOS 26, from the project's
  settings.
- A copy downloaded from GitHub would be quarantined and need notarization (reported, forum
  thread 117136); a local build isn't.
- The saver makes the version 2.1.0 (8), and the README gets a "Screensaver" section
  (installing it, what it shows, the playlist, and the log command) before the push.
  `plan.md`'s open question points here.

**Files:**

| File | What it holds |
|---|---|
| `Screensaver/Info.plist` | The bundle's description |
| `Screensaver/ScreensaverView.swift` | `@objc(SGFToolsScreenSaverView) final class ScreensaverView: ScreenSaverView`: lifecycle, the timer, visibility, one screen's scene |
| `Screensaver/SaverScene.swift` | One screen's layers (game, board, details) and applying a timeline state to them |
| `Screensaver/SaverTimeline.swift` | Pure: elapsed time to what's shown (section 4) |
| `Screensaver/SaverLayout.swift` | Pure: screen size, details size, and a random number generator to the board's and the details' rects (section 5) |
| `Screensaver/SaverGame.swift` | A playable game: its positions from 0 to N moves, their last moves, its details, and its source |
| `Screensaver/GameLibrary.swift` | Per process: the three sources, picking for each screen, the recent list |
| `Screensaver/PlaylistStore.swift` | Reads and indexes the playlist, and reads it again when it's replaced |
| `Screensaver/DirectSource.swift` | Direct mode: the classes' health, time-outs, giving up |
| `Screensaver/InstanceRegistry.swift` | Which views may play (section 8) |
| `Screensaver/DetailsRenderer.swift` | The details, drawn with Core Text into an image |
| `Screensaver/SaverLog.swift` | The `Logger`s (section 9) |
| `Screensaver/thumbnail.png`, `thumbnail@2x.png` | The picker's thumbnail, 90x58 points, drawn by a test from johnVsGnu |
| `Shared/Look.swift` | + a "Screensaver" section: the timing, sizes, fonts, and colors below |
| `Shared/Playlist.swift` | The format: the header, writing a game as a line, reading lines |
| `Shared/GameCandidates.swift` | The Spotlight query, the exclusions, and location classes |
| `Shared/GameFileReader.swift` | `stat`, the bounded read, parsing, qualifying, and the outcome |
| `App/PlaylistBuilder.swift` | The app's builder, with its status for the window |
| `App/AccessCheck.swift` | Asking macOS for access to Documents and the volumes, on the click (1.5) |
| `App/ContentView.swift`, `App/SGFToolsApp.swift` | The Screensaver row; the update when the app opens |
| `App/SGFTools.entitlements`, `App/Info.plist` | The two exceptions; the reasons |
| `Tests/Screensaver*.swift`, `Tests/Playlist*.swift` | Section 10 |
| `Tests/SandboxCheck/` | The sandbox check (section 10) |

The builder, the reader, the library, and the direct source take their Spotlight query, their
file reads, their clock, and their random number generator as parameters, so the tests run them
on synthetic files and paths.

## 3. Rendering

- **A layer-backed view:** `wantsLayer = true`, `layerContentsRedrawPolicy = .never`, and a black
  root layer holding one **game layer**, whose opacity makes the fades, with two sublayers: the
  **board** and the **details**. `draw(_:)` fills black, for the moment before the layers exist.
- **The board** is `BoardRenderer(style: .shaded, margin: 0)`, as the preview draws it, without
  coordinates, the last move marked with a ring: `makeImage(of:lastMove:size:scale:)` at the
  board's size and the window's backing scale. A game's positions are all computed when it's read
  (about 0.5 ms for 50 moves, verified); each move's image is drawn off the main thread, one move
  ahead, and only the current and next images are kept. A shaded board of 2,800 pixels a side
  took 42 ms (median) in a release build on the test Mac, and 18 ms at 1,800 pixels (verified):
  about 8% of one core at two moves a second.
- **A move** sets the board layer's contents inside a 0.3-second `CATransition` fade, so the new
  stone appears and captured stones vanish together. A pass is half a second with no new stone
  and no ring.
- **The details** are drawn once per game into an image at the screen's scale, by the same code
  that makes the tests' PNGs.
- **Memory:** one board image is 15 to 31 MB on today's screens, two per screen. They're
  released whenever the screen pauses (section 8), and drawn again when the backing scale changes.
- SGFRendering needs no change.

## 4. Playback timeline

`SaverTimeline` is a pure function from the time since the game started (from
`CACurrentMediaTime()`) to what's shown, so late or irregular ticks never drift the moves. With N
the number of moves played, 50 or the whole main line if it's shorter, passes counted:

| Time (s) | What happens |
|---|---|
| 0 | The game layer starts fading in (2 s), showing the position before move 1: an empty board, or handicap and setup stones |
| 0.75 | The details start fading in (1.5 s) |
| 3 | Move 1 |
| 3 + (n − 1) / 2 | Move n, two a second, to move N (at 27.5 s for N = 50) |
| N / 2 + 12.5 | After the last position has held for 10 s, the board and details fade out (2 s) |
| N / 2 + 14.5 | Black for 1 s |
| N / 2 + 15.5 | The next game starts (40.5 s for N = 50) |

The pace is two constants in `Look`: `screensaverMoveInterval`, 0.5 s, and
`screensaverFinalHold`, 10 s. So a game's length follows its moves: about 25 s of moves and a
10 s hold for 50 moves, less for a shorter game.

**The first game after a start**, whenever a screen starts playing (full screen, the preview, or
a new size), comes in quicker, so that there's something to see almost at once: the screen is
black for 0.4 s, then the board fades in over 1 s, the details start at 0.3 s and take 1 s, and
move 1 comes at 2 s. So the board is there about 1.4 s after the screen starts, not up to 5 s.
That game's last position holds a random 0 to 3 s longer on each screen, so that screens that
start together don't fade out and in together afterward. The games after it follow the table.

All 50 moves on every board size, as the plan says (question 5). No sound. The fades are Core
Animation animations, so the CPU does nothing between moves.

**The clock:** each view runs its own `DispatchSourceTimer` on the main queue, ten times a second,
while it plays, and applies the timeline's state when it changes. `animateOneFrame` does nothing,
and `animationTimeInterval` is 1 second, because other developers found the host's calls to it
unreliable in recent releases (reported: Wade Tregaskis).

## 5. Layout

**The details:** five lines, each only if the game has it:
- a small drawn black stone and Black's name and rank, as `GameSummary` gives them ("Black
  Tester 3d")
- a small drawn white stone and White's name and rank
- the result, in the preview's words (`GameSummary.describe`): "White won by resignation"
- the event
- the date, spelled out by `GameSummary.describeDate`: "May 1, 2009".

The stones are drawn circles, a black one with a faint light rim so that it shows on black; text
symbols would take the text's color. The system font: the players at 2.6% of the screen's
shorter side, white at 95% opacity; the rest at 1.9%, white at 70%. The block is at most 30% of
the screen's width (90% on a portrait screen), and a long line ends in an ellipsis. For the
saver's own game, the hint follows the date.

**The placement**, `SaverLayout`, for a screen of W by H points, with a margin m of 4% of the
shorter side, and a random number generator that the tests seed:
1. **A preview** is any view whose shorter side is under 400 points: the board is 90% of the
   shorter side, centered, with no details.
2. **Otherwise** the details go beside the board on the screen's long axis. On a landscape screen,
   the board's side is s = min(0.86 H, W − w − 3m), where w is the details' width, so a band for
   the details always fits; the board is centered vertically.
3. A side, left or right, is chosen at random among those that can hold the details, then the
   board's position at random within the range that leaves that band at least w + 2m wide.
4. The details go at a random place in that band, at least m from every edge and from the board.
5. A portrait screen is the same turned: the details go above or below the board, with their
   height in place of their width.
6. If s comes out under 60% of the shorter side, an unusual shape, or the details are too tall
   for the band, that game has no details and the board is centered (logged).

So the board moves a little from game to game, which also spares the screen a fixed image. On a
16-inch MacBook Pro (1728 by 1117 points), the board is 961 points and the side bands share 767.

## 6. Multiple displays

The host makes one view per screen, in one process (reported: ScreenSaverMinimal). They share
the game library: one query, one playlist, one read queue. Each screen picks its own game,
never one on another screen, and has its own layout and generator. The screens start their
first games together, quickly, and each holds its first game's last position a random 0 to 3
seconds longer, so the screens don't fade in step afterward (section 4). Each view logs its
display's ID, frame, and scale. A reported macOS 26 bug hides a third-party saver on a second
display (FB19206021); that's out of our hands, and the log shows which screens got a view.

## 7. Preview mode

The small preview in System Settings uses the same code. Because `isPreview` is reported wrong on
macOS 26 (FB17895600, forum thread 787444), the saver decides by size only, as in section 5, and
logs the flag. In a preview it:
- plays games with the board at 90% of the shorter side and no details
- plays from the playlist or its own game, and **never runs direct mode**, so opening System
  Settings can't raise a permission request
- does nothing while its bounds are empty
- starts half a second after it's in a window, since the host doesn't call `startAnimation` for
  it (John's test: "5 s in a window without startAnimation; playing anyway"), with the quick
  first game of section 4.

## 8. The host's quirks

Reported for macOS 14 through 26 (forum thread 787444, ScreenSaverMinimal, Wade Tregaskis, Aerial
issue #1339): the host makes a new view each time the saver starts and doesn't free the old ones,
which keep running (FB19204084); two views appear while the picker is open (FB19201567);
`stopAnimation` is called only for the preview; `com.apple.screensaver.willstop` is the signal
that the saver is ending, though it's sometimes missed when the saver starts and stops quickly.

**The rule:** a view plays only while
- `startAnimation` has been called and `stopAnimation` hasn't since; or it has been in a window
  for 5 seconds without `startAnimation` ever being called, which is logged, so a host that never
  calls it doesn't leave the screen black. The host's calls win over this fallback. A preview
  waits only half a second, since the host doesn't call `startAnimation` there (section 7). On a
  display the host calls it about half a second after `didstart` (John's test), and the longer
  wait lets its call come first, so that a view it started has the `willstop` grace below. The
  other rules, which keep hidden and duplicate views from playing, apply to both.
- it has a window and a size that isn't empty
- no `willstop` has arrived since its last `startAnimation`, or since `didstart`. A `willstop`
  less than 2 seconds after a view's `startAnimation` doesn't stop that view (logged): the
  notifications and the host's calls aren't ordered, so it may be the previous session's.
- it's **the newest live view for its key** of those that meet the rules above: its display
  (`CGDirectDisplayID` from its window's screen), or "preview" for a preview. A view has a key
  only while it's in a window, so a view the host makes and never shows competes with none; a
  view with no screen yet waits.
- its window isn't occluded. Occlusion is trusted only after the window has once reported
  itself visible, so a host that misreports it can't keep the saver black.

`InstanceRegistry`, on the main actor, holds every view weakly with its serial number and key,
and checks the rule again on `startAnimation`, `stopAnimation`, `viewDidMoveToWindow`, a screen
change, an occlusion change, a size change, a new view, a view's `deinit`, `willstop`, and
`didstart`.

**Pausing** cancels the timer and pending drawing, drops the layers' images, and gives the game
back to the library, so a forgotten view costs a few kilobytes and no CPU. **Resuming** starts a
new game, the quick first game of section 4. `didstop` is only logged, and `deinit` logs, so the log shows
whether the host ever frees a view.

**No `exit(0)`.** Aerial and ScreenSaverMinimal exit the host on `willstop`, but that's reported
to leave black screens that needed a restart on macOS 26, and it would also end a preview in the
same process. If the first runs show views piling up anyway, John decides.

**After a new build**, the host keeps the old code loaded until it exits: `killall
legacyScreenSaver`, then install the new bundle (reported: Wade Tregaskis).

## 9. Logging

`Logger(subsystem: "com.pragmaphilia.SGFTools.Screensaver", category:)`. Everything the first run
needs is at the notice level, which the system keeps, so `log show` finds it afterward; each read
and tick is at the info or debug level. File paths are private; location classes, volume names,
counts, error domains and codes, and timings are public.

| Category | When | What |
|---|---|---|
| `lifecycle` | Loading; each view's `init`, `startAnimation`, `stopAnimation`, window and screen changes, occlusion changes, play and pause (with the reason), and `deinit`; each notification | The saver's version, the host's process ID and name, the macOS version; the view's serial number, frame, scale, display ID, `isPreview`, preview by size, and the number of live views |
| `environment` | Once per process | `NSHomeDirectory()` and whether it's a container, and the real home folder found |
| `playlist` | Each read | Whether it exists, the error if it can't be read, its size, format, date made and age, number of games, and indexing time; lines skipped and why |
| `direct` | Direct mode | The query's count and time; the count per location class, **including every mounted volume, even when it's 0**; the paths left out, by reason; each read's class, outcome, error, bytes, and time; a class denied, and the permission it would need; giving up |
| `play` | Each game | The screen, the source (playlist, direct, or its own game), the board size, the moves, and the drawing time (median and slowest) and image size |

The app logs its builder under `com.pragmaphilia.SGFTools`, category `playlist`, with the tallies
of 1.5, and, on the click, the places it asks about, the volumes it leaves out and why, and each
place's access and wait.

The first real run answers the open questions: whether the real host reads the playlist
(`playlist`), whether Spotlight answers inside it and how fast, and whether it can read Documents
and the external volume (`direct`, from step 7 of section 11), and how many views are made and
freed on how many displays, and whether the preview is recognized (`lifecycle`).

## 10. Headless tests

Nothing here launches ScreenSaverEngine, System Settings, or the app, or builds the app target.
Fixtures are synthetic, made in code as the existing tests make theirs, plus johnVsGnu.

**Unit tests** in `SGFToolsTests`, with Swift Testing:
1. **The playlist format:** writing and reading round-trip; escaping of `\` and `]`, and tabs and
   line breaks in names; non-ASCII names; the header; a format other than 1 is refused; a last
   line cut short is skipped; 10,000 lines are indexed in under 50 ms.
2. **Lines and positions:** for fixtures with handicap stones, AE in the middle of a game, passes
   (including `tt`), captures, compressed point lists, a 19x13 board, 9x9 and 13x13 boards, a game
   shorter than 50 moves, and a collection (its first game), the line's
   `position(afterMainLineMoves: k)` equals the original's for every k from 0 to 50, its main-line
   moves are the original's first 50, and its `GameInfo` has the same players, ranks, result,
   event, and date.
3. **What counts as a game:** no PB, a PB of spaces, no PW, GM 2, 19 moves, and 20 moves plus a
   pass; each gets the right outcome.
4. **The reader,** on files in a temporary folder: missing, a file over 2 MB with its game at the
   start, a cut-off file, and each outcome of the table in 1.7 from an injected read function
   (`EPERM`, `EACCES`, and other errors).
5. **Candidates:** location classes from paths, and every exclusion; the query, built from the
   importer's attribute names, and the sandbox check's copy of it.
6. **The builder,** with paths and reads injected: the 10,000 cap, a seeded shuffle giving the
   same file twice, the tallies, the temporary file renamed into place, an unwritable folder
   reported, and the old playlist kept when no game could be read, reads were refused, its
   volume is away, or a guarded place came up empty, but replaced when its games are gone. The
   access check, with the volumes and reads injected, never the real Documents or volumes: the
   places chosen, an update by itself never asking, the click asking about each place before
   Spotlight, and what the window says for each outcome.
7. **The library:** the order playlist, direct, own game; no game on two screens at once; no
   repeats among the last 200; no game twice in a row on a screen, for playlists of 2 to 150
   games and in direct mode; the playlist read again when it's replaced, and a playlist that
   can't be opened logged once; a preview never uses direct mode; each rule of direct mode in 1.8
   (two `denied` deny a class, `missing` doesn't, time-outs, a late success clears a class, a
   blocked class denied while another plays, late reads no longer counting, giving up); and the
   log lines, through a logger protocol.
8. **The timeline:** the state at chosen times for a 50-move and a 23-move game, and the quick
   first game; ticks at irregular times land on the right move. The player gives each start a
   quick first game, and the screens different holds.
9. **The layout:** for 1920x1080, 2560x1440, 1728x1117, 3440x1440, 1080x1920, 1024x768, 1024x1024,
   300x190, and 0x0, over 1,000 seeds: the board fits, the details are on screen, at least m from
   the board and every edge, and on more than one side over the seeds; a preview has no details;
   empty bounds give no layout.
10. **The registry:** the newest view per display plays; `willstop` pauses all, until
    `startAnimation` or `didstart`, except a view that has just started; `startAnimation` on an
    older view is ignored; `stopAnimation` stops a view the fallback started, and the fallback
    never starts a view that has had `startAnimation`; a newer view that can't play doesn't pause
    an older one; a preview is its own key, and plays after half a second without
    `startAnimation`, when a view on a display doesn't yet; occlusion before the first "visible"
    is ignored.
11. **The details:** the wording and order, missing fields, and truncation.

**Rendering tests**, as `PreviewRenderingTests` does: build one screen's layer tree without a
window, set the timeline to fixed times, render it with `CALayer.render(in:)` into a bitmap, and
check pixels: black outside the board and details, wood in the board, light text in the details'
rect. With `TEST_RUNNER_SGF_SCREENSAVER_SAMPLES` set to a folder, PNGs are written for 1920x1080,
1728x1117, 1080x1920, and a 300x190 preview, half faded in, after moves 1, 25, and 50, and during
the fade-out. With `TEST_RUNNER_SGF_SCREENSAVER_THUMBNAIL` set to `"$PWD/Screensaver"`, from the
repository's folder, a test draws `thumbnail.png` and `thumbnail@2x.png`, as the app icon's
artwork is drawn.

**The bundle**, after building the "SGF Tools Screensaver" scheme: `plutil -p` shows the principal
class, the identifier, the versions, and macOS 26.0; `lipo -archs` is `arm64`; `codesign -dv`
shows a valid ad hoc signature and `codesign -d --entitlements -` none; `nm -m` finds
`_OBJC_CLASS_$_SGFToolsScreenSaverView`. With `TEST_RUNNER_SGF_SCREENSAVER_BUNDLE` naming the
built bundle, a test loads it with `Bundle(url:)`, checks that the principal class is a
`ScreenSaverView`, and makes one at 1920x1080 and one at 300x190 without a window.

**The sandbox check**, `Tests/SandboxCheck/check.sh`, run by hand after each macOS update and
before a release (not part of `xcodebuild test`): it builds a small probe twice with `swiftc`
(a sandboxed command-line tool needs an `Info.plist` with a bundle identifier in its
`__TEXT,__info_plist` section, or it stops with SIGTRAP before `main`), signs one with the host's
public file entitlements, read from the installed host so that a change shows, and one with
`App/SGFTools.entitlements`. Then both probes find `~/Library/Application Support/SGF Tools/`
through `getpwuid`, as the app and the saver do, and it's compared with the folder `dscl` gives;
the app probe writes a test file there, the host probe reads it and is refused a write there,
both count the screensaver's games in Spotlight, with the query a test keeps equal to
`GameCandidates.query`, and get every result's path as `GameCandidates` does, and the test file
is removed. It never opens an SGF file, so it can't raise a permission request. It leaves two
small containers, `com.pragmaphilia.SGFTools.SandboxCheck.*`, in `~/Library/Containers`.

**The existing suites**, `swift test` in SGFKit and `xcodebuild … test` for the app's tests, still
pass.

## 11. John's manual test

1. **The app.** Build and install SGF Tools as usual (README, "Trying it out"), and check its
   entitlements with `codesign -d --entitlements - "/Applications/SGF Tools.app"`. Open it and
   click **Update Screensaver Games**; allow each permission request (Documents, the external
   volume). The window should say how many games it chose. Because the app is signed ad hoc,
   macOS may ask again after each new build.
2. **The saver.** `xcodegen generate`, then
   `xcodebuild -project SGFTools.xcodeproj -scheme "SGF Tools Screensaver" -configuration Release build`,
   and copy `SGF Tools.saver` from the build products into `~/Library/Screen Savers/`.
3. **The log.** In Terminal:

   ```sh
   log stream --level info --style compact --predicate 'subsystem BEGINSWITH "com.pragmaphilia.SGFTools"'
   ```

4. **The preview.** In System Settings > Wallpaper > Screen Saver, choose SGF Tools (third-party
   savers are under Other). For a minute, the preview should play games with no details, and no
   permission request should appear.
5. **The saver.** Start it (a hot corner, or waiting), and let it run three games, about two
   minutes, on every display. Look for: the fades, two moves a second, the details in a new place
   for each game and clear of the board, a different game on each display, and nothing on screen
   that shouldn't be.
6. **The host.** Right after stopping it, and again after starting and stopping it five times
   quickly:

   ```sh
   ps -o pid,%cpu,rss,etime,command -p $(pgrep -d, legacyScreenSaver)
   ```

7. **Direct mode.** Rename the playlist:

   ```sh
   cd ~/Library/Application\ Support/SGF\ Tools
   mv "Screensaver Games.sgfplaylist" "Screensaver Games.sgfplaylist.off"
   ```

   Start the saver for three minutes. If macOS asks whether legacyScreenSaver may read files,
   note the wording and click Don't Allow. Stop it, look in System Settings > Privacy & Security
   (Files & Folders, and Full Disk Access) for a legacyScreenSaver entry, and rename the playlist
   back.
8. **The log, saved** for the review of the run:

   ```sh
   log show --last 1h --info --style compact \
       --predicate 'subsystem BEGINSWITH "com.pragmaphilia.SGFTools"' > ~/Desktop/sgf-screensaver-log.txt
   ```

9. **After each new build** of the saver: `killall legacyScreenSaver`, then copy the new bundle
   over the old one.

## 12. Risks, and how each shows up

1. **The real host isn't the probe.** It's an Apple platform binary started through ExtensionKit,
   and it may not read the playlist's folder as the probe did. The `playlist` log line shows
   `EPERM`, and the saver falls back to direct mode. The fix is `/Users/Shared/SGF Tools/`, which
   the host-like probe could list, with the app's exception changed to that absolute path.
2. **The app's permission requests.** Spotlight never asks, so without the reads of 1.5 the app
   finds nothing (John's test of 2.1.0). Whether reading a volume's top level asks for the fixed
   external disk, and whether Spotlight answers with a place's files as soon as it's allowed, are
   untested. An ad hoc signed app is a new client for TCC after every build, so macOS asks again.
   If John declines, the app keeps the playlist it had, if that has more games, or else writes
   only what it could read, and the window names the places refused and opens their settings.
3. **Direct mode can raise a request for legacyScreenSaver**, perhaps when nobody is there to
   answer it, and a read waiting on it blocks a thread. The 3-second limit, denying a class
   after 3 time-outs in a row, and giving up when 6 abandoned reads haven't come back bound the
   cost; the preview never runs direct mode.
4. **The host's lifecycle on macOS 27 is untested**, since no third-party saver has run on the
   test Mac: views that pile up, `startAnimation` and `willstop` that don't come, a wrong
   occlusion state, and a second display that stays black. Section 8's rule has a fallback for
   each, and the `lifecycle` log shows which happened.
5. **The playlist can be a week old:** new games wait for the next update, and a deleted game
   still plays, since its moves are in the playlist.
6. **The first draft departs from the plan's "reads the actual file"** while the saver runs
   (question 1).
7. **The app's new entitlements and window can't be checked headlessly** without building the
   app, which registers its importer. Until John builds it (section 11, step 1), that code is
   compiled only by the test target.

## 13. Questions for John

Each has a default, which the first draft builds.

1. **Playing from the playlist.** The app reads the files and the saver plays what it took,
   instead of reading the file while it runs. *Default: yes.*
2. **The app's sandbox:** two temporary exceptions (read-only everywhere, and read-write on its one
   folder), or no sandbox for the app? As the sandbox profile grants them, they also let the
   app run programs and issue read extensions (1.5); the read exception could be narrowed to
   `/Users/` and `/Volumes/`. *Default: the exceptions, on `/`.*
3. **Freshness:** a new playlist when the app opens and the old one is a week old, and the button;
   or a background helper that refreshes it? *Default: the former.*
4. **How many:** a new random 10,000 at each update, or all of them (about 38 MB)? *Default:
   10,000.*
5. **Fifty moves on every board size**, as the plan says, or 50, 30, and 20 by size, as the
   thumbnails? (63,893 of the test Mac's 64,020 games are 19x19.) *Default: 50.*
6. **The result is shown from the start**, as the plan says, or held back until the last move?
   *Default: from the start.*
7. **Paths in the playlist:** each line starts with its file's URL, for the log and later
   features, which puts the names of files in Documents and on other disks where any of the
   user's processes may read them (1.6); or an opaque identity, such as a hash of the path?
   *Default: the URLs, as the README says.*

## 14. Later

- **The saver inside the app:** the app carries `SGF Tools.saver` in its Resources, and an
  "Install Screen Saver…" command opens it with `NSWorkspace`, so System Settings installs it and
  the app needs no write access to `~/Library/Screen Savers`. The app could then offer to update
  an older installed copy.
- **The opening in the Spotlight index,** as 1.x kept a position: a hidden importer attribute
  with each game's playlist line would let the app build the playlist from the index in a second,
  with no permission requests, and direct mode play without opening files. It needs a schema entry
  and every SGF file imported again (`mdimport -i`), so it waits for the first run's findings.
- **Direct mode first,** if the first run shows the host reads every location without a request.
- Drawing the empty board once and only the stones for each move (a new SGFRendering option), if
  the timings call for it.
- The plan's later options: move sounds, games from a chosen folder, and board and stone sets.

## 15. As built

The first draft, 2.1.0 (8), follows the design above, except:

1. **Values made fit for one line.** A tab or line break in a move or setup value becomes a space
   rather than being dropped, and a backslash left unpaired at the end of a value (only a value
   cut off by the end of a file has one) gets its pair. Either way the value means the same point,
   list, or pass. SZ is written from the size SGFKit read, and left out when it isn't valid, which
   also means 19x19.
2. **Spotlight's paths** come from each result's `MDItem`: `MDQueryGetAttributeValueOfResultAtIndex`
   gives no `kMDItemPath`, even with it among the query's value attributes.
3. **Direct mode's errors.** `unreadable` also covers errors other than `EACCES`, with their
   `errno` in the log, and `ENOTDIR` counts as missing.
4. **A pick relaxes what it avoids** in steps, so that a small playlist still plays (1.8).
5. **A new size or backing scale** starts a new game, as a start does, rather than drawing the
   current one again.
6. **The thumbnails stay PNGs** (`COMBINE_HIDPI_IMAGES` is off), as in Apple's own savers; Xcode
   would otherwise combine them into `thumbnail.tiff`.
7. **The bundle test doesn't link ScreenSaver.framework.** It declares the view's initializer in
   an `@objc` protocol instead, because the framework links Photos, which starts Contacts in the
   test process.
8. **A screen's game loop is in `Screensaver/SaverPlayer.swift`**, not in the view, so that the
   tests can play games on a scene with a clock they move; the view keeps its life in the host
   and the timer. The next game is prepared while the current one plays, but its first board is
   drawn only once the current game reaches its last move, so a screen holds two boards at a time.
9. **`BoardSize.sgf` is public again**, since the playlist line writes it (code review, L4).

**After the code review**, the same day, the sections above were revised where the reviewers
found the first build wrong: what a pick avoids, so that a small collection never shows a screen
the same game twice in a row, and direct mode's reads, one at a time, with a limit on those that
haven't come back rather than on all abandoned reads, so that a blocked location is denied and
the others still play (1.8); an update that keeps a playlist with more games, and the app waiting
for an update before it quits (1.5); the reader's outcomes (1.7); which views play (section 8);
the rights the entitlements grant (1.5); and the sandbox check (section 10). A playlist that can
be found but not opened is now logged once, and each game's source is named in words in the log.

Checked headlessly, on 2026-09-25, after the review's fixes:
- the package's tests (213) and the app's logic tests (162), which include the screensaver's,
  among them a game played through on a scene without a window, and three screens playing at
  once; the Release bundle with `plutil`, `lipo`, `codesign`, and `nm`; and the bundle test, which
  loaded it and made its view at 1920x1080 and 300x190
- the app's sources, type-checked with `swiftc -typecheck` in Swift 6 mode, since the app isn't
  built
- `Tests/SandboxCheck/check.sh`: every step passed; both probes found the playlist's folder
  through `getpwuid`, and each got 64,020 games and 64,020 paths from Spotlight
- before the review's fixes, which left the lines as they were: the builder on the test Mac's
  games, from an unsandboxed command-line tool with a release build of SGFKit: 10,000 games of
  64,020 chosen in 2.9 seconds, 5.2 MB. Every line of a playlist of
  all 63,996 qualifying games outside `~/Library` replays as its file does, position by position
  to move 50, with the same players, ranks, result, event, and date. Lines are 518 bytes on
  average and 1,045 at most.

Not checked, and left for John's test (section 11): anything under TCC, since the tool read with
the terminal's access; the real host, System Settings, and the app itself, which wasn't built.

**After John's first test**, 2.1.1 (9), on 2026-09-26:
1. **The app asks for access before it asks Spotlight.** 2.1.0 found no games, since Spotlight
   hides the files an app may not read and never asks (1.2). On the click, the app now reads the
   top level of Documents and of each local volume first, so that macOS asks, and names the
   places refused, with a button that opens Files & Folders (1.5). An update when the app opens
   never asks.
2. **A place that comes up empty keeps the playlist.** An update that finds no games in a place
   TCC guards, where the playlist has some, keeps the playlist unless it may read the place and
   the games are gone (1.5), since 2.1.0's rules would have replaced 10,000 games with the few in
   the places the app could still read.
3. **The first game after a start comes in quickly** (section 4). With 2.1.0, the board was
   readable about 5 s after the saver started, after a random wait of up to 3 s and a 2 s fade,
   and John dismissed it twice before then; the preview waited 5 s more for a `startAnimation`
   that never came, and now waits half a second (sections 7 and 8).
4. **Two moves a second**, not one, and the last position held for 10 s, not 5, John's choice
   after watching it: a 50-move game takes about 40 s, not a minute (section 4). The playlist
   still holds 50 moves a game.

## Appendix: what was checked

On the test Mac, macOS 27.0 (26A428), on 2026-09-25:
- `codesign -d --entitlements -` on `legacyScreenSaver.appex`, `WallpaperLegacyExtension.appex`,
  and `WallpaperAgent.app`; `lipo -archs` on the host, `mdworker_shared`, and the importer.
- `plutil -p` on the host container's `.com.apple.containermanagerd.metadata.plist`, and `ls` of
  the container and of both Screen Savers folders; `log show` for the host (no entries).
- `application.sb`, read for `yasb`, the `/` exception, and `com.apple.metadata.mds`; `grep -a` of
  `loginwindow` for the screensaver notifications.
- `mdfind` counts of SGF files and qualifying games, by location; `diskutil info` on the external
  volume.
- The probes, built with `swiftc` and signed with `codesign -s - --entitlements`: the Spotlight
  query with `MDQuery` and `NSMetadataQuery` and five reads per location, with the host's file
  entitlements and with the app's; folder listings and writes; and the playlist round trip,
  with an app-like writer and a host-like reader.
- `BoardRenderer` timings and mock screens, from a release build of SGFKit.

Sources:
- ScreenSaverMinimal (the Aerial project), README and `ScreenSaverMinimalView.swift`:
  <https://github.com/AerialScreensaver/ScreenSaverMinimal>
- macOS 26 Tahoe Screen Saver issues: <https://developer.apple.com/forums/thread/787444>
- Is there any future for screensavers on macOS?: <https://developer.apple.com/forums/thread/797121>
- ScreenSaver: legacyScreenSaver process?: <https://developer.apple.com/forums/thread/117136>
- Preemptively enable external volume access: <https://developer.apple.com/forums/thread/686498>
- App data protection: <https://developer.apple.com/forums/thread/739602>,
  <https://developer.apple.com/forums/thread/766275>
- Wade Tregaskis, How to make a macOS screen saver:
  <https://wadetregaskis.com/how-to-make-a-macos-screen-saver/>
- WebViewScreenSaver README: <https://github.com/liquidx/webviewscreensaver>
- Aerial: troubleshooting
  (<https://github.com/JohnCoates/Aerial/blob/master/Documentation/Troubleshooting.md>), FAQ
  (<https://aerialscreensaver.github.io/faq/>), issues #879 and #1339
