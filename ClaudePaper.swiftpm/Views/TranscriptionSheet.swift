import SwiftUI

/// Relecture de la transcription avant envoi au tuteur.
struct TranscriptionSheet: View {
    @ObservedObject var model: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let pending = model.pendingTranscription {
                    header(for: pending.transcription)
                    if let snapshot = pending.snapshot {
                        Image(uiImage: snapshot.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))
                    }
                    Text("Texte reconnu (modifiable) :")
                        .font(.subheadline.weight(.semibold))
                    TextEditor(text: textBinding)
                        .font(.body)
                        .frame(minHeight: 160)
                        .padding(6)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    if let draft = pending.transcription.onDeviceDraft, pending.transcription.source == .claudeVision, !draft.isEmpty {
                        DisclosureGroup("Brouillon de la reconnaissance de l'iPad") {
                            Text(draft)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.subheadline)
                    }
                    if let activity = model.activity {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(activity.label)
                                .font(.subheadline)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Relire ma réponse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        model.cancelReview()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.pendingTranscription?.snapshot != nil, model.pendingTranscription?.transcription.source != .claudeVision {
                        Button {
                            model.reanalyzePendingWithClaude()
                        } label: {
                            Label("Analyser l'image avec Claude", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(model.isBusy)
                    }
                    Button {
                        model.submitReviewedTranscription()
                        dismiss()
                    } label: {
                        Label("Envoyer", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || (model.pendingTranscription?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
                }
            }
        }
        .presentationDetents([.large])
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { model.pendingTranscription?.text ?? "" },
            set: { model.pendingTranscription?.text = $0 }
        )
    }

    private func header(for transcription: Transcription) -> some View {
        HStack(spacing: 12) {
            Label(transcription.source.label, systemImage: transcription.source == .claudeVision ? "sparkles" : "ipad")
            Text("confiance ≈ \(Int((transcription.confidence * 100).rounded())) %")
                .foregroundStyle(.secondary)
            if let modelID = transcription.modelID, !modelID.isEmpty {
                Text(ClaudeModel.named(modelID).displayName)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .font(.caption)
    }
}
