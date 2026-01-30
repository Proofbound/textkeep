# TextKeep

<p align="center">
  <img src="marketing/textkeep-logo-with-text.svg" alt="TextKeep Logo" width="200"/>
</p>

A macOS app for exporting your iMessage conversations to Markdown files.

**Part of the [Proofbound](https://proofbound.com) family of tools.**

<p align="center">
  <img src="marketing/screenshot-export-example.png" alt="TextKeep Export Example" width="400"/>
</p>

## Features

- **Export to Markdown** - Save your message history as clean, readable Markdown files
- **Group Chat Support** - Export both individual conversations and group messages with full participant attribution
- **Contact Integration** - Displays contact names from your Contacts app instead of raw phone numbers
- **Smart Consolidation** - Groups multiple phone numbers for the same contact (e.g., "+1 (555) 123-4567" and "5551234567" are recognized as the same person)
- **Message Preview** - See recent messages before exporting to verify you have the right conversation
- **Attachment Support** - Copies images, videos, and audio files to an `attachments/` folder with proper Markdown links
- **Date Range Filtering** - Export only messages within a specific date range
- **Reaction Support** - iMessage reactions displayed with emoji (❤️ Loved, 👍 Liked, 😂 Laughed at, etc.)
- **Group Actions** - System messages for member changes formatted clearly (added/removed participants)
- **Built-in Help** - Comprehensive documentation accessible from within the app

## Requirements

- macOS 13.0 or later
- **Full Disk Access** - Required to read the Messages database (`~/Library/Messages/chat.db`)
- **Contacts Access** (optional) - For displaying contact names instead of phone numbers

## Installation

### Download Pre-built App (Recommended)

1. Download the latest release from [GitHub Releases](https://github.com/Proofbound/textkeep/releases)
2. Unzip `TextKeep-v1.3.4.zip`
3. Move `TextKeep.app` to your Applications folder
4. Launch and follow the permission prompts

### Build from Source

1. Clone the repository
2. Open `TextKeep.xcodeproj` in Xcode
3. Build and run (Cmd+R)
4. Grant Full Disk Access when prompted (System Settings > Privacy & Security > Full Disk Access)

## Usage

1. **Launch TextKeep** - You'll see a welcome screen on first launch
2. **Grant permissions when prompted:**
   - **Full Disk Access** - Click "Open System Settings" and enable TextKeep (required to read your Messages)
   - **Contacts** - Click "Allow" when the system dialog appears (optional, but recommended for showing names instead of phone numbers)
3. **Select a contact** from the sidebar
4. **Review the message preview** to confirm it's the conversation you want
5. **Set your desired date range**
6. **Click "Export to Markdown"** and choose a save location

## Export Format

### Individual Conversations

```markdown
# Messages with John Doe

**Contact:** +1 (555) 123-4567
**Date Range:** January 1, 2024 - January 20, 2025
**Total Messages:** 142
**Exported:** Jan 20, 2025 at 3:45 PM

---

## January 15, 2024

10:30 AM - **Me**
> Hey, how's it going?

10:32 AM - **John Doe**
> Great! Just finished that project.

10:33 AM - **Me**
> ❤️ Loved: "Great! Just finished that project."

![Image: photo.jpg](attachments/1_photo.jpg)
```

### Group Chats

```markdown
# Group Chat: Weekend Plans

**Participants:** John Doe (+1 555-123-4567), Jane Smith (jane@example.com), Bob Wilson (+1 555-987-6543)
**Date Range:** January 1, 2025 - January 22, 2026
**Total Messages:** 234
**Exported:** Jan 22, 2026 at 3:45 PM

---

## January 15, 2025

9:15 AM - **System**
> ℹ️ [System] John Doe added Bob Wilson

10:30 AM - **John Doe**
> Hey everyone, meeting at 3pm?

10:32 AM - **Me**
> Sounds good!

10:33 AM - **Jane Smith**
> I'll be there
```

## Privacy & Security

- **Read-only** - TextKeep only reads from your Messages database; it never modifies it
- **Local only** - No data is sent anywhere; everything stays on your Mac
- **No telemetry** - No analytics, tracking, or network connections
- **Open source** - Full source code available for review

## Technical Details

- Built with SwiftUI
- Uses SQLite3 to read the Messages database directly
- Uses the Contacts framework for contact name resolution
- Handles both modern (NSKeyedArchiver) and legacy (typedstream) `attributedBody` blob formats
- Dual-source text extraction ensures complete message recovery from database

## Known Limitations

- **iCloud Messages** - Attachments stored only in iCloud may show as "not found". Scroll through old conversations in Messages.app to trigger downloads.

## About Proofbound

TextKeep is developed by [Proofbound](https://proofbound.com), creators of AI-powered book creation tools. We believe in building useful, privacy-respecting software.

## Changelog

### v1.3.4 (2026-01-29)
- **Update Checker** - Check for new versions directly from the app with "Check for Updates..." menu command (Help > Check for Updates or Cmd+U)
- **Smart Version Display** - All version displays now read dynamically from app bundle (no more hardcoded versions)
- **In-App Update Notifications** - Get notified when new versions are available with one-click download links
- **Privacy-Focused** - Manual checking only, no automatic background checks or telemetry

### v1.3.2 (2026-01-23)
- **Fixed Message Truncation** - Added NSUnarchiver support for legacy typedstream format messages (fixes truncated text from older conversations)
- **Dual-Source Text Extraction** - Compares both `text` column and `attributedBody` blob, uses whichever is more complete
- **Improved Blob Parsing** - Increased heuristic scanning limit from 5KB to 100KB for very long messages
- **Enhanced About Menu** - Displays Proofbound copyright and link to proofbound.com
- **Help Menu** - Added Help menu (Cmd+?) that opens comprehensive help documentation in separate window
- **Reaction Formatting** - Display iMessage reactions with emoji (❤️ Loved, 👍 Liked, etc.)
- **Group Action Messages** - Show system messages for group member changes (ℹ️ [System] Added Person)
- **Cleaner Exports** - Removed attachment identifier artifacts and metadata leakage from exports

### v1.2.0 (2026-01-22)
- **Group Message Support** - Full support for exporting group chats with proper sender attribution
- **Enhanced UI** - Added Proofbound logo, improved header with tagline, consistent custom fonts throughout
- **Built-in Help** - Comprehensive help page with documentation, troubleshooting, and about section
- **Protocol-Oriented Architecture** - Unified handling of individual and group conversations
- Performance optimizations with sender name caching for group exports

### v1.1.1 (2026-01-22)
- Fixed Contacts permission dialog not appearing on first launch
- Added required addressbook entitlement for proper macOS permission prompts

### v1.1.0 (2026-01-22)
- Welcome screen with onboarding instructions
- Custom fonts (Crimson Text, Inter)
- Privacy Policy and Terms of Service links
- Updated bundle identifier to com.proofbound.textkeep

### v1.0.0 (2026-01-21)
- Initial release
- Export iMessage conversations to Markdown
- Contact integration with name display
- Attachment support with automatic copying
- Date range filtering

## License

MIT License - See LICENSE file for details.
