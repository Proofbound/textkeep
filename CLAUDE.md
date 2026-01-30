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

## Distribution & Release Process

### Version Bumping

Version is controlled by `MARKETING_VERSION` in `project.pbxproj` (set in both Debug and Release configurations).

```bash
# Update version in project file (replace X.X.X with new version)
# Lines ~363 and ~394 in project.pbxproj
MARKETING_VERSION = 1.3.4;
```

### Full Release Process

**1. Update Version Number**
```bash
# Edit project.pbxproj to bump MARKETING_VERSION
# Both Debug and Release configurations must match
```

**2. Build and Notarize in Xcode**
```bash
# Open Xcode
Product > Archive
# When archive completes, click "Distribute App"
# Select "Developer ID" distribution
# Choose "Upload" (this notarizes automatically)
# Wait for notarization to complete (check email or Xcode Organizer)
# Click "Export Notarized App" and save to a temporary location
```

**3. Copy Notarized App to Repo**
```bash
cd "/Users/sprague/dev/MacOS Apps/MessagesExporter"
# Copy the notarized TextKeep.app from Xcode export to repo root
cp -R ~/path/to/exported/TextKeep.app .
```

**4. Staple Notarization Ticket (Optional but Recommended)**
```bash
# This embeds the notarization ticket so the app works offline
xcrun stapler staple TextKeep.app
# Should output: "The staple and validate action worked!"
```

**5. Create Versioned Zip**
```bash
# Use ditto to preserve all metadata and notarization
ditto -c -k --keepParent TextKeep.app TextKeep-v1.3.4.zip
# Result: TextKeep-v1.3.4.zip (~1.2MB)
```

**6. Commit and Push**
```bash
git add .
git commit -m "Release v1.3.4: Description of changes"
git push
```

**7. Create GitHub Release**
```bash
# Using gh CLI (recommended)
gh release create v1.3.4 TextKeep-v1.3.4.zip \
  --title "Release v1.3.4: Feature description" \
  --notes "$(cat <<'EOF'
## New Features
- Feature 1
- Feature 2

## Improvements
- Improvement 1

## Bug Fixes
- Fix 1
EOF
)"

# Or manually at: https://github.com/Proofbound/textkeep/releases/new
```

**8. Update Version Check Endpoint**
```bash
# Update https://proofbound.com/textkeep/version.json
{
  "version": "1.3.4",
  "downloadUrl": "https://proofbound.com/textkeep"
}
```

### Quick Reference Commands

```bash
# Complete release from notarized app in Downloads
cd "/Users/sprague/dev/MacOS Apps/MessagesExporter"
cp -R ~/Downloads/TextKeep.app .
xcrun stapler staple TextKeep.app
ditto -c -k --keepParent TextKeep.app TextKeep-v1.3.4.zip
git add . && git commit -m "Release v1.3.4: Description"
git push
gh release create v1.3.4 TextKeep-v1.3.4.zip --title "..." --notes "..."
# Then update version.json on proofbound.com
```

### Update Checker System

TextKeep v1.3.4+ includes automatic update checking:
- Users can check via Help menu → "Check for Updates..." (Cmd+U)
- Or via "Check for Updates" button in Help view footer
- Fetches latest version from `https://proofbound.com/textkeep/version.json`
- On new release, update the JSON file to notify users:
  ```json
  {
    "version": "1.3.5",
    "downloadUrl": "https://proofbound.com/textkeep"
  }
  ```
