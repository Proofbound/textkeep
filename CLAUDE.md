# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TextKeep is a macOS utility app for exporting iMessage conversations (both individual and group chats) to Markdown files. It reads the local Messages database, consolidates contacts, and generates formatted markdown with attachments. Part of the Proofbound family of tools.

- **Bundle ID:** `com.proofbound.textkeep`
- **Min macOS:** 13.0+
- **Privacy:** Local-only processing, no data collection

## Build Commands

```bash
# Build from command line
cd "/Users/sprague/dev/MacOS Apps/MessagesExporter"
xcodebuild -scheme TextKeep -configuration Release build

# Build and copy to /Applications
xcodebuild -scheme TextKeep -configuration Release build && \
rm -rf /Applications/TextKeep.app && \
cp -R "$(xcodebuild -scheme TextKeep -configuration Release -showBuildSettings | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')/TextKeep.app" /Applications/

# Clean build
xcodebuild -scheme TextKeep -configuration Release clean build
```

Or open `TextKeep.xcodeproj` in Xcode and build with Cmd+B.

## Architecture

```
TextKeepApp.swift          → App entry, first-run state management
    ├── WelcomeView.swift  → Onboarding screen with permissions instructions
    ├── ContentView.swift  → Main UI: conversation list + export panel
    └── HelpView.swift     → Help documentation and about page

MessagesViewModel.swift    → Core business logic (~800+ lines)
    ├── SQLite3 access to ~/Library/Messages/chat.db
    ├── Contact consolidation (groups handles by person)
    ├── Group chat loading with participant resolution
    ├── Message extraction (plain text + attributedBody blob parsing)
    └── Markdown export with attachment copying and sender attribution

ContactsService.swift      → Contacts.framework integration
    ├── Permission management
    ├── Phone/email normalization
    └── Display name lookup

Models.swift               → Data structures
    ├── Conversation protocol (unifies individual & group chats)
    ├── ConsolidatedContact, GroupChat, GroupParticipant
    └── Message (with sender attribution for groups)
```

## Key Technical Details

- **Database:** Direct SQLite3 C API (read-only) to Messages chat.db
- **Date Epoch:** Apple's CoreData epoch (Jan 1, 2001), stored as nanoseconds
- **Blob Parsing:** attributedBody uses Apple's "typedstream" format for newer messages
- **Group Messages:** Uses `message.handle_id` for sender attribution in group chats
- **Architecture:** Protocol-oriented design with `Conversation` protocol unifying individual and group chats
- **Entitlements:**
  - App sandbox disabled (requires Full Disk Access)
  - `com.apple.security.personal-information.addressbook` - Required for Contacts permission dialog
  - `com.apple.security.files.user-selected.read-write` - For export file saving
- **Fonts:** Crimson Text (headings), Inter (body) - bundled in Fonts/
- **UI:** SwiftUI with custom Proofbound branding and comprehensive help system

## Required Permissions

1. **Full Disk Access** - To read ~/Library/Messages/chat.db
2. **Contacts** (optional) - To show names instead of phone numbers

## Version Management

Version is set in `project.pbxproj` via `MARKETING_VERSION`. Update in both Debug and Release configurations.

## Distribution

For public releases:
1. Update `MARKETING_VERSION` in project.pbxproj
2. In Xcode: Product > Archive
3. Distribute with Developer ID (handles signing and notarization automatically)
4. Export notarized app and create zip file
5. Upload to GitHub releases with version tag (e.g., v1.1.1)
