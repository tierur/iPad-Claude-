import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey = ""
    @State private var keySaved = false

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                modelsSection
                thinkingSection
                handwritingSection
                safetySection
                aboutSection
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear { draftKey = settings.apiKey }
        }
    }

    // MARK: Sections

    private var apiKeySection: some View {
        Section {
            SecureField("sk-ant-…", text: $draftKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button("Enregistrer la clé") {
                    settings.apiKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    keySaved = settings.keychainError == nil
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines) == settings.apiKey)
                Spacer()
                if settings.hasAPIKey {
                    Label("Clé enregistrée dans le trousseau", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Aucune clé", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            if let error = settings.keychainError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            Link("Créer une clé sur console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.subheadline)
        } header: {
            Text("Compte Claude (clé API)")
        } footer: {
            Text("L'app utilise l'API Anthropic avec ta clé, facturée à l'usage. Un abonnement Claude Pro/Max ne s'utilise pas depuis une app tierce : il faut créer une clé sur la console (avec un crédit prépayé). La clé reste sur l'iPad, dans le trousseau.")
        }
    }

    private var modelsSection: some View {
        Section {
            ModelPicker(title: "Tuteur (questions, évaluation, indices)", selection: $settings.tutorModelID)
            ModelPicker(title: "Discussion", selection: $settings.chatModelID)
            ModelPicker(title: "Lecture de l'écriture (analyse d'image)", selection: $settings.transcriptionModelID)
        } header: {
            Text("Modèles")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ClaudeModel.catalog) { model in
                    Text("**\(model.displayName)** — \(model.summary) \(model.priceLabel).")
                }
            }
        }
    }

    private var thinkingSection: some View {
        Section {
            Picker("Effort", selection: $settings.effort) {
                ForEach(Effort.allCases) { effort in
                    Text(effort.label).tag(effort)
                }
            }
            Toggle("Afficher le résumé de la réflexion", isOn: $settings.showThinking)
        } header: {
            Text("Réflexion")
        } footer: {
            Text("L'effort règle la profondeur de réflexion (et le coût). « Élevé » convient au tutorat ; « Maximum » pour les démonstrations difficiles. Claude Fable 5.1 réfléchit toujours ; Claude Haiku 4.5 ne réfléchit pas.")
        }
    }

    private var handwritingSection: some View {
        Section {
            Picker("Transcription", selection: $settings.transcriptionMode) {
                ForEach(TranscriptionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
            Toggle("Relire la transcription avant l'envoi", isOn: $settings.reviewTranscriptionBeforeSending)
            Toggle("Toujours joindre l'image de la page à la réponse", isOn: $settings.attachImageWithAnswer)
            Toggle("Autoriser l'écriture au doigt", isOn: $settings.allowFingerDrawing)
            Picker("Papier", selection: $settings.paperStyle) {
                ForEach(PaperStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Écriture manuscrite")
        } footer: {
            Text("La reconnaissance de l'iPad (Vision) lit le français mais pas les symboles mathématiques. En mode automatique, Claude analyse l'image de la page dès que le texte contient des mathématiques ou que la confiance est faible, et le résultat est enregistré avec la page. Si le tuteur n'arrive pas à interpréter ta réponse, il demande lui-même l'image.")
        }
    }

    private var safetySection: some View {
        Section {
            Toggle("Repli automatique en cas de refus", isOn: $settings.useServerFallbacks)
        } header: {
            Text("Fiabilité")
        } footer: {
            Text("Avec Claude Opus 5 et Claude Fable 5.1, si les classifieurs de sécurité refusent une requête, l'API la rejoue automatiquement sur un modèle de repli recommandé par Anthropic (facturé au tarif de ce modèle).")
        }
    }

    private var aboutSection: some View {
        Section("À propos") {
            Text("ClaudePaper — papier intelligent pour iPad et Apple Pencil. Les discussions, pages et transcriptions sont enregistrées dans Fichiers → Sur mon iPad → ClaudePaper.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModelPicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(ClaudeModel.catalog) { model in
                Text(model.displayName).tag(model.id)
            }
        }
    }
}
