import SwiftUI

struct WelcomeView: View {
    @Binding var hasSeenWelcome: Bool

    private let privacyURL = URL(string: "https://app.proofbound.com/privacy")!
    private let termsURL = URL(string: "https://app.proofbound.com/terms")!

    private var proofboundText: AttributedString {
        var string = AttributedString("Part of the family of Proofbound™ products that make it easy to publish your own book on Amazon")
        if let range = string.range(of: "Proofbound™") {
            string[range].link = URL(string: "https://proofbound.com")
        }
        return string
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo + Title
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)

                Text("Welcome to TextKeep")
                    .font(.custom("CrimsonText-SemiBold", size: 32))

                Text("Export your Messages to Markdown")
                    .font(.custom("Inter-Regular", size: 16))
                    .foregroundColor(.secondary)

                Text(proofboundText)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            Spacer()

            // Instructions
            VStack(alignment: .leading, spacing: 16) {
                InstructionRow(
                    icon: "lock.shield.fill",
                    title: "Full Disk Access Required",
                    description: "Grant access in System Settings to read your Messages database"
                )

                InstructionRow(
                    icon: "person.crop.circle.fill",
                    title: "Contacts (Optional)",
                    description: "Show contact names instead of phone numbers"
                )

                InstructionRow(
                    icon: "doc.text.fill",
                    title: "Export to Markdown",
                    description: "Save conversations as readable, searchable files"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // Get Started button
            Button(action: {
                hasSeenWelcome = true
            }) {
                Text("Get Started")
                    .font(.custom("Inter-SemiBold", size: 16))
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Legal links
            HStack(spacing: 8) {
                Link("Privacy Policy", destination: privacyURL)
                Text("•")
                    .foregroundColor(.secondary)
                Link("Terms of Service", destination: termsURL)
            }
            .font(.custom("Inter-Regular", size: 12))
            .foregroundColor(.secondary)

            Text("Version 1.3.3")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct InstructionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.custom("Inter-Regular", size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Inter-SemiBold", size: 14))

                Text(description)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView(hasSeenWelcome: .constant(false))
        .frame(width: 500, height: 500)
}
