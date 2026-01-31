import SwiftUI

// MARK: - Mock Data

extension ConsolidatedContact {
    static let mockContacts = [
        ConsolidatedContact(
            id: "1",
            displayName: "Sarah Johnson",
            handles: [MessageHandle(id: 1, identifier: "+1 (555) 123-4567")],
            contactIdentifier: "CNContact:1"
        ),
        ConsolidatedContact(
            id: "2",
            displayName: "Mike Chen",
            handles: [MessageHandle(id: 2, identifier: "+1 (555) 987-6543")],
            contactIdentifier: "CNContact:2"
        ),
        ConsolidatedContact(
            id: "3",
            displayName: "+1 (555) 246-8101",
            handles: [MessageHandle(id: 3, identifier: "+1 (555) 246-8101")],
            contactIdentifier: nil
        ),
        ConsolidatedContact(
            id: "4",
            displayName: "Emma Rodriguez",
            handles: [MessageHandle(id: 4, identifier: "+1 (555) 555-0123")],
            contactIdentifier: "CNContact:4"
        ),
        ConsolidatedContact(
            id: "5",
            displayName: "Alex Thompson",
            handles: [MessageHandle(id: 5, identifier: "+1 (555) 777-9999")],
            contactIdentifier: "CNContact:5"
        ),
        ConsolidatedContact(
            id: "6",
            displayName: "Lisa Park",
            handles: [MessageHandle(id: 6, identifier: "+1 (555) 321-7654")],
            contactIdentifier: "CNContact:6"
        ),
        ConsolidatedContact(
            id: "7",
            displayName: "David Kim",
            handles: [MessageHandle(id: 7, identifier: "+1 (555) 888-4321")],
            contactIdentifier: "CNContact:7"
        ),
        ConsolidatedContact(
            id: "8",
            displayName: "Rachel Green",
            handles: [MessageHandle(id: 8, identifier: "+1 (555) 456-7890")],
            contactIdentifier: "CNContact:8"
        )
    ]
}

extension Message {
    static let mockMessages = [
        Message(
            id: 1,
            text: "Hey! Are we still meeting for coffee tomorrow?",
            date: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!,
            isFromMe: false,
            attachments: [],
            senderHandleId: 3,
            senderIdentifier: "+1 (555) 246-8101",
            senderName: "+1 (555) 246-8101"
        ),
        Message(
            id: 2,
            text: "Yes! Looking forward to it. 10am works great for me.",
            date: Calendar.current.date(byAdding: .hour, value: -1, to: Date())!,
            isFromMe: true,
            attachments: [],
            senderHandleId: 0,
            senderIdentifier: nil,
            senderName: nil
        ),
        Message(
            id: 3,
            text: "Perfect! See you at the usual spot.",
            date: Calendar.current.date(byAdding: .minute, value: -45, to: Date())!,
            isFromMe: false,
            attachments: [],
            senderHandleId: 3,
            senderIdentifier: "+1 (555) 246-8101",
            senderName: "+1 (555) 246-8101"
        ),
        Message(
            id: 4,
            text: "Can't wait! I'll bring those photos I mentioned.",
            date: Calendar.current.date(byAdding: .minute, value: -30, to: Date())!,
            isFromMe: true,
            attachments: ["photo1.jpg", "photo2.jpg"],
            senderHandleId: 0,
            senderIdentifier: nil,
            senderName: nil
        ),
        Message(
            id: 5,
            text: "Awesome! Thanks!",
            date: Calendar.current.date(byAdding: .minute, value: -15, to: Date())!,
            isFromMe: false,
            attachments: [],
            senderHandleId: 3,
            senderIdentifier: "+1 (555) 246-8101",
            senderName: "+1 (555) 246-8101"
        )
    ]
}

// MARK: - Mock ViewModel

class MockMessagesViewModel: ObservableObject {
    @Published var conversations: [any Conversation] = ConsolidatedContact.mockContacts
    @Published var selectedContactId: String? = "3"  // Select the 555 number
    @Published var previewMessages: [Message] = Message.mockMessages
    @Published var hasAccess = true
    @Published var contactsAuthorized = true
    @Published var isExporting = false
    @Published var errorMessage: String? = nil

    var selectedConversation: (any Conversation)? {
        conversations.first(where: { $0.id == selectedContactId })
    }

