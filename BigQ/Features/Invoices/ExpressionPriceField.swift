import AppKit
import SwiftUI

/// Price field that accepts a number or a formula. `=4750*2` becomes 9,500.00
/// when you leave the field or press Return.
struct ExpressionPriceField<Tag: Hashable>: View {
    @Binding var value: Decimal
    var prompt: String
    var focus: FocusState<Tag?>.Binding
    var tag: Tag
    var alignment: TextAlignment = .trailing

    @State private var text = ""
    @State private var editing = false

    var body: some View {
        TextField(prompt, text: $text)
            .multilineTextAlignment(alignment)
            .monospacedDigit()
            .focused(focus, equals: tag)
            .onSubmit(commit)
            .onAppear(perform: sync)
            .onChange(of: focus.wrappedValue) { _, newValue in
                let active = newValue == tag
                if active, !editing {
                    beginEditing()
                } else if editing, !active {
                    commit()
                }
                editing = active
            }
            .onChange(of: text) { _, newText in
                guard editing else { return }
                pushLive(newText)
            }
            .onChange(of: value) { _, newValue in
                guard !editing else { return }
                text = display(newValue)
            }
            .help("A price, or math like =4750*2")
            .accessibilityLabel(prompt)
    }

    private func sync() {
        text = display(value)
        guard focus.wrappedValue == tag else { return }
        editing = true
        selectAll()
    }

    private func beginEditing() {
        text = display(value)
        selectAll()
    }

    private func pushLive(_ newText: String) {
        guard MoneyExpression.appliesWhileTyping(newText) else { return }
        guard let resolved = MoneyExpression.resolve(newText) else { return }
        guard resolved != value else { return }
        value = resolved
    }

    private func commit() {
        if let resolved = MoneyExpression.resolve(text) {
            if resolved != value {
                value = resolved
            }
            text = display(resolved)
        } else {
            text = display(value)
        }
    }

    private func selectAll() {
        let token = tag
        Task { @MainActor in
            guard focus.wrappedValue == token else { return }
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func display(_ value: Decimal) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(2))
                .locale(Locale(identifier: "en_US"))
        )
    }
}
