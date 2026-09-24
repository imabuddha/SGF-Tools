# Spotlight on macOS 27: what works

Notes from the feasibility test for step 4 of the plan, run on 2026-09-24 and 25 on macOS 27.0
(26A428) with Xcode 27.0, Apple Silicon, and from building the importer for 2.0.2 (see
[The importer in 2.0.2](#the-importer-in-202)). The feasibility test used two throwaway
prototypes, both ad hoc signed and built from the command line:

- **(A)** an app with a Spotlight import extension: `NSExtensionPointIdentifier`
  `com.apple.spotlight.import`, a `CSImportExtension` subclass, `CSSupportedContentTypes`
  `com.red-bean.sgf`, sandboxed, and custom attributes set with
  `CSCustomAttributeKey(keyName: "com_breedingpinetrees_sgf_black")` and the like
- **(B)** an app with an old-style `.mdimporter` bundle in `Contents/Library/Spotlight/`: a
  CFPlugIn (`MDImporterURLInterfaceStruct`, C glue calling Swift), a `CFBundleDocumentTypes` entry
  with role `MDImporter` for `com.red-bean.sgf`, a `schema.xml` that declares the custom attributes,
  and an `en.lproj/schema.strings`.

Both read the file with SGFKit and set the same attributes: Title, Authors, Participants, Coverage,
and Contents (`kMDItemTextContent`), plus six of the 1.x custom attributes.

## Result

**(B) works; (A) is never called for files on disk.** Use a `.mdimporter` embedded in the app.

| Question | (A) import extension | (B) embedded `.mdimporter` |
|---|---|---|
| Picked up | Yes: `pluginkit -m -p com.apple.spotlight.import`, `mdimport -e`, and a Login Items & Extensions (BTM) entry of type `spotlight` | Yes: `mdimport -L`, and a BTM entry of type `spotlight` |
| Called when a file is imported | **No.** Not once: not while it was the only importer for the type (new files, imported with `mdimport <file>` and by saving them), and not while (B) was registered too | Yes, in one to three seconds |
| Standard attributes indexed | No (never called) | Yes |
| Custom attributes indexed and found by `mdfind` | No (never called) | Yes: strings, numbers, and Booleans |
| Display names (`mdimport -A`) | Not testable | Yes, from `schema.strings` |

Details for (A):
- Spotlight's server (`mds`) handed the SGF files to `mdworker_shared`, and the extension process
  never started for an import. Neither did Apple's own `PDFImporter.appex` or
  `LegacyImporterHost.appex` in six hours of log; PDFs are imported by the old
  `/System/Library/Spotlight/PDF.mdimporter`.
- `mdimport -m -y com.red-bean.sgf -u file://…` (the tool's "modern importer" test) launches the
  extension but fails with "Connection init failed at lookup with error 3" before the import. It
  fails the same way with Apple's `PDFImporter.appex` and a PDF, so the tool can't test extensions
  on macOS 27 either.
- This matches what Apple's DTS said in September 2025: `CSImportExtension` "was never fully
  implemented on macOS", and the old MDImporter API is the only option
  (<https://developer.apple.com/forums/thread/788126>).

Details for (B):
- The plug-in runs in an `mdworker` process launched for it alone, and can read the file it
  imports. Ad hoc signing is enough.
- A custom attribute that `schema.xml` doesn't declare (the prototype set one) is still stored and
  `mdfind` finds it, but it has no display name.
- A Boolean attribute is listed with `nosearch = 1` in `mdimport -X`, but a query on it by name,
  such as `com_breedingpinetrees_sgf_iscollection == 1`, works.
- Korean text (declared EUC-KR, and undeclared CP949), text before the first `(`, and a collection
  all indexed correctly.
- The largest SGF file on the test Mac (1.78 MB, 4,002 game trees), parsed in full with the
  comments of every game: `mdimport -t -d1 -p` reports 0.27 seconds in the plug-in.

## Commands and what they showed

```sh
mdimport -L                      # legacy plug-ins mds knows (per user)
mdimport -e                      # import extensions
pluginkit -m -v -p com.apple.spotlight.import
mdimport -A | grep breedingpinetrees   # custom attributes with their display names
mdimport -X                      # the merged schema
mdimport -t -d2 file.sgf         # dry run: which plug-in, and what it returns (works for (B))
mdimport file.sgf; mdls file.sgf # real import, then read the index
mdfind 'com_breedingpinetrees_sgf_black == "*Mifsud*"c'
mdfind 'com_breedingpinetrees_sgf_komi > 6'
mdfind 'com_breedingpinetrees_sgf_iscollection == 1'
mdfind 'kMDItemParticipants == "*Whitmore*"c'
mdfind xylophonic                # a word from a comment (kMDItemTextContent)
```

## Registration: things to know

- **Xcode registers what it builds.** A build of the app in DerivedData becomes a working importer
  right away, next to any installed copy. Unregister build copies with
  `lsregister -u <app>` when done.
- **When an extension and an `.mdimporter` both claim a type, the `.mdimporter` is used.**
- `mds` refreshes its list of plug-ins (its "BundleFinder") after LaunchServices reports an app
  registered or unregistered: after 10 seconds to 2 minutes when that is rare, but it backs off.
  Each refresh that follows closely on another raises a penalty by one, and the next refresh
  waits that many minutes: on 2026-09-24 and 25 the refreshes came 2, 3, 4, … 14 minutes apart
  (`log show --predicate 'process == "mds" AND eventMessage CONTAINS "BundleFinder"'` shows
  `oldPenalty` and `newPenalty`). The penalty went back to 0 after a few quiet hours. A refresh
  can also run too early: one ran half a second after a build's registration began and missed
  it, so the importer appeared only at the next refresh, 14 minutes later. Registering an app
  that is already registered doesn't refresh it.
  **If the bundle is deleted before the refresh, `mds` keeps a stale entry** and keeps trying to
  load the missing plug-in for that type, so the type isn't imported at all. Registering the app
  again at the same path and then unregistering it clears the entry. So: unregister, wait for
  `mdimport -L` to drop it, and only then delete.
- A worker process keeps the plug-in it loaded until it exits, so right after a rebuild a test
  import can still run the old code. Workers exit after a minute or two.
- Registering the prototype didn't re-import the other SGF files on the Mac while it was
  registered (about half an hour in all): `mdfind 'com_breedingpinetrees_sgf_black == "*"'` found
  only the test files.

## Re-importing SGF files

- `mdimport <folder>` re-imports every file under the folder, whether or not it changed. This is
  the simplest way to re-index a folder of games.
- `mdimport a.sgf b.sgf …` re-imported only the first file (though `mdimport -t` test-imports
  every file it is given). With `xargs`, pass one path per call:

  ```sh
  mdfind -0 'kMDItemContentType == "com.red-bean.sgf"' | xargs -0 -n 1 mdimport
  ```

  This reached every file. Each call takes 6 to 20 ms, so about 10 to 30 minutes for the 92,000
  SGF files on the test Mac, plus the importing itself, which Spotlight does in the background.
- A file imported in the last minute or so isn't imported again on request.
- `mdimport -r <importer>` asks Spotlight to re-import every file of the importer's types on every
  volume. Not tested here, deliberately.
- Files that Spotlight indexed long ago still have the kind (`kMDItemKind`) they got then. On the
  test Mac, 70,016 of 92,113 SGF files have "SmartGoFormat", which saved searches of 2010 look
  for, and 22,099 have "SGF", the description of the `com.red-bean.sgf` type that SmartGo now
  exports. A file gets the current kind when it is imported again, so once everything is
  re-imported, "Kind is SmartGoFormat" finds nothing, and `Kind is SGF` (`kMDItemKind = "SGF*"cdw`)
  finds everything. Without SmartGo, SGF Tools' own declaration gives "SGF game record".

## The importer in 2.0.2

Built from `Spotlight/` as `SGFToolsSpotlight.mdimporter` and embedded in the app at
`Contents/Library/Spotlight/`: `PlugIn.c` is the CFPlugIn glue, `Importer.swift` the entry point,
and `SpotlightAttributes.swift` the mapping, which the unit tests compile too. Xcode converts the
UTF-8 `schema.strings` files to UTF-16 as it copies them. Checked on 2026-09-25 with a Release
build, registered by Xcode, on synthetic games and `johnVsGnu.sgf`:

- `mdimport -t -d2` names the plug-in and returns all 24 custom attributes and the standard ones;
  after `mdimport <folder>`, `mdls` shows them in the index, and `mdfind` finds the files by Black
  Player, Event, Year Played, Winner, Participants, a word from a comment, Collection, Komi and
  Handicap together, and a range of Date Played. Plain searches (`mdfind Quillfeather`) find
  games by the players in Participants.
- `mdimport -A` lists the 24 display names, and `mdimport -X` shows the type's `allattrs` and
  `displayattrs`. CFBundle picks the right `schema.strings` for each of the 10 languages
  (`zh-Hant` for Taiwan and Hong Kong), and English otherwise.
- Korean in EUC-KR and Japanese in UTF-8 index correctly. A `.sgf` file with no game, or an empty
  one, gets only the basic attributes, and nothing is logged under the importer's subsystem,
  `com.pragmaphilia.SGFTools.Spotlight`, which only reports files it can't read.
- `xmllint --schema …/Metadata.framework/Resources/MetadataSchema.xsd schema.xml` rejects only
  the type name, `com.red-bean.sgf`: the XSD's pattern for type names allows a third part of
  two characters only (its last group lacks a `*`). `mds` accepts it.

**Reading at most 2 MB of a file.** Spotlight's workers have memory limits in
`/System/Library/LaunchDaemons/com.apple.jetsamproperties.Mac.plist`: 150 MB for
`com.apple.mdworker.shared` and `.single.arm64`, 100 MB for `.isolation` and `.bundles`. They
are soft limits: a test import of 8 MB, which takes about 250 MB, wasn't killed, but a worker
over its limit is the first to go when memory is short. SGFKit's parsed games take about 30
times the file's size in memory for a collection of ordinary games (64 MB for 2 MB and 4,000
games) and up to 70 times for one game that is all moves and variations (145 MB for 2 MB),
mostly because the parser holds two forms of the tree for a moment. So the importer reads only
a file's first 2 MB; the parser takes a game cut off there as it would a truncated file. The
largest SGF file on the test Mac, 1.78 MB with 4,002 games, is read in full. If larger files
matter one day, parsing one game at a time, or a leaner tree in SGFKit, would allow more.

**Speed.** Plug-in time reported by `mdimport -t -d1 -p`: about 1 ms for a single game, and
0.40 to 0.44 seconds at the 2 MB limit (4,000 or more ordinary games, or one game of about
350,000 moves). The same work compiled into one module with `-O` and run on its own takes 0.16
seconds, 60% of it parsing and the rest the game information of every game, which the collected
values need.

**Testing doesn't build the app.** The scheme builds the app for running, profiling, analyzing,
and archiving only, because every build of the app is registered and becomes a live importer.

## Translations for a native speaker to check

The display names are those of 1.x, with these errors fixed in 2.0.2: the English description of
Komi ("Amount of komi the white player received"), the French "Informatino", the Japanese stray
">" in Board Size and the Chinese form 黑 for Black (now 黒), and the Swedish "Regler" (Rules),
which was on Opening. Swedish Opening is now "Öppning", and "Regler" moved to Ruleset, which was
in English; both need a check.

Left as they were, because they look doubtful but may be right:
- Japanese 円形 ("circle") for Round (Round Number & Type)
- Korean 열기 and Russian Открытие for Opening, which read like the opening of a door or an
  exhibition rather than of a game
- also: Japanese ゲームの番号 ("game number") for Games (the number of games); German "Partie",
  French "Partie", and Russian "Партия" ("a game") for Game Type (the kind of game); and in
  French, some agreements, such as "l'ouverture utilisé" and "Règles utilisés".

Some names were never translated and are still in English: in both Chinese files Game Type,
Opening, Winner, Loser, and Collection; in Swedish Game Type, Year Played, Winner, Loser,
Collection, and half of Old Handicap ("Old Handikapp"); and in Polish and Russian Year Played.

## Not tested

- Finder's search attribute picker ("Other…"), and the rows of the example saved search, can
  only be checked in the Finder, by hand. The display names it would use are the ones
  `mdimport -A` lists.
- `mdimport -r`, which would re-import every SGF file on the Mac.
