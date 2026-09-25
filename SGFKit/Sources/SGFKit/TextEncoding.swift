import CoreFoundation
import Foundation

/// How the values of one game are decoded, chosen from its CA property.
struct Charset {
    enum Kind {
        /// No CA, or CA says UTF-8 or names an unknown charset: UTF-8 if the text is valid
        /// UTF-8. If it isn't, the charset is detected; see ``CharsetDetection``.
        case utf8
        /// The charset ``CharsetDetection`` found for text that should have been UTF-8 but
        /// wasn't.
        case detected(String.Encoding)
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

    /// The charset detected for a game whose text isn't valid UTF-8, keeping what the game
    /// declared (UTF-8, an unknown charset, or nothing).
    init(detected encoding: String.Encoding, replacing declared: Charset) {
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
        self.init(kind: .detected(encoding), declaredName: declared.declaredName,
                  leadBytes: Self.leadBytes(for: cfEncoding), isUnknown: declared.isUnknown)
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

/// Guessing the charset of a game's text when it should be UTF-8 but isn't.
///
/// Files with no CA property, or with a wrong one, come in every charset: GB2312 and GBK from
/// Chinese servers, EUC-KR from Korean ones, Shift_JIS from Japanese programs, Big5 from Taiwan,
/// and Windows-1252 from Western ones. Their bytes are valid in several of these at once, so
/// macOS's detection (`NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)`)
/// picks the likeliest of ``candidates``.
///
/// That detection is unreliable for short Western text. An accented capital followed by a
/// lowercase letter, as in "Émile", is also a valid Big5 or GBK character, and a lone accented
/// capital is a half-width katakana in Shift_JIS. So text that reads as ordinary Western
/// European text in Windows-1252 (see ``looksWestern(_:)``) stays Windows-1252, as it was before
/// detection existed.
enum CharsetDetection {
    /// The charsets to choose from, each as the Windows superset that decodes the most files:
    /// GB18030 (for GB2312 and GBK), CP949 (for EUC-KR), CP932 (for Shift_JIS), Big5-HKSCS
    /// (for Big5), and Windows-1252 (for Latin-1).
    static let candidates: [String.Encoding] = [gb18030, cp949, cp932, big5, .windowsCP1252]

    static let gb18030 = encoding(.GB_18030_2000)
    static let cp949 = encoding(.dosKorean)
    static let cp932 = encoding(.dosJapanese)
    static let big5 = encoding(.big5_HKSCS_1999)

    /// At most this many bytes are passed to detection, so a huge file stays fast.
    static let maximumSampleSize = 65536

    /// The charset of text that isn't valid UTF-8: one of ``candidates``.
    ///
    /// - Parameter sample: The game's values that contain non-ASCII bytes, separated by line
    ///   breaks.
    /// - Returns: The detected charset, or Windows-1252 if detection finds none of the others
    ///   or the text reads as Western European text in Windows-1252.
    static func detect(_ sample: [UInt8]) -> String.Encoding {
        let sample = sample.count > maximumSampleSize ? Array(sample[..<maximumSampleSize]) : sample
        let western = sample.withUnsafeBufferPointer { TextDecoding.windows1252($0[...]) }
        if looksWestern(western) { return .windowsCP1252 }
        var converted: NSString?
        var usedLossyConversion: ObjCBool = false
        let rawValue = NSString.stringEncoding(
            for: Data(sample),
            encodingOptions: [
                .suggestedEncodingsKey: candidates.map(\.rawValue),
                .useOnlySuggestedEncodingsKey: true,
                .allowLossyKey: false,
            ],
            convertedString: &converted,
            usedLossyConversion: &usedLossyConversion
        )
        let detected = String.Encoding(rawValue: rawValue)
        guard rawValue != 0, !usedLossyConversion.boolValue, candidates.contains(detected) else {
            return .windowsCP1252
        }
        return detected
    }

    /// Whether text decoded as Windows-1252 reads as Western European text: every non-ASCII
    /// character is a Latin letter or a common punctuation mark or symbol, and no more than
    /// three of them come in a row.
    ///
    /// Text in a Chinese, Korean, or Japanese charset read this way turns into runs of symbols
    /// and accented letters, one pair of bytes per character, so it almost never passes. The
    /// rare text that passes (such as a lone "3段" in Shift_JIS) is decoded as Windows-1252, as
    /// before detection existed.
    static func looksWestern(_ text: String) -> Bool {
        var run = 0
        for scalar in text.unicodeScalars {
            guard !scalar.isASCII else {
                run = 0
                continue
            }
            run += 1
            guard run <= 3, isWestern(scalar) else { return false }
        }
        return true
    }

    /// Latin letters, and the punctuation marks and symbols Western text commonly uses. Left
    /// out are the C1 controls, the spacing diacritics other than the acute accent (which
    /// stands in for an apostrophe), and rare symbols such as `¤` and `¦`.
    private static func isWestern(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xC0 ... 0xFF: // Latin-1 letters, and × and ÷
            true
        case 0xA0 ... 0xBF:
            !"¤¦¨¬\u{AD}¯¸".unicodeScalars.contains(scalar)
        default:
            "ŒœŠšŽžŸƒ‘’‚“”„–—…•‹›€™".unicodeScalars.contains(scalar)
        }
    }

    /// The name of a detected charset, for warnings: the name files usually declare it by.
    static func name(of encoding: String.Encoding) -> String {
        switch encoding {
        case gb18030: "GB18030"
        case cp949: "EUC-KR"
        case cp932: "Shift_JIS"
        case big5: "Big5"
        case .windowsCP1252: "Windows-1252"
        default:
            CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(encoding.rawValue))
                .map { $0 as String } ?? "\(encoding)"
        }
    }

    private static func encoding(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }
}

/// Decoding of byte ranges to strings.
enum TextDecoding {
    /// Decodes bytes as UTF-8, or returns `nil` if they aren't valid UTF-8.
    ///
    /// Programs that wrap long lines with soft line breaks (a backslash before a line break) by
    /// counting bytes can put one inside a character. So bytes that aren't valid UTF-8 are
    /// checked again without their soft line breaks, which FF[4] Text removes anyway.
    static func utf8(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> String? {
        if let string = String(validating: bytes, as: UTF8.self) { return string }
        guard bytes.contains(backslash) else { return nil }
        return String(validating: removingSoftLineBreaks(bytes), as: UTF8.self)
    }

    /// The bytes without their soft line breaks: each backslash before a line break (`\n`,
    /// `\r\n`, `\n\r`, or `\r`) is removed with the line break. Other escapes are kept whole.
    static func removingSoftLineBreaks(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> [UInt8] {
        func isLineBreak(_ byte: UInt8) -> Bool { byte == 0x0A || byte == 0x0D }
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            index += 1
            guard byte == backslash, index < bytes.endIndex else {
                result.append(byte)
                continue
            }
            let escaped = bytes[index]
            index += 1
            if isLineBreak(escaped) {
                if index < bytes.endIndex, isLineBreak(bytes[index]), bytes[index] != escaped { index += 1 }
            } else {
                result += [byte, escaped]
            }
        }
        return result
    }

    private static let backslash: UInt8 = 0x5C

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
