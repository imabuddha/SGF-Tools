# SGF Tools 1.x: what was there, and what to carry forward

A read-through of the original SGF Tools (2009-2010), written before the rewrite. Checked against
the GitHub repository (tip 56362ce, 2021-01-06), its unmerged branches, and what macOS 27 does
with .sgf files today.

## 1. The repository

- **github.com/imabuddha/SGF-Tools**, public. On GitHub it is a *fork* of
  **github.com/threeve/SGF-Tools**, Jason Foreman's original, which hasn't been pushed to since
  2010-01-20 (at v1.4.2).
- 162 commits on master: 25 by Jason Foreman and 137 by John Mifsud. Jason made the initial import
  on 2009-07-17: the SGF parser and a first Spotlight importer. John joined on 2009-12-21 with
  version 1.2.1. Everything from 1.2.1 to 1.4.5 happened in five weeks, ending on 2010-01-24.
  The last commit is the 2021 README ("I'd love it if someone decides to revive it").
- Tags run from rel-1.0 to v1.4.5. The localize, localize-qlgen, and qlthumb branches are merged.
  **stoneSavour** has 5 commits that aren't on master: a screensaver project that is only Xcode's
  empty template, so the screensaver was never written.
- There are two issues, both closed, both from apetresc in 2010: a file with no board thumbnail
  (it had never been indexed), and the icon of a closed Dock stack.

## 2. License and credit

- **MIT**, in `Documents/License.txt`: "Copyright (c) 2009,2010 SGF Tools Developers".
  `Documents/Authors.txt` names the developers: Jason Foreman <jason@threeve.org> and John Mifsud
  <imabuddha@gmail.com>. GitHub detects MIT on Jason's repository but not on the fork, because the
  file isn't at the root.
- The README thanks Anders Kierulf (testing, suggestions, and translations), Kirk McElhearn
  (testing, suggestions, and French), and Frank G. Sion (German).
- The rewrite will share no code, so MIT wouldn't strictly require keeping the old notice. We keep
  it anyway, because Jason started the project. Plan: a root `LICENSE` (MIT) that keeps the 2009-2010
  notice for Jason Foreman and John Mifsud and adds 2026 for the new version, plus a History
  section in the README that credits Jason as the original author and names the contributors.

## 3. How 1.x worked

Five pieces, all Objective-C or C, built with Xcode 3.2 for 10.6 (32/64-bit Intel):

1. **SGF parser** (Jason). A streaming C parser: a Ragel-generated scanner (`sgf/sgfscan.rl`) feeds
   a Lemon LALR grammar (`sgf/sgfparse.y`). Callbacks fire for begin tree, end tree, property, and
   value data, and values stream in chunks of up to 512 bytes. Building it needs Ragel, which
   doesn't ship with Xcode, so the old TODO already said "replace parser w/ simple self-contained
   module that doesn't require non-Xcode tools".
2. **Spotlight importer** (`SGF.mdimporter`, `SpotlightImporter/SGFImporter.m`). It maps the root
   properties to 14 standard Spotlight attributes (Title, Authors, Participants, Contents, and so on)
   and 24 custom ones (`com_breedingpinetrees_sgf_*`: Black and White players, their ranks and
   teams, Result, Event, Komi, Handicap, Size, Round, Ruleset, Opening, and more). The custom
   attribute names are localized in 10 languages. It also derives some values:
   - Winner and Loser, from RE, PB, and PW
   - Year Played, as a number, because many old games only have a year
   - Games and Collection, for files that hold several games
   - Moves: the main line of the first game, without passes or variations
   - the game's name, from GM
   - **the board position** (see section 4).
   The mapping is documented in `Documents/SGFimporter Prop-Attr Mapping.rtf`.
3. **Quick Look generator** (`SGF.qlgenerator`). The thumbnail is a board image; a collection gets
   a backdrop of stacked boards. The preview is the board next to a metadata panel from a nib,
   also localized in 10 languages. **Both read the Spotlight metadata, not the file itself.**
4. **Board model** (`common/SGFGoban`). Boards up to 52x52. It plays moves with captures (a
   recursive liberty search) and suicide, and handles AB and AW.
5. **Board drawing** (`common/SGFDrawBoard`):
   - a kaya texture (`boardFill.png`) or a flat color
   - a black outer line with half-strength inner lines
   - star points for every board size (none on 4x4; 3x3 and 5x5 have their own patterns; up to
     11x11 on the third line, larger boards on the fourth; a center point on odd sizes; side points
     on odd sizes of 13 and up)
   - shaded stones (a radial gradient and a drop shadow) or flat ones, chosen in Info.plist.

Around the five pieces:
- an installer package whose postinstall ran `find / -iname *.sgf | xargs mdimport` to force a
  reindex
- a force-index script
- two example saved searches.

## 4. The "compact encoding": it stores a position, not moves

The trick worth remembering isn't a move list. At index time, the importer replays the first game's
main line with captures:
- the first **50 moves** on 19x19 and larger boards
- **30** on 13x13 to 18x18
- **20** on smaller boards.

Then it stores the resulting **position** as a short string:

    size,<black points>,<white points>      e.g.  19,pdpq...,dddp...

Each point is two SGF letters (a-z = 1-26, A-Z = 27-52, as in FF[4]). A 50-move position fits in
about 200 bytes. The attribute is marked `nosearch`, so it never bloated the search index. The
thumbnail and preview just decode and draw it, so Quick Look never had to parse SGF.

