# SGF Tools 2.0: the plan

Decisions as of 2026-09-24. The background is in `old-version-analysis.md`.

## Platform

- **Apple Silicon only, macOS 26 or later.** It's a fresh start, every Apple Silicon Mac can run
  macOS 26, and only macOS 27 is available for testing. No Intel builds.
- Swift and SwiftUI. SGFKit has no dependencies.
- File type: the shared `com.red-bean.sgf` type identifier.

## Repository

- 1.x is preserved on the `legacy-1.x` branch, and its tags stay. The rewrite replaces the contents
  of `main`, which was called `master` until 2026-09-24.
- MIT. The root `LICENSE` keeps the 2009-2010 notice for Jason Foreman and John Mifsud, and the
  README credits Jason as the original author.

## Order

1. **SGFKit** (done): a tolerant parser, the game model, and game info.
2. **SGFRendering** (done): the board drawing that the thumbnail, the preview, and the
   screensaver all share.
3. **SGF Tools.app** with the Quick Look thumbnail and preview extensions. Thumbnails read the
   file itself, with no dependency on Spotlight.
4. **Spotlight import extension.** It starts with a test of whether Finder offers our own fields
   (such as "Black Player" and "Komi") from an import extension; the standard attributes work
   either way. The translated field names of 1.x (10 languages) come from the
   `legacy-1.x` branch (`SpotlightImporter/*.lproj/schema.strings`).
5. **The screensaver.**

## Parser decisions

- A file that claims UTF-8, or names no charset, but isn't valid UTF-8 is decoded with macOS's
  charset detection among GB18030, CP949 (EUC-KR), CP932 (Shift_JIS), Big5, and Windows-1252,
  with Windows-1252 as the last resort. Text that reads as ordinary Western European text in
  Windows-1252 stays Windows-1252, because the detection alone takes short Western text such as
  "Émile" for Big5 or Shift_JIS. A Latin-1 label is read as Windows-1252, as browsers do.
- Text that was already garbled on disk (double-encoded UTF-8, literal U+FFFD) is left as it is.
- "The first 50 moves" counts passes, so move 50 matches the move numbers in other SGF programs.
- A point off the board (including `tt` on boards up to 19x19) is a pass. Several setup properties
  in one node apply in the order AB, AW, AE.

## The screensaver, first draft

- It picks a random game from the SGF files Spotlight has indexed, reads the actual file, and plays
  out the first 50 moves:
  - the board fades in
  - it plays about one move per second, with no sound
  - it fades out and picks another random game.
- As each game fades in, its details appear at a random place on the screen: the players and their
  ranks, the result (who won), the event, and the date.
- Only files that name both players and have at least 20 main-line moves count as games, which
  leaves out book diagrams and problems.
- With several displays, each screen shows its own random game.
- No options in the first draft.

Later options:
- move sounds
- games from a chosen folder only
- board and stone sets made from John's own boards and stones, chosen by the user or at random.

**Open question for the first draft: getting at the files.** macOS 27 runs third-party screensavers in a sandboxed host
  (`legacyScreenSaver`). Its entitlements allow read-only access to the whole disk and to folders
  the user picks, but the protected folders (Documents, Desktop, and Downloads) may still be
  refused while the screensaver runs, and it's untested whether a Spotlight query works from
  inside the host. If they're refused, the app can keep a small playlist that the screensaver can
  read: for each game, its details and its first 50 moves in a compact string. That's the idea
  behind the 1.x position string, used again for moves.
