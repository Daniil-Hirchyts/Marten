# Paste - Documentation

**macOS clipboard manager with iCloud sync**  
**Status:** Phase 7 Beta Testing (Ready)  
**Version:** 1.3.0

> **For AI agents:** Start with [CODEBASE.md](./CODEBASE.md) for architecture boundaries and implementation map.

---

## Documentation

- **[CODEBASE.md](./CODEBASE.md)** - Current architecture, component map, and implementation ownership
- **[BEST-PRACTICES.md](./BEST-PRACTICES.md)** - Security, logging, architecture, concurrency, and testing standards
- **[ARCHITECTURE-DECISIONS.md](./ARCHITECTURE-DECISIONS.md)** - ADRs for major technical decisions
- **[SETUP.md](./SETUP.md)** - Local setup, testing commands, signed CloudKit workflow

---

## Project Status

**Current:** Phase 7 - Beta Testing (Ready) ✅  
**Next:** Phase 8 - App Store Preparation

| Phase | Status | Description |
|-------|--------|-------------|
| 1. Core Foundation | ✅ Complete | Core Data model, capture baseline, initial UI shell |
| 2. Full Capture & UI | ✅ Complete | Multi-format extraction, pinboards, search UX |
| 3. Paste Behaviors | ✅ Complete | Paste engine, global hotkeys, paste stack workflows |
| 4. Privacy & Settings | ✅ Complete | Filtering, onboarding, permissions, settings surfaces |
| 5. CloudKit Sync | ✅ Complete | Inbound/outbound sync, conflict handling, assets |
| 6. Hardening & Refactor | ✅ Complete | Coordinator/DI cleanup, overlay decomposition, protocol boundaries |
| 7. Beta Testing | ✅ Ready | Stabilization complete, validation green, known risks documented |
| 8. App Store Prep | 🔜 Planned | Distribution assets, metadata, submission checks |
| 9. Launch | ⏸️ Planned | Release and post-launch monitoring |

---

## Preparation-to-Beta Modifications

- First-launch starter content seeding (`FirstLaunchContentSeeder`)
- Revamped onboarding flow and window lifecycle handling
- Native drag support with custom drag preview pipeline
- Sync hardening with inbound fetch timeout guardrails
- Asset cleanup planning for safer deletion flows
- Screen-sharing capture protection integration
- Improved image metadata quality via image resolution resolver

---

## Current Metrics

- **Swift files (Sources + Tests):** 304
- **Swift LOC (Sources + Tests):** 43,619
- **Module breakdown:**
  - `ClipboardCore/Sources` - 61 files / 8,366 LOC
  - `ClipboardCore/Tests` - 27 files / 4,635 LOC
  - `ClipboardMac/Sources` - 165 files / 26,161 LOC
  - `ClipboardMac/Tests` - 51 files / 4,457 LOC
- **Core Data entities:** 6 (`ClipItem`, `ClipRepresentation`, `Pinboard`, `LinkPreview`, `StackSession`, `StackEntry`)

---

## Validation Snapshot (2026-02-09)

- `ClipboardCore`: `swift test` passed (194 tests, 0 failures)
- `ClipboardMac`: `swift test` passed (192 tests, 0 failures, 10 skipped)
- UI tests in `ClipboardMacUITests` require an Xcode host runner and are skipped in plain SwiftPM runs

---

## Tech Stack

Swift 5.9+ | SwiftUI + AppKit | Core Data | CloudKit | XCTest  
**Third-party dependencies:** None

---

**Last Updated:** 2026-02-09
