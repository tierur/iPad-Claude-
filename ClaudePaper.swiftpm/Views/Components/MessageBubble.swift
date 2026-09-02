import SwiftUI

/// Pastille représentant une pièce jointe.
struct AttachmentChip: View {
    let attachment: Attachment
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(attachment.filename)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(sizeLabel)
                .foregroundStyle(.secondary)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill), in: Capsule())
    }

    private var icon: String {
        switch attachment.kind {
        case .pdf: return "doc.richtext"
        case .image: return attachment.isPageSnapshot ? "pencil.and.scribble" : "photo"
        case .text: return "doc.text"
        }
    }

    private var sizeLabel: String {
        let kb = Double(attachment.byteCount) / 1024
        return kb < 1000 ? String(format: "%.0f Ko", kb) : String(format: "%.1f Mo", kb / 1024)
    }
}

/// Bulle d'un message de la discussion.
struct MessageBubble: View {
    let message: ChatMessage
    let attachments: [Attachment]

    var body: some View {
        if message.kind == .note {
            noteView
        } else {
            HStack(alignment: .top, spacing: 0) {
                if message.role == .user { Spacer(minLength: 80) }
                VStack(alignment: .leading, spacing: 6) {
                    if let badge {
                        Label(badge.text, systemImage: badge.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(message.role == .user ? Color.white.opacity(0.85) : Color.accentColor)
                    }
                    if !attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(attachments) { AttachmentChip(attachment: $0) }
                        }
                    }
                    MarkdownText(text: message.text)
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                    if message.role == .assistant, let modelID = message.modelID, !modelID.isEmpty {
                        Text(ClaudeModel.named(modelID).displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if message.role == .assistant { Spacer(minLength: 80) }
            }
        }
    }

    private var noteView: some View {
        HStack {
            Spacer()
            MarkdownText(text: message.text, font: .callout)
                .foregroundStyle(message.isError ? Color.red : Color.secondary)
                .multilineTextAlignment(.leading)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            Spacer()
        }
    }

    private var bubbleBackground: Color {
        if message.role == .user { return Color.accentColor }
        return Color(.secondarySystemBackground)
    }

    private var badge: (text: String, icon: String)? {
        switch message.kind {
        case .chat: return nil
        case .question: return (message.role == .user ? "Demande de question" : "Question", "questionmark.circle")
        case .answer: return ("Réponse manuscrite", "pencil.and.scribble")
        case .feedback: return ("Retour du tuteur", "checkmark.seal")
        case .hint: return ("Indice", "lightbulb")
        case .help: return ("Aide", "lifepreserver")
        case .note: return nil
        }
    }
}
