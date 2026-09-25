import AppKit
import SwiftUI

/// SGF Tools: a small window that explains what the app does. The app is mainly the home of its
/// Quick Look extensions, which draw thumbnails and previews of SGF files in Finder, and of its
/// Spotlight importer, which indexes the games. It also chooses the games the screensaver plays.
@main
struct SGFToolsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("SGF Tools", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            // One window, and no documents: nothing to create or open.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Link("SGF Tools on GitHub", destination: URL(string: "https://github.com/imabuddha/SGF-Tools")!)
            }
        }
    }
}

/// Chooses the screensaver's games when the app opens, if they are due, and quits the app when
/// its window closes, as single-window utilities do, once an update of the games has finished.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ScreensaverGames.shared.appDidLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Waits for an update of the screensaver's games to finish, which writes the playlist only
    /// at its end, so that quitting doesn't throw away the files read so far.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let games = ScreensaverGames.shared
        guard games.isUpdating else { return .terminateNow }
        games.afterUpdate { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
