# Code review, 2026-09-25

A review of SGF Tools 2.0 at `853a4f2` (2.0.3, build 4): SGFKit, SGFRendering, the app with its
Quick Look extensions, the Spotlight importer, the tests, and the docs. It looks for duplication,
for types in the wrong place, for bugs, for dead code and stale docs, and for inconsistencies.

Each finding gives its location, its severity (**bug**, **design**, or **tidy**), and the fix,
or why it is left as it is. Line numbers are those of `853a4f2`.

## Bugs

**B1. A GM of -9223372036854775808 crashes GameInfo.** `SGFKit/Sources/SGFKit/GameInfo.swift:197`,
`gameTypeName(for:)`: `names.indices.contains(gameType - 1)` overflows when GM is `Int.min`,
which `SGFValue.number` reads without complaint, and the overflow traps. A file with that GM
would crash the Spotlight worker that imports it and the Quick Look preview (checked: the process
stops with SIGTRAP). *Fix:* check the range before subtracting; a test for GM at `Int.min` and
`Int.max`.

**B2. A Real too large for a Double reads as infinity.** `SGFKit/Sources/SGFKit/SGFProperty.swift:77`,
`SGFValue.real`: a value of 400 digits gives `+infinity` where `number` gives `nil` for a value too
large for an `Int`. Infinity would reach the preview's Komi ("∞") and Spotlight's Komi and
Duration. *Fix:* `nil` unless the value is finite; a test.

**B3. A win's margin is read with Swift's number rules, not SGF's.** `Shared/GameSummary.swift:117`,
`describeMargin`: `Double(text)` accepts hexadecimal and exponents, so `B+0x10` reads "Black won
by 16 points" and `B+1e2` "Black won by 100 points", and it refuses the decimal comma that SGFKit
accepts in komi, so `B+3,5` reads "Black won (3,5)". *Fix:* read the margin as an SGF Real
(`SGFValue.real`), which also makes the `isFinite` check unnecessary; tests. The wording stays as
it is.

**B4. The preview reads and parses every game of a file, however large.**
`Shared/GamePreviewView.swift:14`, `GamePreview.init?(contentsOf:)`: the whole file is parsed so
that the preview can count its games, and `GameInfo(collection:)` also joins the comments of
every game, all in the extension. A made-up collection of 18.7 MB (40,000 games) takes 1.0 s
and 554 MB (release build); parsing takes about 30 times a file's size in memory
(`docs/spotlight-notes.md`), so a 100 MB file would take gigabytes. Thumbnails stop after the
first game, and the importer reads at most 2 MB, but the preview has no limit. *Fix:* read a file
over 2 MB only to its first game, as thumbnails do. The preview then says the file holds
"Several" games, as it already does for a file read partly. A test. The limit is the importer's,
for the same reason, and covers every SGF file found so far (the largest is 1.78 MB).

**B5. The README's way to index existing games misses every file on an external disk.**
`README.md`, "Indexing the games you have", recommends
`mdfind -0 'kMDItemContentType == "com.red-bean.sgf"' | xargs -0 -n 1 mdimport`. On John's Mac
(macOS 27, 2026-09-25) it left 20,165 files indexed, all on the internal disk, and none of the
64,812 on an external volume: there, `mdimport <file>` and `mdimport -i <file>` return without
storing anything, although `mdimport -t -d2 <file>` shows the importer working.
`mdimport -i <folder>` imports and stores on both disks. Whether the internal files came from the
per-file calls or from Spotlight's own background pass is unknown. *Fix:* recommend
`mdimport -i <folder>` for each folder that holds SGF files, drop the per-file command, and
record the finding in `docs/spotlight-notes.md`, whose "This reached every file" it corrects.

## Design

**D1. The main line's moves are worked out in several places.** `SGFGame.mainLineMoveCount`
(`SGFGame.swift:55`), `GameInfo.init` (`GameInfo.swift:161`), and `OpeningPosition.init`
(`Shared/OpeningPosition.swift:26`) each map the main line through `move(on: boardSize)`, as do
three tests (`OpeningPositionTests.swift:24`, `GameTests.swift:10`, `SampleSheet.swift:73`), and
`position(afterMainLineMoves:)` walks the main line with a loop of its own. *Fix:* one walk of the
main line in `SGFGame`, used by `mainLine`, `mainLineMoveCount`, `position(afterMainLineMoves:)`,
and a new `mainLineMoves: [Move]`, which `OpeningPosition` and the tests use. `GameInfo` keeps
counting on the main line it has already walked for its fields: a second walk, for
`mainLineMoves`, measured about a tenth slower. Adds `SGFGame.mainLineMoves` to the public API.

