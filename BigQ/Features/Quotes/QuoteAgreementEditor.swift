import SwiftData
import SwiftUI

struct QuoteAgreementEditor: View {
    @Binding var title: String
    @Binding var html: String
    var templates: [Contract]
    var onApplyTemplate: (Contract) -> Void
    var onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Agreement")
                    .font(.headline)
                Spacer()
                if !templates.isEmpty {
                    Menu("Use template") {
                        ForEach(templates) { template in
                            Button(template.displayTitle) {
                                onApplyTemplate(template)
                            }
                        }
                    }
                }
                if !title.isEmpty || !html.isEmpty {
                    Button("Clear", role: .destructive, action: onClear)
                }
            }
            TextField("Title", text: $title)
            TextEditor(text: $html)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 180)
                .overlay(alignment: .topLeading) {
                    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Paste or write the agreement. Plain text or simple HTML.")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .studioCard(cornerRadius: 10)
        }
    }
}
