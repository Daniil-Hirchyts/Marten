# Paste - Documentation

**macOS clipboard manager with iCloud sync**  
**Status:** Phase 6 Complete | Production Ready  
**Version:** 1.3.0

> **For AI agents:** Start with [CODEBASE.md](./CODEBASE.md) - it has a "Where is X?" quick reference table.

---

## Documentation

- **[CODEBASE.md](./CODEBASE.md)** - Start here: codebase overview, quick reference
- **[ARCHITECTURE-DECISIONS.md](./ARCHITECTURE-DECISIONS.md)** - 12 ADRs explaining key decisions
- **[SETUP.md](./SETUP.md)** - Development environment setup

---

## Project Status

**Current:** Phase 6 Complete ✅  
**Next:** Phase 7 - Beta Testing

| Phase | Status | Tests | Description |
|-------|--------|-------|-------------|
| 1. Core Foundation | ✅ | 32 | Core Data, capture, UI |
| 2. Full Capture & UI | ✅ | 36 | All types, pinboards, search |
| 3. Paste Behaviors | ✅ | 68 | Paste, hotkeys, stack |
| 4. Privacy & Settings | ✅ | 28 | Filters, settings, onboarding |
| 5. CloudKit Sync | ✅ | 133 | Sync, conflicts, assets |
| 6. Hardening | ✅ | 289 | Performance, tests, accessibility |
| 7. Beta Testing | 🔜 | - | Internal + TestFlight |
| 8. App Store | ⏸️ | - | Assets, submission |
| 9. Launch | ⏸️ | - | Release, monitoring |

**289/289 tests passing** ✅

---

## Key Metrics

**Code:** 123 Swift files (44 Core + 79 Mac), ~15k LOC  
**Entities:** 7 Core Data entities  
**Services:** 10 system services  
**Performance:** All targets met ✅

---

## Features

**Core:** Clipboard monitoring, deduplication, retention, overlay UI, pinboards, search, paste engine, hotkeys, quick paste (1-9), paste stack  
**Privacy:** Ignored apps, confidential content detection, link previews, settings, onboarding  
**Sync:** CloudKit bi-directional, conflict resolution, asset sync, error handling  
**Hardening:** Performance optimization, UI tests, VoiceOver, migration, crash reporting

---

## Tech Stack

Swift 5.9+ | SwiftUI + AppKit | Core Data | CloudKit | XCTest  
**No third-party dependencies**

---

**Questions?** Read [CODEBASE.md](./CODEBASE.md) or [ARCHITECTURE-DECISIONS.md](./ARCHITECTURE-DECISIONS.md)

**Last Updated:** 2026-02-02
