import CoreServices
import Foundation

/// Where an SGF file is, as far as macOS's privacy settings go. The app tallies what it reads by
/// location, and the screensaver's direct mode stops reading from a location that refuses it.
enum LocationClass: Hashable, Sendable, Comparable, CustomStringConvertible {
    case documents
    case desktop
    case downloads
    /// The rest of the home folder.
    case home
    /// The rest of the startup disk.
    case startupDisk
    /// A volume under `/Volumes`, by name.
    case volume(String)

    var description: String {
        switch self {
        case .documents: "Documents"
        case .desktop: "Desktop"
        case .downloads: "Downloads"
        case .home: "the home folder"
        case .startupDisk: "the startup disk"
        case .volume(let name): "the volume \(name)"
        }
    }

    /// The setting in System Settings > Privacy & Security that lets a process read files here.
    var permission: String {
        switch self {
        case .documents: "Files & Folders: Documents Folder"
        case .desktop: "Files & Folders: Desktop Folder"
        case .downloads: "Files & Folders: Downloads Folder"
        case .home, .startupDisk: "Full Disk Access"
        case .volume: "Files & Folders: Removable Volumes or Network Volumes"
        }
    }
}

/// The SGF files that Spotlight says are games for the screensaver, less the places they must
/// never be read from, each with its location (see `docs/screensaver.md`, 1.7).
struct GameCandidates: Sendable {
    /// Spotlight's query for files that name both players and have at least 20 main-line
    /// moves, from the attributes SGF Tools' importer sets. The screensaver checks each game
    /// again when it reads it.
    static let query = """
        kMDItemContentType == "com.red-bean.sgf" && com_breedingpinetrees_sgf_black == "*" && \
        com_breedingpinetrees_sgf_white == "*" && com_breedingpinetrees_sgf_moves >= \(Playlist.minimumMoves)
        """

    /// Why a path is left out.
    enum Exclusion: String, CaseIterable, Sendable, Comparable {
        /// Under `~/Library`: other apps' containers, where a read asks about "data from other
        /// apps", and iCloud Drive, where it would download the file.
        case library = "~/Library"
        /// In the Trash: `~/.Trash`, or a volume's `.Trashes`.
        case trash = "Trash"
        /// Spotlight's own store on a volume.
        case spotlightStore = ".Spotlight-V100"
        /// The document versions macOS keeps on a volume.
        case documentRevisions = ".DocumentRevisions-V100"

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One file that may be read.
    struct Candidate: Sendable, Hashable {
        let path: String
        let location: LocationClass
    }

    /// The number of paths Spotlight returned.
    let found: Int

    /// The paths that may be read, in Spotlight's order.
    let candidates: [Candidate]

    /// The number of paths left out, by reason.
    let excluded: [Exclusion: Int]

    /// Sorts Spotlight's paths into candidates and exclusions.
    ///
    /// - Parameter home: The real home folder (see ``Playlist/realHomeDirectory``).
    init(paths: [String], home: URL = Playlist.realHomeDirectory) {
        let home = home.standardizedFileURL.path
        var candidates: [Candidate] = []
        candidates.reserveCapacity(paths.count)
        var excluded: [Exclusion: Int] = [:]
        for path in paths {
            if let reason = Self.exclusion(of: path, home: home) {
                excluded[reason, default: 0] += 1
            } else {
                candidates.append(Candidate(path: path, location: Self.location(of: path, home: home)))
            }
        }
        found = paths.count
        self.candidates = candidates
        self.excluded = excluded
    }

    /// The number of candidates in each location.
    var countsByLocation: [LocationClass: Int] {
        candidates.reduce(into: [:]) { counts, candidate in counts[candidate.location, default: 0] += 1 }
    }

    /// Why a path must never be read, or `nil` if it may be.
    static func exclusion(of path: String, home: String) -> Exclusion? {
        if path.hasPrefix(home + "/Library/") { return .library }
        if path.hasPrefix(home + "/.Trash/") { return .trash }
        let components = path.split(separator: "/")
        if components.contains(".Trashes") { return .trash }
        if components.contains(".Spotlight-V100") { return .spotlightStore }
        if components.contains(".DocumentRevisions-V100") { return .documentRevisions }
        return nil
    }

    /// The location of a path.
    static func location(of path: String, home: String) -> LocationClass {
        for (folder, location) in [("Documents", LocationClass.documents), ("Desktop", .desktop), ("Downloads", .downloads)]
        where path.hasPrefix("\(home)/\(folder)/") {
            return location
        }
        if path.hasPrefix(home + "/") { return .home }
        if path.hasPrefix("/Volumes/") {
            let name = path.dropFirst("/Volumes/".count).prefix { $0 != "/" }
            if !name.isEmpty { return .volume(String(name)) }
        }
        return .startupDisk
    }

    /// The volumes mounted under `/Volumes`, for logging a count for each, even when it is 0.
    static func mountedVolumes() -> [LocationClass] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("/Volumes/") else { return nil }
            return .volume(String(path.dropFirst("/Volumes/".count)))
        }
    }

    // MARK: - Spotlight

    /// Why Spotlight couldn't answer.
    enum QueryError: Error, CustomStringConvertible {
        case couldNotCreate
        case couldNotRun

        var description: String {
            switch self {
            case .couldNotCreate: "the query couldn't be created"
            case .couldNotRun: "the query failed"
            }
        }
    }

    /// Asks Spotlight, on the whole computer, for the paths of the files that match ``query``.
    /// It runs synchronously, so callers call it off the main thread; on the test Mac, 64,020
    /// paths took 0.9 seconds.
    static func spotlightPaths() throws(QueryError) -> [String] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, Self.query as CFString, nil, nil) else {
            throw .couldNotCreate
        }
        MDQuerySetSearchScope(query, [kMDQueryScopeComputer] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { throw .couldNotRun }
        let count = MDQueryGetResultCount(query)
        var paths: [String] = []
        paths.reserveCapacity(count)
        // Each result's own path. (MDQueryGetAttributeValueOfResultAtIndex gives no paths, even
        // with kMDItemPath among the query's value attributes.)
        for index in 0 ..< count {
            guard let result = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(result).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { paths.append(path) }
        }
        return paths
    }
}
