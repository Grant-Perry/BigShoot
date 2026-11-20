import Foundation

@MainActor
enum InvoiceMailDelivery {
    static func send(
        invoice: Invoice,
        recipient: String,
        replyTo: String,
        subject: String,
        body: String,
        extras: [MailFileDraft]
    ) async -> QuoteMailResult {
        guard let staged = write(invoice: invoice, extras: extras) else {
            return .failed("Couldn’t create the invoice PDF.")
        }
        let letter = InvoiceMailMerge.ensuringPayLink(body, invoice: invoice)
        let url = InvoiceMailMerge.payURL(for: invoice)
        let plain = QuoteMailMerge.plainText(letter, payURL: url, phrase: InvoiceMailMerge.payLinkPhrase)
        let linked = QuoteComposer.linkedLetter(plain, phrase: InvoiceMailMerge.payLinkPhrase, urlString: url)
        var items: [Any] = [linked, staged.pdfURL]
        items.append(contentsOf: staged.extras.map(\.url))
        var files = [
            StudioMailDispatch.File(url: staged.pdfURL, contentType: "application/pdf"),
        ]
        files.append(contentsOf: staged.extras.map {
            StudioMailDispatch.File(url: $0.url, contentType: $0.contentType)
        })
        return await StudioMailDispatch.send(
            items: items,
            files: files,
            recipients: [recipient],
            replyTo: replyTo,
            subject: subject,
            plainBody: plain,
            html: QuoteMailMerge.htmlLetter(letter, payURL: url, phrase: InvoiceMailMerge.payLinkPhrase),
            payURL: url,
            savedOn: "invoice"
        )
    }

    // MARK: - Private

    private struct Staged {
        var pdfURL: URL
        var extras: [StagedMailFile]
    }

    private static func write(invoice: Invoice, extras: [MailFileDraft]) -> Staged? {
        let directory = FileManager.default.temporaryDirectory
        let pdfURL = directory.appendingPathComponent(attachmentName(invoice: invoice))
        do {
            try InvoicePDFRenderer.render(invoice).write(to: pdfURL, options: .atomic)
        } catch {
            DebugPrint(mode: .error, "Could not write invoice PDF: \(error.localizedDescription)")
            return nil
        }
        guard let staged = MailFileStaging.write(extras, to: directory) else { return nil }
        return Staged(pdfURL: pdfURL, extras: staged)
    }

    private static func attachmentName(invoice: Invoice) -> String {
        let stored = invoice.studio?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let studio = stored.isEmpty ? StudioBrand.defaultName : stored
        let number = fileToken(invoice.displayNumber)
        let name = "\(studio) - Invoice \(number).pdf"
        return MailFileName.safe(name) ?? "Invoice-\(number).pdf"
    }

    private static func fileToken(_ number: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = number.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let token = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return token.isEmpty ? "Draft" : token
    }
}
