import SwiftUI

/// Détail d'une session : onglets Page / Discussion + actions rapides (Aide, Question, menu).
struct SessionView: View {
    @StateObject private var model: SessionViewModel
    @EnvironmentObject private var settings: AppSettings

    init(session: StudySession, store: SessionStore, settings: AppSettings) {
        _model = StateObject(wrappedValue: SessionViewModel(session: session, store: store, settings: settings))
    }

    var body: some View {
        Group {
            switch model.tab {
            case .page:
                PaperView(model: model)
            case .discussion:
                ChatView(model: model)
            }
        }
        .navigationTitle(model.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Onglet", selection: $model.tab) {
                    ForEach(SessionViewModel.Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    model.askHelp()
                } label: {
                    Label("Aide", systemImage: "lifepreserver")
                }
                .disabled(model.isBusy)

                Button {
                    model.tab = .discussion
                    model.focusComposer = true
                } label: {
                    Label("Question", systemImage: "text.bubble")
                }

                Menu {
                    Button {
                        model.showExerciseSetup = true
                    } label: {
                        Label("Nouvel exercice", systemImage: "sparkles")
                    }
                    Button {
                        model.addBlankPage()
                        model.tab = .page
                    } label: {
                        Label("Nouvelle page", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Picker("Modèle pour cette discussion", selection: tutorModelBinding) {
                        Text("Selon les réglages (\(settings.tutorModel.displayName))").tag("")
                        ForEach(ClaudeModel.catalog) { candidate in
                            Text(candidate.displayName).tag(candidate.id)
                        }
                    }
                } label: {
                    Label("Plus", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Un problème est survenu", isPresented: errorPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: $model.pendingTranscription) { _ in
            TranscriptionSheet(model: model)
        }
        .sheet(isPresented: $model.showExerciseSetup) {
            ExerciseSetupSheet(model: model)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var tutorModelBinding: Binding<String> {
        Binding(
            get: { model.session.tutorModelID ?? "" },
            set: { model.setTutorModel($0.isEmpty ? nil : $0) }
        )
    }
}

/// Feuille « Nouvel exercice » : sujet, consignes, documents joints.
struct ExerciseSetupSheet: View {
    @ObservedObject var model: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var instructions = ""
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sujet") {
                    TextField("Ex. : Topologie — espaces métriques", text: $subject)
                }
                Section {
                    TextField("Ex. : niveau L3, commence par les définitions puis des démonstrations courtes", text: $instructions, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Consignes (facultatif)")
                }
                Section {
                    if model.pendingAttachments.isEmpty && model.session.attachments.filter({ !$0.isPageSnapshot }).isEmpty {
                        Text("Aucun document. Tu peux joindre ton cours (PDF, texte ou photos) pour que les questions s'appuient dessus.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.pendingAttachments) { attachment in
                        AttachmentChip(attachment: attachment) { model.removePendingAttachment(attachment.id) }
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Joindre un cours", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("Documents")
                } footer: {
                    let previous = model.session.attachments.filter { !$0.isPageSnapshot }
                    if !previous.isEmpty {
                        Text("Déjà dans la discussion : " + previous.map(\.filename).joined(separator: ", "))
                    }
                }
            }
            .navigationTitle("Nouvel exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commencer") {
                        model.startExercise(subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                                            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear { subject = model.session.subject }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image, .plainText, .text], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls { model.importDocument(from: url) }
                }
            }
        }
    }
}
