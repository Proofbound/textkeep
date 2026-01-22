import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)

                    Text("TextKeep Help")
                        .font(.custom("CrimsonText-SemiBold", size: 28))

                    Text("Export your Messages to Markdown")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top)

                Divider()

                // Getting Started
                HelpSection(
                    title: "Getting Started",
                    icon: "star.fill",
                    iconColor: .yellow,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TextKeep allows you to export your iMessage conversations to readable Markdown files with attachments.")
                                .font(.custom("Inter-Regular", size: 13))

                            Text("To get started:")
                                .font(.custom("Inter-Medium", size: 13))
                                .padding(.top, 4)

                            HelpStep(number: "1", text: "Grant Full Disk Access in System Settings")
                            HelpStep(number: "2", text: "Optionally grant Contacts access for names")
                            HelpStep(number: "3", text: "Select a conversation from the list")
                            HelpStep(number: "4", text: "Choose date range and export location")
                        }
                    }
                )

                // Permissions
                HelpSection(
                    title: "Required Permissions",
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    content: {
                        VStack(alignment: .leading, spacing: 16) {
                            PermissionDetail(
                                title: "Full Disk Access (Required)",
                                description: "TextKeep needs this permission to read your Messages database located at ~/Library/Messages/chat.db. Without this, the app cannot access your messages.",
                                steps: [
                                    "Open System Settings",
                                    "Go to Privacy & Security > Full Disk Access",
                                    "Enable the toggle next to TextKeep"
                                ]
                            )

                            PermissionDetail(
                                title: "Contacts (Optional)",
                                description: "Allows TextKeep to display contact names instead of phone numbers or email addresses. If not granted, conversations will show using identifiers.",
                                steps: [
                                    "Open System Settings",
                                    "Go to Privacy & Security > Contacts",
                                    "Enable the toggle next to TextKeep"
                                ]
                            )
                        }
                    }
                )

                // Features
                HelpSection(
                    title: "Features",
                    icon: "star.circle.fill",
                    iconColor: .purple,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureItem(
                                icon: "person.2.fill",
                                title: "Individual & Group Conversations",
                                description: "Export both 1-on-1 chats and group messages with full participant attribution"
                            )

                            FeatureItem(
                                icon: "calendar",
                                title: "Date Range Selection",
                                description: "Export all messages or choose a specific date range"
                            )

                            FeatureItem(
                                icon: "paperclip",
                                title: "Attachment Handling",
                                description: "Automatically copies photos, videos, and files alongside your exported markdown"
                            )

                            FeatureItem(
                                icon: "doc.text",
                                title: "Markdown Format",
                                description: "Messages are exported in clean, readable Markdown format that can be opened in any text editor"
                            )

                            FeatureItem(
                                icon: "magnifyingglass",
                                title: "Search & Filter",
                                description: "Quickly find conversations by searching for names, phone numbers, or email addresses"
                            )
                        }
                    }
                )

                // Export Format
                HelpSection(
                    title: "Export Format",
                    icon: "doc.richtext.fill",
                    iconColor: .green,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Each export creates:")
                                .font(.custom("Inter-Medium", size: 13))

                            BulletPoint(text: "A Markdown file (.md) with all messages")
                            BulletPoint(text: "An 'attachments' folder with all media files")
                            BulletPoint(text: "Messages organized by date with timestamps")
                            BulletPoint(text: "Sender names from your Contacts (when available)")

                            Text("For group chats, each message includes the sender's name to show who said what.")
                                .font(.custom("Inter-Regular", size: 12))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
                )

                // Privacy & Security
                HelpSection(
                    title: "Privacy & Security",
                    icon: "hand.raised.fill",
                    iconColor: .orange,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            BulletPoint(text: "All processing happens locally on your Mac")
                            BulletPoint(text: "No data is sent to external servers")
                            BulletPoint(text: "Your messages remain private and secure")
                            BulletPoint(text: "Exported files are saved only where you choose")

                            Text("TextKeep only reads from your Messages database. It never modifies or deletes your messages.")
                                .font(.custom("Inter-Regular", size: 12))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
                )

                // Troubleshooting
                HelpSection(
                    title: "Troubleshooting",
                    icon: "wrench.and.screwdriver.fill",
                    iconColor: .red,
                    content: {
                        VStack(alignment: .leading, spacing: 16) {
                            TroubleshootItem(
                                problem: "No conversations appear",
                                solution: "Ensure Full Disk Access is enabled in System Settings. You may need to restart TextKeep after granting permission."
                            )

                            TroubleshootItem(
                                problem: "Showing phone numbers instead of names",
                                solution: "Grant Contacts permission in System Settings to see contact names."
                            )

                            TroubleshootItem(
                                problem: "Export fails or is incomplete",
                                solution: "Make sure you have sufficient disk space and write permissions for the chosen export location."
                            )

                            TroubleshootItem(
                                problem: "Missing messages",
                                solution: "Check the date range selection. Some conversations may have messages outside the selected range."
                            )
                        }
                    }
                )

                // About & Footer
                VStack(spacing: 16) {
                    Divider()

                    VStack(spacing: 12) {
                        Text("About TextKeep")
                            .font(.custom("CrimsonText-SemiBold", size: 18))

                        VStack(spacing: 8) {
                            Text("Version 1.2.0")
                                .font(.custom("Inter-Regular", size: 11))
                                .foregroundColor(.secondary)

                            Text("© 2026 Proofbound. All rights reserved.")
                                .font(.custom("Inter-Regular", size: 11))
                                .foregroundColor(.secondary)

                            Link("View on GitHub", destination: URL(string: "https://github.com/Proofbound/textkeep")!)
                                .font(.custom("Inter-Medium", size: 11))
                        }

                        Text("Part of the Proofbound family of tools")
                            .font(.custom("Inter-Regular", size: 10))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    HStack(spacing: 16) {
                        Link("Privacy Policy", destination: URL(string: "https://app.proofbound.com/privacy")!)
                        Text("•")
                            .foregroundColor(.secondary)
                        Link("Terms of Service", destination: URL(string: "https://app.proofbound.com/terms")!)
                        Text("•")
                            .foregroundColor(.secondary)
                        Link("Support", destination: URL(string: "https://proofbound.com/support")!)
                    }
                    .font(.custom("Inter-Regular", size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 32)
        }
        .frame(minWidth: 600, minHeight: 700)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Helper Views

struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.custom("Inter-Regular", size: 20))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.custom("CrimsonText-SemiBold", size: 20))
            }

            content
        }
    }
}

struct HelpStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.custom("Inter-SemiBold", size: 12))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.custom("Inter-Regular", size: 13))
        }
    }
}

struct PermissionDetail: View {
    let title: String
    let description: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Inter-SemiBold", size: 14))

            Text(description)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundColor(.secondary)

            Text("How to enable:")
                .font(.custom("Inter-Medium", size: 12))
                .padding(.top, 4)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.custom("Inter-Medium", size: 11))
                        .foregroundColor(.secondary)
                    Text(step)
                        .font(.custom("Inter-Regular", size: 11))
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.custom("Inter-Regular", size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Inter-SemiBold", size: 13))

                Text(description)
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.custom("Inter-Regular", size: 13))
            Text(text)
                .font(.custom("Inter-Regular", size: 13))
        }
    }
}

struct TroubleshootItem: View {
    let problem: String
    let solution: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Problem:")
                    .font(.custom("Inter-SemiBold", size: 12))
                Text(problem)
                    .font(.custom("Inter-Regular", size: 12))
            }

            HStack(alignment: .top, spacing: 6) {
                Text("Solution:")
                    .font(.custom("Inter-SemiBold", size: 12))
                Text(solution)
                    .font(.custom("Inter-Regular", size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }
}

#Preview {
    HelpView()
}