**D2. Whether SZ is valid is decided in three places.** `SGFGame.init` (`SGFGame.swift:23`), the
parser's invalid-size warning (`SGFParser.swift:204`), and `SpotlightAttributes`
(`Spotlight/SpotlightAttributes.swift:102`), which parses the root's SZ again to learn whether
SGFKit could read it. *Fix:* `SGFGame.declaredBoardSize`, the size SZ gives or `nil`, next to
`boardSize`; the parser and the importer use it. Adds `SGFGame.declaredBoardSize` to the public
API.

**D3. The thumbnail's image maker is a test helper in the product, and a copy.**
`Shared/Thumbnail.swift:46`, `Thumbnail.makeImage(size:scale:)`, sets up a bitmap as
`BoardRenderer.makeImage(size:scale:drawing:)` (`BoardRenderer.swift:146`) does, without its
checks, and only the tests call it: the extension draws with `draw(in:rect:)`. *Fix:* remove it;
the tests draw thumbnails into the test bitmap of D4, as the extension draws them.

**D4. The tests read pixels with five copies of the same code.** In the app's tests,
`ThumbnailTests.alpha(_:x:y:)`, `PreviewRenderingTests.brightness(of:in:)` and
`warmth(of:in:)` (the same twelve lines twice), and `AppIconArtwork`'s `Bitmap` each draw an image
into a bitmap to read it, and `PreviewRenderingTests.write` and `AppIconArtwork.writePNG` both
write PNGs. In SGFKit's rendering tests, four tests create the same bitmap context inline, and
`Pixels.bytesForComparison` rebuilds the bytes that `Pixels` already holds. *Fix:* one `Bitmap`
and one `writePNG` in `Tests/TestSupport.swift`; a `bitmapContext(width:height:)` helper and
`Pixels.bytes` in `SGFRenderingTests`. The two test targets keep their own helpers, because the
Xcode test bundle can't use SwiftPM's test targets.

**D5. The preview extension compiles a file it doesn't use.** `project.yml:88`: it takes all of
`Shared`, including `Thumbnail.swift`, while the thumbnail extension lists its files. *Fix:* list
the preview's shared files too.

**D6. The preview's model is in its view file, and a view is named after the wrong model.**
`Shared/GamePreviewView.swift`: `GamePreview`, which reads the file, sits with the views, unlike
`Thumbnail`, `OpeningPosition`, and `GameSummary`, which have files of their own; and
`GameInfoView` shows a `GameSummary`, not SGFKit's `GameInfo`. *Fix:* move `GamePreview` to
`Shared/GamePreview.swift`, and rename the view `GameSummaryView`.

## Tidy

**T1.** `SGFKit/Sources/SGFRendering/Palette.swift:47` and `:79`: both palettes are
`nonisolated(unsafe)` with no reason given. They need it because `CGGradient` isn't `Sendable`;
the palettes never change. *Fix:* declare `Palette` `@unchecked Sendable`, with that reason.

**T2.** `Shared/GameSummary.swift:128` and `Spotlight/SpotlightAttributes.swift:137` force-unwrap
`TimeZone(secondsFromGMT: 0)`. *Fix:* `.gmt`.

**T3.** `SGFKit/Sources/SGFKit/SGFParser.swift:424` and `:431` build fallback warnings inline, with
`charset.declaredName ?? ""` for a name that is never `nil` there, beside the local
`fallback(to:)` that does the same. *Fix:* use it.

**T4.** `SGFKit/Sources/SGFKit/BoardSize.swift:64`: `Character.isASCIIDigit` serves the value
types, board sizes, and dates, but lives with board sizes. *Fix:* move it next to the value
parsing in `SGFProperty.swift`.

**T5.** Doc comments left unwrapped by earlier edits: `BoardRenderer.swift:14` breaks a paragraph
after "Grid lines are", `BoardLayout.swift:6` runs to 114 columns, and
`SpotlightAttributes.swift:145` runs two paragraphs together. *Fix:* reflow.

**T6.** `SGFParser.swift:24`: `stopAfterFirstGame` is "for thumbnails of large collection files";
after B4 it is for large previews too. *Fix:* say so.

**T7.** `project.yml:11` and `:25` set the deployment target twice: `options.deploymentTarget`
sets it on every target, which overrides the project-level `MACOSX_DEPLOYMENT_TARGET`. *Fix:*
keep `options.deploymentTarget`, and check that every product still says macOS 26.

## Left as is

