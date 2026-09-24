/// How the board and stones look.
///
/// Two styles are built in and drawn entirely in code: ``shaded`` and ``flat``. The type is a
/// struct rather than an enum so that more kinds of style can be added later, such as sets of
/// board and stone images, without changing code that picks or stores a style.
public struct BoardStyle: Sendable, Hashable, CustomStringConvertible {
    /// A warm wood board with a subtle grain, and stones with a soft highlight and a small drop
    /// shadow. White stones are slightly off-white at the rim, so they read against the board.
    public static let shaded = BoardStyle(look: .shaded)

    /// A crisp look like a printed diagram: a plain light board, solid black stones, and white
    /// stones with a black outline.
    public static let flat = BoardStyle(look: .flat)

    /// The styles drawn in code, in the order to offer them.
    public static let builtIn: [BoardStyle] = [.shaded, .flat]

    /// A stable name for storing the choice, such as in settings: `"shaded"` or `"flat"`.
    public var identifier: String {
        switch look {
        case .shaded: "shaded"
        case .flat: "flat"
        }
    }

    /// The built-in style with an identifier, or `nil` if there is none.
    public init?(identifier: String) {
        guard let style = Self.builtIn.first(where: { $0.identifier == identifier }) else { return nil }
        self = style
    }

    public var description: String { identifier }

    /// What the renderer draws. Internal, so that new kinds can be added without breaking
    /// callers.
    enum Look: Sendable, Hashable {
        case shaded
        case flat
    }

    let look: Look

    private init(look: Look) {
        self.look = look
    }
}
