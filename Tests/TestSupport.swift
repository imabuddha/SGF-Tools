import Foundation
import SGFKit
import Testing

/// Parses SGF text.
func collection(_ sgf: String, stopAfterFirstGame: Bool = false) -> SGFCollection {
    SGFParser.parse(Data(sgf.utf8), options: .init(stopAfterFirstGame: stopAfterFirstGame))
}

/// The first game of SGF text.
func game(_ sgf: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> SGFGame {
    try #require(collection(sgf).games.first, sourceLocation: sourceLocation)
}

/// A game on a board of a size with `count` moves and no captures: Black fills the even rows
/// from the top and White the odd ones, each leaving the last column empty, so every row keeps
/// a liberty.
func longGame(size: Int, moves count: Int, passAt passes: Set<Int> = []) -> String {
    var sgf = "(;GM[1]FF[4]SZ[\(size)]"
    let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var blackIndex = 0
    var whiteIndex = 0
    for number in stride(from: 1, through: count, by: 1) {
        let isBlack = number % 2 == 1
        if passes.contains(number) {
            sgf += isBlack ? ";B[]" : ";W[]"
            continue
        }
        let index = isBlack ? blackIndex : whiteIndex
        let perRow = size - 1
        let row = (index / perRow) * 2 + (isBlack ? 0 : 1)
        let point = "\(letters[index % perRow])\(letters[row])"
        sgf += isBlack ? ";B[\(point)]" : ";W[\(point)]"
        if isBlack { blackIndex += 1 } else { whiteIndex += 1 }
    }
    return sgf + ")"
}

/// Synthetic files. None are real games, and none contain anyone else's commentary.
enum Fixtures {
    /// A made-up 19x19 game with every field the preview shows.
    static let fullInfo = """
        (;GM[1]FF[4]CA[UTF-8]SZ[19]KM[6.5]HA[0]RU[Japanese]GN[Fixture game]
        PB[Black Tester]BR[3d]PW[White Tester]WR[4d]BT[Team Kuro]WT[Team Shiro]
        EV[Fixture Cup]RO[2]DT[2024-03-17]PC[Nowhere]RE[W+2.5]
        GC[A game made up for tests.\nIt has two lines.]
        ;B[pd];W[dp];B[pp];W[dd];B[fq];W[cn])
        """

    /// John Mifsud's 3-stone handicap game against GNU Go, from the SGF Tools 1.x test files.
    static func johnVsGnu() throws -> URL {
        try #require(Bundle(for: BundleToken.self).url(forResource: "johnVsGnu", withExtension: "sgf"))
    }
}

private final class BundleToken {}
