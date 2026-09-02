import SwiftUI

/// Carte affichée sur la page avec l'évaluation de Claude.
struct FeedbackCard: View {
    let feedback: Feedback
    let onNext: () -> Void
    let onRetry: () -> Void
    let onOpenDiscussion: () -> Void
    let onDismiss: () -> Void

    @State private var showReading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(feedback.verdict.label)
                    .font(.headline)
                if feedback.usedImage {
                    Label("image analysée", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                MarkdownText(text: feedback.message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            if let reading = feedback.reading {
                DisclosureGroup("Ce que Claude a lu", isExpanded: $showReading) {
                    Text(reading)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.subheadline)
            }
            HStack {
                Button("Réessayer", action: onRetry)
                Spacer()
                Button("Voir la discussion", action: onOpenDiscussion)
                if feedback.verdict == .correct || feedback.nextQuestion != nil {
                    Button(action: onNext) {
                        Label("Question suivante", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.6), lineWidth: 1.5)
        )
        .frame(maxWidth: 720)
        .padding(.horizontal, 16)
    }

    private var color: Color {
        switch feedback.verdict {
        case .correct: return .green
        case .partial: return .orange
        case .incorrect: return .red
        case .unreadable: return .gray
        case .notApplicable: return .accentColor
        }
    }

    private var icon: String {
        switch feedback.verdict {
        case .correct: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .unreadable: return "eye.slash.circle.fill"
        case .notApplicable: return "text.bubble.fill"
        }
    }
}

/// Bandeau d'activité (transcription, réflexion, réponse en cours).
struct ActivityBanner: View {
    let activity: SessionViewModel.Activity
    let thinking: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressView()
                Text(activity.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Interrompre", action: onCancel)
                    .font(.subheadline)
            }
            if !thinking.isEmpty {
                Text(thinking.suffix(400))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 720)
        .padding(.horizontal, 16)
    }
}
