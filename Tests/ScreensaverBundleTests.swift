import AppKit
import Foundation
import Testing

/// What the test needs of a screensaver view, declared here so that the test bundle doesn't link
/// ScreenSaver.framework: linking it loads the Photos framework, which starts Contacts in the
/// test process.
@objc private protocol ScreensaverViewMaking {
    init?(frame: NSRect, isPreview: Bool)
    var animationTimeInterval: TimeInterval { get }
    var hasConfigureSheet: Bool { get }
}

/// Loads the built screensaver, when the environment variable `SGF_SCREENSAVER_BUNDLE` names it
/// (with `xcodebuild test`, set `TEST_RUNNER_SGF_SCREENSAVER_BUNDLE`), and makes its view as the
/// host would, without a window. Without the variable, the test does nothing.
@Suite("Screensaver: the built bundle")
struct ScreensaverBundleTests {
    nonisolated static let path = ProcessInfo.processInfo.environment["SGF_SCREENSAVER_BUNDLE"]

    @Test(.enabled(if: path != nil, "SGF_SCREENSAVER_BUNDLE names no bundle"))
    @MainActor
    func loadsAndMakesItsView() throws {
        let path = try #require(Self.path)
        let bundle = try #require(Bundle(url: URL(fileURLWithPath: path)))
        #expect(bundle.bundleIdentifier == "com.pragmaphilia.SGFTools.Screensaver")
        #expect(bundle.infoDictionary?["NSPrincipalClass"] as? String == "SGFToolsScreenSaverView")
        #expect(bundle.url(forResource: "johnVsGnu", withExtension: "sgf") != nil)
        #expect(bundle.url(forResource: "thumbnail", withExtension: "png") != nil)
        try bundle.loadAndReturnError()

        let principal: AnyClass = try #require(bundle.principalClass)
        #expect(NSStringFromClass(principal) == "SGFToolsScreenSaverView")
        let base: AnyClass = try #require(NSClassFromString("ScreenSaverView"), "loaded with the bundle")
        #expect((principal as? NSObject.Type)?.isSubclass(of: base) == true)

        class_addProtocol(principal, ScreensaverViewMaking.self)
        let maker = try #require(principal as? ScreensaverViewMaking.Type)
        let screen = maker.init(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), isPreview: false)
        #expect(screen?.animationTimeInterval == 1)
        #expect(screen?.hasConfigureSheet == false)
        let preview = maker.init(frame: NSRect(x: 0, y: 0, width: 300, height: 190), isPreview: true)
        #expect((preview as? NSView)?.frame.width == 300)
    }
}