**L1. Results and dates.** `GameInfo` keeps the result and the date as written, with what they
mean (`outcome`, `datePlayed`); `GameSummary` spells them out for the preview, and
`SpotlightAttributes` stores the result as written and the date as a moment. Nothing is decided
twice. The only common piece is a Gregorian calendar in UTC, three lines in each; a shared helper
would need new SGFKit API or a file that both the preview and the importer compile.

**L2. `GameInfo.moveCount` and `SGFGame.mainLineMoveCount`.** Similar names for different counts:
without passes, as the Moves field of 1.x, and with passes, as SGF numbers moves. Both docs say
which is which, `GameInfo` keeps the fields of 1.x, and after D1 the code reads
`mainLineMoves.count { !$0.isPass }`. *Changed in 2.0.5, as John decided; see the outcome.*

**L3. `GameInfo(collection:)` joins the comments of every game, which only the tests read.** The
importer makes each game's `GameInfo` itself, for the values it collects from every game, and the
preview doesn't show comments. It stays SGFKit's view of a file as 1.x indexed it, and after B4
its cost in the preview is bounded.

**L4. Public API that only its own module or the tests use:** `BoardRenderer.compactCellSize`,
`collectionDepth`, and `drawCollectionBackdrop(for:in:rect:)`, `BoardCoordinates.name(of:on:)`,
`GameInfo.gameTypeName(for:)`, `Board.compactPosition`, and `SGFGame.subscript(id:)`. Each is
small and documented, and the screensaver, or the playlist the plan mentions, may want it.
*Changed in 2.0.5, as John decided; see the outcome.*

**L5. Charset names.** `Charset(declared:)` (`TextEncoding.swift:44`) matches common names of UTF-8
and Latin-1 itself before asking Core Foundation, which knows most of them. The list covers
spellings that aren't IANA names, such as `utf8`, `iso8859-1`, and `cp1252`.

**L6. `PartialDate`'s year** (`GameInfo.swift:293`) is found with a loop of its own beside
`digitRun()`: the year must be a run of exactly four digits, in a run of any length, which
`digitRun()`, at most nine digits, doesn't express.

**L7. Mapped files.** Thumbnails and previews map the file (`SGFCollection.swift:29`); a file
truncated by another process while it is mapped raises SIGBUS in the extension. Apps save by
replacing the file, which a mapping survives, and only the extension would stop.

**L8. The preview parses on the main thread** (`PreviewViewController.swift:17`), which after B4
takes at most about 0.1 s.

**L9. Similar fixtures.** `Fixtures.game19` (SGFKit), `Fixtures.fullInfo`, and
`SpotlightAttributesTests.everyProperty` are all made-up games with most properties. Each target
is self-contained, and each fixture fits its tests' expectations.

