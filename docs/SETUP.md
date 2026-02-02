# Setup

## Prerequisites

- macOS 26.0+
- Xcode 26.0+
- Swift 5.9+
- Apple Developer account (for code signing and CloudKit)

---

## Quick Start

### 1. Build and Run (Command Line)

```bash
# Build + test ClipboardCore
cd ClipboardCore
swift build
swift test

# Build + test ClipboardMac
cd ../ClipboardMac
swift build
swift test

# Run the app (unsigned, no iCloud sync)
swift run ClipboardMac
```

### 2. Build Signed App (Required for iCloud Sync)

CloudKit requires a signed `.app` with correct entitlements.

1. Open `ClipboardMacWrapper/ClipboardMacWrapper.xcodeproj` in Xcode
2. Select the app target
3. In **Signing & Capabilities**:
   - Choose your Team
   - Set a bundle identifier you own (e.g., `com.yourcompany.paste`)
   - Add **iCloud** capability:
     - Enable **CloudKit**
     - Select/create a container (e.g., `iCloud.com.yourcompany.paste`)
   - Add **Push Notifications** capability (required for CloudKit subscriptions)
4. Update container ID in `ClipboardCore/Sources/Sync/CloudKitConfiguration.swift` if different
5. Build & Run in Xcode (produces signed `.app` with entitlements)

---

## Permissions

The app requires these system permissions:

- **Accessibility** — Required for paste injection (CGEvent Cmd+V)
- **Input Monitoring** — Required for global hotkeys
- **Screen Recording** — Optional, for screen sharing mode

Permissions are requested at runtime when features are first used.

---

## Development Workflow

### Running Tests

```bash
# Unit tests (ClipboardCore + ClipboardMac)
swift test

# UI tests (requires Xcode)
# Open in Xcode and use Test Navigator (⌘6)
```

### Project Structure

```
Paste/
├── ClipboardCore/          Swift package (business logic)
│   ├── Sources/
│   │   ├── BusinessRules/      Stores, repositories, services
│   │   ├── DataModel/          Core Data entities
│   │   ├── Persistence/        Core Data stack
│   │   └── Sync/               CloudKit sync
│   └── Tests/              Unit tests
│
├── ClipboardMac/           Swift package (macOS app)
│   ├── Sources/
│   │   ├── ClipboardMacApp/      UI & app lifecycle
│   │   └── ClipboardMacServices/ System services
│   └── Tests/              Unit & UI tests
│
└── docs/                   Documentation
```

### Build Configurations

- **Debug:** Local development, verbose logging
- **Release:** Optimized, privacy-safe logging only

---

## Troubleshooting

### "CloudKit Sync Unavailable"
- Ensure app is signed with correct entitlements
- Verify CloudKit container ID matches configuration
- Check iCloud account is signed in (System Settings)

### "Accessibility Permission Denied"
- Go to System Settings → Privacy & Security → Accessibility
- Add the app and enable

### Tests Fail
- Run `swift build` first to ensure clean build
- Check test output for specific failures
- UI tests require Xcode runner (can't run via `swift test`)

---

## References

- [CODEBASE.md](./CODEBASE.md) — Architecture overview
- [BEST-PRACTICES.md](./BEST-PRACTICES.md) — Development guidelines
- [ARCHITECTURE-DECISIONS.md](./ARCHITECTURE-DECISIONS.md) — Design decisions

---

**Last Updated:** 2026-02-03
