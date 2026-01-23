import Foundation
import SQLite3
import SwiftUI

class MessagesViewModel: ObservableObject {
    @Published var conversations: [any Conversation] = []
    @Published var selectedContactId: String?
    @Published var hasAccess = false
    @Published var isExporting = false
    @Published var errorMessage: String?
    @Published var previewMessages: [Message] = []
    @Published var contactsAuthorized = false

    var contactsService = ContactsService()
    private let dbPath: String

    var selectedConversation: (any Conversation)? {
        guard let id = selectedContactId else { return nil }
        return conversations.first { $0.id == id }
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        dbPath = home.appendingPathComponent("Library/Messages/chat.db").path
    }

    func checkAccessAndLoadContacts() {
        hasAccess = FileManager.default.isReadableFile(atPath: dbPath)
        // Check initial contacts authorization
        contactsAuthorized = contactsService.authorizationStatus == .authorized

        if hasAccess {
            // Request contacts access and then load
            Task {
                _ = await contactsService.requestAccess()
                await MainActor.run {
                    contactsAuthorized = contactsService.authorizationStatus == .authorized
                    contactsService.loadContacts()
                }
                loadAllConversations()
            }
        }
    }

    private func loadAllConversations() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let individuals = self.loadIndividualConversations()
            let groups = self.loadGroupConversations()

            // Merge and sort with stable secondary key
            var allConversations: [any Conversation] = individuals + groups
            allConversations.sort { lhs, rhs in
                let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if nameComparison == .orderedSame {
                    return lhs.id < rhs.id  // Stable secondary sort
                }
                return nameComparison == .orderedAscending
            }

