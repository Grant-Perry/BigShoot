import Foundation
import SwiftData

@Model
final class Contract {
    #Unique<Contract>([\.shootqID])

    var shootqID: String?
    var title: String
    var status: String
    /// Agreement HTML exported from ShootQ. Signature ink was not in the export.
    var html: String
    var eventLabel: String
    var sentAt: Date?
    /// Stable id written into a backup. Empty until the first backup stamps it.
    var archiveID: String = ""

    var job: Job?

    @Relationship(deleteRule: .cascade, inverse: \ContractSignature.contract)
    var signatures: [ContractSignature]

    init(
        shootqID: String? = nil,
        title: String = "",
        status: String = "",
        html: String = "",
        eventLabel: String = "",
        sentAt: Date? = nil,
        job: Job? = nil
    ) {
        self.shootqID = shootqID
        self.title = title
        self.status = status
        self.html = html
        self.eventLabel = eventLabel
        self.sentAt = sentAt
        self.job = job
        self.signatures = []
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled contract" : trimmed
    }

    var isSigned: Bool {
        status.caseInsensitiveCompare("signed") == .orderedSame || signatures.contains(where: \.completed)
    }
}
