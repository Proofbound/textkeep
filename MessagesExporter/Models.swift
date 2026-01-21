import Foundation

struct Contact: Identifiable, Hashable {
    let id: Int
    let identifier: String  // Phone number or email
    let displayName: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Contact, rhs: Contact) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a single handle (phone number or email) from the Messages database
struct MessageHandle: Identifiable, Hashable {
    let id: Int           // handle ROWID from Messages DB
    let identifier: String // Raw phone/email from database
}

/// Represents a consolidated contact that may have multiple handles
struct ConsolidatedContact: Identifiable, Hashable {
    let id: String                    // CNContact.identifier or normalized phone
    let displayName: String           // Name from Contacts or formatted phone
    let handles: [MessageHandle]      // All associated handles
    let contactIdentifier: String?    // CNContact.identifier if matched

    /// Returns all handle IDs for database queries
    var handleIds: [Int] { handles.map { $0.id } }

    /// Returns all raw identifiers (phone numbers/emails)
    var identifiers: [String] { handles.map { $0.identifier } }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ConsolidatedContact, rhs: ConsolidatedContact) -> Bool {
        lhs.id == rhs.id
    }
}

struct Message: Identifiable {
    let id: Int
    let text: String
    let date: Date
    let isFromMe: Bool
    let attachments: [String]
}
