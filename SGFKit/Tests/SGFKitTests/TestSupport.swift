import Foundation
import Testing
@testable import SGFKit

/// Parses SGF source text given as a Swift string (encoded as UTF-8).
func parse(_ text: String, options: SGFParser.Options = .init()) -> SGFCollection {
    SGFParser.parse(Data(text.utf8), options: options)
}

/// Parses raw bytes, for fixtures that need exact control over the encoding.
func parse(bytes: [UInt8], options: SGFParser.Options = .init()) -> SGFCollection {
    SGFParser.parse(Data(bytes), options: options)
}

/// Parses SGF source text and returns its first game, failing the test if there is none.
func firstGame(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> SGFGame {
    try #require(parse(text).games.first, sourceLocation: sourceLocation)
}

/// Parses raw bytes and returns the first game, failing the test if there is none.
func firstGame(bytes: [UInt8], sourceLocation: SourceLocation = #_sourceLocation) throws -> SGFGame {
    try #require(parse(bytes: bytes).games.first, sourceLocation: sourceLocation)
}

/// The UTF-8 bytes of a string, for building byte-level fixtures.
func ascii(_ text: String) -> [UInt8] {
    Array(text.utf8)
}

/// A point from its SGF letters, failing the test if they are not a valid point.
func pt(_ sgf: String, sourceLocation: SourceLocation = #_sourceLocation) -> SGFPoint {
    guard let point = SGFPoint(sgf: sgf) else {
        Issue.record("Invalid SGF point \(sgf)", sourceLocation: sourceLocation)
        return SGFPoint(column: 1, row: 1)
    }
    return point
}

/// Synthetic fixtures. None of these are real games, and none contain anyone else's commentary.
enum Fixtures {
    /// A made-up 19x19 game of 24 moves between two made-up players. It includes a capture
    /// (Black takes White's R14 stone with move 23), comments, a node name, and one short
    /// variation at move 20.
    static let game19 = """
        (;GM[1]FF[4]CA[UTF-8]AP[FixtureWriter:1.0]SZ[19]KM[6.5]RU[Japanese]
        PB[Black Tester]BR[3d]PW[White Tester]WR[4d]BT[Team Kuro]WT[Team Shiro]
        EV[Fixture Cup]RO[2]DT[2024-03-17]PC[Nowhere]RE[W+2.5]TM[3600]OT[5x30 byo-yomi]
        ON[Nirensei]SO[Invented]AN[Nobody]US[Tester]CP[Public domain]GN[Fixture game]
        GC[A game made up for tests.]
        ;B[pd];W[dp];B[pp];W[dd]C[Both sides take corners.]
        ;B[fq];W[cn];B[jp];W[qf]N[Approach]
        ;B[nc];W[rd];B[qc];W[qi]
        ;B[qk];W[ok];B[qn];W[ic]
        ;B[qe];W[re];B[rf]
        (;W[rg];B[qg];W[dj];B[pf];W[jd])
        (;W[pf]C[A variation.]))
        """

    /// A two-stone handicap game.
    static let handicap = """
        (;GM[1]FF[4]SZ[19]HA[2]KM[0.5]PB[Black]PW[White]RE[B+R]AB[pd][dp]
        ;W[dd];B[pp];W[qf])
        """

    /// The classic top-left snapback on a 5x5 board: Black throws in at A5, White takes it at
    /// B5, and Black retakes at A5, capturing three stones.
    static let snapback = """
        (;GM[1]FF[4]SZ[5]AB[ac][bc][cb][ca]AW[ab][bb]
        ;B[aa];W[ba];B[aa])
        """

    /// A ko on a 5x5 board: White takes, both sides play elsewhere, and Black retakes.
    static let ko = """
        (;GM[1]FF[4]SZ[5]AB[ba][ab][cb][bc]AW[ca][db][cc]
        ;W[bb];B[ee];W[ed];B[cb])
        """

    /// A collection of three games on different board sizes.
    static let collection = """
        (;GM[1]FF[4]SZ[9]PB[First Black]PW[First White]C[one];B[ee]C[two];W[cc])
        (;GM[1]FF[4]SZ[13]PB[Second Black]N[three];B[gg])
        (;GM[1]FF[4]SZ[19]PB[Third Black];B[pd];W[dd];B[pp])
        """

    /// A game with variations. The main line is B E5, W C7, B G3, and the second variation adds
    /// setup stones that must never reach a main-line position.
    static let variations = """
        (;GM[1]FF[4]SZ[9]
        ;B[ee]
        (;W[cc];B[gg])
        (;W[gc]AB[aa][ab];B[cg])
        (;W[cg]))
        """

    /// An FF[3] file with long property names, whose lowercase letters must be ignored.
    static let ff3 = """
        (;GaMe[1]FileFormat[3]SiZe[9]PlayerBlack[Old Black]PlayerWhite[Old White]
        AddBlack[cc][gg];White[ee];Black[tt];White[ge])
        """
}
