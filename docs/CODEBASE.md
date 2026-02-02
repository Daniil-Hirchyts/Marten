# Paste - Codebase Guide

**macOS clipboard manager with iCloud sync**  
**Status:** Phase 6 Complete | SwiftPM tests passing | Production-ready

---

## Quick Navigation

```
Paste/
├── ClipboardCore/          Platform-agnostic logic
│   ├── Sources/           Assets, business rules, persistence, sync
│   └── Tests/             Unit tests
│
├── ClipboardMac/           macOS package
│   ├── Sources/
│   │   ├── ClipboardMacApp/       UI + lifecycle
│   │   ├── ClipboardMacServices/  System services
│   │   └── ClipboardMacValidation/ Validation executable
│   └── Tests/              Unit + UI tests
│
├── ClipboardMacWrapper/    Xcode wrapper project (signing, entitlements, assets)
│
└── docs/                   Documentation
    ├── INDEX.md           Main navigation
    ├── CODEBASE.md        This file
    ├── ARCHITECTURE-DECISIONS.md  ADRs
    └── SETUP.md           Dev setup
```

---

## Where is Functionality X?

| Feature | Location |
|---------|----------|
| **Clipboard capture** | `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/` |
| **Capture orchestration** | `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/CaptureCoordinator.swift` |
| **Paste to app** | `ClipboardMac/Sources/ClipboardMacServices/Services/PasteEngine/` |
| **Global hotkeys** | `ClipboardMac/Sources/ClipboardMacServices/Services/HotkeyManager/` |
| **Hotkey coordination** | `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/HotkeyCoordinator.swift` |
| **Overlay UI** | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayShellView.swift` |
| **Overlay coordinators** | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayPreviewCoordinator.swift`, `OverlayActionHandlers.swift`, `OverlayPinboardLockHandler.swift` |
| **Item cards** | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemCard.swift` |
| **Search** | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlaySearchViewModel.swift` |
| **Settings** | `ClipboardMac/Sources/ClipboardMacApp/UI/Settings/` |
| **Settings providers** | `ClipboardMac/Sources/ClipboardMacServices/Services/Settings/*Providing.swift` |
| **Core Data CRUD** | `ClipboardCore/Sources/BusinessRules/ClipItemRepository.swift` |
| **CloudKit sync** | `ClipboardCore/Sources/Sync/SyncCoordinator.swift` |
| **Password detection** | `ClipboardCore/Sources/BusinessRules/Classifiers/` |
| **Thumbnails** | `ClipboardMac/Sources/ClipboardMacServices/Services/Thumbnails/` |

---

## Architecture Components

### Services (ClipboardCore/Sources/BusinessRules/)
- **ClipItemRepository** — CRUD operations, persistence façade
- **ClipItemStore** — Thin façade over repository (for legacy compatibility)
- **PinboardRepository** — Pinboard management
- **SearchService** — Search text extraction
- **AssetManagementService** — Asset lifecycle management
- **ClipItemDeduplicationService** — Duplicate detection
- **ClipItemRetentionService** — Retention policy enforcement
- **ClipItemUsageService** — Usage tracking

### Coordinators (ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/)
- **CaptureCoordinator** — Orchestrates capture pipeline
- **HotkeyCoordinator** — Hotkey registration and reload
- **OnboardingCoordinator** — Onboarding flow management
- **IntegrityCheckService** — Startup integrity checks

### Overlay Coordinators (ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/)
- **OverlayPreviewCoordinator** — Preview popover state and editor window coordination
- **OverlayPinboardLockHandler** — Pinboard lock/unlock and visibility logic
- **OverlayActionHandlers** — Consolidates all item/pinboard user actions

### Settings Providers (ClipboardMac/Sources/ClipboardMacServices/Services/Settings/)
- **CaptureSettingsProviding** — Capture behavior settings
- **LinkPreviewSettingsProviding** — Link preview toggle
- **PasteSettingsProviding** — Paste behavior settings
- **ScreenSharingSettingsProviding** — Screen sharing visibility behavior

---

## Core Concepts

### ClipItem
The fundamental unit - a captured clipboard item.
- **Entity:** Core Data `ClipItem`
- **Props:** `id`, `primaryText`, `itemType`, `contentHash`, `createdAt`
- **Relations:** `representations` (multiple formats), `pinnedInPinboards`

### Representations
Multiple formats of the same content (text + RTF + HTML).
- **Entity:** `ClipRepresentation`
- **Kinds:** plainText, rtf, html, image, fileData, url

### Pinboards
User-created folders for organization.
- **Entity:** `Pinboard`
- **Special:** "All Items", "Favorites", "Paste Stack"

### Other Entities
- **LinkPreview:** URL metadata (title, description, image)
- **StackSession:** Paste stack workflow container
- **StackEntry:** Individual items in a paste stack

