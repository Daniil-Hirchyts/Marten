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
# MartenCore
cd MartenCore
swift build
swift test

# MartenMac
cd ../MartenMac
swift build
swift test

# MartenIOS (Phase 3 complete)
cd ../MartenIOS
swift build
swift test

# MartenIOSWrapper unsigned build (app + share/keyboard/widgets extensions)
xcodebuild -project ../MartenIOSWrapper/MartenIOSWrapper.xcodeproj \
  -scheme MartenIOSWrapper \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

# Run unsigned executable (local development)
swift run MartenMac
```

Notes:
- Unsigned `swift run MartenMac` is useful for local workflow validation.
- iCloud sync and push workflows require a signed app with proper entitlements.

### 2) Signed Build for CloudKit Sync

CloudKit requires a signed `.app` with matching entitlements/container.

This repo includes wrapper resources under `MartenMacWrapper/MartenMacWrapper/`:
- `MartenMacWrapper/MartenMacWrapper/Info.plist`
- `MartenMacWrapper/MartenMacWrapper/MartenMacWrapper.entitlements`
- `MartenMacWrapper/MartenMacWrapper/Assets.xcassets`

The wrapper Xcode project itself is intentionally not checked in.

If you already have a local wrapper project:
1. Open `MartenMacWrapper.xcodeproj` locally.
2. Select your app target.
3. In **Signing & Capabilities**:
   - choose your Team
   - set a bundle identifier you own (e.g. `com.yourcompany.marten`)
   - add **iCloud** + **CloudKit**
   - set/select your CloudKit container (e.g. `iCloud.com.yourcompany.marten`)
   - add **Push Notifications**
4. If needed, update container ID in `MartenCore/Sources/Sync/CloudKitConfiguration.swift`.
5. Build and run signed app.

If you do not yet have a local wrapper project:
- Create one locally (do not commit it).
- Wire it to package/build the `MartenMac` executable target.
- Reuse the provided wrapper resources above.

---

## Permissions

Marten uses runtime permission requests when related features are used.

- **Accessibility** - required for synthetic paste (Cmd+V injection)
- **Input Monitoring** - required for global hotkeys
- **Screen Recording** - required for OCR text capture; optional for screen-sharing mode

---

## Development Workflow

### Test Commands

```bash
# from MartenCore/
swift test

# from MartenMac/
swift test
```

UI tests in `MartenMac/Tests/MartenMacUITests` require an Xcode host runner.
Use Xcode Test Navigator for UI suites.

### Current Validation Snapshot (2026-02-11)

- `MartenCore`: `swift test` passed
- `MartenMac`: `swift test` passed (hosted UI suites still require Xcode runner)
- `MartenIOS`: `swift test` passed
- `MartenIOSWrapper`: unsigned iOS build passed with
  - `xcodebuild -project MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- Skipped tests are host-dependent UI tests in plain SwiftPM runs

### Beta Smoke Commands

```bash
# Optional: force onboarding flow for smoke validation
swift run MartenMac -- -resetOnboarding
```

Use this only when validating onboarding and first-launch UX flows.

---

## Project Structure

```text
Marten/
├── MartenCore/
│   ├── Sources/
│   └── Tests/
├── MartenMac/
│   ├── Sources/
│   └── Tests/
├── MartenIOS/
│   ├── Sources/
│   └── Tests/
├── MartenMacWrapper/
├── MartenIOSWrapper/
└── docs/
```

For detailed paths and ownership:
- [`CODEBASE.md`](./CODEBASE.md)

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
- [`BEST-PRACTICES.md`](./BEST-PRACTICES.md)
- [`ARCHITECTURE-DECISIONS.md`](./ARCHITECTURE-DECISIONS.md)

---

**Last Updated:** 2026-02-11
