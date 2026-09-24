import CoreFoundation
import Foundation

/// How the values of one game are decoded, chosen from its CA property.
struct Charset {
    enum Kind {
        /// No CA, or CA says UTF-8: UTF-8 if the text is valid UTF-8, Windows-1252 otherwise.
        case utf8
        /// CA names Latin-1, Windows-1252, or ASCII: Windows-1252, a superset of the printable
        /// Latin-1 characters, unless the text is valid UTF-8 with non-ASCII characters in it.
        case western
        /// Any other charset Core Foundation knows.
        case other(String.Encoding)
    }

    let kind: Kind

    /// The CA value as written (trimmed), or `nil` if the game has none.
    let declaredName: String?

    /// For multibyte charsets whose second byte can be `\` or `]` (Shift_JIS, GBK, GB18030,
    /// Big5): which bytes start a two-byte character. The parser must skip the byte after one of
    /// these inside a value. `nil` for charsets where every byte of a multibyte character is
    /// above 0x7F.
    let leadBytes: [Bool]?

    /// Whether the CA value named a charset nobody knows.
    let isUnknown: Bool

    /// The charset for UTF-8 input with no declared charset.
    static let utf8 = Charset(kind: .utf8, declaredName: nil, leadBytes: nil, isUnknown: false)

    /// Resolves a CA value.
    init(declared name: String?) {
        guard let name, !name.isEmpty else {
            self = .utf8
            return
        }
        let key = name.lowercased().filter { !$0.isWhitespace }
        switch key {
        case "utf-8", "utf8":
            self.init(kind: .utf8, declaredName: name, leadBytes: nil, isUnknown: false)
            return
        case "iso-8859-1", "iso8859-1", "iso_8859-1", "iso-latin-1", "latin1", "latin-1", "l1",
             "cp1252", "windows-1252", "us-ascii", "ascii", "iso646-us":
            self.init(kind: .western, declaredName: name, leadBytes: nil, isUnknown: false)
            return
        default:
            break
        }
        var cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cfEncoding == kCFStringEncodingInvalidId {
            self.init(kind: .utf8, declaredName: name, leadBytes: nil, isUnknown: true)
            return
        }
        cfEncoding = Self.superset(of: cfEncoding)
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        switch encoding {
        case .utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian:
            // A file parsed byte by byte can't be in UTF-16 or UTF-32, whatever it says. (Real
            // UTF-16 files are converted to UTF-8 before parsing.)
            self.init(kind: .utf8, declaredName: name, leadBytes: nil, isUnknown: false)
        case .isoLatin1, .windowsCP1252, .ascii:
            self.init(kind: .western, declaredName: name, leadBytes: nil, isUnknown: false)
        default:
            self.init(kind: .other(encoding), declaredName: name, leadBytes: Self.leadBytes(for: cfEncoding),
                      isUnknown: false)
        }
    }

    private init(kind: Kind, declaredName: String?, leadBytes: [Bool]?, isUnknown: Bool) {
        self.kind = kind
        self.declaredName = declaredName
        self.leadBytes = leadBytes
        self.isUnknown = isUnknown
    }

    /// The Windows superset of a charset, as web browsers use it: files labeled Shift_JIS,
    /// GB2312, or EUC-KR are often written by Windows programs that use the extended versions.
    private static func superset(of encoding: CFStringEncoding) -> CFStringEncoding {
        switch encoding {
        case CFStringEncoding(CFStringEncodings.shiftJIS.rawValue):
            CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
        case CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue),
             CFStringEncoding(CFStringEncodings.EUC_CN.rawValue),
             CFStringEncoding(CFStringEncodings.GBK_95.rawValue),
             CFStringEncoding(CFStringEncodings.dosChineseSimplif.rawValue):
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        case CFStringEncoding(CFStringEncodings.EUC_KR.rawValue):
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
        default:
            encoding
        }
    }

    /// The lead bytes of the multibyte charsets whose trail bytes include `\` and `]`.
    private static func leadBytes(for encoding: CFStringEncoding) -> [Bool]? {
        let shiftJIS: [CFStringEncodings] = [.dosJapanese, .shiftJIS, .shiftJIS_X0213, .macJapanese]
        let doubleByte: [CFStringEncodings] = [
            .GB_18030_2000, .GBK_95, .dosChineseSimplif, .big5, .big5_HKSCS_1999, .big5_E,
            .dosChineseTrad, .macChineseTrad, .dosKorean,
        ]
        var table = Array(repeating: false, count: 256)
        if shiftJIS.contains(where: { CFStringEncoding($0.rawValue) == encoding }) {
            for byte in 0x81 ... 0x9F { table[byte] = true }
            for byte in 0xE0 ... 0xFC { table[byte] = true }
            return table
        }
        if doubleByte.contains(where: { CFStringEncoding($0.rawValue) == encoding }) {
            for byte in 0x81 ... 0xFE { table[byte] = true }
            return table
        }
        return nil
    }
}

/// Decoding of byte ranges to strings.
enum TextDecoding {
    /// Decodes bytes as UTF-8, or returns `nil` if they aren't valid UTF-8.
    static func utf8(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> String? {
        String(validating: bytes, as: UTF8.self)
    }

    /// Decodes bytes as Windows-1252. The five bytes Windows-1252 leaves undefined become the
    /// Latin-1 control characters with the same numbers, so decoding never fails.
    static func windows1252(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> String {
        if bytes.allSatisfy({ $0 < 0x80 }) {
            return String(decoding: bytes, as: UTF8.self)
        }
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(bytes.count)
        for byte in bytes {
            if (0x80 ... 0x9F).contains(byte) {
                scalars.append(Unicode.Scalar(windows1252High[Int(byte) - 0x80])!)
            } else {
                scalars.append(Unicode.Scalar(byte))
            }
        }
        return String(scalars)
    }

    /// Decodes bytes with a Foundation encoding, or returns `nil` if they aren't valid in it.
    static func decode(_ bytes: Slice<UnsafeBufferPointer<UInt8>>, as encoding: String.Encoding) -> String? {
        if bytes.allSatisfy({ $0 < 0x80 }) {
            return String(decoding: bytes, as: UTF8.self)
        }
        return String(bytes: bytes, encoding: encoding)
    }

    /// Windows-1252 characters for bytes 0x80-0x9F.
    private static let windows1252High: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    ]
}
