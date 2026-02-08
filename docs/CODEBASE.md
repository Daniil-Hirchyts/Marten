# Paste - Codebase Guide

**macOS clipboard manager with iCloud sync**  
**Status:** Phase 7 Beta Testing (Ready) | SwiftPM tests passing

---

## Quick Navigation

```text
Paste/
├── ClipboardCore/                 Platform-agnostic package
│   ├── Sources/
│   │   ├── Assets/
│   │   ├── BusinessRules/
│   │   ├── DataModel/
│   │   ├── Persistence/
│   │   └── Sync/
│   └── Tests/
│
├── ClipboardMac/                  macOS package
│   ├── Sources/
│   │   ├── ClipboardMacApp/       App lifecycle + UI composition
│   │   ├── ClipboardMacServices/  System/macOS integrations
│   │   └── ClipboardMacValidation/ Validation executable
│   └── Tests/
│
├── ClipboardMacWrapper/           Local wrapper resources (signing/entitlements/assets)
└── docs/
    ├── INDEX.md
    ├── CODEBASE.md
    ├── BEST-PRACTICES.md
    ├── ARCHITECTURE-DECISIONS.md
    └── SETUP.md
```

---

## Current Architecture Snapshot

- **Swift files (Sources + Tests):** 304
- **Swift LOC (Sources + Tests):** 43,619
- **Module footprint:**
  - `ClipboardCore/Sources` - 61 files / 8,366 LOC
  - `ClipboardCore/Tests` - 27 files / 4,635 LOC
  - `ClipboardMac/Sources` - 165 files / 26,161 LOC
  - `ClipboardMac/Tests` - 51 files / 4,457 LOC
- **Type map (major declarations):**
  - `ClipboardCore/Sources` - 93 protocol/class/struct/actor declarations
  - `ClipboardMac/Sources` - 287 protocol/class/struct/actor declarations
- **Largest source files (maintainability hotspots):**
  - `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemCardRow.swift` (~1,106)
  - `ClipboardCore/Sources/Sync/InboundSyncEngine.swift` (~796)
  - `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemCompactColumn.swift` (~729)
  - `ClipboardCore/Sources/BusinessRules/ClipItemRepository.swift` (~715)
  - `ClipboardCore/Sources/Sync/OutboundSyncEngine.swift` (~621)
  - `ClipboardMac/Sources/ClipboardMacApp/UI/Onboarding/OnboardingScreens.swift` (~601)

---

## Where Is Functionality X?