            DispatchQueue.main.async {
                self.conversations = allConversations
            }
        }
    }

    private func loadIndividualConversations() -> [ConsolidatedContact] {
        var db: OpaquePointer?

        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_close(db) }

        // Only get handles from 1-on-1 chats (single participant)
        let query = """
            SELECT DISTINCT h.ROWID, h.id
            FROM handle h
            JOIN chat_handle_join chj ON h.ROWID = chj.handle_id
            JOIN chat c ON chj.chat_id = c.ROWID
            WHERE (
                SELECT COUNT(*) FROM chat_handle_join
                WHERE chat_id = c.ROWID
            ) = 1
            ORDER BY h.id
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var handles: [MessageHandle] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let identifier = String(cString: sqlite3_column_text(statement, 1))
            handles.append(MessageHandle(id: id, identifier: identifier))
        }

        return consolidateHandles(handles)
    }

    private func loadGroupConversations() -> [GroupChat] {
        var db: OpaquePointer?

        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_close(db) }

        // Get all group chats (multiple participants)
        let query = """
            SELECT c.ROWID, c.display_name, c.room_name
            FROM chat c
            JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
            GROUP BY c.ROWID
            HAVING COUNT(chj.handle_id) > 1
            ORDER BY c.ROWID DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var groups: [GroupChat] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let chatId = Int(sqlite3_column_int(statement, 0))

            var displayName = ""
            if let namePtr = sqlite3_column_text(statement, 1) {
                displayName = String(cString: namePtr)
            }

            if displayName.isEmpty, let roomNamePtr = sqlite3_column_text(statement, 2) {
                displayName = String(cString: roomNamePtr)
            }

            let participants = loadParticipants(for: chatId, db: db)

            if displayName.isEmpty {
                // Generate name from participants
                let names = participants.prefix(3)
                    .map { $0.displayName.isEmpty ? $0.identifier : $0.displayName }
                    .filter { !$0.isEmpty }

                if !names.isEmpty {
                    displayName = "Group with " + names.joined(separator: ", ")
                    if participants.count > 3 {
                        displayName += " and \(participants.count - 3) more"
                    }
                } else {
                    // Fallback if all names are empty
                    displayName = "Unnamed Group Chat"
                }
            }

            groups.append(GroupChat(
                id: "group_\(chatId)",
                chatId: chatId,
                displayName: displayName,
                participants: participants
            ))
        }

        return groups
    }

    private func loadParticipants(for chatId: Int, db: OpaquePointer?) -> [GroupParticipant] {
        let query = """
            SELECT h.ROWID, h.id
            FROM handle h
            JOIN chat_handle_join chj ON h.ROWID = chj.handle_id
            WHERE chj.chat_id = ?
            ORDER BY h.id
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(chatId))

        var participants: [GroupParticipant] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let handleId = Int(sqlite3_column_int(statement, 0))
            let identifier = String(cString: sqlite3_column_text(statement, 1))
            let displayName = contactsService.getDisplayName(for: identifier)

            participants.append(GroupParticipant(
                id: handleId,
                handleId: handleId,
                identifier: identifier,
                displayName: displayName
            ))
        }

        return participants
    }

    private func consolidateHandles(_ handles: [MessageHandle]) -> [ConsolidatedContact] {
        // Group handles by contact identifier (from Contacts app) or by normalized phone number
        var groupedByContactId: [String: [MessageHandle]] = [:]
        var groupedByNormalizedPhone: [String: [MessageHandle]] = [:]
        var contactIdToName: [String: String] = [:]

        for handle in handles {
            if let contactId = contactsService.getContactIdentifier(for: handle.identifier) {
                // This handle matches a contact in the Contacts app
                groupedByContactId[contactId, default: []].append(handle)
                if contactIdToName[contactId] == nil {
                    contactIdToName[contactId] = contactsService.getDisplayName(for: handle.identifier)
                }
            } else {
                // No contact found - group by normalized identifier
                let normalized: String
                if handle.identifier.contains("@") {
                    normalized = handle.identifier.lowercased()
                } else {
                    normalized = contactsService.normalizePhoneNumber(handle.identifier)
                }
                groupedByNormalizedPhone[normalized, default: []].append(handle)
            }
        }

        var result: [ConsolidatedContact] = []

        // Create consolidated contacts for matched contacts
        for (contactId, handleList) in groupedByContactId {
            let displayName = contactIdToName[contactId] ?? handleList.first?.identifier ?? "Unknown"
            result.append(ConsolidatedContact(
                id: contactId,
                displayName: displayName,
                handles: handleList,
                contactIdentifier: contactId
            ))
        }

        // Create consolidated contacts for unmatched identifiers
        for (normalizedId, handleList) in groupedByNormalizedPhone {
            let displayName = contactsService.getDisplayName(for: handleList.first?.identifier ?? normalizedId)
            result.append(ConsolidatedContact(
                id: normalizedId,
                displayName: displayName,
                handles: handleList,
                contactIdentifier: nil
            ))
        }

        // Sort by display name
        result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return result
    }

    func loadPreviewMessages(for conversation: any Conversation, limit: Int = 5) {
        if conversation.isGroup {
            loadPreviewMessagesForGroup(conversation as! GroupChat, limit: limit)
        } else {
            loadPreviewMessagesForContact(conversation as! ConsolidatedContact, limit: limit)
        }
    }

    private func loadPreviewMessagesForContact(_ contact: ConsolidatedContact, limit: Int = 5) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var db: OpaquePointer?

            guard sqlite3_open_v2(self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return
            }

            defer { sqlite3_close(db) }

            let handleIds = contact.handleIds
            let placeholders = handleIds.map { _ in "?" }.joined(separator: ", ")

            let query = """
                SELECT DISTINCT m.ROWID, m.text, m.date, m.is_from_me, m.cache_has_attachments, m.attributedBody,
                    m.associated_message_type, m.group_action_type
                FROM message m
                JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                JOIN chat c ON cmj.chat_id = c.ROWID
                JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
                JOIN handle h ON chj.handle_id = h.ROWID
                WHERE h.ROWID IN (\(placeholders))
                ORDER BY m.date DESC
                LIMIT ?
            """

            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return
            }

            defer { sqlite3_finalize(statement) }

            for (index, handleId) in handleIds.enumerated() {
                sqlite3_bind_int(statement, Int32(index + 1), Int32(handleId))
            }
            sqlite3_bind_int(statement, Int32(handleIds.count + 1), Int32(limit))

            var messages: [Message] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))

                // Read metadata fields
                let associatedType = sqlite3_column_type(statement, 6) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 6) : nil
                let groupActionType = sqlite3_column_type(statement, 7) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 7) : nil

                // Skip removed reactions (3000-3005)
                if let type = associatedType, type >= 3000 && type < 3006 {
                    continue
                }

                var text = ""
                if let textPtr = sqlite3_column_text(statement, 1) {
                    text = String(cString: textPtr)
                }

                if text.isEmpty {
                    if let blobPointer = sqlite3_column_blob(statement, 5) {
                        let blobSize = sqlite3_column_bytes(statement, 5)
                        let data = Data(bytes: blobPointer, count: Int(blobSize))
                        text = self.extractTextFromAttributedBody(data)
                    }
                }

                // Format with metadata (reactions, group actions)
                text = self.formatMessageWithMetadata(
                    text: text,
                    associatedType: associatedType,
                    groupActionType: groupActionType
                )

                // Sanitize text
                text = text
                    .replacingOccurrences(of: "\0", with: "")
                    .replacingOccurrences(of: "\u{FFFC}", with: "") // Object Replacement Character
                    .replacingOccurrences(of: "\u{FFFD}", with: "") // Replacement Character
                    .replacingOccurrences(of: "\u{200B}", with: "") // Zero-width space
                    .replacingOccurrences(of: "\u{200C}", with: "") // Zero-width non-joiner
                    // Note: keeping U+200D (zero-width joiner) as it's used in emoji sequences
                    .replacingOccurrences(of: "\u{FEFF}", with: "") // BOM
                    .filter { char in
                        guard let ascii = char.asciiValue else { return true }
                        return ascii >= 32 || char == "\n" || char == "\t"
                    }
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let dateNano = sqlite3_column_double(statement, 2)
                let date = Date(timeIntervalSinceReferenceDate: dateNano / 1_000_000_000)

                let isFromMe = sqlite3_column_int(statement, 3) == 1
                let hasAttachments = sqlite3_column_int(statement, 4) == 1

                var attachments: [String] = []
                if hasAttachments {
                    attachments = self.getAttachments(for: id, db: db)
                }

                // For 1-on-1 chats, sender is implicit (always 0)
                messages.append(Message(
                    id: id,
                    text: text,
                    date: date,
                    isFromMe: isFromMe,
                    attachments: attachments,
                    senderHandleId: 0,
                    senderIdentifier: nil,
                    senderName: nil
                ))
            }

            // Reverse to show oldest first (chronological order)
            messages.reverse()

            DispatchQueue.main.async {
                self.previewMessages = messages
            }
        }
    }

    private func loadPreviewMessagesForGroup(_ group: GroupChat, limit: Int = 5) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var db: OpaquePointer?

            guard sqlite3_open_v2(self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return
            }

            defer { sqlite3_close(db) }

            // Build sender cache for this group
            var senderCache: [Int: (String, String)] = [:]  // handleId -> (identifier, displayName)
            for participant in group.participants {
                senderCache[participant.handleId] = (participant.identifier, participant.displayName)
            }

            let query = """
                SELECT DISTINCT m.ROWID, m.text, m.date, m.is_from_me, m.cache_has_attachments,
                       m.attributedBody, m.handle_id, h.id as sender_identifier,
                       m.associated_message_type, m.group_action_type
                FROM message m
                JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                JOIN chat c ON cmj.chat_id = c.ROWID
                LEFT JOIN handle h ON m.handle_id = h.ROWID
                WHERE c.ROWID = ?
                ORDER BY m.date DESC
                LIMIT ?
            """

            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(group.chatId))
            sqlite3_bind_int(statement, 2, Int32(limit))

            var messages: [Message] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))

                // Read metadata fields
                let associatedType = sqlite3_column_type(statement, 8) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 8) : nil
                let groupActionType = sqlite3_column_type(statement, 9) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 9) : nil

                // Skip removed reactions (3000-3005)
                if let type = associatedType, type >= 3000 && type < 3006 {
                    continue
                }

                var text = ""
                if let textPtr = sqlite3_column_text(statement, 1) {
                    text = String(cString: textPtr)
                }

                if text.isEmpty {
                    if let blobPointer = sqlite3_column_blob(statement, 5) {
                        let blobSize = sqlite3_column_bytes(statement, 5)
                        let data = Data(bytes: blobPointer, count: Int(blobSize))
                        text = self.extractTextFromAttributedBody(data)
                    }
                }

                // Format with metadata (reactions, group actions)
                text = self.formatMessageWithMetadata(
                    text: text,
                    associatedType: associatedType,
                    groupActionType: groupActionType
                )

                // Sanitize text
                text = text
                    .replacingOccurrences(of: "\0", with: "")
                    .replacingOccurrences(of: "\u{FFFC}", with: "")
                    .replacingOccurrences(of: "\u{FFFD}", with: "")
                    .replacingOccurrences(of: "\u{200B}", with: "")
                    .replacingOccurrences(of: "\u{200C}", with: "")
                    .replacingOccurrences(of: "\u{FEFF}", with: "")
                    .filter { char in
                        guard let ascii = char.asciiValue else { return true }
                        return ascii >= 32 || char == "\n" || char == "\t"
                    }
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let dateNano = sqlite3_column_double(statement, 2)
                let date = Date(timeIntervalSinceReferenceDate: dateNano / 1_000_000_000)

                let isFromMe = sqlite3_column_int(statement, 3) == 1
                let hasAttachments = sqlite3_column_int(statement, 4) == 1

                var attachments: [String] = []
                if hasAttachments {
                    attachments = self.getAttachments(for: id, db: db)
                }

                // Get sender information
                let senderHandleId = Int(sqlite3_column_int(statement, 6))
                var senderIdentifier: String? = nil
                if let identifierPtr = sqlite3_column_text(statement, 7) {
                    senderIdentifier = String(cString: identifierPtr)
                }

                // Resolve sender name from cache
                var senderName: String? = nil
                if !isFromMe {
                    if let cached = senderCache[senderHandleId] {
                        senderName = cached.1  // displayName
                        if senderIdentifier == nil {
                            senderIdentifier = cached.0  // identifier
                        }
                    } else if let identifier = senderIdentifier {
                        // Fallback: use identifier as name
                        senderName = identifier
                    }
                }

                messages.append(Message(
                    id: id,
                    text: text,
                    date: date,
                    isFromMe: isFromMe,
                    attachments: attachments,
                    senderHandleId: senderHandleId,
                    senderIdentifier: senderIdentifier,
                    senderName: senderName
                ))
            }

            // Reverse to show oldest first (chronological order)
            messages.reverse()

            DispatchQueue.main.async {
                self.previewMessages = messages
            }
        }
    }

    func exportMessages(for conversation: any Conversation, from startDate: Date, to endDate: Date, to url: URL, completion: @escaping (Bool) -> Void) {
        if conversation.isGroup {
            exportMessagesForGroup(conversation as! GroupChat, from: startDate, to: endDate, to: url, completion: completion)
        } else {
            exportMessagesForContact(conversation as! ConsolidatedContact, from: startDate, to: endDate, to: url, completion: completion)
        }
    }

    private func exportMessagesForContact(_ contact: ConsolidatedContact, from startDate: Date, to endDate: Date, to url: URL, completion: @escaping (Bool) -> Void) {
        isExporting = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var db: OpaquePointer?

            guard sqlite3_open_v2(self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to open database"
                    self.isExporting = false
                    completion(false)
                }
                return
            }

            defer { sqlite3_close(db) }

            // Convert dates to Apple's CoreData timestamp (seconds since 2001-01-01)
            let appleEpoch = Date(timeIntervalSinceReferenceDate: 0)
            let startTimestamp = startDate.timeIntervalSince(appleEpoch) * 1_000_000_000
            let endTimestamp = endDate.timeIntervalSince(appleEpoch) * 1_000_000_000

            // Build placeholders for all handle IDs
            let handleIds = contact.handleIds
            let placeholders = handleIds.map { _ in "?" }.joined(separator: ", ")

            let query = """
                SELECT DISTINCT m.ROWID, m.text, m.date, m.is_from_me, m.cache_has_attachments, m.attributedBody,
                    m.associated_message_type, m.group_action_type
                FROM message m
                JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                JOIN chat c ON cmj.chat_id = c.ROWID
                JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
                JOIN handle h ON chj.handle_id = h.ROWID
                WHERE h.ROWID IN (\(placeholders))
                AND m.date >= ?
                AND m.date <= ?
                ORDER BY m.date ASC
            """

            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to prepare query"
                    self.isExporting = false
                    completion(false)
                }
                return
            }

            defer { sqlite3_finalize(statement) }

            // Bind all handle IDs
            for (index, handleId) in handleIds.enumerated() {
                sqlite3_bind_int(statement, Int32(index + 1), Int32(handleId))
            }
            // Bind date parameters after handle IDs
            sqlite3_bind_double(statement, Int32(handleIds.count + 1), startTimestamp)
            sqlite3_bind_double(statement, Int32(handleIds.count + 2), endTimestamp)

            var messages: [Message] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))

                // Read metadata fields
                let associatedType = sqlite3_column_type(statement, 6) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 6) : nil
                let groupActionType = sqlite3_column_type(statement, 7) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 7) : nil

                // Skip removed reactions (3000-3005)
                if let type = associatedType, type >= 3000 && type < 3006 {
                    continue
                }

                var text = ""
                // Try the text column first
                if let textPtr = sqlite3_column_text(statement, 1) {
                    text = String(cString: textPtr)
                }

                // If text is empty, try to extract from attributedBody (newer macOS)
                if text.isEmpty {
                    if let blobPointer = sqlite3_column_blob(statement, 5) {
                        let blobSize = sqlite3_column_bytes(statement, 5)
                        let data = Data(bytes: blobPointer, count: Int(blobSize))
                        text = self.extractTextFromAttributedBody(data)
                    }
                }

                // Format with metadata (reactions, group actions)
                text = self.formatMessageWithMetadata(
                    text: text,
                    associatedType: associatedType,
                    groupActionType: groupActionType
                )

                let dateNano = sqlite3_column_double(statement, 2)
                let date = Date(timeIntervalSinceReferenceDate: dateNano / 1_000_000_000)

                let isFromMe = sqlite3_column_int(statement, 3) == 1
                let hasAttachments = sqlite3_column_int(statement, 4) == 1

                var attachments: [String] = []
                if hasAttachments {
                    attachments = self.getAttachments(for: id, db: db)
                }

                // For 1-on-1 chats, sender is implicit
                messages.append(Message(
                    id: id,
                    text: text,
                    date: date,
                    isFromMe: isFromMe,
                    attachments: attachments,
                    senderHandleId: 0,
                    senderIdentifier: nil,
                    senderName: nil
                ))
            }

            // Create attachments folder and copy images
            let attachmentsFolder = url.deletingLastPathComponent().appendingPathComponent("attachments")
            let copiedAttachments = self.copyAttachments(from: messages, to: attachmentsFolder)

            // Generate markdown with image references
            let markdown = self.generateMarkdown(conversation: contact, messages: messages, startDate: startDate, endDate: endDate, attachmentMapping: copiedAttachments)

            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to write file: \(error.localizedDescription)"
                    self.isExporting = false
                    completion(false)
                }
            }
        }
    }

    private func exportMessagesForGroup(_ group: GroupChat, from startDate: Date, to endDate: Date, to url: URL, completion: @escaping (Bool) -> Void) {
        isExporting = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var db: OpaquePointer?

            guard sqlite3_open_v2(self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to open database"
                    self.isExporting = false
                    completion(false)
                }
                return
            }

            defer { sqlite3_close(db) }

            // Build sender cache for this group
            var senderCache: [Int: (String, String)] = [:]  // handleId -> (identifier, displayName)
            for participant in group.participants {
                senderCache[participant.handleId] = (participant.identifier, participant.displayName)
            }

            // Convert dates to Apple's CoreData timestamp (seconds since 2001-01-01)
            let appleEpoch = Date(timeIntervalSinceReferenceDate: 0)
            let startTimestamp = startDate.timeIntervalSince(appleEpoch) * 1_000_000_000
            let endTimestamp = endDate.timeIntervalSince(appleEpoch) * 1_000_000_000

            let query = """
                SELECT DISTINCT m.ROWID, m.text, m.date, m.is_from_me, m.cache_has_attachments,
                       m.attributedBody, m.handle_id, h.id as sender_identifier,
                       m.associated_message_type, m.group_action_type
                FROM message m
                JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                JOIN chat c ON cmj.chat_id = c.ROWID
                LEFT JOIN handle h ON m.handle_id = h.ROWID
                WHERE c.ROWID = ?
                AND m.date >= ?
                AND m.date <= ?
                ORDER BY m.date ASC
            """

            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to prepare query"
                    self.isExporting = false
                    completion(false)
                }
                return
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(group.chatId))
            sqlite3_bind_double(statement, 2, startTimestamp)
            sqlite3_bind_double(statement, 3, endTimestamp)

            var messages: [Message] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))

                // Read metadata fields
                let associatedType = sqlite3_column_type(statement, 8) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 8) : nil
                let groupActionType = sqlite3_column_type(statement, 9) != SQLITE_NULL ?
                    sqlite3_column_int(statement, 9) : nil

                // Skip removed reactions (3000-3005)
                if let type = associatedType, type >= 3000 && type < 3006 {
                    continue
                }

                var text = ""
                if let textPtr = sqlite3_column_text(statement, 1) {
                    text = String(cString: textPtr)
                }

                if text.isEmpty {
                    if let blobPointer = sqlite3_column_blob(statement, 5) {
                        let blobSize = sqlite3_column_bytes(statement, 5)
                        let data = Data(bytes: blobPointer, count: Int(blobSize))
                        text = self.extractTextFromAttributedBody(data)
                    }
                }

                // Format with metadata (reactions, group actions)
                text = self.formatMessageWithMetadata(
                    text: text,
                    associatedType: associatedType,
                    groupActionType: groupActionType
                )

                let dateNano = sqlite3_column_double(statement, 2)
                let date = Date(timeIntervalSinceReferenceDate: dateNano / 1_000_000_000)

                let isFromMe = sqlite3_column_int(statement, 3) == 1
                let hasAttachments = sqlite3_column_int(statement, 4) == 1

                var attachments: [String] = []
                if hasAttachments {
                    attachments = self.getAttachments(for: id, db: db)
                }

                // Get sender information
                let senderHandleId = Int(sqlite3_column_int(statement, 6))
                var senderIdentifier: String? = nil
                if let identifierPtr = sqlite3_column_text(statement, 7) {
                    senderIdentifier = String(cString: identifierPtr)
                }

                // Resolve sender name from cache
                var senderName: String? = nil
                if !isFromMe {
                    if let cached = senderCache[senderHandleId] {
                        senderName = cached.1  // displayName
                        if senderIdentifier == nil {
                            senderIdentifier = cached.0  // identifier
                        }
                    } else if let identifier = senderIdentifier {
                        // Fallback: use identifier as name
                        senderName = identifier
                    }
                }

                messages.append(Message(
                    id: id,
                    text: text,
                    date: date,
                    isFromMe: isFromMe,
                    attachments: attachments,
                    senderHandleId: senderHandleId,
                    senderIdentifier: senderIdentifier,
                    senderName: senderName
                ))
            }

            // Create attachments folder and copy images
            let attachmentsFolder = url.deletingLastPathComponent().appendingPathComponent("attachments")
            let copiedAttachments = self.copyAttachments(from: messages, to: attachmentsFolder)

            // Generate markdown with image references
            let markdown = self.generateMarkdown(conversation: group, messages: messages, startDate: startDate, endDate: endDate, attachmentMapping: copiedAttachments)

            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to write file: \(error.localizedDescription)"
                    self.isExporting = false
                    completion(false)
                }
            }
        }
    }

    private func copyAttachments(from messages: [Message], to folder: URL) -> [String: String] {
        var mapping: [String: String] = [:] // original path -> relative path

        let fm = FileManager.default

        // Collect all attachments
        var allAttachments: [String] = []
        for message in messages {
            allAttachments.append(contentsOf: message.attachments)
        }

        guard !allAttachments.isEmpty else { return mapping }

        // Create attachments folder
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        for (index, attachment) in allAttachments.enumerated() {
            // Expand ~ to home directory
            let expandedPath = (attachment as NSString).expandingTildeInPath
            let sourceURL = URL(fileURLWithPath: expandedPath)

            guard fm.fileExists(atPath: expandedPath) else { continue }

            let filename = sourceURL.lastPathComponent
            let ext = sourceURL.pathExtension.lowercased()

            // Generate unique filename to avoid collisions
            let uniqueFilename = "\(index + 1)_\(filename)"
            let destURL = folder.appendingPathComponent(uniqueFilename)

            do {
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: sourceURL, to: destURL)
                mapping[attachment] = "attachments/\(uniqueFilename)"
            } catch {
                print("Failed to copy attachment: \(error)")
            }
        }

        return mapping
    }

    // MARK: - Message Metadata Formatting

    private func formatMessageWithMetadata(text: String, associatedType: Int32?, groupActionType: Int32?) -> String {
        // Handle reaction messages (2000-2005)
        if let type = associatedType, type >= 2000 && type < 3000 {
            let (emoji, verb) = reactionEmojiAndVerb(for: type)

            // Extract quoted message if present
            if text.hasPrefix("Loved ") || text.hasPrefix("Liked ") ||
               text.hasPrefix("Disliked ") || text.hasPrefix("Laughed at ") ||
               text.hasPrefix("Emphasized ") || text.hasPrefix("Questioned ") {
                // Remove the verb prefix, keep the quoted message
                let quotedPart = text.components(separatedBy: " ").dropFirst().joined(separator: " ")
                return "\(emoji) \(verb): \(quotedPart)"
            }

            return "\(emoji) \(verb) this message"
        }

        // Handle group action messages (1 = member change)
        if let type = groupActionType, type == 1 {
            return "ℹ️ [System] \(text)"
        }

        // Regular message - return as-is
        return text
    }

    private func reactionEmojiAndVerb(for type: Int32) -> (String, String) {
        switch type {
        case 2000: return ("❤️", "Loved")
        case 2001: return ("👍", "Liked")
        case 2002: return ("👎", "Disliked")
        case 2003: return ("😂", "Laughed at")
        case 2004: return ("‼️", "Emphasized")
        case 2005: return ("❓", "Questioned")
        case 3000...3005: return ("", "Removed reaction")  // Skip in export
        default: return ("", "")
        }
    }

    // MARK: - AttributedBody Text Extraction

    private func extractTextFromAttributedBody(_ data: Data) -> String {
        // Three-strategy approach to extract text from Apple's typedstream format

        // Strategy 1: Try NSKeyedUnarchiver (safest, most reliable)
        if let text = extractViaKeyedUnarchiver(data), !text.isEmpty {
            return text
        }

        // Strategy 2: Pattern-based extraction (handles most cases)
        if let text = extractViaPatternMatching(data), !text.isEmpty {
            return text
        }

        // Strategy 3: Heuristic scanning (fallback for edge cases)
        if let text = extractViaHeuristicScanning(data), !text.isEmpty {
            return text
        }

        return ""
    }

    private func extractViaKeyedUnarchiver(_ data: Data) -> String? {
        do {
            // Modern attributed strings use NSKeyedArchiver
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false

            if let attributedString = try unarchiver.decodeTopLevelObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString {
                let text = attributedString.string
                return text.isEmpty ? nil : text
            }

            // Try alternate key
            if let attributedString = try unarchiver.decodeTopLevelObject(forKey: "NS.string") as? NSAttributedString {
                let text = attributedString.string
                return text.isEmpty ? nil : text
            }
        } catch {
            // Silently fail and try next strategy
        }

        return nil
    }

    private func extractViaPatternMatching(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 20 else { return nil }

        // Find all NSString/NSMutableString markers
        let markers = findStringMarkers(in: bytes)

        // Try each marker location
        for markerEnd in markers {
            var i = markerEnd

            // Skip class metadata bytes (typically 5-10 bytes)
            i += min(10, bytes.count - i - 10)

            while i < bytes.count - 5 {
                // Look for length-prefixed strings
                // Single-byte length (0x01-0x7F)
                if bytes[i] > 0 && bytes[i] < 0x80 {
                    let length = Int(bytes[i])
                    if length >= 5 && i + 1 + length <= bytes.count {
                        if let text = extractAndValidateText(bytes, start: i + 1, length: length) {
                            return text
                        }
                    }
                }
                // Multi-byte varint (0x80-0xFF marks continuation)
                else if bytes[i] >= 0x80 && i + 2 < bytes.count {
                    let length = decodeVarint(bytes, startingAt: i)
                    let varintSize = varintByteCount(bytes, startingAt: i)

                    if length >= 5 && length < 10000 && i + varintSize + length <= bytes.count {
                        if let text = extractAndValidateText(bytes, start: i + varintSize, length: length) {
                            return text
                        }
                    }
                }

                i += 1
            }
        }

        return nil
    }

    private func findStringMarkers(in bytes: [UInt8]) -> [Int] {
        let patterns = [
            Array("NSString".utf8),
            Array("NSMutableString".utf8)
        ]

        var markers: [Int] = []
        for pattern in patterns {
            var i = 0
            while i < bytes.count - pattern.count {
                if matchesPattern(bytes, at: i, pattern: pattern) {
                    markers.append(i + pattern.count)
                }
                i += 1
            }
        }

        return markers.sorted()
    }

    private func extractAndValidateText(_ bytes: [UInt8], start: Int, length: Int) -> String? {
        guard start + length <= bytes.count else { return nil }

        let textBytes = Array(bytes[start..<(start + length)])
        guard let text = String(bytes: textBytes, encoding: .utf8) else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // More rigorous validation
        guard trimmed.count >= 5 else { return nil }  // Minimum meaningful message
        guard isActualMessageText(trimmed) else { return nil }

        return trimmed
    }

    private func decodeVarint(_ bytes: [UInt8], startingAt index: Int) -> Int {
        var result = 0
        var shift = 0
        var i = index

        while i < bytes.count {
            let byte = bytes[i]
            result |= Int(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                break
            }

            shift += 7
            i += 1

            if shift > 28 { return 0 }  // Invalid varint
        }

        return result
    }

    private func varintByteCount(_ bytes: [UInt8], startingAt index: Int) -> Int {
        var count = 0
        var i = index

        while i < bytes.count {
            count += 1
            if (bytes[i] & 0x80) == 0 {
                break
            }
            i += 1
            if count > 5 { return 1 }  // Invalid, treat as single byte
        }

        return count
    }

    private func extractViaHeuristicScanning(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        var bestText = ""

        // Only scan after finding reasonable starting points
        let potentialStarts = findPotentialTextStarts(in: bytes)

        for start in potentialStarts {
            // Try various lengths, prioritizing longer strings
            for length in stride(from: min(bytes.count - start, 5000), through: 10, by: -5) {
                guard start + length <= bytes.count else { continue }

                let slice = Array(bytes[start..<(start + length)])
                if let text = String(bytes: slice, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isActualMessageText(trimmed) && trimmed.count > bestText.count {
                        bestText = trimmed
                    }
                }
            }
        }

        return bestText.isEmpty ? nil : bestText
    }

    private func findPotentialTextStarts(in bytes: [UInt8]) -> [Int] {
        var starts: [Int] = []

        // Look for patterns that typically precede text:
        // - After NSString markers
        // - Transition from control chars to printable
        // - After null bytes

        for i in 0..<bytes.count {
            if i > 0 {
                let prev = bytes[i - 1]
                let curr = bytes[i]

                // Transition from control chars to printable
                if prev < 32 && curr >= 32 && curr < 127 {
                    starts.append(i)
                }

                // After null bytes
                if prev == 0 && curr != 0 {
                    starts.append(i)
                }
            }
        }

        return starts
    }

    private func matchesPattern(_ bytes: [UInt8], at index: Int, pattern: [UInt8]) -> Bool {
        guard index + pattern.count <= bytes.count else { return false }
        for j in 0..<pattern.count {
            if bytes[index + j] != pattern[j] {
                return false
            }
        }
        return true
    }

    private func isActualMessageText(_ text: String) -> Bool {
        // Reject metadata patterns
        let metadataPatterns = [
            "NSString", "NSMutableString", "NSAttributedString", "NSMutableAttributedString",
            "NSDictionary", "NSMutableDictionary", "NSArray", "NSMutableArray",
            "NSNumber", "NSValue", "NSData", "NSObject", "NSFont", "NSColor",
            "NSParagraphStyle", "NSMutableParagraphStyle", "NSKern", "NSBaselineOffset",
            "streamtyped", "__kIM", "IMMessagePart", "IMFileTransfer",
            "$class", "$classes", "$classname", "NSKeyedArchiver"
        ]

        for pattern in metadataPatterns {
            if text.contains(pattern) {
                return false
            }
        }

        // Minimum meaningful length
        guard text.count >= 5 else { return false }

        // Stricter printable threshold (90% instead of 80%)
        let printableCount = text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) ||
            CharacterSet.punctuationCharacters.contains(scalar) ||
            CharacterSet.whitespaces.contains(scalar) ||
            scalar.value > 127  // Unicode (emoji, etc.)
        }.count

        let printableRatio = Double(printableCount) / Double(text.count)
        guard printableRatio > 0.9 else { return false }

        // Reject single character repeated
        let uniqueChars = Set(text)
        guard uniqueChars.count >= 3 else { return false }

        return true
    }

    private func isImageFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"].contains(ext)
    }

    private func isVideoFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
    }

    private func isAudioFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["mp3", "m4a", "wav", "aac", "caf", "aiff"].contains(ext)
    }

    private func getAttachments(for messageId: Int, db: OpaquePointer?) -> [String] {
        let query = """
            SELECT a.filename
            FROM attachment a
            JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
            WHERE maj.message_id = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(messageId))

        var attachments: [String] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let filenamePtr = sqlite3_column_text(statement, 0) {
                attachments.append(String(cString: filenamePtr))
            }
        }

        return attachments
    }

    private func generateMarkdown(conversation: any Conversation, messages: [Message], startDate: Date, endDate: Date, attachmentMapping: [String: String]) -> String {
        if conversation.isGroup {
            return generateGroupMarkdown(conversation as! GroupChat, messages: messages, startDate: startDate, endDate: endDate, attachmentMapping: attachmentMapping)
        } else {
            return generateIndividualMarkdown(conversation as! ConsolidatedContact, messages: messages, startDate: startDate, endDate: endDate, attachmentMapping: attachmentMapping)
        }
    }

    private func generateIndividualMarkdown(_ contact: ConsolidatedContact, messages: [Message], startDate: Date, endDate: Date, attachmentMapping: [String: String]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let fullFormatter = DateFormatter()
        fullFormatter.dateStyle = .medium
        fullFormatter.timeStyle = .short

        let identifiersText = contact.identifiers.joined(separator: ", ")

        var markdown = """
        # Messages with \(contact.displayName)

        **Contact:** \(identifiersText)
        **Date Range:** \(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))
        **Total Messages:** \(messages.count)
        **Exported:** \(fullFormatter.string(from: Date()))

        ---

        """

        var currentDay = ""

        for message in messages {
            let dayString = dateFormatter.string(from: message.date)

            if dayString != currentDay {
                currentDay = dayString
                markdown += "\n## \(dayString)\n\n"
            }

            let time = timeFormatter.string(from: message.date)
            let sender = message.isFromMe ? "**Me**" : "**\(contact.displayName)**"

            markdown += "\(time) - \(sender)\n"

            // Sanitize text: remove null characters, object replacement chars, and other control characters
            let sanitizedText = message.text
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "\u{FFFC}", with: "") // Object Replacement Character (attachment placeholder)
                .replacingOccurrences(of: "\u{FFFD}", with: "") // Replacement Character
                .replacingOccurrences(of: "\u{200B}", with: "") // Zero-width space
                .replacingOccurrences(of: "\u{200C}", with: "") // Zero-width non-joiner
                // Note: keeping U+200D (zero-width joiner) as it's used in emoji sequences (keep for emoji sequences? removing for now)
                .replacingOccurrences(of: "\u{FEFF}", with: "") // BOM / Zero-width no-break space
                .filter { char in
                    // Keep non-ASCII characters (emoji, etc.) and printable ASCII, plus newlines/tabs
                    guard let ascii = char.asciiValue else { return true }
                    return ascii >= 32 || char == "\n" || char == "\t"
                }
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !sanitizedText.isEmpty {
                // Indent message text and handle multi-line
                let indentedText = sanitizedText.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
                markdown += "\(indentedText)\n"
            }

            if !message.attachments.isEmpty {
                for attachment in message.attachments {
                    let filename = (attachment as NSString).lastPathComponent

                    if let relativePath = attachmentMapping[attachment] {
                        // URL-encode the path for markdown
                        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath

                        if isImageFile(attachment) {
                            // Embed image
                            markdown += "\n![Image: \(filename)](\(encodedPath))\n"
                        } else if isVideoFile(attachment) {
                            // Link to video
                            markdown += "> [Video: \(filename)](\(encodedPath))\n"
                        } else if isAudioFile(attachment) {
                            // Link to audio
                            markdown += "> [Audio: \(filename)](\(encodedPath))\n"
                        } else {
                            // Generic file link
                            markdown += "> [Attachment: \(filename)](\(encodedPath))\n"
                        }
                    } else {
                        // Attachment couldn't be copied
                        markdown += "> *[Attachment not found: \(filename)]*\n"
                    }
                }
            }

            markdown += "\n"
        }

        if messages.isEmpty {
            markdown += "\n*No messages found in the specified date range.*\n"
        }

        return markdown
    }

    private func generateGroupMarkdown(_ group: GroupChat, messages: [Message], startDate: Date, endDate: Date, attachmentMapping: [String: String]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let fullFormatter = DateFormatter()
        fullFormatter.dateStyle = .medium
        fullFormatter.timeStyle = .short

        // Build participants list with identifiers
        let participantsText = group.participants
            .map { "\($0.displayName) (\($0.identifier))" }
            .joined(separator: ", ")

        var markdown = """
        # Group Chat: \(group.displayName)

        **Participants:** \(participantsText)
        **Date Range:** \(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))
        **Total Messages:** \(messages.count)
        **Exported:** \(fullFormatter.string(from: Date()))

        ---

        """

        var currentDay = ""

        for message in messages {
            let dayString = dateFormatter.string(from: message.date)

            if dayString != currentDay {
                currentDay = dayString
                markdown += "\n## \(dayString)\n\n"
            }

            let time = timeFormatter.string(from: message.date)
            // For group messages, always show the sender name
            let sender = message.isFromMe ? "**Me**" : "**\(message.senderName ?? "Unknown")**"

            markdown += "\(time) - \(sender)\n"

            // Sanitize text
            let sanitizedText = message.text
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .replacingOccurrences(of: "\u{FFFD}", with: "")
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\u{200C}", with: "")
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .filter { char in
                    guard let ascii = char.asciiValue else { return true }
                    return ascii >= 32 || char == "\n" || char == "\t"
                }
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !sanitizedText.isEmpty {
                let indentedText = sanitizedText.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
                markdown += "\(indentedText)\n"
            }

            if !message.attachments.isEmpty {
                for attachment in message.attachments {
                    let filename = (attachment as NSString).lastPathComponent

                    if let relativePath = attachmentMapping[attachment] {
                        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath

                        if isImageFile(attachment) {
                            markdown += "\n![Image: \(filename)](\(encodedPath))\n"
                        } else if isVideoFile(attachment) {
                            markdown += "> [Video: \(filename)](\(encodedPath))\n"
                        } else if isAudioFile(attachment) {
                            markdown += "> [Audio: \(filename)](\(encodedPath))\n"
                        } else {
                            markdown += "> [Attachment: \(filename)](\(encodedPath))\n"
                        }
                    } else {
                        markdown += "> *[Attachment not found: \(filename)]*\n"
                    }
                }
            }

            markdown += "\n"
        }

        if messages.isEmpty {
            markdown += "\n*No messages found in the specified date range.*\n"
        }

        return markdown
    }
}
