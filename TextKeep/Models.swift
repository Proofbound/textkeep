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

/// Protocol that unifies individual contacts and group chats
protocol Conversation: Identifiable, Hashable {
    var id: String { get }
    var displayName: String { get }
    var isGroup: Bool { get }
    var participantCount: Int { get }
    var participantNames: [String] { get }
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

/// Extend ConsolidatedContact to conform to Conversation protocol
extension ConsolidatedContact: Conversation {
    var isGroup: Bool { false }
    var participantCount: Int { 1 }
    var participantNames: [String] {
        // Include both display name and identifiers for search
        return [displayName] + identifiers
    }
}

/// Represents a group chat conversation
struct GroupChat: Conversation {
    let id: String                    // "group_{chatId}"
    let chatId: Int                   // chat.ROWID for queries
    let displayName: String
    let participants: [GroupParticipant]

    var isGroup: Bool { true }
    var participantCount: Int { participants.count }
    var participantNames: [String] {
        participants.map { $0.displayName }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: GroupChat, rhs: GroupChat) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a participant in a group chat
struct GroupParticipant: Identifiable {
    let id: Int                       // Same as handleId
    let handleId: Int                 // handle.ROWID
    let identifier: String            // Phone/email
    let displayName: String           // From ContactsService
}

struct Message: Identifiable {
    let id: Int                       // message.ROWID
    let text: String
    let date: Date
    let isFromMe: Bool
    let attachments: [String]
    let senderHandleId: Int           // message.handle_id
    let senderIdentifier: String?     // handle.id (phone/email)
    let senderName: String?           // Resolved via ContactsService
}
