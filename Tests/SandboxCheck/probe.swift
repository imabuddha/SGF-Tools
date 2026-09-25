// The sandbox check's probe (see check.sh): one small command-line tool that check.sh builds
// twice, signed once with the screensaver host's file entitlements and once with the app's, to
// see what each may do with the playlist's folder and with Spotlight. It never opens an SGF file,
// so it can't raise a permission request.
//
//     probe write <path>    creates the file's folder if needed, and writes the file
//     probe read <path>     reads the file and prints its contents
//     probe remove <path>   removes the file
//     probe count           counts, with Spotlight, the SGF files that are games for the screensaver
//
// Each prints one line, "ok …" or "refused …", and exits 0 or 1.

import CoreServices
import Foundation

/// The query of Shared/GameCandidates.swift.
let query = """
    kMDItemContentType == "com.red-bean.sgf" && com_breedingpinetrees_sgf_black == "*" && \
    com_breedingpinetrees_sgf_white == "*" && com_breedingpinetrees_sgf_moves >= 20
    """

func finish(_ ok: Bool, _ message: String) -> Never {
    print("\(ok ? "ok" : "refused") \(message)")
    exit(ok ? 0 : 1)
}

func describe(_ error: any Error) -> String {
    let error = error as NSError
    let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { " (\($0.domain) \($0.code))" } ?? ""
    return "\(error.domain) \(error.code)\(underlying)"
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { finish(false, "usage: probe write|read|remove <path>, or probe count") }
switch (arguments[1], arguments.count > 2 ? URL(fileURLWithPath: arguments[2]) : nil) {
case ("write", let url?):
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("SGF Tools sandbox check\n".utf8).write(to: url, options: .atomic)
        finish(true, "wrote \(url.lastPathComponent)")
    } catch {
        finish(false, "writing: \(describe(error))")
    }
case ("read", let url?):
    do {
        let text = try String(contentsOf: url, encoding: .utf8)
        finish(true, "read \(text.utf8.count) bytes")
    } catch {
        finish(false, "reading: \(describe(error))")
    }
case ("remove", let url?):
    do {
        try FileManager.default.removeItem(at: url)
        finish(true, "removed \(url.lastPathComponent)")
    } catch {
        finish(false, "removing: \(describe(error))")
    }
case ("count", nil):
    guard let spotlight = MDQueryCreate(kCFAllocatorDefault, query as CFString, nil, nil) else {
        finish(false, "the query couldn't be created")
    }
    MDQuerySetSearchScope(spotlight, [kMDQueryScopeComputer] as CFArray, 0)
    guard MDQueryExecute(spotlight, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { finish(false, "the query failed") }
    finish(true, "\(MDQueryGetResultCount(spotlight)) games")
default:
    finish(false, "usage: probe write|read|remove <path>, or probe count")
}
