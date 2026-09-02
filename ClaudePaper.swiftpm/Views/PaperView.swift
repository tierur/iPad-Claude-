import PencilKit
import SwiftUI

/// La « page blanche » : question en haut, canevas Pencil au milieu, Indice en bas à gauche, Finir en bas à droite.
struct PaperView: View {
    @ObservedObject var model: SessionViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showToolPicker = true
    @State private var showHints = false
    @State private var showFeedback = true

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(model: model)
            Divider()
            ZStack(alignment: .bottom) {
                PencilCanvasView(drawing: model.drawing,
                                 reloadToken: model.canvasReloadToken,
                                 paperStyle: settings.paperStyle,
                                 allowFinger: settings.allowFingerDrawing,
                                 showToolPicker: showToolPicker,
                                 onChange: { model.drawingChanged($0) })
                VStack(spacing: 10) {
                    if let activity = model.activity {
                        ActivityBanner(activity: activity, thinking: model.thinkingText, onCancel: model.cancelCurrentTask)
                    }
                    if let feedback = model.page.feedback, showFeedback {
                        FeedbackCard(feedback: feedback,
                                     onNext: { model.nextQuestion() },
                                     onRetry: { model.retryCurrentPage() },
                                     onOpenDiscussion: { model.tab = .discussion },
                                     onDismiss: { showFeedback = false })
                    }
                    bottomBar
                }
                .padding(.bottom, 12)
            }
            Divider()
            PageStrip(model: model, showToolPicker: $showToolPicker)
        }
        .onChange(of: model.page.feedback?.createdAt) { _, _ in
            showFeedback = true
        }
        .onChange(of: model.session.currentPageIndex) { _, _ in
            showFeedback = true
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                showHints = true
            } label: {
                Label("Indice", systemImage: "lightbulb")
                    .font(.headline)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!model.page.hasQuestion || model.isBusy)
            .popover(isPresented: $showHints) {
                HintsPopover(model: model)
            }

            Spacer()

            Button {
                model.finishAnswer()
            } label: {
                Label("Finir", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
    }
}

// MARK: - En-tête : la question

struct QuestionHeader: View {
    @ObservedObject var model: SessionViewModel
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Page \(model.page.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                StatusBadge(status: model.page.status)
                if let transcription = model.page.transcription {
                    Text("Transcription : \(transcription.source.label)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                if model.page.hasQuestion {
                    Button(expanded ? "Réduire" : "Agrandir") {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.caption)
                }
            }
            if let question = model.page.question, !question.isEmpty {
                ScrollView {
                    MarkdownText(text: question)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: expanded ? 460 : 150)
            } else {
                HStack(alignment: .center) {
                    Text("Page libre : écris ce que tu veux avec le Pencil, puis touche « Finir » pour l'envoyer à Claude. Ou demande une question d'exercice.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.showExerciseSetup = true
                    } label: {
                        Label("Demander une question", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}

struct StatusBadge: View {
    let status: PageStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case .blank: return "Page libre"
        case .drafting: return "À répondre"
        case .evaluating: return "Évaluation…"
        case .correct: return "Correct"
        case .partial: return "Partiel"
        case .incorrect: return "Incorrect"
        case .unreadable: return "Illisible"
        }
    }

    private var color: Color {
        switch status {
        case .blank: return .gray
        case .drafting: return .blue
        case .evaluating: return .purple
        case .correct: return .green
        case .partial: return .orange
        case .incorrect: return .red
        case .unreadable: return .gray
        }
    }
}

// MARK: - Barre des pages

struct PageStrip: View {
    @ObservedObject var model: SessionViewModel
    @Binding var showToolPicker: Bool
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.selectPage(model.session.currentPageIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.session.currentPageIndex == 0)

            Text("Page \(model.session.currentPageIndex + 1) / \(model.session.pages.count)")
                .font(.subheadline.monospacedDigit())

            Button {
                model.selectPage(model.session.currentPageIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.session.currentPageIndex >= model.session.pages.count - 1)

            Button {
                model.addBlankPage()
            } label: {
                Label("Nouvelle page", systemImage: "plus.square.on.square")
            }

            Spacer()

            if model.session.answeredCount > 0 {
                Text("\(model.session.correctCount) / \(model.session.answeredCount) bonnes réponses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $showToolPicker) {
                Label("Outils", systemImage: "pencil.tip.crop.circle")
            }
            .toggleStyle(.button)

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .confirmationDialog("Supprimer cette page ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Effacer l'écriture seulement") { model.clearCurrentPage() }
                Button("Supprimer la page", role: .destructive) { model.deleteCurrentPage() }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Indices

struct HintsPopover: View {
    @ObservedObject var model: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Indices")
                .font(.headline)
            if model.page.hints.isEmpty {
                Text("Aucun indice pour l'instant. Claude tiendra compte de ce que tu as déjà écrit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(model.page.hints.enumerated()), id: \.offset) { index, hint in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Indice \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                MarkdownText(text: hint, font: .callout)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            Button {
                model.requestHint()
            } label: {
                Label(model.page.hints.isEmpty ? "Demander un indice" : "Un autre indice", systemImage: "lightbulb")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(model.isBusy)
        }
        .padding(16)
        .frame(width: 380)
    }
}
