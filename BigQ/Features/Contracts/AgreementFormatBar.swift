import AppKit
import SwiftUI

struct AgreementFormatBar: View {
    var body: some View {
        HStack(spacing: 4) {
            formatButton("Bold", symbol: "bold") {
                AgreementFormatActions.toggleTrait(.boldFontMask)
            }
            formatButton("Italic", symbol: "italic") {
                AgreementFormatActions.toggleTrait(.italicFontMask)
            }
            formatButton("Underline", symbol: "underline") {
                AgreementFormatActions.toggleUnderline()
            }
            Divider().frame(height: 18)
            formatButton("Smaller", symbol: "textformat.size.smaller") {
                AgreementFormatActions.bumpFontSize(-1)
            }
            formatButton("Larger", symbol: "textformat.size.larger") {
                AgreementFormatActions.bumpFontSize(1)
            }
            Divider().frame(height: 18)
            formatButton("Align Left", symbol: "text.alignleft") {
                NSApp.sendAction(#selector(NSText.alignLeft(_:)), to: nil, from: nil)
            }
            formatButton("Align Center", symbol: "text.aligncenter") {
                NSApp.sendAction(#selector(NSText.alignCenter(_:)), to: nil, from: nil)
            }
            formatButton("Align Right", symbol: "text.alignright") {
                NSApp.sendAction(#selector(NSText.alignRight(_:)), to: nil, from: nil)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(StudioDesign.Surface.paper.opacity(0.7))
    }

    private func formatButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

@MainActor
enum AgreementFormatActions {
    private static let minimumSize: CGFloat = 12
    private static let maximumSize: CGFloat = 28

    static func toggleTrait(_ trait: NSFontTraitMask) {
        let item = NSMenuItem()
        item.tag = Int(trait.rawValue)
        NSFontManager.shared.addFontTrait(item)
    }

    /// Steps selection (or typing attributes) by 1pt, clamped to the agreement sans range.
    static func bumpFontSize(_ delta: CGFloat) {
        guard let textView = focusedTextView() else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let current = (attrs[.font] as? NSFont) ?? AgreementRichTextEditing.bodyFont()
            attrs[.font] = resized(current, by: delta)
            textView.typingAttributes = attrs
            return
        }
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let current = (value as? NSFont) ?? AgreementRichTextEditing.bodyFont()
            storage.addAttribute(.font, value: resized(current, by: delta), range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    static func toggleUnderline() {
        guard let textView = focusedTextView(),
              let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else {
            var attrs = textView.typingAttributes
            let current = attrs[.underlineStyle] as? Int ?? 0
            attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        var underlined = false
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, stop in
            if (value as? Int ?? 0) != 0 {
                underlined = true
                stop.pointee = true
            }
        }
        if underlined {
            storage.removeAttribute(.underlineStyle, range: range)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    private static func focusedTextView() -> NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    private static func resized(_ font: NSFont, by delta: CGFloat) -> NSFont {
        let size = min(max(font.pointSize + delta, minimumSize), maximumSize)
        let traits = NSFontManager.shared.traits(of: font)
            .intersection([.boldFontMask, .italicFontMask])
        let family = font.familyName
            ?? NSFont.systemFont(ofSize: size).familyName
            ?? "Helvetica Neue"
        return NSFontManager.shared.font(
            withFamily: family,
            traits: traits,
            weight: traits.contains(.boldFontMask) ? 9 : 5,
            size: size
        ) ?? AgreementRichTextEditing.bodyFont(size: size)
    }
}