| Feature | Location |
|--------|----------|
| Clipboard monitoring | `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/PasteboardMonitor.swift` |
| Capture orchestration | `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/CaptureCoordinator.swift` |
| Capture extraction/filter/classification | `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/PasteboardRepresentationExtractor.swift`, `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/ClipboardContentFilter.swift`, `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/ItemTypeClassifier.swift` |
| OCR capture orchestration | `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/OCRCaptureCoordinator.swift` |
| OCR selection overlay | `ClipboardMac/Sources/ClipboardMacApp/UI/OCR/OCRSelectionOverlayController.swift` |
| OCR recognition and capture services | `ClipboardMac/Sources/ClipboardMacServices/Services/OCR/` |
| OCR settings provider | `ClipboardMac/Sources/ClipboardMacServices/Services/Settings/OCRSettingsProviding.swift` |
| First-launch starter content seeding | `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/FirstLaunchContentSeeder.swift` |
| Onboarding flow | `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/OnboardingCoordinator.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Onboarding/` |
| Paste engine | `ClipboardMac/Sources/ClipboardMacServices/Services/PasteEngine/PasteEngine.swift` |
| Global hotkeys | `ClipboardMac/Sources/ClipboardMacServices/Services/HotkeyManager/HotkeyManager.swift` |
| Hotkey orchestration | `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/HotkeyCoordinator.swift` |
| Overlay window/controller | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayWindow.swift` |
| Overlay root + shell | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayRootView.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/Shell/OverlayShellView.swift` |
| Overlay dependencies/interfaces | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayDependencies.swift` |
| Native drag source and pipeline | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/NativeDragSource.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/DragCoordinator.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/DragTypes.swift` |
| Drag preview rendering | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/DragPreviewWindow.swift` |
| Item card UI | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemCard/ItemCard.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemCard/ItemCardThumbnail.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemCardRow.swift` |
| Image resolution metadata resolver | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemCard/ItemCardThumbnail.swift` |
| Item editor | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemEditor/ItemEditorContentView.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemEditorWindow.swift` |
| Overlay coordinators/handlers | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayPreviewCoordinator.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayActionHandlers.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayPinboardLockHandler.swift` |
| Overlay search state | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlaySearchViewModel.swift` |
| Settings UI | `ClipboardMac/Sources/ClipboardMacApp/UI/Settings/` |
| Settings providers | `ClipboardMac/Sources/ClipboardMacServices/Services/Settings/` |
| Core item store facade | `ClipboardCore/Sources/BusinessRules/ClipItemStore.swift` |
| Core CRUD repository | `ClipboardCore/Sources/BusinessRules/ClipItemRepository.swift` |
| Asset lifecycle and cleanup planning | `ClipboardCore/Sources/BusinessRules/AssetManagementService.swift` |
| CloudKit sync orchestration | `ClipboardCore/Sources/Sync/SyncCoordinator.swift` |
| Inbound fetch timeout guard | `ClipboardCore/Sources/Sync/InboundSyncEngine.swift` |
| Outbound batching/retry engine | `ClipboardCore/Sources/Sync/OutboundSyncEngine.swift` |
| Menu bar controller | `ClipboardMac/Sources/ClipboardMacApp/App/MenuBarController.swift` |
| Permissions manager | `ClipboardMac/Sources/ClipboardMacServices/Services/Permissions/PermissionManager.swift` |
| Crash reporting | `ClipboardMac/Sources/ClipboardMacServices/Services/CrashReporter.swift` |
| Apple Intelligence text transforms | `ClipboardMac/Sources/ClipboardMacServices/Services/AppleIntelligence/`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemEditorAITextEditing.swift` |
| Screen sharing mode logic | `ClipboardMac/Sources/ClipboardMacServices/Services/ScreenSharing/ScreenSharingManager.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Settings/PrivacyTab.swift` |
| Screen-sharing capture protection for windows | `ClipboardMac/Sources/ClipboardMacApp/App/AppCoordinator.swift` |
| Pinboard lock | `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/PinboardLockController.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayPinboardLockHandler.swift` |
| Sign in with Apple (sync gating) | `ClipboardCore/Sources/BusinessRules/AppleAuthManager.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Settings/AccountTab.swift` |

---

## Architecture Boundaries

### Lifecycle Root

- `ClipboardMac/Sources/ClipboardMacApp/App/AppDelegate.swift` remains intentionally thin.
- `ClipboardMac/Sources/ClipboardMacApp/App/AppCoordinator.swift` owns startup/shutdown orchestration:
  - overlay setup
  - capture + hotkey + OCR coordinators
  - onboarding and first-launch seeding
  - menu bar wiring
  - retention scheduling
  - push-notification forwarding to sync
  - screen-sharing capture protection policy

### Composition Root and DI

- `ClipboardMac/Sources/ClipboardMacApp/App/AppServiceContainer.swift` composes app dependencies.
- Provider protocols define scoped boundaries:
  - `CaptureServicesProviding`
  - `OCRServicesProviding`
  - `PasteServicesProviding`
  - `OverlayServicesProviding`
  - `SyncServicesProviding`
  - unified `AppServiceProviding`

### Core Persistence and Domain Layer

- `ClipboardCore` encapsulates Core Data entities, repositories, services, and sync engine.
- Key protocol boundaries:
  - `ClipItemStoring`, `ClipItemRepositoryProtocol`
  - `PinboardRepositoryProtocol`
  - `AssetManagementServicing`
  - `ClipItemRetentionServicing`
  - `ClipItemUsageServicing`
  - `SearchServicing`

### Overlay Dependency Model

- `OverlayDependencies` injects shell dependencies:
  - `clipItemStore: any ClipItemStoring`
  - `itemOperations: any ItemOperating`
  - `pinboards: any PinboardManaging`
  - `previewCoordinator: OverlayPreviewCoordinator`
  - `appleIntelligence: any AppleIntelligenceTextServicing`
  - `screenSharingManager: ScreenSharingManager`
  - `pasteboardMonitor: PasteboardMonitor`

### Capture Pipeline Split

- `PasteboardRepresentationExtractor` - representation extraction
- `ClipboardContentFilter` - transient/confidential filtering policy
- `ItemTypeClassifier` - item type classification
- `PasteboardExtractor` composes the above into `ClipItemPayload`

### OCR Capture Pipeline Split

- `OCRCaptureCoordinator` - permission gate + overlay lifecycle + clipboard write orchestration
- `OCRSelectionOverlayController` - crosshair/drag selection UI
- `ScreenImageCapturing` + `SelectionImageCropper` - snapshot/live region capture + coordinate conversion
- `TextRecognizing` (`VisionTextRecognizer`) - OCR recognition with auto-detect and preferred-language fallback

### Sync Orchestration

- `SyncCoordinator` implements `SyncCoordinating` and composes:
  - `CloudKitManager`
  - `OutboundSyncEngine`
  - `InboundSyncEngine`
  - `AssetSyncManager`
  - `PeriodicSyncScheduler`
  - `SyncStateMachine`

---

## Core Concepts

### ClipItem and Representations

- **Primary entity:** `ClipItem`
- **Multi-format payloads:** `ClipRepresentation`
- A single clipboard entry can preserve text + rich text + binary variants.

### Pinboards

- User-managed organization via `Pinboard`.
- Supports all-items behavior, pinning workflows, and pinboard ordering.

### Locked Pinboards

- Lock state is managed by `PinboardLockController` with LocalAuthentication.
- Locked pinboards can be hidden until unlocked.

### Sync

- Bi-directional CloudKit sync with explicit orchestration.
- Outbound and inbound paths are independently managed and coordinated.

---

## Data Flows

### Capture

```text
PasteboardMonitor -> CaptureCoordinator -> PasteboardExtractor
  -> (RepresentationExtractor + ContentFilter + ItemTypeClassifier)
  -> ClipItemStore/ClipItemRepository -> Core Data
  -> optional thumbnails/link previews
  -> outbound sync engine publishes to CloudKit when enabled
