# Spotlight on macOS 27: what works

Notes from the feasibility test for step 4 of the plan, run on 2026-09-24 and 25 on macOS 27.0
(26A428) with Xcode 27.0, Apple Silicon. Two throwaway prototypes, both ad hoc signed and built
from the command line:

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
- `mds` refreshes its list of plug-ins between 10 seconds and 2 minutes after LaunchServices
  reports an app registered or unregistered. Registering an app that is already registered doesn't refresh it.
  **If the bundle is deleted before the refresh, `mds` keeps a stale entry** and keeps trying to
  load the missing plug-in for that type, so the type isn't imported at all. Registering the app
  again at the same path and then unregistering it clears the entry. So: unregister, wait for
  `mdimport -L` to drop it, and only then delete.
- Registering the prototype didn't re-import the other SGF files on the Mac while it was
  registered (about half an hour in all): `mdfind 'com_breedingpinetrees_sgf_black == "*"'` found
  only the test files.

## Re-importing SGF files

- `mdimport <folder>` re-imports every file under the folder, whether or not it changed. This is
  the simplest way to re-index a folder of games.
- `mdimport a.sgf b.sgf …` re-imported only the first file. With `xargs`, pass one path per call:

  ```sh
  mdfind -0 'kMDItemContentType == "com.red-bean.sgf"' | xargs -0 -n 1 mdimport
  ```

  This reached every file, at about 10 ms per call (so an hour or two for 50,000 files, plus the
  importing itself, which Spotlight does in the background).
- A file imported in the last minute or so isn't imported again on request.
- `mdimport -r <importer>` asks Spotlight to re-import every file of the importer's types on every
  volume. Not tested here, deliberately.

## Not tested

- Finder's search attribute picker ("Other…") can only be checked in the Finder, by hand. The
  display names it would use are the ones `mdimport -A` lists, which (B) provides.
