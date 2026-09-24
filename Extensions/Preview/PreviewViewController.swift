import AppKit
import Quartz
import SwiftUI

/// Quick Look's preview of SGF files: the first game's board after the opening moves, beside
/// the game information (see ``GamePreviewView``). A file with no game gets Quick Look's
/// standard preview instead.
final class PreviewViewController: NSViewController, QLPreviewingController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView()
        preferredContentSize = Look.previewSize
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard let preview = try GamePreview(contentsOf: url) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }
        let hostingView = NSHostingView(rootView: GamePreviewView(preview: preview))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
