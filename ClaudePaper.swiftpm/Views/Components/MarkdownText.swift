import SwiftUI

/// Bloc Markdown simple (titres, listes, code, paragraphes).
enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case code(String)
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func flushLists() {
            if !bullets.isEmpty {
                blocks.append(.bullets(bullets))
                bullets = []
            }
            if !numbered.isEmpty {
                blocks.append(.numbered(numbered))
                numbered = []
            }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    flushParagraph()
                    flushLists()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                flushLists()
                continue
            }
            if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                flushLists()
                blocks.append(.rule)
                continue
            }
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                let content = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if level <= 6, !content.isEmpty {
                    flushParagraph()
                    flushLists()
                    blocks.append(.heading(level, content))
                    continue
                }
            }
            if let item = Self.bulletItem(line) {
                flushParagraph()
                if !numbered.isEmpty { flushLists() }
                bullets.append(item)
                continue
            }
            if let item = Self.numberedItem(line) {
                flushParagraph()
                if !bullets.isEmpty { flushLists() }
                numbered.append(item)
                continue
            }
            if !bullets.isEmpty || !numbered.isEmpty {
                // Ligne de continuation d'un élément de liste.
                if !bullets.isEmpty { bullets[bullets.count - 1] += "\n" + line }
                else { numbered[numbered.count - 1] += "\n" + line }
                continue
            }
            paragraph.append(line)
        }
        if inCode { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph()
        flushLists()
        return blocks
    }

    private static func bulletItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "• ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}

/// Rendu Markdown léger : suffisant pour les explications du tuteur (maths en Unicode).
struct MarkdownText: View {
    let text: String
    var font: Font = .body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            inline(content)
                .font(level == 1 ? .title2.bold() : (level == 2 ? .title3.bold() : .headline))
                .padding(.top, 4)
        case .paragraph(let content):
            inline(content).font(font)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").font(font)
                        inline(item).font(font)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).").font(font).monospacedDigit()
                        inline(item).font(font)
                    }
                }
            }
        case .code(let content):
            Text(content)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        }
    }

    private func inline(_ content: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: content, options: options) {
            return Text(attributed)
        }
        return Text(content)
    }
}
