import Darwin
import Foundation
import os

/// Asks macOS for access to the places its privacy settings guard where games are likely to be,
/// before the app asks Spotlight for games (see `docs/screensaver.md`, 1.5).
///
/// Spotlight leaves out of its results the files the app isn't allowed to read, and asking it
/// never makes macOS ask the user. Reading a place's top level does: macOS asks once for each
/// place, with the reasons in the app's `Info.plist`, and remembers the answer. So the app reads
/// each place first, but only right after someone clicks Update Screensaver Games, never when it
/// updates the games by itself.
///
/// **The places:** Documents, and each volume mounted under `/Volumes` that is on this Mac, shown
/// in Finder, and not the startup disk. Network volumes are left out, since Spotlight's search
/// (``GameCandidates/spotlightPaths()``) covers only the Mac's own volumes and the home folder.
/// The Desktop and Downloads folders are left out too: collections are rarely kept there, and
/// the request would come for every user, so games there are chosen only with Full Disk Access.
struct AccessCheck: Sendable {
    /// A place to ask about.
    struct Place: Sendable, Hashable {
        let location: LocationClass
        let path: String
    }

    /// A volume mounted under `/Volumes`, as far as choosing places goes.
    struct Volume: Sendable, Equatable {
        /// Its folder's name in `/Volumes`.
        let name: String
        /// On this Mac, not on a server.
        var isLocal = true
        /// Shown in Finder.
        var isBrowsable = true
        /// The startup disk.
        var isRootFileSystem = false
    }

    /// What reading a place's top level came to.
    enum Access: Sendable, Equatable, CustomStringConvertible {
        case allowed
        /// Refused by macOS's privacy settings (`EPERM`, which the sandbox never gives, since it
        /// allows reading everywhere).
        case denied
        /// Another error, with its `errno`: the place isn't there (`ENOENT`), or the folder's own
        /// permissions refuse it (`EACCES`).
        case failed(Int32)

        init(errorCode code: Int32) {
            self = code == EPERM ? .denied : .failed(code)
        }

        var description: String {
            switch self {
            case .allowed: "allowed"
            case .denied: "denied (EPERM)"
            case .failed(let code): "failed (errno \(code))"
            }
        }
    }

    /// The real home folder.
    var home = Playlist.realHomeDirectory

    /// The volumes mounted under `/Volumes`; replaced by the tests.
    var volumes: @Sendable () -> [Volume] = { Self.mountedVolumes() }

    /// Reads the top level of a folder, and returns `errno` if it fails; replaced by the tests,
    /// which must never read the real Documents folder or volumes.
    var readTopLevel: @Sendable (_ path: String) -> Int32? = Self.readTopLevel(ofFolderAt:)

    private static let log = Logger(subsystem: "com.pragmaphilia.SGFTools", category: "playlist")

    /// A read that takes longer than this, in seconds, most likely waited on macOS asking.
    static let requestThreshold: Double = 0.5

    /// The places to ask about, in order: Documents, then each volume by name.
    static func places(home: URL, volumes: [Volume]) -> [Place] {
        let documents = Place(location: .documents, path: home.standardizedFileURL.appendingPathComponent("Documents").path)
        let chosen = volumes.filter { reasonToLeaveOut($0) == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return [documents] + chosen.map { Place(location: .volume($0.name), path: "/Volumes/\($0.name)") }
    }

    /// Why a volume isn't asked about, or `nil` if it is.
    static func reasonToLeaveOut(_ volume: Volume) -> String? {
        if volume.isRootFileSystem { return "the startup disk" }
        if !volume.isLocal { return "a network volume, which Spotlight doesn't search" }
        if !volume.isBrowsable || volume.name.isEmpty || volume.name.hasPrefix(".") || volume.name.contains("/") {
            return "hidden"
        }
        return nil
    }

    /// Reads each place's top level in turn, and says what came of it. A read that macOS asks
    /// about waits for the answer, so this runs off the main thread.
    ///
    /// - Parameter asking: Called before each place is read.
    func run(asking: (Place) -> Void = { _ in }) -> [LocationClass: Access] {
        let volumes = volumes()
        let places = Self.places(home: home, volumes: volumes)
        let leftOut = volumes.compactMap { volume in
            Self.reasonToLeaveOut(volume).map { "\(LocationClass.volume(volume.name)) (\($0))" }
        }
        Self.log.notice("""
            Asking macOS for access to \(places.map(\.location.description).joined(separator: ", "), privacy: .public); \
            left out: \(leftOut.isEmpty ? "none" : leftOut.joined(separator: ", "), privacy: .public)
            """)
        var results: [LocationClass: Access] = [:]
        for place in places {
            asking(place)
            let clock = ContinuousClock()
            let start = clock.now
            let access = readTopLevel(place.path).map(Access.init(errorCode:)) ?? .allowed
            let seconds = (clock.now - start) / .seconds(1)
            results[place.location] = access
            let (name, outcome) = (place.location.description, access.description)
            if seconds < Self.requestThreshold {
                Self.log.notice("Access to \(name, privacy: .public): \(outcome, privacy: .public), at once, so macOS didn't ask")
            } else {
                Self.log.notice("""
                    Access to \(name, privacy: .public): \(outcome, privacy: .public), after \
                    \(seconds, format: .fixed(precision: 1), privacy: .public) s, so macOS most likely asked
                    """)
            }
        }
        return results
    }

    // MARK: - The system

    /// The volumes mounted under `/Volumes`, except hidden ones. Only their mount points are
    /// looked at, which macOS never asks about.
    static func mountedVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsBrowsableKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let name = GameCandidates.volumeName(of: url) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Volume(name: name, isLocal: values?.volumeIsLocal ?? true, isBrowsable: values?.volumeIsBrowsable ?? true,
                          isRootFileSystem: values?.volumeIsRootFileSystem ?? false)
        }
    }

    /// Opens a folder and reads its first entry, which is what macOS's privacy settings check,
    /// and returns `errno` if either fails.
    static func readTopLevel(ofFolderAt path: String) -> Int32? {
        guard let folder = opendir(path) else { return errno }
        defer { closedir(folder) }
        errno = 0
        return readdir(folder) == nil && errno != 0 ? errno : nil
    }
}
