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

    /// Best agreement to seed a quote: readable draft first, otherwise the newest on the job.
    static func preferredAgreement(for job: Job) -> Contract? {
        let contracts = forJob(job).filter {
            ContractDocument.hasReadableBody($0.html)
                || !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let draft = contracts.first(where: { !$0.isSigned }) {
            return draft
        }
        return contracts.first
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
