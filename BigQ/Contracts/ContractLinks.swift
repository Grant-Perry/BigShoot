import Foundation
import SwiftData

/// Contracts a person can open: ones they signed, and ones filed on their jobs.
@MainActor
enum ContractLinks {
    static func forContact(_ contact: Contact) -> [Contract] {
        var byID: [PersistentIdentifier: Contract] = [:]
        for signature in contact.contractSignatures {
            if let contract = signature.contract, !contract.isTemplate {
                byID[contract.persistentModelID] = contract
            }
        }
        for job in contact.jobs {
            for contract in job.contracts where !contract.isTemplate {
                byID[contract.persistentModelID] = contract
            }
        }
        return byID.values.sorted(by: newerFirst)
    }

    static func forJob(_ job: Job) -> [Contract] {
        job.contracts.filter { !$0.isTemplate }.sorted(by: newerFirst)
    }

    private static func newerFirst(_ lhs: Contract, _ rhs: Contract) -> Bool {
        switch (lhs.sentAt, rhs.sentAt) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }
}
