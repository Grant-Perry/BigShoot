import SwiftUI

/// How the quote letter will read once it leaves the Mac.
struct QuoteEmailPreview: View {
    var recipient: String
    var subject: String
    var bodyText: String
    var payURL: String
    var payPhrase: String = QuoteMailMerge.payLinkPhrase
    var documentTitle: String = "Quote PDF"
    var includesAgreement: Bool = false
    var extraNames: [String] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioDesign.Spacing.section) {
                    header
                    letter
                    attachments
                }
                .padding(StudioDesign.Spacing.card)
                .frame(maxWidth: 680, alignment: .leading)
            }
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .help("Close the preview")
                }
            }
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    private var header: some View {
        StudioLabeledStack {
            StudioLabeledRow("To") {
                Text(recipient.isEmpty ? "No recipient" : recipient)
                    .textSelection(.enabled)
            }
            StudioLabeledRow("Subject") {
                Text(subject)
                    .textSelection(.enabled)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                letterText(paragraph)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if bodyText.contains(payPhrase), payURL.isEmpty {
                Text("The pay link is created when you send.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Attachments", systemImage: "paperclip")
                .font(.headline)
            Label(documentTitle, systemImage: "doc.richtext")
                .font(.callout)
            if includesAgreement {
                Label("Agreement PDF", systemImage: "signature")
                    .font(.callout)
            }
            ForEach(Array(extraNames.enumerated()), id: \.offset) { _, name in
                Label(name, systemImage: "paperclip")
                    .font(.callout)
            }
        }
        .padding(StudioDesign.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var paragraphs: [String] {
        bodyText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func letterText(_ paragraph: String) -> Text {
        var copy = AttributedString(paragraph)
        guard let url = URL(string: payURL), !payURL.isEmpty else { return Text(copy) }
        var search = copy.startIndex
        while let range = copy[search...].range(of: payPhrase) {
            copy[range].link = url
            copy[range].underlineStyle = .single
            copy[range].foregroundColor = StudioDesign.gold
            search = range.upperBound
            if search >= copy.endIndex { break }
        }
        return Text(copy)
    }
}
