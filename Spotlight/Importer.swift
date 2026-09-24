import CoreFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.pragmaphilia.SGFTools.Spotlight", category: "import")

/// Adds the Spotlight attributes of the SGF file at `url` to `attributes` (see
/// ``SpotlightAttributes``). Called by `PlugIn.c` for each file Spotlight imports.
///
/// - Returns: `true` if the file was read, or `false` if it can't be read or holds no game.
@_cdecl("SGFToolsImporterGetMetadata")
func importerGetMetadata(_ attributes: CFMutableDictionary, _ url: CFURL) -> DarwinBoolean {
    autoreleasepool {
        let fileURL = url as URL
        let found: SpotlightAttributes?
        do {
            found = try SpotlightAttributes(contentsOf: fileURL)
        } catch {
            logger.error("Can't read \(fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard let found else { return false }
        let dictionary = attributes as NSMutableDictionary
        for (name, value) in found.values {
            dictionary[name] = value.object
        }
        return true
    }
}
