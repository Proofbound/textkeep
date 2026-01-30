import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MessagesViewModel()

    // Update checker for version checking (passed from parent)
    var updateChecker: UpdateChecker?
    var onUpdateCheckComplete: (() -> Void)?

    @State private var searchText = ""
    @State private var startDate = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1))!
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

                if !viewModel.hasAccess {
                    accessWarningView
                } else if !viewModel.contactsAuthorized {
                    contactsInfoView
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.hasAccess {
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
                            selectedConversationView(conversation)
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
            } else {
                Spacer()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("Export Complete", isPresented: $showExportSuccess) {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(exportedPath, inFileViewerRootedAtPath: (exportedPath as NSString).deletingLastPathComponent)
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Messages exported to:\n\(exportedPath)")
        }
        .sheet(isPresented: $showHelp) {
            HelpView(
                updateChecker: updateChecker,
                onUpdateCheckComplete: onUpdateCheckComplete
            )
        }
        .onAppear {
            viewModel.checkAccessAndLoadContacts()
        }
        .onChange(of: viewModel.selectedContactId) { newValue in
            if let conversationId = newValue,
               let conversation = viewModel.conversations.first(where: { $0.id == conversationId }) {
                viewModel.loadPreviewMessages(for: conversation)
            } else {
                viewModel.previewMessages = []
            }
        }
    }

    var accessWarningView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.custom("Inter-Regular", size: 40))
                .foregroundColor(.orange)

            Text("Full Disk Access Required")
                .font(.custom("Inter-SemiBold", size: 16))

            Text("This app needs permission to read your Messages database.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Check Again") {
                viewModel.checkAccessAndLoadContacts()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    var contactsInfoView: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .foregroundColor(.blue)

            Text("Grant Contacts access to see names instead of phone numbers")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundColor(.secondary)

            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    func selectedConversationView(_ conversation: any Conversation) -> some View {
        if conversation.isGroup {
            groupDetailView(conversation as! GroupChat)
        } else {
            individualDetailView(conversation as! ConsolidatedContact)
        }
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

                if viewModel.previewMessages.isEmpty {
                    Text("Loading...")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.previewMessages) { message in
                                MessagePreviewRow(message: message, contactName: contact.displayName)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
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
                Button(action: exportMessages) {
                    Label("Export to Markdown", systemImage: "square.and.arrow.up")
                        .font(.custom("Inter-Medium", size: 14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if viewModel.isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding()

            Spacer()
        }
    }

    func groupDetailView(_ group: GroupChat) -> some View {
        VStack(spacing: 20) {
            // Group info
            VStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.custom("Inter-Regular", size: 60))
                    .foregroundColor(.purple)

                Text(group.displayName)
                    .font(.custom("CrimsonText-SemiBold", size: 22))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Participants (\(group.participantCount))")
                        .font(.custom("Inter-SemiBold", size: 13))

                    ForEach(group.participants.prefix(10)) { participant in
                        Text("• \(participant.displayName)")
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundColor(.secondary)
                    }

                    if group.participantCount > 10 {
                        Text("• ...and \(group.participantCount - 10) more")
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.top, 20)

            Divider()

            // Recent messages preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Messages")
                    .font(.custom("Inter-SemiBold", size: 15))

                if viewModel.previewMessages.isEmpty {
                    Text("Loading...")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.previewMessages) { message in
                                MessagePreviewRow(message: message, contactName: nil)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
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
                Button(action: exportMessages) {
                    Label("Export to Markdown", systemImage: "square.and.arrow.up")
                        .font(.custom("Inter-Medium", size: 14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if viewModel.isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding()

            Spacer()
        }
    }

    func exportMessages() {
        guard let conversation = viewModel.selectedConversation else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "\(conversation.displayName) - Messages.md"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.exportMessages(for: conversation, from: startDate, to: endDate, to: url) { success in
                    if success {
                        exportedPath = url.path
                        showExportSuccess = true
                    }
                }
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: any Conversation

    var body: some View {
        HStack {
            if conversation.isGroup {
                Image(systemName: "person.3.fill")
                    .font(.custom("Inter-Regular", size: 17))
                    .foregroundColor(.purple)
            } else {
                let contact = conversation as! ConsolidatedContact
                Image(systemName: contact.contactIdentifier != nil ? "person.circle.fill" : "phone.circle.fill")
                    .font(.custom("Inter-Regular", size: 17))
                    .foregroundColor(contact.contactIdentifier != nil ? .accentColor : .secondary)
            }

            VStack(alignment: .leading) {
                Text(conversation.displayName)
                    .font(.custom("Inter-Medium", size: 13))

                if conversation.isGroup {
                    Text("\(conversation.participantCount) participants")
                        .font(.custom("Inter-Regular", size: 11))
                        .foregroundColor(.secondary)
                } else {
                    let contact = conversation as! ConsolidatedContact
                    if contact.handles.count > 1 {
                        Text("\(contact.handles.count) numbers")
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text(contact.identifiers.first ?? "")
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct MessagePreviewRow: View {
    let message: Message
    let contactName: String?  // Optional for group messages

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    private var senderName: String {
        if message.isFromMe {
            return "Me"
        } else if let contactName = contactName {
            // 1-on-1 conversation
            return contactName
        } else {
            // Group conversation - use sender name from message
            return message.senderName ?? "Unknown"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Sender indicator
            Image(systemName: message.isFromMe ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(message.isFromMe ? .blue : .green)
                .font(.custom("Inter-Regular", size: 11))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(senderName)
                        .font(.custom("Inter-Medium", size: 11))
                    Spacer()
                    Text(timeFormatter.string(from: message.date))
                        .font(.custom("Inter-Regular", size: 10))
                        .foregroundColor(.secondary)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.custom("Inter-Regular", size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !message.attachments.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.custom("Inter-Regular", size: 10))
                        Text("\(message.attachments.count) attachment\(message.attachments.count == 1 ? "" : "s")")
                            .font(.custom("Inter-Regular", size: 10))
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(message.isFromMe ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
