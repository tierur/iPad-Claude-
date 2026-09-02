import SwiftUI

/// Vue racine : liste des discussions à gauche, session courante à droite.
struct RootView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: SymbolLibrary
    @State private var selection: UUID?
    @State private var showSettings = false
    @State private var showNewSession = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(store.sessions) { session in
                    SessionRow(session: session)
                        .tag(session.id)
                }
                .onDelete { offsets in
                    let doomed = offsets.map { store.sessions[$0] }
                    for session in doomed {
                        if selection == session.id { selection = nil }
                        store.delete(session)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Discussions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Réglages", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewSession = true
                    } label: {
                        Label("Nouvelle discussion", systemImage: "square.and.pencil")
                    }
                }
            }
            .overlay {
                if store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune discussion", systemImage: "pencil.and.outline")
                    } description: {
                        Text("Crée une discussion pour commencer à écrire avec le Pencil.")
                    } actions: {
                        Button("Nouvelle discussion") { showNewSession = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        } detail: {
            if let id = selection, let session = store.session(withID: id) {
                SessionView(session: session, store: store, settings: settings, library: library)
                    .id(session.id)
            } else {
                ContentUnavailableView {
                    Label("ClaudePaper", systemImage: "applepencil.and.scribble")
                } description: {
                    Text("Choisis une discussion, ou crée-en une nouvelle.")
                } actions: {
                    Button("Nouvelle discussion") { showNewSession = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet { title, subject in
                let session = store.create(title: title, subject: subject)
                selection = session.id
            }
        }
        .onAppear {
            if !settings.hasAPIKey { showSettings = true }
            if selection == nil { selection = store.sessions.first?.id }
        }
        .alert("Lecture des données", isPresented: Binding(get: { store.loadError != nil }, set: { if !$0 { store.loadError = nil } })) {
            Button("OK") { store.loadError = nil }
        } message: {
            Text(store.loadError ?? "")
        }
    }
}

struct SessionRow: View {
    let session: StudySession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title.isEmpty ? "Sans titre" : session.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 8) {
                if !session.subject.isEmpty {
                    Text(session.subject).lineLimit(1)
                }
                Spacer()
                if session.answeredCount > 0 {
                    Text("\(session.correctCount)/\(session.answeredCount) ✓")
                        .monospacedDigit()
                }
                Text(session.updatedAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct NewSessionSheet: View {
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subject = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre (ex. : Topologie — chapitre 2)", text: $title)
                TextField("Matière ou sujet (facultatif)", text: $subject)
            }
            .navigationTitle("Nouvelle discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(cleanTitle.isEmpty ? (cleanSubject.isEmpty ? "Nouvelle discussion" : cleanSubject) : cleanTitle, cleanSubject)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
