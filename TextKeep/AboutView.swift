import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            // App Name
            Text("TextKeep")
                .font(.custom("CrimsonText-SemiBold", size: 32))

            // Version
            Text("Version 1.3.2")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundColor(.secondary)

            Divider()
                .padding(.vertical, 8)

            // Copyright
            VStack(spacing: 8) {
                Text("© 2026 Proofbound. All rights reserved.")
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundColor(.secondary)

                Link("proofbound.com", destination: URL(string: "https://proofbound.com")!)
                    .font(.custom("Inter-Medium", size: 12))
            }

            // Tagline
            Text("Part of the Proofbound family of tools")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 350)
    }
}

#Preview {
    AboutView()
}
