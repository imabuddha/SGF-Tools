import Foundation

/// A property of a node: an identifier such as `B` or `AB`, and one or more values.
public struct SGFProperty: Sendable, Hashable {
    /// The identifier, in uppercase letters only. Lowercase letters in FF[1]-FF[3] identifiers
    /// are dropped when parsing, so `AddBlack` becomes `AB`.
    public let identifier: String

    /// The values, in file order. The parser never produces a property without values.
    public let values: [SGFValue]

    /// Creates a property.
    public init(identifier: String, values: [SGFValue]) {
        self.identifier = identifier
        self.values = values
    }

    /// The first value (or an empty value if there are none).
    public var value: SGFValue { values.first ?? SGFValue(raw: "") }
}

/// One property value, as it appears between `[` and `]`, decoded to text.
///
/// ``raw`` keeps the SGF escapes, because what they mean depends on the value's type: in a
/// composed value, `\:` is a colon that doesn't split the value. The accessors interpret it as
/// one of the FF[4] value types.
public struct SGFValue: Sendable, Hashable, CustomStringConvertible {
    /// The value's text with the SGF escapes still in it.
    public let raw: String

    /// Creates a value from its raw text, escapes included.
    public init(raw: String) {
        self.raw = raw
    }

    public var description: String { raw }

    /// The value as FF[4] Text: escapes are resolved, a soft line break (a backslash before a
    /// line break) is removed, every other line break (`\n`, `\r\n`, `\n\r`, or `\r`) becomes
    /// `\n`, and tabs, vertical tabs, and form feeds become spaces.
    public var text: String { Self.unescape(raw, keepingLineBreaks: true) }

    /// The value as FF[4] SimpleText: like ``text``, but line breaks become spaces as well.
    public var simpleText: String { Self.unescape(raw, keepingLineBreaks: false) }

    /// The two halves of a composed value such as `aa:cc` or `CGoban:3`, split at the first
    /// colon that isn't escaped, or `nil` if there is no such colon.
    public var composed: (first: SGFValue, second: SGFValue)? {
        var scalars = raw.unicodeScalars.makeIterator()
        var first = String.UnicodeScalarView()
        while let scalar = scalars.next() {
            if scalar == "\\" {
                first.append(scalar)
                if let escaped = scalars.next() { first.append(escaped) }
            } else if scalar == ":" {
                var second = String.UnicodeScalarView()
                while let rest = scalars.next() { second.append(rest) }
                return (SGFValue(raw: String(first)), SGFValue(raw: String(second)))
            } else {
                first.append(scalar)
            }
        }
        return nil
    }

    /// The value as an FF[4] Number: optional sign and digits, with surrounding whitespace
    /// allowed. `nil` for anything else.
    public var number: Int? {
        let text = trimmed
        let digits = text.first == "+" || text.first == "-" ? text.dropFirst() : text[...]
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(text.first == "+" ? String(digits) : text)
    }

    /// The value as an FF[4] Real, such as `6.5`. A decimal comma (`6,5`) is accepted too.
    /// `nil` for anything else, and for a number too large for a `Double`.
    public var real: Double? {
        var text = trimmed
        if !text.contains("."), text.filter({ $0 == "," }).count == 1 {
            text = text.replacingOccurrences(of: ",", with: ".")
        }
        var body = text[...]
        if body.first == "+" || body.first == "-" { body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count),
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              parts.contains(where: { !$0.isEmpty }),
              let value = Double(text.first == "+" ? String(text.dropFirst()) : text),
              value.isFinite
        else { return nil }
        return value
    }

    /// The value as a single point, such as `pd`, or `nil` if it isn't two SGF letters.
    public var point: SGFPoint? { SGFPoint(sgf: raw) }

    /// The value as a point or a compressed rectangle of points (`aa:cc`, with the corners in
    /// either order). Empty if the value is neither.
    public var points: [SGFPoint] {
        if let point { return [point] }
        guard let parts = composed, let corner1 = parts.first.point, let corner2 = parts.second.point else {
            return []
        }
        var result: [SGFPoint] = []
        for column in min(corner1.column, corner2.column) ... max(corner1.column, corner2.column) {
            for row in min(corner1.row, corner2.row) ... max(corner1.row, corner2.row) {
                result.append(SGFPoint(column: column, row: row))
            }
        }
        return result
    }

    // MARK: - Private

    private var trimmed: String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r"
    }

    /// Tab, vertical tab, and form feed, which FF[4] Text turns into spaces. Other Unicode
    /// spaces, such as the ideographic space, are text and are kept.
    private static func isOtherWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\t" || scalar == "\u{0B}" || scalar == "\u{0C}"
    }

    /// Resolves escapes and line breaks as described for ``text`` and ``simpleText``.
    private static func unescape(_ raw: String, keepingLineBreaks: Bool) -> String {
        // Most values have nothing to change.
        guard raw.utf8.contains(where: { $0 == 0x5C || (0x09 ... 0x0D).contains($0) }) else { return raw }
        let scalars = Array(raw.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0

        /// Skips the line break starting at `index`: one of `\n`, `\r`, `\r\n`, or `\n\r`.
        func skipLineBreak() {
            let first = scalars[index]
            index += 1
            if index < scalars.count, isLineBreak(scalars[index]), scalars[index] != first {
                index += 1
            }
        }

        while index < scalars.count {
            var scalar = scalars[index]
            if scalar == "\\" {
                index += 1
                guard index < scalars.count else { break }  // a lone trailing backslash
                if isLineBreak(scalars[index]) {
                    skipLineBreak()  // a soft line break
                    continue
                }
                scalar = scalars[index]
            } else if isLineBreak(scalar) {
                skipLineBreak()
                result.append(keepingLineBreaks ? "\n" : " ")
                continue
            }
            result.append(isOtherWhitespace(scalar) ? " " : scalar)
            index += 1
        }
        return String(result)
    }
}

extension Character {
    /// Whether this is one of the ASCII digits 0-9, the only digits of SGF's numbers, sizes,
    /// and dates.
    var isASCIIDigit: Bool { ("0" ... "9").contains(self) }
}
