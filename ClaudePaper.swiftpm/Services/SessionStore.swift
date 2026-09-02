import Foundation
import Combine

/// Persistance des sessions (un fichier JSON par session dans Documents/ClaudePaper/Sessions).
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [StudySession] = []
    @Published var loadError: String?

    let attachments: AttachmentStore
    private let sessionsDirectory: URL
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let base = documents.appendingPathComponent("ClaudePaper", isDirectory: true)
        sessionsDirectory = base.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        attachments = AttachmentStore(baseDirectory: base)
        load()
    }

    func load() {
        var loaded: [StudySession] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                var session = try Self.decoder.decode(StudySession.self, from: data)
                if session.pages.isEmpty { session.pages = [Page(number: 1)] }
                session.currentPageIndex = min(max(session.currentPageIndex, 0), session.pages.count - 1)
                loaded.append(session)
            } catch {
                loadError = "Impossible de lire \(file.lastPathComponent) : \(error.localizedDescription)"
            }
        }
        sessions = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func session(withID id: UUID) -> StudySession? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    func create(title: String, subject: String) -> StudySession {
        let session = StudySession(title: title, subject: subject)
        sessions.insert(session, at: 0)
        persistNow(session)
        return session
    }

    /// Met à jour la session en mémoire et planifie l'écriture sur disque (regroupée).
    func update(_ session: StudySession, touch: Bool = true) {
        var updated = session
        if touch { updated.updatedAt = Date() }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = updated
        } else {
            sessions.insert(updated, at: 0)
        }
        scheduleSave(updated)
    }

    func delete(_ session: StudySession) {
        pendingSaves[session.id]?.cancel()
        pendingSaves[session.id] = nil
        sessions.removeAll { $0.id == session.id }
        for attachment in session.attachments {
            attachments.delete(attachment)
        }
        try? FileManager.default.removeItem(at: fileURL(for: session.id))
    }

    func flush() {
        for session in sessions where pendingSaves[session.id] != nil {
            pendingSaves[session.id]?.cancel()
            pendingSaves[session.id] = nil
            persistNow(session)
        }
    }

    // MARK: - Privé

    private func fileURL(for id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func scheduleSave(_ session: StudySession) {
        pendingSaves[session.id]?.cancel()
        pendingSaves[session.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self else { return }
            self.pendingSaves[session.id] = nil
            if let latest = self.session(withID: session.id) {
                self.persistNow(latest)
            }
        }
    }

    private func persistNow(_ session: StudySession) {
        let url = fileURL(for: session.id)
        let encoder = Self.encoder
        Task.detached(priority: .utility) {
            do {
                let data = try encoder.encode(session)
                try data.write(to: url, options: .atomic)
            } catch {
                // L'écriture sera retentée à la prochaine modification.
            }
        }
    }
}
