# Paste - Documentation

**macOS clipboard manager with iCloud sync**  
**Status:** Phase 7 Beta Testing  
**Version:** 1.3.0

> **For AI agents:** Start with [CODEBASE.md](./CODEBASE.md) for architecture, boundaries, and "Where is X?" navigation.

---

## Documentation

- **[CODEBASE.md](./CODEBASE.md)** - Current architecture, component map, data flows, and implementation boundaries
- **[FILE-INVENTORY.md](./FILE-INVENTORY.md)** - Full Swift file appendix (Sources + Tests)
- **[BEST-PRACTICES.md](./BEST-PRACTICES.md)** - Security, logging, architecture, and testing standards
- **[ARCHITECTURE-DECISIONS.md](./ARCHITECTURE-DECISIONS.md)** - ADRs for key technical decisions
- **[SETUP.md](./SETUP.md)** - Local development and signed CloudKit setup

---

## Project Status

**Current:** Phase 7 - Beta Testing ✅  
**Next:** Phase 8 - App Store Preparation

| Phase | Status | Description |
|-------|--------|-------------|
| 1. Core Foundation | ✅ Complete | Core Data model, capture baseline, initial UI shell |
| 2. Full Capture & UI | ✅ Complete | Multi-format extraction, pinboards, search UX |
| 3. Paste Behaviors | ✅ Complete | Paste engine, global hotkeys, paste stack workflows |
| 4. Privacy & Settings | ✅ Complete | Filtering, onboarding, permissions, settings surfaces |
| 5. CloudKit Sync | ✅ Complete | Inbound/outbound sync, conflict handling, assets |
| 6. Hardening & Refactor | ✅ Complete | Coordinator/DI cleanup, overlay decomposition, protocol boundaries |
| 7. Beta Testing | ✅ In Progress | Stabilization, UX polish, regression testing |
| 8. App Store Prep | 🔜 Planned | Distribution assets, metadata, submission checks |
| 9. Launch | ⏸️ Planned | Release and post-launch monitoring |

---

## Current Metrics

- **Swift files (Sources + Tests):** 291
- **Swift LOC (Sources + Tests):** 38,618
- **Module breakdown:**
  - `ClipboardCore/Sources` - 61 files / 7,872 LOC
  - `ClipboardCore/Tests` - 27 files / 4,454 LOC
  - `ClipboardMac/Sources` - 158 files / 22,449 LOC
  - `ClipboardMac/Tests` - 45 files / 3,843 LOC
- **Core Data entities:** 6 (`ClipItem`, `ClipRepresentation`, `Pinboard`, `LinkPreview`, `StackSession`, `StackEntry`)

---

## Validation Snapshot (2026-02-04)

- `ClipboardCore`: `swift test` passed (189 tests, 0 failures)
- `ClipboardMac`: `swift test` passed (167 tests, 0 failures, 10 skipped)
- UI tests in `ClipboardMacUITests` require an Xcode host runner and are skipped in plain SwiftPM runs

---

## Feature Areas

- **Core:** Clipboard monitoring, deduplication, retention policies, pinboards, search, paste stack
- **Privacy:** Confidential/transient filtering, ignored apps, locked pinboards, screen sharing mode
- **Sync:** Manual CloudKit orchestration with inbound/outbound engines and asset synchronization
- **Power Tools:** Shortcut recorder, OCR text capture (static/live modes), share/save actions, optional Apple Intelligence text transforms

---

## Tech Stack

Swift 5.9+ | SwiftUI + AppKit | Core Data | CloudKit | XCTest  
**No third-party dependencies**

---

**Last Updated:** 2026-02-04