### Sync
Bi-directional CloudKit synchronization.
- **Engines:** OutboundSyncEngine (local→cloud), InboundSyncEngine (cloud→local)
- **Conflicts:** Last-writer-wins for Pinboards, append-only for ClipItems

---

## Key Patterns

**MVVM:** SwiftUI views + `@ObservableObject` ViewModels
**Repository:** `ClipItemRepository` abstracts persistence (replaces direct ClipItemStore usage)
**Service Layer:** Domain services for dedupe, retention, usage, asset management
**DI:** `AppServiceContainer` provides dependencies via protocols
**Coordinator:** `CaptureCoordinator`, `HotkeyCoordinator`, `SyncCoordinator` orchestrate workflows
**Settings Providers:** Protocol-based settings access (no @AppStorage in services)

---

## Data Flows

### Capture
```
User copies → PasteboardMonitor polls → ClipItemStore creates →
Core Data insert → OutboundSyncEngine → CloudKit upload
```

### Paste
```
User presses hotkey → HotkeyManager → OverlayWindow shows →
User selects item → PasteEngine copies to pasteboard →
Sends Cmd+V CGEvent to active app
```

### Sync (Inbound)
```
Push notification → InboundSyncEngine fetches changes →
CloudRecordMapper converts → ConflictResolver handles conflicts →
Merge into Core Data → UI updates
```

---

## Key Decisions

See [`ARCHITECTURE-DECISIONS.md`](./ARCHITECTURE-DECISIONS.md) for full ADRs:

- **Core Data vs SwiftData:** Core Data for CloudKit compatibility
- **Manual CloudKit vs Auto:** Manual for explicit conflict resolution
- **Polling vs Notifications:** Polling (NSPasteboard has no change notifications)
- **AppKit + SwiftUI:** Hybrid for system integration + modern UI
- **Heuristic Classifiers:** Fast, on-device vs ML overhead

---

## Testing

**Test targets:** `ClipboardCoreTests`, `ClipboardMacTests`, `ClipboardMacAppTests`, `ClipboardMacUITests`

**Run:** `swift test` for unit tests, or Xcode Test Navigator for UI tests.

---

## Common Tasks

### Find where a feature is implemented
1. Check "Where is Functionality X?" table above
2. Or grep: `grep -r "class FeatureName" ClipboardCore ClipboardMac`

### Add a new feature
1. Understand requirements and design approach
2. Add business logic to ClipboardCore if platform-agnostic
3. Add UI to ClipboardMacApp
4. Add system service to ClipboardMacServices if needed
5. Write tests

### Fix a bug
1. Locate code (use table above or grep)
2. Understand intended behavior from code/tests
3. Fix with minimal change
4. Add regression test

---

## Performance Targets

- Overlay open: <500ms ✅ (~415ms avg)
- Capture: <50ms ✅ (~30ms avg)
- Search: <100ms ✅ (~4ms for 1k items)
- Hashing: <1ms ✅ (~0.3ms avg)

---

## Dependencies

**ClipboardCore:** Foundation, CoreData, CloudKit, CryptoKit, Combine  
**ClipboardMac:** AppKit, SwiftUI, AVFoundation, CoreGraphics

**No third-party dependencies**

---

## Permissions Required

- **Accessibility:** Required for paste (CGEvent Cmd+V)
- **Input Monitoring:** Required for global hotkeys
- **Screen Recording:** Optional for screen sharing mode

---

## Recent Architecture Changes (Feb 2026)

### Repository Pattern Introduction
- `ClipItemStore` refactored to thin façade over `ClipItemRepository`
- Domain services extracted: deduplication, retention, usage tracking, asset management
- Better separation of concerns and testability

### Coordinator Extraction
- `AppDelegate` responsibilities moved to focused coordinators
- `CaptureCoordinator`: Capture pipeline orchestration
- `HotkeyCoordinator`: Hotkey management
- `OnboardingCoordinator`: Onboarding flow
- `IntegrityCheckService`: Startup checks

### Overlay Decomposition
- `OverlayShellView` reduced from 799 → 766 lines
- Extracted coordinators for preview, lock handling, actions
- Reduced mixed responsibilities by moving focused behavior into dedicated types

### Settings Provider Pattern
- Removed @AppStorage from services layer
- Introduced protocol-based settings providers
- Services now depend on injected providers, not SwiftUI

### Best Practices
See [BEST-PRACTICES.md](./BEST-PRACTICES.md) for security, logging, and architecture guidelines.

---

## Next Steps

**Phase 7 (Current):** Beta testing
**Phase 8:** App Store prep (icon, screenshots, privacy policy)
**Phase 9:** Launch

---

**Version:** 1.3.0
**Last Updated:** 2026-02-03
**Full Documentation:** See [`INDEX.md`](./INDEX.md)
