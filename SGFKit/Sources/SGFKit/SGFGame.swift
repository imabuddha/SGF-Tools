import Foundation

/// One game record: a tree of nodes, from one top-level game tree of an SGF file.
///
/// The nodes are kept in a flat array in file order, so a game of any length or depth can be
/// read, walked, and freed without recursion. The main line is the first child at every branch.
public struct SGFGame: Sendable {
    /// All nodes in file order. The root is first, and a node's ``SGFNode/id`` is its index here.
    public let nodes: [SGFNode]

    /// The text encoding the values were decoded with.
    public let encoding: String.Encoding

    /// The board size from the root's SZ property; 19x19 if it is missing or invalid.
    public let boardSize: BoardSize

    /// Creates a game from its nodes, which must be in file order with valid parent and child
    /// IDs. The board size is read from the root's SZ property.
    public init(nodes: [SGFNode], encoding: String.Encoding = .utf8) {
        precondition(!nodes.isEmpty, "A game needs at least a root node.")
        self.nodes = nodes
        self.encoding = encoding
        boardSize = nodes[0]["SZ"].flatMap { BoardSize(sgf: $0.value.simpleText) } ?? .standard
    }

    /// The root node, which holds the game information and any handicap stones.
    public var root: SGFNode { nodes[0] }

    /// The node with an ID.
    public subscript(id: SGFNode.ID) -> SGFNode { nodes[id] }

    /// The children of a node; the first one continues the main line.
    public func children(of node: SGFNode) -> [SGFNode] {
        node.childIDs.map { nodes[$0] }
    }

    /// The parent of a node, or `nil` for the root.
    public func parent(of node: SGFNode) -> SGFNode? {
        node.parentID.map { nodes[$0] }
    }

    /// The main line: the root, its first child, that node's first child, and so on.
    public var mainLine: [SGFNode] { Array(mainLineNodes) }

    /// The moves of the main line, in order, passes included.
    public var mainLineMoves: [Move] {
        mainLineNodes.compactMap { $0.move(on: boardSize) }
    }

    /// The number of moves on the main line, passes included.
    public var mainLineMoveCount: Int {
        mainLineNodes.count { $0.move(on: boardSize) != nil }
    }

    /// The nodes of ``mainLine``, one at a time.
    private var mainLineNodes: UnfoldFirstSequence<SGFNode> {
        sequence(first: nodes[0]) { [nodes] node in node.childIDs.first.map { nodes[$0] } }
    }

    /// The position after the first `moveCount` moves of the main line.
    ///
    /// Moves are counted as SGF numbers them: every B or W node counts, passes included. The
    /// position includes the setup (AB, AW, and AE) of every main-line node up to the node of
    /// the last counted move, and nothing from variations or later nodes. With `0`, it is the
    /// position before the first move: handicap and other setup stones. A count past the end of
    /// the main line gives the final position.
    public func position(afterMainLineMoves moveCount: Int) -> Board {
        var board = Board(size: boardSize)
        let target = max(0, moveCount)
        var played = 0
        for node in mainLineNodes {
            let move = node.move(on: boardSize)
            if move != nil, played == target { break }
            for point in node.points("AB") { board.place(.black, at: point) }
            for point in node.points("AW") { board.place(.white, at: point) }
            for point in node.points("AE") { board.place(nil, at: point) }
            if let move {
                if let point = move.point { board.play(move.color, at: point) }
                played += 1
                if played == target { break }
            }
        }
        return board
    }
}

/// A node of a game tree: its properties and its place in the tree.
public struct SGFNode: Sendable, Hashable, Identifiable {
    /// The node's index in ``SGFGame/nodes``.
    public let id: Int

    /// The ID of the parent node, or `nil` for the root.
    public let parentID: Int?

    /// The IDs of the child nodes. The first child continues the main line; the others start
    /// variations.
    public let childIDs: [Int]

    /// The properties, in file order, each identifier at most once.
    public let properties: [SGFProperty]

    /// Creates a node.
    public init(id: Int, parentID: Int?, childIDs: [Int], properties: [SGFProperty]) {
        self.id = id
        self.parentID = parentID
        self.childIDs = childIDs
        self.properties = properties
    }

    /// The property with an identifier, such as `"B"` or `"AB"`, if the node has it.
    public subscript(identifier: String) -> SGFProperty? {
        properties.first { $0.identifier == identifier }
    }

    /// All points in a property's values, with compressed lists (`aa:cc`) expanded. Empty if
    /// the node doesn't have the property.
    public func points(_ identifier: String) -> [SGFPoint] {
        self[identifier]?.values.flatMap(\.points) ?? []
    }

    /// The node's move, or `nil` if it has neither B nor W (B wins if it has both).
    ///
    /// An empty value is a pass, and so is any value that isn't a point on the board. That
    /// includes `tt`, the FF[3] pass, on boards up to 19x19; on larger boards `tt` is a move.
    public func move(on size: BoardSize) -> Move? {
        let color: StoneColor
        let property: SGFProperty
        if let black = self["B"] {
            (color, property) = (.black, black)
        } else if let white = self["W"] {
            (color, property) = (.white, white)
        } else {
            return nil
        }
        guard let point = property.value.point, size.contains(point) else {
            return Move(color: color, point: nil)
        }
        return Move(color: color, point: point)
    }
}