In 2010 that made the Quick Look side trivial and fast. The price was that **a board appeared only
after Spotlight had indexed the file**. Some files never got one:
- files not indexed yet (issue #1)
- files in folders excluded from Spotlight
- files on network or external volumes.

Version 1.4.3 had to fall back to the default icon for these. On a current Mac, parsing 50 moves
takes microseconds, so the new thumbnail extension should read the file directly. The encoding
then isn't needed for thumbnails. Keep the idea (a small summary computed at index time) for
later, for example to find games that share an opening.

## 5. What to keep

- The feature set: board thumbnails, a preview with the game information, and Spotlight search on
  players, ranks, event, date, result, and comments.
- The mapping from SGF properties to Spotlight attributes, and the derived values (winner and loser,
  year played, move count, games in a collection).
- Using standard attributes where they fit (Participants, Title, Authors, Contents, Headline), so
  plain Spotlight and Finder searches find games with no custom fields at all.
- The 10 languages of translated attribute names, so we don't lose Anders', Kirk's, and Frank's
  work.
- The board drawing rules: star points for every size, and the shaded and flat styles.
- The collection look: stacked boards for files with several games.
- The ideas on the old TODO: a search and view app, the screensaver, and a per-user install.

## 6. Lessons: what went wrong or was fragile (each becomes a test)

- **Anything before the first `(` killed the parse.** The untracked "why bad" files in the old
  clone all start with a literal `&#65279;`, an HTML-escaped byte-order mark left by a web
  download, and none of them got indexed. Readers should skip text before `(;`.
- **Encodings.** Only CA[UTF-8] was recognized; everything else was read as Latin-1. A file that
  says UTF-8 but isn't comes out garbled. Four of the "why bad" files do this: their only
  non-ASCII bytes are `A1 AF`, the right single quote `’` in the Chinese and Korean charsets (GBK,
  CP949), not Latin-1. A BOM wasn't handled.
- **Escapes.** `\]` and soft line breaks were never unescaped, so the backslash stays in the text.
- **Results.** Anything that doesn't start with "W+" counts as a Black win, so a draw (RE[0]), a
  void game, or an unknown result (RE[?]) all make Black the winner.
- **Setup stones.** AB and AW anywhere in the first game are added to the position, even in a
  variation or after move 50. AE (remove stones) is ignored.
- **Rectangular boards.** SZ[19:13] isn't supported, although FF[4] allows it.
- **Dates.** Only an exact YYYY-MM-DD becomes Date Played; anything shorter gets only the year.
- **Game names.** The GM list has typos: "omoku+Renju" should be Gomoku+Renju, and "Hnefatal"
  should be Hnefatafl.
- **The installer** ran `find /` over the whole disk.

## 7. What changed in macOS since 2010 (checked on this Mac, macOS 27.0, Xcode 27)

- **Quick Look:** current macOS no longer loads `.qlgenerator` plug-ins. The replacements are
  Quick Look *extensions* inside an app: a thumbnail extension (`QLThumbnailProvider`) and a preview
  extension (`QLPreviewingController`, or the data-based `QLPreviewProvider`). Nothing on this Mac
  provides either one for SGF today.
- **Spotlight:** `/Library/Spotlight` no longer exists here. Spotlight has an import *extension*
  type (`com.apple.spotlight.import`, `CSImportExtension`), which Apple's own PDF importer uses, and
  old `.mdimporter` bundles run through a system "legacy importer host". **Open question, to test
  first:** do custom fields such as "Black Player" or "Komi" from an import extension show up in
  Finder's search attributes the way `schema.xml` attributes did? If they don't, the standard
  attributes still work.
- **File type:** 1.x declared its own type identifier, `com.breedingpinetrees.sgf`. Everything on
  this Mac now uses **`com.red-bean.sgf`** (SmartGo and Kifubara both declare it). The
  new version should import that identifier, not invent another.
- **Screensaver:** third-party screensavers are still `.saver` bundles (`ScreenSaverView`). Apple's
  own savers are now private extensions, and macOS 27 runs third-party `.saver` bundles in a
  "legacy" host. That host has had well-known quirks since macOS 14 (for example, a saver not being
  told to stop), so this needs testing on 27.
- **Packaging:** extensions ship inside an app, so the new SGF Tools *is* an app. That fits the old
  TODO's "custom sgf search/view app". Anyone else will need a signed and notarized download, or
  the Mac App Store.
- **Language:** Swift and SwiftUI, with no Ragel and no Lemon.

## 8. Proposed shape of 2.0 (for discussion)

- **SGFKit**, a Swift package in this repository, used by everything below:
  - a tolerant parser (leading junk, BOM, CA, mislabeled encodings, escapes, FF[1]-FF[4],
    collections, rectangular boards)
  - a game model with captures
  - a Core Graphics board renderer.
- **SGF Tools.app**, a small host app (settings such as the board style; later perhaps a game
  browser), containing:
  - the thumbnail extension, which reads the file itself: no Spotlight dependency
  - the preview extension: the board and the game information
  - the Spotlight import extension, with the metadata of 1.x under the new type identifier.
- **The screensaver** (StoneSavour, if the old pun stays): it plays the first 50 or so moves of a
  random game from a chosen folder, then moves on to another.
- **Tests:**
  - public-domain and own games
  - a synthetic file for each lesson in section 6
  - no one else's commentary in the public repository.
- **Order:** SGFKit, then thumbnails and preview, then Spotlight, then the screensaver.
