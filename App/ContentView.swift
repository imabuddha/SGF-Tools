import AppKit
import SwiftUI

/// The app's window: what SGF Tools does, where to see it, the screensaver's games, and the
/// version.
struct ContentView: View {
    /// The version shown, such as "2.0.2 (3)".
    var version = Self.bundleVersion

    /// The screensaver's games.
    var screensaverGames = ScreensaverGames.shared

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
                ScreensaverRow(games: screensaverGames)
            }

            Text("Thumbnails, previews, and search need no setup: once SGF Tools is in your Applications "
                + "folder, macOS uses it for SGF files. If thumbnails or previews don’t appear, check that SGF "
                + "Tools is turned on in System Settings > General > Login Items & Extensions, under Quick "
                + "Look. Games Spotlight indexed before SGF Tools was installed become searchable once they "
                + "are indexed again. The screensaver is installed on its own. The README on GitHub explains "
                + "both.")
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

/// One feature: an SF Symbol, a title, a sentence or two, and anything else below them.
private struct Feature<Extra: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).fixedSize(horizontal: false, vertical: true)
                extra
            }
        }
    }
}

extension Feature where Extra == EmptyView {
    init(symbol: String, title: String, text: String) {
        self.init(symbol: symbol, title: title, text: text) { EmptyView() }
    }
}

/// The screensaver's feature: what it does, what games it has, the button that chooses new
/// ones, and, when macOS refused the app access to places that may hold games, a button that
/// opens the setting.
private struct ScreensaverRow: View {
    let games: ScreensaverGames

    var body: some View {
        Feature(
            symbol: "play.display",
            title: "Screensaver",
            text: "The SGF Tools screensaver plays the opening of a random game on each display. SGF Tools "
                + "chooses up to 10,000 of the games Spotlight has indexed, and chooses again when you "
                + "open it a week later."
        ) {
            Text(games.status)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            ForEach(games.problems, id: \.self) { problem in
                Text(problem)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Update Screensaver Games") { games.update() }
                    .disabled(games.isUpdating)
                    .help("Choose a new set of random games for the screensaver. macOS may first ask whether "
                        + "SGF Tools may read your Documents folder and your other disks.")
                if let pane = games.settingsPane {
                    Button("Open System Settings") { NSWorkspace.shared.open(pane.url) }
                        .help("Open \(pane.rawValue) in Privacy & Security, where you can let SGF Tools read "
                            + "the folders and disks that hold your games.")
                }
            }
            .padding(.top, 6)
        }
    }
}
