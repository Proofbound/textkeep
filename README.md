# TextKeep

<p align="center">
  <img src="marketing/textkeep-logo-with-text.svg" alt="TextKeep Logo" width="200"/>
</p>

A macOS app for exporting your iMessage conversations to Markdown files.

**Part of the [Proofbound](https://proofbound.com) family of tools.**

## Features

- **Export to Markdown** - Save your message history as clean, readable Markdown files
- **Contact Integration** - Displays contact names from your Contacts app instead of raw phone numbers
- **Smart Consolidation** - Groups multiple phone numbers for the same contact (e.g., "+1 (555) 123-4567" and "5551234567" are recognized as the same person)
- **Message Preview** - See recent messages before exporting to verify you have the right conversation
- **Attachment Support** - Copies images, videos, and audio files to an `attachments/` folder with proper Markdown links
- **Date Range Filtering** - Export only messages within a specific date range

## Requirements

- macOS 13.0 or later
- **Full Disk Access** - Required to read the Messages database (`~/Library/Messages/chat.db`)
- **Contacts Access** (optional) - For displaying contact names instead of phone numbers

## Installation

1. Clone the repository
2. Open `TextKeep.xcodeproj` in Xcode
3. Build and run (Cmd+R)
4. Grant Full Disk Access when prompted (System Settings > Privacy & Security > Full Disk Access)

## Usage

1. Launch TextKeep
2. Grant permissions when prompted:
   - **Full Disk Access** - Required to read your Messages
   - **Contacts** - Optional, but enables showing names instead of phone numbers
3. Select a contact from the sidebar
4. Review the message preview to confirm it's the conversation you want
5. Set your desired date range
6. Click "Export to Markdown" and choose a save location

## Export Format

Messages are exported as Markdown with the following structure:

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

![Image: photo.jpg](attachments/1_photo.jpg)
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
- Handles the `attributedBody` blob format for newer macOS message storage

## Known Limitations

- **iCloud Messages** - Attachments stored only in iCloud may show as "not found". Scroll through old conversations in Messages.app to trigger downloads.
- **Group Messages** - Currently focuses on individual conversations; group chat support is limited.

## About Proofbound

TextKeep is developed by [Proofbound](https://proofbound.com), creators of AI-powered book creation tools. We believe in building useful, privacy-respecting software.

## License

MIT License - See LICENSE file for details.
