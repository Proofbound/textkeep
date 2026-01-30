//
//  UpdateChecker.swift
//  TextKeep
//
//  Created by Claude on 2026-01-29.
//

import Foundation
import SwiftUI

/// Service for checking if a new version of TextKeep is available
@MainActor
class UpdateChecker: ObservableObject {
    // MARK: - Published Properties

    /// True if a newer version is available
    @Published var updateAvailable: Bool = false

    /// The latest version number available
    @Published var latestVersion: String = ""

    /// URL where users can download the update
    @Published var downloadUrl: String = ""

    /// True while a check is in progress
    @Published var isChecking: Bool = false

    /// True if the last check failed (network error, etc.)
    @Published var lastCheckFailed: Bool = false

    /// Error message if check failed
    @Published var errorMessage: String = ""

    // MARK: - Constants

    /// URL endpoint for version information
    private let versionEndpoint = "https://proofbound.com/textkeep/version.json"

    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 10.0

    // MARK: - Public Methods

    /// Checks for updates by fetching the latest version from the server
    func checkForUpdates() async {
        isChecking = true
        lastCheckFailed = false
        errorMessage = ""

        defer {
            isChecking = false
        }

        // Get current version
        let currentVersion = Bundle.main.appVersion

        // Fetch latest version from server
        guard let url = URL(string: versionEndpoint) else {
            handleError(message: "Invalid version endpoint URL")
            return
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                handleError(message: "Invalid server response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                handleError(message: "Server returned status code \(httpResponse.statusCode)")
                return
            }

            // Parse JSON response
            let versionInfo = try JSONDecoder().decode(VersionInfo.self, from: data)

            // Clean version strings (remove "v" prefix if present)
            let cleanLatestVersion = versionInfo.version.replacingOccurrences(of: "v", with: "")
            let cleanCurrentVersion = currentVersion.replacingOccurrences(of: "v", with: "")

            // Compare versions
            let hasUpdate = compareVersions(current: cleanCurrentVersion, latest: cleanLatestVersion)

            // Update state
            self.latestVersion = cleanLatestVersion
            self.downloadUrl = versionInfo.downloadUrl
            self.updateAvailable = hasUpdate
            self.lastCheckFailed = false

        } catch let decodingError as DecodingError {
            handleError(message: "Unable to parse version information")
            print("Decoding error: \(decodingError)")
        } catch let urlError as URLError {
            // Handle specific network errors
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                handleError(message: "No internet connection")
            case .timedOut:
                handleError(message: "Request timed out")
            case .cannotFindHost, .cannotConnectToHost:
                handleError(message: "Unable to reach update server")
            default:
                handleError(message: "Network error occurred")
            }
            print("Network error: \(urlError)")
        } catch {
            handleError(message: "Unable to check for updates")
            print("Unexpected error: \(error)")
        }
    }

    /// Returns the current app version
    func getCurrentVersion() -> String {
        return Bundle.main.appVersion
    }

    /// Opens the download URL in the default browser
    func openDownloadPage() {
        guard let url = URL(string: downloadUrl), !downloadUrl.isEmpty else {
            // Fallback to default TextKeep page
            if let fallbackUrl = URL(string: "https://proofbound.com/textkeep") {
                NSWorkspace.shared.open(fallbackUrl)
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private Methods

    /// Compares two semantic version strings
    /// Returns true if latest > current (update available)
    private func compareVersions(current: String, latest: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        // Compare each version component (major, minor, patch)
        for i in 0..<max(currentParts.count, latestParts.count) {
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0

            if latestPart > currentPart {
                return true  // Update available
            }
            if latestPart < currentPart {
                return false  // Current version is newer
            }
            // Continue to next component if equal
        }

        return false  // Versions are equal
    }

    /// Handles errors by updating state
    private func handleError(message: String) {
        self.lastCheckFailed = true
        self.errorMessage = message
        self.updateAvailable = false
    }
}

// MARK: - Data Models

/// Response structure from the version endpoint
struct VersionInfo: Codable {
    let version: String
    let downloadUrl: String
}
