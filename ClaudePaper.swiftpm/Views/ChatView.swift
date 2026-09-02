import SwiftUI
import UniformTypeIdentifiers

/// Onglet Discussion : historique, réponse en streaming, composeur avec pièces jointes.
struct ChatView: View {
    @ObservedObject var model: SessionViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showImporter = false
    @FocusState private var composerFocused: Bool

    private static let importTypes: [UTType] = {
        var types: [UTType] = [.pdf, .image, .plainText, .text]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.session.messages.isEmpty {
                            WelcomeCard(model: model, onImport: { showImporter = true })
                        }
                        ForEach(model.session.messages) { message in
                            MessageBubble(message: message,
                                          attachments: message.attachmentIDs.compactMap { model.attachment(withID: $0) })
                                .id(message.id)
                        }
                        if model.activity == .streaming {
                            StreamingBubble(text: model.streamingText, thinking: model.thinkingText)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: model.session.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: model.streamingText) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            Divider()
            composer
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls { model.importDocument(from: url) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: model.focusComposer) { _, focus in
            if focus {
                composerFocused = true
                model.focusComposer = false
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                model.removePendingAttachment(attachment.id)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Joindre un cours (PDF, texte, image)", systemImage: "doc.badge.plus")
                    }
                    Button {
                        model.attachCurrentPageToComposer()
                    } label: {
                        Label("Joindre la page manuscrite actuelle", systemImage: "pencil.and.scribble")
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                }
                .disabled(model.isBusy)

                TextField("Pose une question à Claude…", text: $model.composerText, axis: .vertical)
                    .lineLimit(1...8)
                    .textFieldStyle(.roundedBorder)
                    .focused($composerFocused)
                    .onSubmit { model.sendComposer() }

                if model.isBusy {
                    Button(action: model.cancelCurrentTask) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .tint(.red)
                } else {
                    Button(action: model.sendComposer) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingAttachments.isEmpty)
                }
            }
            Text("Modèle : \(model.chatModel.displayName) · effort \(settings.effort.rawValue)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
    }
}

struct StreamingBubble: View {
    let text: String
    let thinking: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if !thinking.isEmpty {
                    DisclosureGroup {
                        Text(thinking)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Réflexion", systemImage: "brain")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if text.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Claude réfléchit…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    MarkdownText(text: text)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 80)
        }
    }
}

struct WelcomeCard: View {
    @ObservedObject var model: SessionViewModel
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bienvenue sur ta page blanche")
                .font(.title3.bold())
            Text("""
            1. Joins ton cours (PDF, notes, photos) avec le trombone.
            2. Demande à Claude de te faire travailler : « Fais-moi réviser la topologie, niveau L3 ».
            3. Sur l'onglet **Page**, réponds à la main avec l'Apple Pencil, puis touche **Finir**.
            4. **Indice** te débloque sans donner la réponse ; **Aide** envoie ta page à Claude.
            """)
            .font(.subheadline)
            HStack {
                Button(action: onImport) {
                    Label("Joindre un cours", systemImage: "doc.badge.plus")
                }
                Button {
                    model.showExerciseSetup = true
                } label: {
                    Label("Commencer un exercice", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
