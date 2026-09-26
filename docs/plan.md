# SGF Tools 2.0: the plan

Decisions as of 2026-09-25. The background is in `old-version-analysis.md`.

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
3. **SGF Tools.app** (done) with the Quick Look thumbnail and preview extensions. Thumbnails read
   the file itself, with no dependency on Spotlight. Both show the position after 50, 30, or 20
   moves by the board's shorter side (19 lines or more, 13 to 18, smaller), counting passes. The
   look's settings are constants in `Shared/Look.swift`.
4. **Spotlight importer** (done): an `.mdimporter` embedded in the app, because macOS 27 never
   calls Spotlight import extensions for files on disk (see `spotlight-notes.md`). It sets the
   attributes of 1.x under their 1.x names, so old saved searches work, with values from
   SGFKit's game information, and names them in the 10 languages of 1.x (from the
   `legacy-1.x` branch's `SpotlightImporter/*.lproj/schema.strings`).
5. **The screensaver** (done): designed in `screensaver.md`, first drafted as 2.1.0 (8), and
   approved by John as 2.1.1 (9) after his hands-on test.
6. **The first public release**: 2.0.7 (10), so that it reads as 2.0, with the build number still
   rising. A disk image on GitHub holds the app and the screensaver, signed ad hoc as before, and
   not notarized; the README says how to let macOS open them. Notarization waits for a Developer
   ID.

## Look

Decided by John on 2026-09-24:

- **No margin.** Thumbnails and previews use a margin of 0, so stones on the edge reach the edge of
  the board, as in 1.x. On a real board the outer line is where an edge stone's center sits, so the
  stone comes up to, or close to, the board's edge. Coordinates go outside the board, in their own
  space, and don't push the stones in.
- **Five star points on 13x13:** the 4-4 points and the center. Every other size keeps the 1.x
  rules.
- **Coordinates on the left and bottom only** (in the preview), as the renderer's default when
  coordinates are on. Past 25 columns the letters go on as AA, AB, and so on.
- **Unchanged:** the flat board stays buff, the shaded board keeps its procedural wood, a
  collection shows three boards stacked behind the front one, and the last move is marked with a
  ring.

## Parser decisions

- A file that claims UTF-8, or names no charset, but isn't valid UTF-8 is decoded with macOS's
  charset detection among GB18030, CP949 (EUC-KR), CP932 (Shift_JIS), Big5, and Windows-1252,
  with Windows-1252 as the last resort. Text that reads as ordinary Western European text in
  Windows-1252 stays Windows-1252, because the detection alone takes short Western text such as
  "Émile" for Big5 or Shift_JIS, unless a non-ASCII byte comes right before a backslash that
  isn't a soft line break, as the second byte of a Shift_JIS, GBK, or Big5 character can. A
  Latin-1 label is read as Windows-1252, as browsers do.
- Western text in UTF-8 with a few stray bytes stays UTF-8, and the stray bytes are read as
  Windows-1252. A soft line break inside a UTF-8 character, left by a program that wraps lines
  by counting bytes, doesn't make the text invalid: the UTF-8 check is repeated without soft line
  breaks.
- Text that was already garbled on disk (double-encoded UTF-8, literal U+FFFD) is left as it is.
- "The first 50 moves" counts passes, so move 50 matches the move numbers in other SGF programs.
- A point off the board (including `tt` on boards up to 19x19) is a pass. Several setup properties
  in one node apply in the order AB, AW, AE.
- Properties right after a game tree's `(`, with no `;`, are its root node, with a warning.

## The screensaver, first draft

- It picks a random game from the SGF files Spotlight has indexed, reads the actual file, and plays
  out the first 50 moves:
  - the board fades in
  - it plays two moves a second, with no sound (the plan said about one; John chose two after
    trying it, on 2026-09-26)
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
  *Answered in `screensaver.md`: the app writes a playlist, each game a short SGF line, and the
  screensaver reads the files itself only when there is none.*
