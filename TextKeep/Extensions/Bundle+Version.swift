//
//  Bundle+Version.swift
//  TextKeep
//
//  Created by Claude on 2026-01-29.
//

import Foundation

extension Bundle {
    /// Returns the app version from Info.plist (CFBundleShortVersionString)
    /// This is set by MARKETING_VERSION in project.pbxproj
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}