    func checkAccessAndLoadContacts() {}
    func loadPreviewMessages(for conversation: any Conversation) {}
    func exportMessages(for conversation: any Conversation, from: Date, to: Date, to url: URL, completion: @escaping (Bool) -> Void) {}
}

// MARK: - Mock ContentView

struct MockContentView: View {
    @StateObject private var viewModel = MockMessagesViewModel()

    @State private var searchText = ""
    @State private var startDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    @State private var endDate = Date()
    @State private var showExportSuccess = false
    @State private var exportedPath = ""
    @State private var showHelp = false

    private let privacyURL = URL(string: "https://app.proofbound.com/privacy")!
    private let termsURL = URL(string: "https://app.proofbound.com/terms")!

    var filteredConversations: [any Conversation] {
        if searchText.isEmpty {
            return viewModel.conversations
        }
        return viewModel.conversations.filter { conversation in
            conversation.displayName.localizedCaseInsensitiveContains(searchText) ||
            conversation.participantNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)

                            Text("TextKeep")
                                .font(.custom("CrimsonText-SemiBold", size: 28))
                        }

                        Text("Export your Messages to Markdown")
                            .font(.custom("Inter-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button(action: { showHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.custom("Inter-Regular", size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show help and documentation")
                    .padding(.trailing, 8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main content
            HSplitView {
                // Left: Contact list
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Search contacts...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.custom("Inter-Regular", size: 13))
                        .padding(8)

                    List(selection: $viewModel.selectedContactId) {
                        ForEach(filteredConversations, id: \.id) { conversation in
                            ConversationRow(conversation: conversation)
                                .tag(conversation.id)
                        }
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 200, maxWidth: 250)

                // Right: Export options
                VStack(spacing: 16) {
                    if let conversation = viewModel.selectedConversation {
                        individualDetailView(conversation as! ConsolidatedContact)
                    } else {
                        Text("Select a contact or group to export messages")
                            .font(.custom("Inter-Regular", size: 14))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 300)
            }

            // Footer with legal links
            Divider()
            HStack {
                Spacer()
                Link("Privacy", destination: privacyURL)
                Text("•").foregroundColor(.secondary)
                Link("Terms", destination: termsURL)
                Spacer()
            }
            .font(.custom("Inter-Regular", size: 11))
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    func individualDetailView(_ contact: ConsolidatedContact) -> some View {
        VStack(spacing: 20) {
            // Contact info
            VStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.custom("Inter-Regular", size: 60))
                    .foregroundColor(.accentColor)

                Text(contact.displayName)
                    .font(.custom("CrimsonText-SemiBold", size: 22))

                if contact.handles.count == 1 {
                    Text(contact.identifiers.first ?? "")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 2) {
                        Text("\(contact.handles.count) numbers/emails")
                            .font(.custom("Inter-Regular", size: 12))
                            .foregroundColor(.secondary)
                        ForEach(contact.identifiers.prefix(3), id: \.self) { identifier in
                            Text(identifier)
                                .font(.custom("Inter-Regular", size: 11))
                                .foregroundColor(.secondary)
                        }
                        if contact.handles.count > 3 {
                            Text("+ \(contact.handles.count - 3) more")
                                .font(.custom("Inter-Regular", size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 20)

            Divider()

            // Recent messages preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Messages")
                    .font(.custom("Inter-SemiBold", size: 15))

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.previewMessages) { message in
                            MessagePreviewRow(message: message, contactName: contact.displayName)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            .padding(.horizontal)

            Divider()

            // Date range
            VStack(alignment: .leading, spacing: 12) {
                Text("Date Range")
                    .font(.custom("Inter-SemiBold", size: 15))

                HStack {
                    DatePicker("From:", selection: $startDate, displayedComponents: .date)
                        .font(.custom("Inter-Regular", size: 13))
                    DatePicker("To:", selection: $endDate, displayedComponents: .date)
                        .font(.custom("Inter-Regular", size: 13))
                }
            }
            .padding(.horizontal)

            Divider()

            // Export button
            VStack(spacing: 12) {
                Button(action: {}) {
                    Label("Export to Markdown", systemImage: "square.and.arrow.up")
                        .font(.custom("Inter-Medium", size: 14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Mock TextKeep Interface") {
    MockContentView()
        .frame(width: 800, height: 600)
}
