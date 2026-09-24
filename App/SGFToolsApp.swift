import AppKit
import SwiftUI

/// SGF Tools: a small window that explains what the app does. The app is mainly the home of its
/// Quick Look extensions, which draw thumbnails and previews of SGF files in Finder.
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

/// Quits the app when its window closes, as single-window utilities do.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
