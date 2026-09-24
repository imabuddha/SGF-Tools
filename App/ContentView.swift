import AppKit
import SwiftUI

/// The app's window: what SGF Tools does, where to see it, and the version.
struct ContentView: View {
    /// The version shown, such as "2.0.2 (3)".
    var version = Self.bundleVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SGF Tools")
                        .font(.largeTitle.weight(.semibold))
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text("SGF Tools shows Go game records (SGF files) in Finder and Quick Look, and lets Spotlight search them.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Feature(
                    symbol: "square.grid.3x3",
                    title: "Thumbnails",
                    text: "Finder shows each game’s board after the opening moves, in icon view, in "
                        + "column view, and in the Get Info window. A file with several games shows a "
                        + "stack of boards."
                )
                Feature(
                    symbol: "eye",
                    title: "Preview",
                    text: "Select a game in Finder and press the Space bar to see its board beside the "
                        + "players, the result, and the rest of the game information."
                )
                Feature(
                    symbol: "magnifyingglass",
                    title: "Search",
                    text: "Spotlight indexes each game’s players, event, date, result, and comments. In a "
                        + "Finder search, choose Other… from the attribute menu for fields such as Black "
                        + "Player, Winner, and Year Played."
                )
            }

            Text("There is nothing to set up: once SGF Tools is in your Applications folder, macOS uses it "
                + "for SGF files. If thumbnails or previews don’t appear, check that SGF Tools is turned "
                + "on in System Settings > General > Login Items & Extensions, under Quick Look. Games "
                + "Spotlight indexed before SGF Tools was installed become searchable once they are indexed "
                + "again; the README on GitHub explains how.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 520)
    }

    /// The app's version and build, such as "2.0.2 (3)".
    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// One feature: an SF Symbol, a title, and a sentence or two.
private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
