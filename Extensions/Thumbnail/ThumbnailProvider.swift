import Foundation
import QuickLookThumbnailing

/// Makes Finder's thumbnails of SGF files: the first game's board after the opening moves (see
/// ``Thumbnail``). A file with no game gets no thumbnail, so Finder shows its usual icon.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let thumbnail: Thumbnail
        do {
            guard let found = try Thumbnail(contentsOf: request.fileURL) else {
                handler(nil, CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: request.fileURL]))
                return
            }
            thumbnail = found
        } catch {
            handler(nil, error)
            return
        }
        let size = Thumbnail.contextSize(fitting: request.maximumSize)
        let reply = QLThumbnailReply(contextSize: size) { context in
            // The context is `size` times the request's scale in pixels, but its user space
            // may be in points or in pixels, so fill whatever it covers.
            let bounds = context.boundingBoxOfClipPath
            let rect = bounds.isNull || bounds.isInfinite || bounds.isEmpty ? CGRect(origin: .zero, size: size) : bounds
            thumbnail.draw(in: context, rect: rect)
            return true
        }
        handler(reply, nil)
    }
}
