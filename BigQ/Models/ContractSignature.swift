import Foundation
import SwiftData

@Model
final class ContractSignature {
    var displayName: String
    var completed: Bool
    var signedAt: Date?
    var ipAddress: String
    var shootqContactID: String?

    var contact: Contact?
    var contract: Contract?

    init(
        displayName: String = "",
        completed: Bool = false,
        signedAt: Date? = nil,
        ipAddress: String = "",
        shootqContactID: String? = nil,
        contact: Contact? = nil
    ) {
        self.displayName = displayName
        self.completed = completed
        self.signedAt = signedAt
        self.ipAddress = ipAddress
        self.shootqContactID = shootqContactID
        self.contact = contact
    }
}
