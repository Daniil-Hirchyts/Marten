# Setup

## Prerequisites

- macOS 26.0+
- Xcode 26.0+
- Swift 5.9+
- Apple Developer account (for signed CloudKit builds)

---

## Quick Start

### 1) Build and Test (Unsigned Development)

```bash
# ClipboardCore
cd ClipboardCore
swift build
swift test

# ClipboardMac
cd ../ClipboardMac
swift build
swift test

# Run unsigned executable (local development)
swift run ClipboardMac
```

Notes:
- Unsigned `swift run ClipboardMac` is useful for local workflow validation.
- iCloud sync and push workflows require a signed app with proper entitlements.

### 2) Signed Build for CloudKit Sync

CloudKit requires a signed `.app` with matching entitlements/container.

This repo includes wrapper resources under `ClipboardMacWrapper/ClipboardMacWrapper/`:
- `ClipboardMacWrapper/ClipboardMacWrapper/Info.plist`
- `ClipboardMacWrapper/ClipboardMacWrapper/ClipboardMacWrapper.entitlements`
- `ClipboardMacWrapper/ClipboardMacWrapper/Assets.xcassets`

The wrapper Xcode project itself is intentionally not checked in.

If you already have a local wrapper project:
1. Open `ClipboardMacWrapper.xcodeproj` locally.
2. Select your app target.
3. In **Signing & Capabilities**:
   - choose your Team
   - set a bundle identifier you own (e.g. `com.yourcompany.paste`)
   - add **iCloud** + **CloudKit**
   - set/select your CloudKit container (e.g. `iCloud.com.yourcompany.paste`)
   - add **Push Notifications**
4. If needed, update container ID in `ClipboardCore/Sources/Sync/CloudKitConfiguration.swift`.
5. Build and run signed app.

If you do not yet have a local wrapper project:
- Create one locally (do not commit it).
- Wire it to package/build the `ClipboardMac` executable target.
- Reuse the provided wrapper resources above.

---

## Permissions

Paste uses runtime permission requests when related features are used.

- **Accessibility** - required for synthetic paste (Cmd+V injection)
- **Input Monitoring** - required for global hotkeys
- **Screen Recording** - required for OCR text capture; optional for screen-sharing mode

---

## Development Workflow

### Test Commands

```bash
# from ClipboardCore/
swift test

# from ClipboardMac/
swift test
```

UI tests in `ClipboardMac/Tests/ClipboardMacUITests` require an Xcode host runner.
Use Xcode Test Navigator for UI suites.

### Current Validation Snapshot (2026-02-04)

- `ClipboardCore`: 189 tests executed, 0 failures
- `ClipboardMac`: 167 tests executed, 0 failures, 10 skipped
- Skipped tests are host-dependent UI tests in plain SwiftPM runs

---

## Project Structure

```text
Paste/
├── ClipboardCore/
│   ├── Sources/
│   └── Tests/
├── ClipboardMac/
│   ├── Sources/
│   └── Tests/
├── ClipboardMacWrapper/
└── docs/
```

For detailed paths and ownership:
- [`CODEBASE.md`](./CODEBASE.md)
- [`FILE-INVENTORY.md`](./FILE-INVENTORY.md)

---

## Build Configurations

- **Debug:** local development and diagnostics
- **Release:** optimized build settings for distribution

---

## Troubleshooting

### "CloudKit Sync Unavailable"
- Confirm app is signed with iCloud + push entitlements.
- Verify container identifier matches `CloudKitConfiguration`.
- Confirm iCloud account is signed in on the machine.

### "Accessibility Permission Denied"
- Open System Settings -> Privacy & Security -> Accessibility.
- Ensure the signed app binary has permission enabled.

### Hotkeys Not Triggering
- Verify Input Monitoring permission is granted.
- Confirm shortcuts in Settings do not conflict with system/global shortcuts.

### OCR Capture Doesn't Start
- Verify Screen Recording permission is granted for the app.
- If denied, reopen OCR capture and use the in-app shortcut to System Settings.

### Swift Tests Pass but UI Tests Do Not Run
- Expected for `swift test` on UI-hosted suites.
- Run UI tests from Xcode with host app context.

---

## References

- [`INDEX.md`](./INDEX.md)
- [`CODEBASE.md`](./CODEBASE.md)
- [`FILE-INVENTORY.md`](./FILE-INVENTORY.md)
- [`BEST-PRACTICES.md`](./BEST-PRACTICES.md)
- [`ARCHITECTURE-DECISIONS.md`](./ARCHITECTURE-DECISIONS.md)

---

**Last Updated:** 2026-02-04
