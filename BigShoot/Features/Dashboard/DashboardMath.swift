import Foundation
import SwiftData

struct AnniversaryItem: Identifiable {
    var id: PersistentIdentifier { contact.persistentModelID }
    let contact: Contact
    let nextDate: Date
    let years: Int
}

enum DashboardMath {
    static func openBalance(in invoices: [Invoice]) -> Decimal {
        invoices.reduce(Decimal.zero) { partial, invoice in
            guard invoice.status != .void, invoice.balance > 0 else { return partial }
            return partial + invoice.balance
        }
    }

    static func overdue(in invoices: [Invoice], now: Date = .now) -> [Invoice] {
        invoices
            .filter { $0.displayStatus == .overdue }
            .sorted { lhs, rhs in
                (lhs.dueDate ?? now) < (rhs.dueDate ?? now)
            }
    }

    static func collectedThisMonth(in receipts: [PaymentReceipt], now: Date = .now) -> Decimal {
        let calendar = Calendar.current
        return receipts.reduce(Decimal.zero) { partial, receipt in
            guard calendar.isDate(receipt.paidAt, equalTo: now, toGranularity: .month) else { return partial }
            return partial + receipt.amount
        }
    }

    static func upcomingAnniversaries(
        in contacts: [Contact],
        limit: Int = 6,
        now: Date = .now
    ) -> [AnniversaryItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return contacts.compactMap { contact -> AnniversaryItem? in
            guard let anniversary = contact.anniversary, !contact.archived else { return nil }
            guard let next = nextOccurrence(of: anniversary, from: today, calendar: calendar) else { return nil }
            let years = calendar.dateComponents([.year], from: anniversary, to: next).year ?? 0
            return AnniversaryItem(contact: contact, nextDate: next, years: max(years, 0))
        }
        .sorted { $0.nextDate < $1.nextDate }
        .prefix(limit)
        .map { $0 }
    }

    static func nextOccurrence(of date: Date, from today: Date, calendar: Calendar = .current) -> Date? {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: today)
        if let thisYear = calendar.date(from: DateComponents(year: year, month: month, day: day)),
           thisYear >= today {
            return thisYear
        }
        return calendar.date(from: DateComponents(year: year + 1, month: month, day: day))
            ?? calendar.date(from: DateComponents(year: year + 1, month: month, day: min(day, 28)))
    }
}
