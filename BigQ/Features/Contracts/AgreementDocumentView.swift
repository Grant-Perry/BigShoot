import AppKit
import SwiftUI

/// Renders an agreement the way the PDF does — colon column + stacked values.
struct AgreementDocumentView: View {
    enum Style {
        /// Black ink on white paper (contract reader / PDF preview).
        case paper
        /// Adapts to the surrounding card (quote detail on the night scene).
        case ambient
    }

    var html: String
    var agreementTitle: String
    var studioName: String?
    var style: Style = .paper

    private var ink: Color {
        style == .paper ? .black : .primary
    }

    private var softInk: Color {
        style == .paper ? .black.opacity(0.85) : .secondary
    }

    private var rule: Color {
        style == .paper ? .black.opacity(0.35) : .secondary.opacity(0.45)
    }

    private var blocks: [AgreementPDFLayout.Block] {
        AgreementPDFLayout.blocks(
            mergedHTML: html,
            agreementTitle: agreementTitle,
            studioName: studioName
        )
    }

    private var fieldRows: [(label: String, value: String)] {
        blocks.compactMap { block in
            if case let .field(label, value) = block { return (label, value) }
            return nil
        }
    }

    private var labelWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 15, weight: .bold)
        let measured = fieldRows
            .map { AgreementPDFLayout.measure("\($0.label):", font: font) }
            .max() ?? 96
        // Keep a stable gutter so short labels still share the colon column.
        return max(ceil(measured), 96)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(grouped.enumerated()), id: \.offset) { _, item in
                switch item {
                case .block(let block):
                    singleBlock(block)
                case .fields(let rows):
                    fieldsColumn(rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private enum Item {
        case block(AgreementPDFLayout.Block)
        case fields([(label: String, value: String)])
    }

    /// Collapse consecutive field blocks into one stack so every colon shares a column.
    private var grouped: [Item] {
        var items: [Item] = []
        var pending: [(label: String, value: String)] = []

        func flush() {
            guard !pending.isEmpty else { return }
            items.append(.fields(pending))
            pending = []
        }

        for block in blocks {
            if case let .field(label, value) = block {
                pending.append((label, value))
            } else {
                flush()
                items.append(.block(block))
            }
        }
        flush()
        return items
    }

    /// Trailing labels + leading values on the SAME row. Continuations stack under values.
    private func fieldsColumn(_ rows: [(label: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let lines = valueLines(row.value)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(row.label):")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.trailing)
                        .frame(width: labelWidth, alignment: .trailing)

                    Text(lines.first ?? " ")
                        .font(.system(size: 15))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Color.clear
                            .frame(width: labelWidth, height: 1)
                        Text(line)
                            .font(.system(size: 15))
                            .foregroundStyle(ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
    }

    private func valueLines(_ value: String) -> [String] {
        value
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func singleBlock(_ block: AgreementPDFLayout.Block) -> some View {
        switch block {
        case .centeredHeadline(let text):
            Text(text)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)

        case .horizontalRule:
            Rectangle()
                .fill(rule)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 16)

        case .centeredSubhead(let text):
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(softInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)

        case .field:
            EmptyView()

        case .paragraph(let text):
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 4)
        }
    }
}
