/// The color of a stone or a player.
public enum StoneColor: Sendable, Hashable, CaseIterable {
    case black
    case white

    /// The other color.
    var opponent: StoneColor {
        switch self {
        case .black: .white
        case .white: .black
        }
    }
}

/// A move: a stone of one color played at a point, or a pass.
public struct Move: Sendable, Hashable {
    /// The color of the player who moved.
    public let color: StoneColor

    /// Where the stone was played, or `nil` for a pass.
    public let point: SGFPoint?

    /// Creates a move; a `nil` point is a pass.
    init(color: StoneColor, point: SGFPoint?) {
        self.color = color
        self.point = point
    }

    /// Whether the move is a pass.
    var isPass: Bool { point == nil }
}

/// A Go board: the stones on it and the number captured so far.
///
/// ``play(_:at:)`` follows the rules of Go for captures and suicide but doesn't enforce ko or
/// forbid anything: an SGF file is a record of what was played, so the board replays it as
/// written. ``place(_:at:)`` applies the setup properties AB, AW, and AE, which never capture.
public struct Board: Sendable, Hashable {
    /// The size of the board.
    public let size: BoardSize

    /// One cell per point, row by row: 0 is empty, 1 is black, 2 is white.
    private var cells: [UInt8]

    /// The number of black stones removed from the board, by capture or by suicide.
    public private(set) var capturedBlackStones = 0

    /// The number of white stones removed from the board, by capture or by suicide.
    public private(set) var capturedWhiteStones = 0

    /// Creates an empty board.
    public init(size: BoardSize) {
        self.size = size
        cells = Array(repeating: 0, count: size.columns * size.rows)
    }

    /// The stone at a point, or `nil` if the point is empty or not on the board.
    public subscript(point: SGFPoint) -> StoneColor? {
        guard let index = index(of: point) else { return nil }
        return Self.color(ofCell: cells[index])
    }

    /// Puts a stone on a point, or empties it when `color` is `nil`, without any captures.
    /// Points off the board are ignored.
    public mutating func place(_ color: StoneColor?, at point: SGFPoint) {
        guard let index = index(of: point) else { return }
        cells[index] = Self.cell(for: color)
    }

    /// Plays a stone, removing any opponent groups left without liberties, and then the
    /// player's own group if it has none (suicide).
    ///
    /// A stone already on the point is replaced. Points off the board are ignored.
    ///
    /// - Returns: The points of the stones removed from the board: the captured opponent stones,
    ///   or the player's own group after a suicide.
    @discardableResult
    public mutating func play(_ color: StoneColor, at point: SGFPoint) -> [SGFPoint] {
        guard let index = index(of: point) else { return [] }
        cells[index] = Self.cell(for: color)
        let opponentCell = Self.cell(for: color.opponent)
        var removed: [Int] = []
        for neighbor in neighbors(of: index) where cells[neighbor] == opponentCell {
            if let group = groupWithoutLiberties(containing: neighbor) {
                removed += group
                for member in group { cells[member] = 0 }
            }
        }
        if removed.isEmpty {
            if let group = groupWithoutLiberties(containing: index) {
                removed = group
                for member in group { cells[member] = 0 }
                count(removed: group.count, of: color)
            }
        } else {
            count(removed: removed.count, of: color.opponent)
        }
        return removed.map(point(at:))
    }

    /// The points holding stones of one color, column by column and then row by row.
    public func stones(of color: StoneColor) -> [SGFPoint] {
        let wanted = Self.cell(for: color)
        var points: [SGFPoint] = []
        for column in 1 ... size.columns {
            for row in 1 ... size.rows where cells[(row - 1) * size.columns + column - 1] == wanted {
                points.append(SGFPoint(column: column, row: row))
            }
        }
        return points
    }

    /// The position in the compact form SGF Tools 1.x stored in Spotlight:
    /// `"size,<black points>,<white points>"`, each point as two SGF letters, listed column by
    /// column. For example, `"19,pdpp,dddp"`. A rectangular board's size is written as in SZ,
    /// such as `"19:13"`.
    var compactPosition: String {
        let black = stones(of: .black).map(\.sgf).joined()
        let white = stones(of: .white).map(\.sgf).joined()
        return "\(size.sgf),\(black),\(white)"
    }

    // MARK: - Private

    private mutating func count(removed: Int, of color: StoneColor) {
        switch color {
        case .black: capturedBlackStones += removed
        case .white: capturedWhiteStones += removed
        }
    }

    private func index(of point: SGFPoint) -> Int? {
        guard size.contains(point) else { return nil }
        return (point.row - 1) * size.columns + point.column - 1
    }

    private func point(at index: Int) -> SGFPoint {
        SGFPoint(column: index % size.columns + 1, row: index / size.columns + 1)
    }

    private func neighbors(of index: Int) -> [Int] {
        let column = index % size.columns
        let row = index / size.columns
        var result: [Int] = []
        result.reserveCapacity(4)
        if column > 0 { result.append(index - 1) }
        if column < size.columns - 1 { result.append(index + 1) }
        if row > 0 { result.append(index - size.columns) }
        if row < size.rows - 1 { result.append(index + size.columns) }
        return result
    }

    /// The group containing a stone, or `nil` if the group has a liberty. Uses an explicit stack,
    /// so a group of any size is safe.
    private func groupWithoutLiberties(containing start: Int) -> [Int]? {
        let color = cells[start]
        guard color != 0 else { return nil }
        var visited = Array(repeating: false, count: cells.count)
        var group: [Int] = []
        var pending = [start]
        visited[start] = true
        while let index = pending.popLast() {
            group.append(index)
            for neighbor in neighbors(of: index) where !visited[neighbor] {
                switch cells[neighbor] {
                case 0:
                    return nil
                case color:
                    visited[neighbor] = true
                    pending.append(neighbor)
                default:
                    break
                }
            }
        }
        return group
    }

    private static func cell(for color: StoneColor?) -> UInt8 {
        switch color {
        case .black: 1
        case .white: 2
        case nil: 0
        }
    }

    private static func color(ofCell cell: UInt8) -> StoneColor? {
        switch cell {
        case 1: .black
        case 2: .white
        default: nil
        }
    }
}