```

### Paste

```text
HotkeyManager -> HotkeyCoordinator -> OverlayWindowController/OverlayRootView
  -> OverlayViewModel -> PasteEngine
  -> clipboard write + target app activation + synthetic Cmd+V
```

### OCR Text Capture

```text
Menu command / OCR hotkey -> OCRCaptureCoordinator
  -> PermissionManager (Screen Recording)
  -> OCRSelectionOverlayController (drag region)
  -> ScreenImageCapturing + SelectionImageCropper
  -> VisionTextRecognizer
  -> PasteEngine.copyPlainTextToClipboard
```

### Sync (Inbound)

```text
Push notification/App trigger -> AppCoordinator -> SyncCoordinator
  -> InboundSyncEngine (timeout-guarded fetch)
  -> CloudRecordMapper + conflict handling
  -> Core Data merge -> UI updates
```

---

## Testing

- **Core package:** `ClipboardCore/Tests/ClipboardCoreTests` (unit/integration/perf)
- **macOS package:**
  - `ClipboardMac/Tests/ClipboardMacTests` (services)
  - `ClipboardMac/Tests/ClipboardMacAppTests` (UI-adjacent app logic)
  - `ClipboardMac/Tests/ClipboardMacUITests` (hosted UI tests)

**Validation snapshot (2026-02-09):**
- `ClipboardCore`: `swift test` passed (194 tests, 0 failures)
- `ClipboardMac`: `swift test` passed (192 tests, 0 failures, 10 skipped)
- UI tests require Xcode host runner and are skipped in plain SwiftPM runs

---

## Dependencies

- **ClipboardCore:** Foundation, CoreData, CloudKit, CryptoKit, Combine
- **ClipboardMac:** AppKit, SwiftUI, AVFoundation, CoreGraphics, LocalAuthentication, OSLog, Vision, ImageIO, FoundationModels
- **Third-party dependencies:** None

---

## Permissions

- **Accessibility:** required for paste injection
- **Input Monitoring:** required for global hotkeys
- **Screen Recording:** required for OCR text capture; optional for screen-sharing mode

---

## Related Documents

- [`INDEX.md`](./INDEX.md)
- [`BEST-PRACTICES.md`](./BEST-PRACTICES.md)
- [`ARCHITECTURE-DECISIONS.md`](./ARCHITECTURE-DECISIONS.md)
- [`SETUP.md`](./SETUP.md)

---

**Version:** 1.3.0  
**Last Updated:** 2026-02-09