**L10.** `SGFValue.unescape` (`SGFProperty.swift:130`) tests for `\` and whitespace with byte
values rather than the parser's private `ASCII` helpers, which would have to become visible
across files for two comparisons.

**L11.** `ThumbnailProvider` and `PreviewViewController` each build the same "no game" error, in
one line.

## Known defects, not in scope

These come later, as John decided, and are not fixed here:

1. The renderer traps on absurd sizes: `BoardRenderer.makeImage(size:scale:drawing:)`
   (`BoardRenderer.swift:150`) converts `size × scale` to `Int` before comparing it with 16,384,
   so a finite size such as 1e300 traps.
2. A soft line break can split a UTF-8 character.
3. Shift_JIS with no CA, and trail bytes that are backslashes.
4. Short French text detected as Chinese, Japanese, or Korean.
5. An implicit root with no `;`.

`GameResult`'s wording also stays as John decided.

## Outcome

Every finding marked *Fix* was fixed, in separate commits for refactors and for behavior changes.
Before each commit, the suite that its change affects passed; both suites pass at the end. The
version became 2.0.4 (5).

**Behavior changes**, all bug fixes:

- B1: a GM of `Int.min` no longer crashes GameInfo, and with it the importer and the preview.
- B2: `SGFValue.real` is `nil` for a number too large for a `Double`, not infinity.
- B3: a win's margin is read as an SGF Real: "B+3,5" is "Black won by 3.5 points", and "W+1e2"
  and "W+0x10" are shown as written instead of as 100 and 16 points.
- B4: the preview reads a file over 2 MB only to its first game and shows "Games: Several".
- B5: the README recommends `mdimport -i <folder>` to index existing games.

**Public API:** `SGFGame` gains `mainLineMoves` and `declaredBoardSize`; `SGFValue.real` returns
`nil` in one more case (B2). Inside the app: `GamePreview.init?(contentsOf:wholeFileLimit:)`,
`GameSummaryView` for `GameInfoView`, and `Thumbnail.makeImage(size:scale:)` is gone.

**D1 took a second try.** The first version walked the main line with `sequence(first:next:)`,
and `GameInfo` counted its moves with `mainLineMoves`; together they made the game information of
4,000 games 29% slower in a release build (41 to 53 ms). The walk is now a small iterator struct,
a little faster than the old loop, and `GameInfo` counts on its own walk: 40 ms.

**Tests:** SGFKit's package went from 200 tests (170 in SGFKitTests, 30 in SGFRenderingTests) to
201, and the app's from 56 to 57; three parameterized tests also gained cases. The icon layers
the tests draw are byte for byte those in `App/AppIcon.icon`.

**Timing**, debug builds as the tests run them: the renderer's median for a 512x512 19x19 board
of 112 stones stayed at about 1.1 ms flat and 2.4 to 2.8 ms shaded (1.16 and 2.81 before);
johnVsGnu's thumbnail at 1024x1024 at about 7.3 ms; the importer's 4,000 games at 0.88 to 0.91 s
(0.89 before).

**The products, checked once, headlessly:** the Release build's app, extensions, and importer are
all 2.0.4 (5), for macOS 26.0. `mdimport -t -d2` used the build's importer: johnVsGnu.sgf gave
all 24 custom attributes and the standard ones, a made-up collection gave Games 3 and Collection
yes, and a made-up file with GM at `Int.min` and a 400-digit komi imported without a crash.
`qlmanage -t -x` made thumbnails of both files, but with the installed 2.0.3 extension, which
Quick Look kept using while the build was registered; the current code draws both thumbnails
pixel for pixel as that extension did. That is a regression guard only: the build's own Quick
Look extensions weren't exercised. Then the build was unregistered, Spotlight dropped its
importer 15 seconds later, and only then were the build products deleted; the copy in
`/Applications` (2.0.3) is again the only one registered.

**Left for John:**

- On an external disk, `mdimport` given a single file stores nothing (B5); that may be worth a
  report to Apple.
- The five known defects above.

### John's decisions, 2026-09-25

- **The 2 MB limit (B4) stays.** John confirmed it. The preview reads a file over 2 MB only to
  its first game and shows "Games: Several", and the importer reads a file's first 2 MB, as
  before. Nothing changed.
- **L2: the count that leaves out passes now says so.** `GameInfo.moveCount` is now
  `GameInfo.moveCountWithoutPasses`, and its doc comment and that of
  `SGFGame.mainLineMoveCount`, which counts passes as SGF numbers moves and keeps its name, each
  point to the other. The Spotlight attribute `com_breedingpinetrees_sgf_moves` keeps its name
  and its count, without passes, as in 1.x.
- **L4: the public API is what is used, and the core others would need.** A declaration stays
  public if the app's shared code, the extensions, the importer, or SGFRendering use it, or if it
  is the core of a type John named for other users of the package: the parser, `SGFCollection`,
  `SGFGame`, `GameInfo`, `Board`, `BoardRenderer`, and `BoardStyle`, with the types in their
  API, such as `SGFNode` and `BoardSize`. Everything else that only its own module or the tests
  used is now internal, and the package's tests reach it with `@testable import`:
  - SGFKit: the initializers that only the parser calls, of `SGFCollection`, `SGFGame`,
    `SGFNode`, `SGFProperty`, `SGFWarning`, and `Move`; `SGFCollection.moreGamesFollow` and
    `SGFGame.encoding`; `GameInfo.init?(collection:)` and `gameTypeName(for:)`;
    `Board.compactPosition`; `StoneColor.opponent`; `Move.isPass`; `GameResult.init(sgf:)` and
    `winner`; `PartialDate.init?(year:month:day:)` and `dateComponents`; `SGFPoint.init?(sgf:)`
    and `sgf`; and `BoardSize.maximum`, `init?(_:)`, `init?(sgf:)`, `isSquare`, `sgf`, and
    `contains(_:)`.
  - SGFRendering: `BoardCoordinates`, `BoardSize.starPoints`, `BoardRenderer.collectionDepth`,
    and `drawCollectionBackdrop(for:in:rect:)`.
  - Removed, because nothing used them: `SGFGame.subscript(id:)`, `PartialDate`'s `Comparable`
    conformance, and `BoardRenderer.compactCellSize`, whose number the renderer's type comment
    now gives.

  One app test makes its date with `PartialDate(sgfDate:)` instead, so the app's tests still
  use only the public API, as the products do.

These follow-ups are version 2.0.5 (6), with no behavior change. SGFKit's 201 tests (171 in
SGFKitTests, 30 in SGFRenderingTests) and the app's 57 pass, as before.
