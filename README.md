# SGF Tools

Tools for SGF (Smart Game Format) Go game files on the Mac: board thumbnails and previews in
Finder and Quick Look, Spotlight search on players, events, dates, and results, and a screensaver
that replays games.

## Status

**Version 2.0 is being written from scratch** for Apple Silicon Macs running macOS 26 or later.
It isn't ready to install yet. So far:

- **SGFKit**, a Swift package with no dependencies:
  - a tolerant SGF parser: every SGF version, collections, any charset, and damaged or
    mislabeled files
  - the game model, with captures
  - the game information that Spotlight will index.
- **SGFRendering**, the board drawing that the thumbnails, the previews, and the screensaver share.

Next come the SGF Tools app with its Quick Look extensions, then Spotlight search, then the
screensaver. The plan is in [docs/plan.md](docs/plan.md).

To run the tests:

```bash
cd SGFKit && swift test
```

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
