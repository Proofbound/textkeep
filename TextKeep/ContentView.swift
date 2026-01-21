import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MessagesViewModel()
    @State private var searchText = ""
    @State private var startDate = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    @State private var endDate = Date()
    @State private var showExportSuccess = false
    @State private var exportedPath = ""

    var filteredContacts: [ConsolidatedContact] {
        if searchText.isEmpty {
            return viewModel.consolidatedContacts
        }
        return viewModel.consolidatedContacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(searchText) ||
            contact.identifiers.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("TextKeep")
                    .font(.title)
                    .fontWeight(.semibold)

                if !viewModel.hasAccess {
                    accessWarningView
                } else if viewModel.contactsService.authorizationStatus != .authorized {
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
                            .padding(8)

                        List(filteredContacts, selection: $viewModel.selectedContactId) { contact in
                            ContactRow(contact: contact)
                                .tag(contact.id)
                        }
                        .listStyle(.inset)
                    }
                    .frame(minWidth: 200, maxWidth: 250)

                    // Right: Export options
                    VStack(spacing: 16) {
                        if let contact = viewModel.selectedContact {
                            selectedContactView(contact)
                        } else {
                            Text("Select a contact to export messages")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 300)
                }
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
        .onAppear {
            viewModel.checkAccessAndLoadContacts()
        }
        .onChange(of: viewModel.selectedContactId) { newValue in
            if let contactId = newValue,
               let contact = viewModel.consolidatedContacts.first(where: { $0.id == contactId }) {
                viewModel.loadPreviewMessages(for: contact)
            } else {
                viewModel.previewMessages = []
            }
        }
    }

    var accessWarningView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Full Disk Access Required")
                .font(.headline)

            Text("This app needs permission to read your Messages database.")
                .font(.subheadline)
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
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    func selectedContactView(_ contact: ConsolidatedContact) -> some View {
        VStack(spacing: 20) {
            // Contact info
            VStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text(contact.displayName)
                    .font(.title2)
                    .fontWeight(.medium)

                if contact.handles.count == 1 {
                    Text(contact.identifiers.first ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 2) {
                        Text("\(contact.handles.count) numbers/emails")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(contact.identifiers.prefix(3), id: \.self) { identifier in
                            Text(identifier)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if contact.handles.count > 3 {
                            Text("+ \(contact.handles.count - 3) more")
                                .font(.caption2)
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
                    .font(.headline)

                if viewModel.previewMessages.isEmpty {
                    Text("Loading...")
                        .font(.caption)
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
                    .font(.headline)

                HStack {
                    DatePicker("From:", selection: $startDate, displayedComponents: .date)
                    DatePicker("To:", selection: $endDate, displayedComponents: .date)
                }
            }
            .padding(.horizontal)

            Divider()

            // Export button
            VStack(spacing: 12) {
                Button(action: exportMessages) {
                    Label("Export to Markdown", systemImage: "square.and.arrow.up")
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
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()

            Spacer()
        }
    }

    func exportMessages() {
        guard let contact = viewModel.selectedContact else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "\(contact.displayName) - Messages.md"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.exportMessages(for: contact, from: startDate, to: endDate, to: url) { success in
                    if success {
                        exportedPath = url.path
                        showExportSuccess = true
                    }
                }
            }
        }
    }
}

struct ContactRow: View {
    let contact: ConsolidatedContact

    var body: some View {
        HStack {
            Image(systemName: contact.contactIdentifier != nil ? "person.circle.fill" : "phone.circle.fill")
                .font(.title2)
                .foregroundColor(contact.contactIdentifier != nil ? .accentColor : .secondary)

            VStack(alignment: .leading) {
                Text(contact.displayName)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    if contact.handles.count > 1 {
                        Text("\(contact.handles.count) numbers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(contact.identifiers.first ?? "")
                            .font(.caption)
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
    let contactName: String

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Sender indicator
            Image(systemName: message.isFromMe ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(message.isFromMe ? .blue : .green)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(message.isFromMe ? "Me" : contactName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(timeFormatter.string(from: message.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !message.attachments.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                        Text("\(message.attachments.count) attachment\(message.attachments.count == 1 ? "" : "s")")
                            .font(.caption2)
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
