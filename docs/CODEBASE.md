# Marten - Codebase Guide

**macOS clipboard manager with iCloud sync**  
**Status:** Phase 7 Beta Testing (Ready) | SwiftPM tests passing

---

## Quick Navigation

```text
Marten/
├── MartenCore/                 Platform-agnostic package
│   ├── Sources/
│   │   ├── Assets/
│   │   ├── BusinessRules/
│   │   ├── DataModel/
│   │   ├── Persistence/
│   │   └── Sync/
│   └── Tests/
│
├── MartenMac/                  macOS package
│   ├── Sources/
│   │   ├── MartenMacApp/       App lifecycle + UI composition
│   │   ├── MartenMacServices/  System/macOS integrations
│   │   └── MartenMacValidation/ Validation executable
│   └── Tests/
│
├── MartenMacWrapper/           Local wrapper resources (signing/entitlements/assets)
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
  - `MartenCore/Sources` - 61 files / 8,366 LOC
  - `MartenCore/Tests` - 27 files / 4,635 LOC
  - `MartenMac/Sources` - 165 files / 26,161 LOC
  - `MartenMac/Tests` - 51 files / 4,457 LOC
- **Type map (major declarations):**
  - `MartenCore/Sources` - 93 protocol/class/struct/actor declarations
  - `MartenMac/Sources` - 287 protocol/class/struct/actor declarations
- **Largest source files (maintainability hotspots):**
  - `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemCardRow.swift` (~1,106)
  - `MartenCore/Sources/Sync/InboundSyncEngine.swift` (~796)
  - `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemCompactColumn.swift` (~729)
  - `MartenCore/Sources/BusinessRules/ClipItemRepository.swift` (~715)
  - `MartenCore/Sources/Sync/OutboundSyncEngine.swift` (~621)
  - `MartenMac/Sources/MartenMacApp/UI/Onboarding/OnboardingScreens.swift` (~601)

---

## Where Is Functionality X?

| Feature | Location |
|--------|----------|
| Marten monitoring | `MartenMac/Sources/MartenMacServices/Services/PasteboardMonitor/PasteboardMonitor.swift` |
| Capture orchestration | `MartenMac/Sources/MartenMacApp/App/Coordinators/CaptureCoordinator.swift` |
| Capture extraction/filter/classification | `MartenMac/Sources/MartenMacServices/Services/PasteboardMonitor/PasteboardRepresentationExtractor.swift`, `MartenMac/Sources/MartenMacServices/Services/PasteboardMonitor/MartenContentFilter.swift`, `MartenMac/Sources/MartenMacServices/Services/PasteboardMonitor/ItemTypeClassifier.swift` |
| OCR capture orchestration | `MartenMac/Sources/MartenMacApp/App/Coordinators/OCRCaptureCoordinator.swift` |
| OCR selection overlay | `MartenMac/Sources/MartenMacApp/UI/OCR/OCRSelectionOverlayController.swift` |
| OCR recognition and capture services | `MartenMac/Sources/MartenMacServices/Services/OCR/` |
| OCR settings provider | `MartenMac/Sources/MartenMacServices/Services/Settings/OCRSettingsProviding.swift` |
| First-launch starter content seeding | `MartenMac/Sources/MartenMacApp/App/Coordinators/FirstLaunchContentSeeder.swift` |
| Onboarding flow | `MartenMac/Sources/MartenMacApp/App/Coordinators/OnboardingCoordinator.swift`, `MartenMac/Sources/MartenMacApp/UI/Onboarding/` |
| Paste engine | `MartenMac/Sources/MartenMacServices/Services/PasteEngine/PasteEngine.swift` |
| Global hotkeys | `MartenMac/Sources/MartenMacServices/Services/HotkeyManager/HotkeyManager.swift` |
| Hotkey orchestration | `MartenMac/Sources/MartenMacApp/App/Coordinators/HotkeyCoordinator.swift` |
| Overlay window/controller | `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayWindow.swift` |
| Overlay root + shell | `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayRootView.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/Shell/OverlayShellView.swift` |
| Overlay dependencies/interfaces | `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayDependencies.swift` |
| Native drag source and pipeline | `MartenMac/Sources/MartenMacApp/UI/Overlay/NativeDragSource.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/DragCoordinator.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/DragTypes.swift` |
| Drag preview rendering | `MartenMac/Sources/MartenMacApp/UI/Overlay/DragPreviewWindow.swift` |
| Item card UI | `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemCard/ItemCard.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemCard/ItemCardThumbnail.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemCardRow.swift` |
| Image resolution metadata resolver | `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemCard/ItemCardThumbnail.swift` |
| Item editor | `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemEditor/ItemEditorContentView.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemEditorWindow.swift` |
| Overlay coordinators/handlers | `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayPreviewCoordinator.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayActionHandlers.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayPinboardLockHandler.swift` |
| Overlay search state | `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlaySearchViewModel.swift` |
| Settings UI | `MartenMac/Sources/MartenMacApp/UI/Settings/` |
| Settings providers | `MartenMac/Sources/MartenMacServices/Services/Settings/` |
| Core item store facade | `MartenCore/Sources/BusinessRules/ClipItemStore.swift` |
| Core CRUD repository | `MartenCore/Sources/BusinessRules/ClipItemRepository.swift` |
| Asset lifecycle and cleanup planning | `MartenCore/Sources/BusinessRules/AssetManagementService.swift` |
| CloudKit sync orchestration | `MartenCore/Sources/Sync/SyncCoordinator.swift` |
| Inbound fetch timeout guard | `MartenCore/Sources/Sync/InboundSyncEngine.swift` |
| Outbound batching/retry engine | `MartenCore/Sources/Sync/OutboundSyncEngine.swift` |
| Menu bar controller | `MartenMac/Sources/MartenMacApp/App/MenuBarController.swift` |
| Permissions manager | `MartenMac/Sources/MartenMacServices/Services/Permissions/PermissionManager.swift` |
| Crash reporting | `MartenMac/Sources/MartenMacServices/Services/CrashReporter.swift` |
| Apple Intelligence text transforms | `MartenMac/Sources/MartenMacServices/Services/AppleIntelligence/`, `MartenMac/Sources/MartenMacApp/UI/Overlay/ItemEditorAITextEditing.swift` |
| Screen sharing mode logic | `MartenMac/Sources/MartenMacServices/Services/ScreenSharing/ScreenSharingManager.swift`, `MartenMac/Sources/MartenMacApp/UI/Settings/PrivacyTab.swift` |
| Screen-sharing capture protection for windows | `MartenMac/Sources/MartenMacApp/App/AppCoordinator.swift` |
| Pinboard lock | `MartenMac/Sources/MartenMacApp/UI/Overlay/PinboardLockController.swift`, `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayPinboardLockHandler.swift` |
| Sign in with Apple (sync gating) | `MartenCore/Sources/BusinessRules/AppleAuthManager.swift`, `MartenMac/Sources/MartenMacApp/UI/Settings/AccountTab.swift` |

---

## Architecture Boundaries

### Lifecycle Root

- `MartenMac/Sources/MartenMacApp/App/AppDelegate.swift` remains intentionally thin.
- `MartenMac/Sources/MartenMacApp/App/AppCoordinator.swift` owns startup/shutdown orchestration:
  - overlay setup
  - capture + hotkey + OCR coordinators
  - onboarding and first-launch seeding
  - menu bar wiring
  - retention scheduling
  - push-notification forwarding to sync
  - screen-sharing capture protection policy

### Composition Root and DI

- `MartenMac/Sources/MartenMacApp/App/AppServiceContainer.swift` composes app dependencies.
- Provider protocols define scoped boundaries:
  - `CaptureServicesProviding`
  - `OCRServicesProviding`
  - `PasteServicesProviding`
  - `OverlayServicesProviding`
  - `SyncServicesProviding`
  - unified `AppServiceProviding`

### Core Persistence and Domain Layer

- `MartenCore` encapsulates Core Data entities, repositories, services, and sync engine.
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
- `MartenContentFilter` - transient/confidential filtering policy
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
  -> PasteEngine.copyPlainTextToMarten
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

- **Core package:** `MartenCore/Tests/MartenCoreTests` (unit/integration/perf)
- **macOS package:**
  - `MartenMac/Tests/MartenMacTests` (services)
  - `MartenMac/Tests/MartenMacAppTests` (UI-adjacent app logic)
  - `MartenMac/Tests/MartenMacUITests` (hosted UI tests)

**Validation snapshot (2026-02-09):**
- `MartenCore`: `swift test` passed (194 tests, 0 failures)
- `MartenMac`: `swift test` passed (192 tests, 0 failures, 10 skipped)
- UI tests require Xcode host runner and are skipped in plain SwiftPM runs

---

## Dependencies

- **MartenCore:** Foundation, CoreData, CloudKit, CryptoKit, Combine
- **MartenMac:** AppKit, SwiftUI, AVFoundation, CoreGraphics, LocalAuthentication, OSLog, Vision, ImageIO, FoundationModels
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
