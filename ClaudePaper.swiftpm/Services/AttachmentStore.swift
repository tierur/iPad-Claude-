import Foundation

/// Fichiers joints (cours PDF, images, instantanés de pages), stockés dans Documents/ClaudePaper/Attachments.
final class AttachmentStore {
    let directory: URL

    init(baseDirectory: URL) {
        directory = baseDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for attachment: Attachment) -> URL {
        directory.appendingPathComponent(attachment.id.uuidString)
    }

    func save(data: Data, filename: String, kind: AttachmentKind, mediaType: String, isPageSnapshot: Bool = false) throws -> Attachment {
        let attachment = Attachment(filename: filename, kind: kind, mediaType: mediaType,
                                    byteCount: data.count, isPageSnapshot: isPageSnapshot)
        try data.write(to: url(for: attachment), options: .atomic)
        return attachment
    }

    func data(for attachment: Attachment) -> Data? {
        try? Data(contentsOf: url(for: attachment))
    }

    func delete(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }
}
