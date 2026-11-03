import SwiftUI

struct AgreementVariableSidebar: View {
    var onInsert: (AgreementVariable) -> Void
    var onAskField: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Variables")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            Text("Blue chips pull from BigQ. Gold Ask fields prompt you when the template is used.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    askSection
                    ForEach(AgreementVariableCatalog.groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                            FlexibleChipWrap(variables: group.variables, style: .model, onInsert: onInsert)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(StudioDesign.Surface.card.opacity(0.55))
    }

    private var askSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask fields")
                .font(.subheadline.weight(.semibold))
            Button(action: onAskField) {
                Text(AgreementVariableCatalog.askFieldActionLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AgreementChipStyle.ask.fill, in: Capsule())
                    .foregroundStyle(AgreementChipStyle.ask.ink)
            }
            .buttonStyle(.plain)
            .help("Insert a prompt answered when this template is used")
        }
    }
}

enum AgreementChipStyle {
    case model
    case ask

    var fill: Color {
        switch self {
        case .model: Color(red: 0.72, green: 0.88, blue: 0.96)
        case .ask: Color(red: 0.93, green: 0.82, blue: 0.55)
        }
    }

    var ink: Color {
        switch self {
        case .model: Color(red: 0.12, green: 0.32, blue: 0.48)
        case .ask: Color(red: 0.42, green: 0.28, blue: 0.06)
        }
    }
}

/// Wraps chips to the real available width (guessed character widths were stacking everything).
private struct FlexibleChipWrap: View {
    var variables: [AgreementVariable]
    var style: AgreementChipStyle
    var onInsert: (AgreementVariable) -> Void

    var body: some View {
        ChipFlowLayout(spacing: 6) {
            ForEach(variables) { variable in
                Button {
                    onInsert(variable)
                } label: {
                    Text(variable.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(style.fill, in: Capsule())
                        .foregroundStyle(style.ink)
                }
                .buttonStyle(.plain)
                .help(variable.token)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left-to-right wrap using each chip’s measured size.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposalWidth: proposal.width, subviews: subviews)
        let width = proposal.width
            ?? rows.flatMap(\.self).map(\.size.width).reduce(0) { max($0, $1) }
        let height = rows.reduce(CGFloat.zero) { partial, row in
            let rowHeight = row.map(\.size.height).max() ?? 0
            return partial + rowHeight
        } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposalWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private struct Item {
        var index: Int
        var size: CGSize
    }

    private func arrange(proposalWidth: CGFloat?, subviews: Subviews) -> [[Item]] {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let limit = proposalWidth ?? .infinity
        var rows: [[Item]] = [[]]
        var x: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let next = x == 0 ? size.width : x + spacing + size.width
            if next > limit, !rows[rows.count - 1].isEmpty {
                rows.append([Item(index: index, size: size)])
                x = size.width
            } else {
                rows[rows.count - 1].append(Item(index: index, size: size))
                x = next
            }
        }
        return rows
    }
}
