import Foundation
import SQLite3
import SwiftUI

class MessagesViewModel: ObservableObject {
    @Published var consolidatedContacts: [ConsolidatedContact] = []
    @Published var selectedContactId: String?
    @Published var hasAccess = false
    @Published var isExporting = false
    @Published var errorMessage: String?
    @Published var previewMessages: [Message] = []
    @Published var contactsAuthorized = false

    var contactsService = ContactsService()
    private let dbPath: String

    var selectedContact: ConsolidatedContact? {
        guard let id = selectedContactId else { return nil }
        return consolidatedContacts.first { $0.id == id }
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
                loadHandlesAndConsolidate()
            }
        }
    }

    private func loadHandlesAndConsolidate() {
        var db: OpaquePointer?

        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to open database"
            }
            return
        }

        defer { sqlite3_close(db) }

        let query = """
            SELECT DISTINCT h.ROWID, h.id
            FROM handle h
            JOIN chat_handle_join chj ON h.ROWID = chj.handle_id
            JOIN chat c ON chj.chat_id = c.ROWID
            ORDER BY h.id
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to prepare query"
            }
            return
        }

        defer { sqlite3_finalize(statement) }

        var handles: [MessageHandle] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let identifier = String(cString: sqlite3_column_text(statement, 1))
            handles.append(MessageHandle(id: id, identifier: identifier))
        }

        let consolidated = consolidateHandles(handles)

        DispatchQueue.main.async {
            self.consolidatedContacts = consolidated
        }
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

    func loadPreviewMessages(for contact: ConsolidatedContact, limit: Int = 5) {
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
                SELECT DISTINCT m.ROWID, m.text, m.date, m.is_from_me, m.cache_has_attachments, m.attributedBody
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

                messages.append(Message(id: id, text: text, date: date, isFromMe: isFromMe, attachments: attachments))
            }

            // Reverse to show oldest first (chronological order)
            messages.reverse()

            DispatchQueue.main.async {
                self.previewMessages = messages
            }
        }
    }

    func exportMessages(for contact: ConsolidatedContact, from startDate: Date, to endDate: Date, to url: URL, completion: @escaping (Bool) -> Void) {
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
                SELECT DISTINCT m.ROWID, m.text, m.date, m.is_from_me, m.cache_has_attachments, m.attributedBody
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

                let dateNano = sqlite3_column_double(statement, 2)
                let date = Date(timeIntervalSinceReferenceDate: dateNano / 1_000_000_000)

                let isFromMe = sqlite3_column_int(statement, 3) == 1
                let hasAttachments = sqlite3_column_int(statement, 4) == 1

                var attachments: [String] = []
                if hasAttachments {
                    attachments = self.getAttachments(for: id, db: db)
                }

                messages.append(Message(id: id, text: text, date: date, isFromMe: isFromMe, attachments: attachments))
            }

            // Create attachments folder and copy images
            let attachmentsFolder = url.deletingLastPathComponent().appendingPathComponent("attachments")
            let copiedAttachments = self.copyAttachments(from: messages, to: attachmentsFolder)

            // Generate markdown with image references
            let markdown = self.generateMarkdown(contact: contact, messages: messages, startDate: startDate, endDate: endDate, attachmentMapping: copiedAttachments)

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

    private func extractTextFromAttributedBody(_ data: Data) -> String {
        // The attributedBody uses Apple's "typedstream" format
        // The text is stored after a specific byte pattern

        let bytes = [UInt8](data)
        guard bytes.count > 10 else { return "" }

        // Look for the pattern that precedes the message text
        // In typedstream, strings are often preceded by their length as a varint
        // or by specific marker bytes

        // Strategy: Find "NSString" or "NSMutableString" marker, then extract the text after it
        // The text length is usually encoded before the actual text

        // First, try to find text after the NSString marker
        if let text = extractTextAfterNSStringMarker(bytes) {
            return text
        }

        // Fallback: look for the largest contiguous UTF-8 text block
        // that doesn't contain Objective-C class names
        if let text = extractLargestTextBlock(bytes) {
            return text
        }

        return ""
    }

    private func extractTextAfterNSStringMarker(_ bytes: [UInt8]) -> String? {
        // Look for "NSString" or similar markers in the data
        let nsStringPattern: [UInt8] = Array("NSString".utf8)
        let nsMutableStringPattern: [UInt8] = Array("NSMutableString".utf8)

        var searchStart = 0

        // Find the last occurrence of NSString/NSMutableString (the actual content, not class def)
        var lastMarkerEnd = -1

        for i in 0..<(bytes.count - nsStringPattern.count) {
            if matchesPattern(bytes, at: i, pattern: nsMutableStringPattern) {
                lastMarkerEnd = i + nsMutableStringPattern.count
            } else if matchesPattern(bytes, at: i, pattern: nsStringPattern) {
                lastMarkerEnd = i + nsStringPattern.count
            }
        }

        if lastMarkerEnd > 0 {
            searchStart = lastMarkerEnd
        }

        // After the marker, look for the text content
        // Skip some header bytes and find readable text
        var i = searchStart
        while i < bytes.count - 1 {
            // Look for a length byte followed by that many readable characters
            let potentialLength = Int(bytes[i])

            if potentialLength > 0 && potentialLength < 10000 && i + 1 + potentialLength <= bytes.count {
                let textBytes = Array(bytes[(i + 1)..<(i + 1 + potentialLength)])

                // Check if these bytes form valid UTF-8 text
                if let text = String(bytes: textBytes, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isLikelyMessageText(trimmed) {
                        return trimmed
                    }
                }
            }

            i += 1
        }

        return nil
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

    private func extractLargestTextBlock(_ bytes: [UInt8]) -> String? {
        var bestText = ""
        var i = 0

        while i < bytes.count {
            // Try to decode a string starting at position i with various lengths
            for length in stride(from: min(bytes.count - i, 5000), through: 1, by: -1) {
                let slice = Array(bytes[i..<(i + length)])
                if let text = String(bytes: slice, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isLikelyMessageText(trimmed) && trimmed.count > bestText.count {
                        bestText = trimmed
                    }
                }
            }
            i += 1
        }

        return bestText.isEmpty ? nil : bestText
    }

    private func isLikelyMessageText(_ text: String) -> Bool {
        // Filter out Objective-C runtime strings and metadata
        let blacklist = [
            "NSString", "NSMutableString", "NSAttributedString", "NSMutableAttributedString",
            "NSDictionary", "NSMutableDictionary", "NSArray", "NSMutableArray",
            "NSNumber", "NSValue", "NSData", "NSObject", "NSFont", "NSColor",
            "NSParagraphStyle", "NSMutableParagraphStyle", "NSKern", "NSBaselineOffset",
            "streamtyped", "__kIM", "IMMessagePart", "IMFileTransfer",
            "$class", "$classes", "$classname"
        ]

        for forbidden in blacklist {
            if text == forbidden || text.hasPrefix(forbidden + "\0") {
                return false
            }
        }

        // Must have at least some content
        guard text.count >= 1 else { return false }

        // Should be mostly printable characters
        let printableCount = text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) ||
            CharacterSet.punctuationCharacters.contains(scalar) ||
            CharacterSet.whitespaces.contains(scalar) ||
            scalar.value > 127 // Allow unicode (emoji, etc)
        }.count

        return Double(printableCount) / Double(text.count) > 0.8
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

    private func generateMarkdown(contact: ConsolidatedContact, messages: [Message], startDate: Date, endDate: Date, attachmentMapping: [String: String]) -> String {
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
}
