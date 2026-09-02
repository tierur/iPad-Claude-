import Combine
import PencilKit
import SwiftUI
import UIKit

/// Orchestration d'une session : page manuscrite, tuteur, discussion.
@MainActor
final class SessionViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case page = "Page"
        case discussion = "Discussion"

        var id: String { rawValue }
    }

    enum Activity: Equatable {
        case transcribing(TranscriptionStage)
        case thinking(String)
        case streaming

        var label: String {
            switch self {
            case .transcribing(let stage): return stage.label
            case .thinking(let text): return text
            case .streaming: return "Claude répond…"
            }
        }
    }

    struct PendingTranscription: Identifiable {
        let id = UUID()
        var text: String
        var transcription: Transcription
        var snapshot: PageSnapshot?
    }

    @Published var session: StudySession
    @Published var tab: Tab = .page
    @Published var activity: Activity? = nil
    @Published var streamingText = ""
    @Published var thinkingText = ""
    @Published var errorMessage: String? = nil
    @Published var pendingTranscription: PendingTranscription? = nil
    @Published var composerText = ""
    @Published var pendingAttachmentIDs: [UUID] = []
    @Published var focusComposer = false
    @Published var showExerciseSetup = false
    @Published var drawing = PKDrawing()
    /// Incrémenté quand le canevas doit recharger `drawing` (changement de page, effacement).
    @Published var canvasReloadToken = 0

    private let store: SessionStore
    private let settings: AppSettings
    private let client: AnthropicClient
    private let tutor: TutorService
    private let transcriber: TranscriptionService
    private var currentTask: Task<Void, Never>? = nil

    init(session: StudySession, store: SessionStore, settings: AppSettings) {
        self.session = session
        self.store = store
        self.settings = settings
        let client = AnthropicClient(apiKeyProvider: { settings.apiKey })
        self.client = client
        tutor = TutorService(client: client, attachments: store.attachments)
        transcriber = TranscriptionService(client: client)
        if session.pages.isEmpty {
            self.session.pages = [Page(number: 1)]
            self.session.currentPageIndex = 0
        }
        drawing = (try? PKDrawing(data: self.session.currentPage.drawingData)) ?? PKDrawing()
    }

    // MARK: - Accès

    var page: Page { session.currentPage }
    var isBusy: Bool { activity != nil }
    var tutorModel: ClaudeModel { ClaudeModel.named(session.tutorModelID ?? settings.tutorModelID) }
    var chatModel: ClaudeModel { ClaudeModel.named(session.tutorModelID ?? settings.chatModelID) }

    var pendingAttachments: [Attachment] {
        pendingAttachmentIDs.compactMap { id in session.attachments.first { $0.id == id } }
    }

    func attachment(withID id: UUID) -> Attachment? {
        session.attachments.first { $0.id == id }
    }

    // MARK: - Pages

    func drawingChanged(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        session.currentPage.drawingData = newDrawing.dataRepresentation()
        session.currentPage.updatedAt = Date()
        if session.currentPage.status == .blank, session.currentPage.hasQuestion {
            session.currentPage.status = .drafting
        }
        persist(touch: false)
    }

    func selectPage(_ index: Int) {
        guard session.pages.indices.contains(index), index != session.currentPageIndex else { return }
        session.currentPageIndex = index
        reloadDrawingFromPage()
        persist(touch: false)
    }

    func addBlankPage() {
        session.pages.append(Page(number: session.pages.count + 1))
        session.currentPageIndex = session.pages.count - 1
        reloadDrawingFromPage()
        persist()
    }

    func clearCurrentPage() {
        session.currentPage.drawingData = Data()
        session.currentPage.transcription = nil
        session.currentPage.feedback = nil
        session.currentPage.status = session.currentPage.hasQuestion ? .drafting : .blank
        reloadDrawingFromPage()
        persist()
    }

    func deleteCurrentPage() {
        guard session.pages.count > 1 else {
            clearCurrentPage()
            return
        }
        session.pages.remove(at: session.currentPageIndex)
        for index in session.pages.indices {
            session.pages[index].number = index + 1
        }
        session.currentPageIndex = min(session.currentPageIndex, session.pages.count - 1)
        reloadDrawingFromPage()
        persist()
    }

    func retryCurrentPage() {
        session.currentPage.feedback = nil
        session.currentPage.status = .drafting
        persist()
    }

    private func reloadDrawingFromPage() {
        drawing = (try? PKDrawing(data: session.currentPage.drawingData)) ?? PKDrawing()
        canvasReloadToken += 1
    }

    // MARK: - Exercices

    /// Demande une première question au tuteur (sur la page courante si elle est vierge, sinon sur une nouvelle page).
    func startExercise(subject: String, instructions: String) {
        showExerciseSetup = false
        if !subject.isEmpty {
            session.subject = subject
            if session.title.isEmpty || session.title == "Nouvelle discussion" {
                session.title = subject
            }
        }
        run(activityText: "Claude prépare une question…") {
            let pageIndex = self.pageIndexForNewQuestion()
            let pageNumber = self.session.pages[pageIndex].number
            let attachmentIDs = self.takePendingAttachments()
            self.appendMessage(ChatMessage(role: .user, kind: .question,
                                           text: "📝 Nouvel exercice (page \(pageNumber))" + (instructions.isEmpty ? "" : " — \(instructions)"),
                                           apiText: TutorPrompts.newExercise(subject: subject, instructions: instructions, pageNumber: pageNumber),
                                           attachmentIDs: attachmentIDs,
                                           pageID: self.session.pages[pageIndex].id))
            let (reply, response) = try await self.askTutor()
            try self.applyQuestion(reply, response: response, pageIndex: pageIndex)
        }
    }

    /// Passe à la question suivante (sans appel réseau si le tuteur l'a déjà proposée).
    func nextQuestion() {
        if let next = page.feedback?.nextQuestion, !next.isEmpty {
            var newPage = Page(number: session.pages.count + 1)
            newPage.question = next
            newPage.status = .drafting
            session.pages.append(newPage)
            session.currentPageIndex = session.pages.count - 1
            reloadDrawingFromPage()
            appendMessage(ChatMessage(role: .assistant, kind: .note, text: "Question suivante (page \(newPage.number)) :\n\n\(next)", pageID: newPage.id))
            persist()
            return
        }
        run(activityText: "Claude prépare la question suivante…") {
            let pageIndex = self.pageIndexForNewQuestion()
            let pageNumber = self.session.pages[pageIndex].number
            self.appendMessage(ChatMessage(role: .user, kind: .question,
                                           text: "➡️ Question suivante (page \(pageNumber))",
                                           apiText: TutorPrompts.nextQuestion(pageNumber: pageNumber),
                                           pageID: self.session.pages[pageIndex].id))
            let (reply, response) = try await self.askTutor()
            try self.applyQuestion(reply, response: response, pageIndex: pageIndex)
        }
    }

    private func pageIndexForNewQuestion() -> Int {
        let current = session.currentPage
        if !current.hasQuestion && current.drawingData.isEmpty {
            return session.currentPageIndex
        }
        session.pages.append(Page(number: session.pages.count + 1))
        session.currentPageIndex = session.pages.count - 1
        reloadDrawingFromPage()
        return session.currentPageIndex
    }

    private func applyQuestion(_ reply: TutorReply, response: ClaudeResponse, pageIndex: Int) throws {
        guard session.pages.indices.contains(pageIndex) else { return }
        let question = reply.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !intro.isEmpty else {
            throw ClaudeError.invalidResponse("le tuteur n'a pas renvoyé de question")
        }
        let finalQuestion = question.isEmpty ? intro : question
        session.pages[pageIndex].question = finalQuestion
        session.pages[pageIndex].status = .drafting
        session.pages[pageIndex].feedback = nil
        var shown = "**Question (page \(session.pages[pageIndex].number))**\n\n\(finalQuestion)"
        if !question.isEmpty, !intro.isEmpty { shown = intro + "\n\n" + shown }
        appendMessage(ChatMessage(role: .assistant, kind: .question, text: shown, apiText: response.text,
                                  pageID: session.pages[pageIndex].id, modelID: response.model))
        tab = .page
    }

    // MARK: - « Finir » : transcription puis évaluation

    func finishAnswer() {
        guard !drawing.strokes.isEmpty else {
            errorMessage = TranscriptionError.emptyPage.localizedDescription
            return
        }
        run(activityText: TranscriptionStage.rendering.label) {
            let outcome = try await self.transcriber.transcribe(
                drawing: self.drawing,
                mode: self.settings.transcriptionMode,
                model: self.settings.transcriptionModel,
                useFallbacks: self.settings.useServerFallbacks
            ) { stage in
                self.activity = .transcribing(stage)
            }
            // Le résultat de la transcription est enregistré avec la page, quoi qu'il arrive ensuite.
            self.session.currentPage.transcription = outcome.transcription
            self.persist()
            if self.settings.reviewTranscriptionBeforeSending {
                self.pendingTranscription = PendingTranscription(text: outcome.transcription.text,
                                                                 transcription: outcome.transcription,
                                                                 snapshot: outcome.snapshot)
            } else {
                try await self.submitAnswer(outcome.transcription, snapshot: outcome.snapshot)
            }
        }
    }

    /// Relance l'analyse de l'image par Claude depuis la feuille de relecture.
    func reanalyzePendingWithClaude() {
        guard let pending = pendingTranscription, let snapshot = pending.snapshot else { return }
        run(activityText: TranscriptionStage.claude.label) {
            let transcription = try await self.transcriber.transcribeWithClaude(
                snapshot: snapshot,
                draft: pending.transcription.onDeviceDraft ?? pending.transcription.text,
                model: self.settings.transcriptionModel,
                useFallbacks: self.settings.useServerFallbacks
            )
            var updated = transcription
            updated.onDeviceDraft = pending.transcription.onDeviceDraft ?? pending.transcription.text
            self.session.currentPage.transcription = updated
            self.pendingTranscription?.text = updated.text
            self.pendingTranscription?.transcription = updated
            self.persist()
        }
    }

    func submitReviewedTranscription() {
        guard let pending = pendingTranscription else { return }
        var transcription = pending.transcription
        let edited = pending.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if edited != transcription.text.trimmingCharacters(in: .whitespacesAndNewlines) {
            transcription.text = edited
            transcription.source = .manual
            transcription.confidence = 1
        }
        pendingTranscription = nil
        run(activityText: "Claude évalue ta réponse…") {
            try await self.submitAnswer(transcription, snapshot: pending.snapshot)
        }
    }

    func cancelReview() {
        pendingTranscription = nil
    }

    private func submitAnswer(_ transcription: Transcription, snapshot: PageSnapshot?) async throws {
        let pageIndex = session.currentPageIndex
        let pageID = session.pages[pageIndex].id
        let pageNumber = session.pages[pageIndex].number
        let question = session.pages[pageIndex].question ?? ""
        session.pages[pageIndex].transcription = transcription
        session.pages[pageIndex].status = .evaluating

        let attachImage = (settings.attachImageWithAnswer || transcription.confidence < 0.6) && snapshot != nil
        var attachmentIDs: [UUID] = []
        if attachImage, let snapshot {
            attachmentIDs = [try storeSnapshot(snapshot, pageNumber: pageNumber)]
        }

        let prompt: String
        if question.isEmpty {
            prompt = """
            [Page libre — page \(pageNumber)]
            Voici ce que j'ai écrit à la main (transcription automatique, \(transcription.source.label)) :
            «««
            \(transcription.text)
            »»»
            Réponds-moi (kind = "message") : corrige, complète ou réponds à ce que j'ai écrit.
            """
        } else {
            prompt = TutorPrompts.answer(pageNumber: pageNumber, question: question, transcription: transcription, imageAttached: attachImage)
        }
        appendMessage(ChatMessage(role: .user, kind: .answer, text: transcription.text, apiText: prompt,
                                  attachmentIDs: attachmentIDs, pageID: pageID))
        activity = .thinking(question.isEmpty ? "Claude lit ta page…" : "Claude évalue ta réponse…")

        var (reply, response) = try await askTutor()
        var usedImage = attachImage

        if reply.needsImage, !attachImage, let snapshot {
            // Claude n'arrive pas à interpréter la transcription : on lui envoie l'image de la page.
            appendMessage(ChatMessage(role: .assistant, kind: .feedback,
                                      text: reply.message.isEmpty ? "Je n'arrive pas à interpréter la transcription, envoie-moi l'image de ta page." : reply.message,
                                      apiText: response.text, pageID: pageID, modelID: response.model))
            let snapshotID = try storeSnapshot(snapshot, pageNumber: pageNumber)
            appendMessage(ChatMessage(role: .user, kind: .answer, text: "📷 Image de la page \(pageNumber) envoyée pour analyse",
                                      apiText: TutorPrompts.imageFollowUp(pageNumber: pageNumber),
                                      attachmentIDs: [snapshotID], pageID: pageID))
            activity = .thinking("Claude analyse l'image de ta page…")
            (reply, response) = try await askTutor()
            usedImage = true
        }

        guard session.pages.indices.contains(pageIndex) else { return }
        let reading = reply.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        if usedImage, !reading.isEmpty {
            // Lecture de Claude enregistrée comme transcription de référence.
            session.pages[pageIndex].transcription = Transcription(text: reading, source: .claudeVision, confidence: 0.9,
                                                                   onDeviceDraft: transcription.text, modelID: response.model)
        }
        let verdict: Verdict = question.isEmpty ? .notApplicable : reply.verdictValue
        let feedback = Feedback(verdict: verdict,
                                message: reply.message,
                                reading: reading.isEmpty ? nil : reading,
                                nextQuestion: reply.question.isEmpty ? nil : reply.question,
                                usedImage: usedImage,
                                modelID: response.model.isEmpty ? tutorModel.id : response.model)
        session.pages[pageIndex].feedback = feedback
        session.pages[pageIndex].status = verdict.pageStatus
        if !question.isEmpty {
            session.answeredCount += 1
            if verdict == .correct { session.correctCount += 1 }
        }
        var shown = question.isEmpty ? reply.message : "**\(verdict.label)**\n\n\(reply.message)"
        if !reading.isEmpty { shown += "\n\n_Ce que Claude a lu :_ \(reading)" }
        if let next = feedback.nextQuestion { shown += "\n\n**Question suivante proposée :** \(next)" }
        appendMessage(ChatMessage(role: .assistant, kind: .feedback, text: shown, apiText: response.text,
                                  pageID: pageID, modelID: response.model))
    }

    // MARK: - Indice

    func requestHint() {
        guard page.hasQuestion else { return }
        run(activityText: "Claude prépare un indice…") {
            let pageIndex = self.session.currentPageIndex
            let pageID = self.session.pages[pageIndex].id
            let pageNumber = self.session.pages[pageIndex].number
            let question = self.session.pages[pageIndex].question ?? ""
            var attachmentIDs: [UUID] = []
            if let snapshot = DrawingRenderer.snapshot(of: self.drawing) {
                attachmentIDs = [try self.storeSnapshot(snapshot, pageNumber: pageNumber)]
            }
            self.appendMessage(ChatMessage(role: .user, kind: .hint,
                                           text: "💡 Demande d'indice (page \(pageNumber))",
                                           apiText: TutorPrompts.hint(pageNumber: pageNumber, question: question,
                                                                      progress: self.session.pages[pageIndex].transcription?.text,
                                                                      imageAttached: !attachmentIDs.isEmpty),
                                           attachmentIDs: attachmentIDs, pageID: pageID))
            let (reply, response) = try await self.askTutor()
            guard self.session.pages.indices.contains(pageIndex) else { return }
            let hint = reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
            self.session.pages[pageIndex].hints.append(hint)
            self.appendMessage(ChatMessage(role: .assistant, kind: .hint, text: hint, apiText: response.text,
                                           pageID: pageID, modelID: response.model))
        }
    }

    // MARK: - Discussion libre

    func sendComposer() {
        let text = composerText
        let attachmentIDs = takePendingAttachments()
        composerText = ""
        sendChat(displayText: text, apiText: nil, attachmentIDs: attachmentIDs)
    }

    func askHelp() {
        let pageNumber = page.number
        var attachmentIDs: [UUID] = []
        if let snapshot = DrawingRenderer.snapshot(of: drawing) {
            if let id = try? storeSnapshot(snapshot, pageNumber: pageNumber) {
                attachmentIDs = [id]
            }
        }
        var prompt = TutorPrompts.help(pageNumber: pageNumber, question: page.question, transcription: page.transcription?.text)
        if attachmentIDs.isEmpty {
            prompt = prompt.replacingOccurrences(of: "L'image de ma page est jointe. ", with: "")
        }
        tab = .discussion
        sendChat(displayText: "🆘 Aide demandée sur la page \(pageNumber)", apiText: prompt, attachmentIDs: attachmentIDs, kind: .help)
    }

    func sendChat(displayText: String, apiText: String?, attachmentIDs: [UUID], kind: MessageKind = .chat) {
        let trimmed = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachmentIDs.isEmpty else { return }
        if session.title.isEmpty || session.title == "Nouvelle discussion" {
            session.title = String(trimmed.prefix(48))
        }
        run(activityText: nil) {
            self.appendMessage(ChatMessage(role: .user, kind: kind, text: trimmed.isEmpty ? "📎 Documents joints" : trimmed,
                                           apiText: apiText, attachmentIDs: attachmentIDs,
                                           pageID: kind == .help ? self.page.id : nil))
            self.activity = .streaming
            self.streamingText = ""
            self.thinkingText = ""
            var fullText = ""
            var model = ""
            var stopReason: String? = nil
            var stopDetails: StopDetails? = nil
            let stream = self.tutor.streamChat(session: self.session,
                                               model: self.chatModel,
                                               effort: self.settings.effort,
                                               showThinking: self.settings.showThinking,
                                               useFallbacks: self.settings.useServerFallbacks)
            for try await event in stream {
                switch event {
                case .started(let servedModel):
                    model = servedModel
                case .text(let text):
                    fullText += text
                    self.streamingText = fullText
                case .thinking(let text):
                    self.thinkingText += text
                case .fallback(_, let to):
                    model = to
                case .finished(let reason, let details, _):
                    stopReason = reason
                    stopDetails = details
                }
            }
            self.streamingText = ""
            self.thinkingText = ""
            if stopReason == "refusal" {
                throw ClaudeError.refused(category: stopDetails?.category, explanation: stopDetails?.explanation)
            }
            var shown = fullText
            if stopReason == "max_tokens" { shown += "\n\n_(Réponse tronquée : limite de longueur atteinte.)_" }
            self.appendMessage(ChatMessage(role: .assistant, kind: .chat, text: shown, apiText: fullText, modelID: model))
        }
    }

    func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
        if !streamingText.isEmpty {
            appendMessage(ChatMessage(role: .assistant, kind: .chat, text: streamingText + "\n\n_(Réponse interrompue.)_", apiText: streamingText))
        }
        streamingText = ""
        thinkingText = ""
        activity = nil
        if session.currentPage.status == .evaluating {
            session.currentPage.status = .drafting
            persist()
        }
    }

    // MARK: - Pièces jointes

    func importDocument(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let kind = AttachmentKind.from(filename: url.lastPathComponent) else {
                errorMessage = "Format non pris en charge : \(url.lastPathComponent). Utilisez un PDF, une image ou un fichier texte."
                return
            }
            var data = try Data(contentsOf: url)
            var mediaType: String
            switch kind {
            case .pdf:
                mediaType = "application/pdf"
                guard data.count < 30_000_000 else {
                    errorMessage = "Ce PDF dépasse 30 Mo : découpez-le avant de le joindre."
                    return
                }
            case .text:
                mediaType = "text/plain"
            case .image:
                guard let image = UIImage(data: data), let normalized = Self.normalizedJPEG(image) else {
                    errorMessage = "Image illisible : \(url.lastPathComponent)."
                    return
                }
                data = normalized
                mediaType = "image/jpeg"
            }
            let attachment = try store.attachments.save(data: data, filename: url.lastPathComponent, kind: kind, mediaType: mediaType)
            session.attachments.append(attachment)
            pendingAttachmentIDs.append(attachment.id)
            persist()
        } catch {
            errorMessage = "Impossible de lire \(url.lastPathComponent) : \(error.localizedDescription)"
        }
    }

    func attachCurrentPageToComposer() {
        guard let snapshot = DrawingRenderer.snapshot(of: drawing) else {
            errorMessage = TranscriptionError.emptyPage.localizedDescription
            return
        }
        do {
            let id = try storeSnapshot(snapshot, pageNumber: page.number)
            pendingAttachmentIDs.append(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePendingAttachment(_ id: UUID) {
        pendingAttachmentIDs.removeAll { $0 == id }
    }

    func takePendingAttachments() -> [UUID] {
        let ids = pendingAttachmentIDs
        pendingAttachmentIDs = []
        return ids
    }

    private func storeSnapshot(_ snapshot: PageSnapshot, pageNumber: Int) throws -> UUID {
        let attachment = try store.attachments.save(data: snapshot.jpegData,
                                                    filename: "page-\(pageNumber).jpg",
                                                    kind: .image,
                                                    mediaType: snapshot.mediaType,
                                                    isPageSnapshot: true)
        session.attachments.append(attachment)
        return attachment.id
    }

    private static func normalizedJPEG(_ image: UIImage, maxDimension: CGFloat = 2000) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }

    // MARK: - Modèle de la session

    func setTutorModel(_ id: String?) {
        session.tutorModelID = id
        persist(touch: false)
    }

    // MARK: - Utilitaires

    private func askTutor() async throws -> (reply: TutorReply, response: ClaudeResponse) {
        let result = try await tutor.askStructured(session: session,
                                                   model: tutorModel,
                                                   effort: settings.effort,
                                                   showThinking: settings.showThinking,
                                                   useFallbacks: settings.useServerFallbacks) { [weak self] event in
            guard let self else { return }
            if case .thinking(let text) = event {
                Task { @MainActor in self.thinkingText += text }
            }
        }
        thinkingText = ""
        return result
    }

    private func appendMessage(_ message: ChatMessage) {
        session.messages.append(message)
        persist()
    }

    private func persist(touch: Bool = true) {
        store.update(session, touch: touch)
    }

    /// Exécute une action asynchrone en gérant l'indicateur d'activité et les erreurs.
    private func run(activityText: String?, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        guard settings.hasAPIKey else {
            errorMessage = ClaudeError.missingAPIKey.localizedDescription
            return
        }
        if let activityText { activity = .thinking(activityText) }
        currentTask = Task { [weak self] in
            do {
                try await operation()
            } catch is CancellationError {
                // Interrompu par l'utilisateur.
            } catch {
                guard let self else { return }
                let description = error.localizedDescription
                self.errorMessage = description
                self.appendMessage(ChatMessage(role: .assistant, kind: .note, text: "⚠️ \(description)", isError: true))
                if self.session.currentPage.status == .evaluating {
                    self.session.currentPage.status = .drafting
                }
            }
            guard let self else { return }
            self.activity = nil
            self.streamingText = ""
            self.thinkingText = ""
            self.currentTask = nil
            self.persist(touch: false)
        }
    }
}
