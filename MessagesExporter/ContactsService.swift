import Foundation
import Contacts

class ContactsService: ObservableObject {
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined

    private let contactStore = CNContactStore()
    private var phoneToContact: [String: CNContact] = [:]
    private var emailToContact: [String: CNContact] = [:]

    init() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            await MainActor.run {
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
            if granted {
                loadContacts()
            }
            return granted
        } catch {
            await MainActor.run {
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
            return false
        }
    }

    func loadContacts() {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        var newPhoneToContact: [String: CNContact] = [:]
        var newEmailToContact: [String: CNContact] = [:]

        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                // Index by normalized phone numbers
                for phoneNumber in contact.phoneNumbers {
                    let normalized = self.normalizePhoneNumber(phoneNumber.value.stringValue)
                    newPhoneToContact[normalized] = contact
                }

                // Index by email addresses (lowercased)
                for email in contact.emailAddresses {
                    let normalized = (email.value as String).lowercased()
                    newEmailToContact[normalized] = contact
                }
            }

            phoneToContact = newPhoneToContact
            emailToContact = newEmailToContact
        } catch {
            print("Failed to fetch contacts: \(error)")
        }
    }

    /// Normalizes a phone number by removing all non-digits and standardizing US numbers
    /// Input: "(123) 456-7890" or "+1-123-456-7890" or "1234567890"
    /// Output: "11234567890" (11 digits for US numbers)
    func normalizePhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-digit characters
        let digitsOnly = phoneNumber.filter { $0.isNumber }

        // Handle US numbers
        if digitsOnly.count == 10 {
            // 10-digit US number - prepend "1"
            return "1" + digitsOnly
        } else if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            // 11-digit US number starting with 1
            return digitsOnly
        }

        // Return as-is for international numbers or other formats
        return digitsOnly
    }

    /// Look up a contact by phone number or email
    func lookupContact(for identifier: String) -> CNContact? {
        // Check if it's an email
        if identifier.contains("@") {
            return emailToContact[identifier.lowercased()]
        }

        // Otherwise treat as phone number
        let normalized = normalizePhoneNumber(identifier)
        return phoneToContact[normalized]
    }

    /// Get display name for an identifier
    func getDisplayName(for identifier: String) -> String {
        if let contact = lookupContact(for: identifier) {
            let name = formatContactName(contact)
            if !name.isEmpty {
                return name
            }
        }

        // Fallback to formatted identifier
        return formatIdentifier(identifier)
    }

    /// Format a CNContact's name
    private func formatContactName(_ contact: CNContact) -> String {
        let givenName = contact.givenName.trimmingCharacters(in: .whitespaces)
        let familyName = contact.familyName.trimmingCharacters(in: .whitespaces)

        if !givenName.isEmpty && !familyName.isEmpty {
            return "\(givenName) \(familyName)"
        } else if !givenName.isEmpty {
            return givenName
        } else if !familyName.isEmpty {
            return familyName
        }

        return ""
    }

    /// Format an identifier for display (phone number or email)
    private func formatIdentifier(_ identifier: String) -> String {
        // If it's an email, return as-is
        if identifier.contains("@") {
            return identifier
        }

        // Format phone number
        let digitsOnly = identifier.filter { $0.isNumber }

        // US number formatting
        if digitsOnly.count == 10 {
            let areaCode = String(digitsOnly.prefix(3))
            let middle = String(digitsOnly.dropFirst(3).prefix(3))
            let last = String(digitsOnly.suffix(4))
            return "(\(areaCode)) \(middle)-\(last)"
        } else if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            let withoutCountry = String(digitsOnly.dropFirst())
            let areaCode = String(withoutCountry.prefix(3))
            let middle = String(withoutCountry.dropFirst(3).prefix(3))
            let last = String(withoutCountry.suffix(4))
            return "+1 (\(areaCode)) \(middle)-\(last)"
        }

        // Return original if we can't format it
        return identifier
    }

    /// Get the contact identifier (CNContact.identifier) for grouping
    func getContactIdentifier(for identifier: String) -> String? {
        return lookupContact(for: identifier)?.identifier
    }
}
