# Architecture Decision Records (ADRs)

**Project:** Paste Clipboard Manager  
**Version:** 1.3.0  
**Last Updated:** 2026-02-09

---

## Purpose

This document records architectural decisions that shape the current implementation of Paste. Each ADR captures context, options, decision, rationale, and consequences.

---

## ADR Format

Each ADR includes:
- **Context** - decision problem
- **Options Considered** - alternatives evaluated
- **Decision** - selected approach
- **Rationale** - why this approach was selected
- **Consequences** - trade-offs and implications

---

## ADR-001: Core Data as Primary Persistence Layer

**Date:** 2026-01-09  
**Status:** Accepted

**Context:** The app needs local persistence for rich clipboard data and reliable integration with CloudKit synchronization.

**Options Considered:**
1. SwiftData
2. Core Data
3. Third-party stores (Realm/SQLite wrappers)

**Decision:** Core Data.

**Rationale:**
- Mature tooling and migration model.
- Strong integration with existing CloudKit workflows.
- Fine-grained fetch/update control needed by sync and retention services.

**Consequences:**
- ✅ Predictable persistence behavior and migration support.
- ✅ Good fit for repository/service layering.
- ❌ More boilerplate than SwiftData.

**References:** `ClipboardCore/Sources/Persistence/`, `ClipboardCore/Sources/DataModel/`

---

## ADR-002: Manual CloudKit Orchestration

**Date:** 2026-01-09  
**Status:** Accepted

**Context:** Sync requires explicit conflict behavior and operational visibility.

**Options Considered:**
1. `NSPersistentCloudKitContainer`
2. Manual CloudKit engine orchestration

**Decision:** Manual orchestration using `SyncCoordinator` + inbound/outbound engines.

**Rationale:**
- Explicit control of scheduling, retries, and conflict handling.
- Clear operational boundaries (`CloudKitManager`, `OutboundSyncEngine`, `InboundSyncEngine`, `AssetSyncManager`).
- Testable engine boundaries with injectable collaborators.

**Consequences:**
- ✅ Deterministic sync pipeline with visible control points.
- ✅ Better fit for custom behaviors (assets, conflict policies).
- ❌ More implementation complexity.

**References:** `ClipboardCore/Sources/Sync/SyncCoordinator.swift`, `ClipboardCore/Sources/Sync/OutboundSyncEngine.swift`, `ClipboardCore/Sources/Sync/InboundSyncEngine.swift`

---

## ADR-003: Swift Package Modular Architecture

**Date:** 2026-01-09  
**Status:** Accepted

**Context:** Separate cross-platform domain logic from macOS-specific runtime/UI.

**Options Considered:**
1. Monolithic target
2. Swift package modularization

**Decision:** Two primary local packages:
- `ClipboardCore`
- `ClipboardMac` (`ClipboardMacApp` + `ClipboardMacServices` + validation executable)

**Rationale:**
- Clear compile-time boundaries.
- Better test segmentation.
- Supports future reuse of `ClipboardCore`.

**Consequences:**
- ✅ Cleaner architecture and dependency direction.
- ✅ Faster targeted builds/tests.
- ❌ More package wiring overhead.

**References:** `ClipboardCore/Package.swift`, `ClipboardMac/Package.swift`

---

## ADR-004: Hybrid AppKit + SwiftUI UI Stack

**Date:** 2026-01-09  
**Status:** Accepted

**Context:** The app needs both modern SwiftUI composition and low-level macOS control for overlay windows, menu bar integration, and system pasteboard behavior.

**Options Considered:**
1. Pure SwiftUI
2. Pure AppKit
3. Hybrid AppKit + SwiftUI

**Decision:** Hybrid stack.

**Rationale:**
- AppKit is required for `NSPanel`, `NSStatusItem`, and system integrations.
- SwiftUI is preferred for UI composition, state-driven views, and maintainability.
- Current architecture cleanly bridges the two via controller/coordinator boundaries.

**Consequences:**
- ✅ Best fit for macOS utility UX.
- ✅ Modern UI composition with required system control.
- ❌ Requires careful boundary discipline between frameworks.

**References:** `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayWindow.swift`, `ClipboardMac/Sources/ClipboardMacApp/App/MenuBarController.swift`

---

## ADR-005: AppCoordinator-Centric Lifecycle

**Date:** 2026-02-04  
**Status:** Accepted

**Context:** Startup/lifecycle responsibilities grew beyond what should live in `AppDelegate`.

**Options Considered:**
1. Keep behavior inside `AppDelegate`
2. Move orchestration to dedicated coordinator

**Decision:** Keep `AppDelegate` thin and move lifecycle orchestration to `AppCoordinator`.

**Rationale:**
- Improves lifecycle testability and readability.
- Consolidates startup flows (capture/hotkeys/onboarding/menu/sync wiring) into a single actor-isolated coordinator.
- Aligns with composition-root architecture.

**Consequences:**
- ✅ Cleaner lifecycle boundaries.
- ✅ Easier reasoning about startup/shutdown side effects.
- ❌ Requires explicit dependency interfaces at app boundary.

**References:** `ClipboardMac/Sources/ClipboardMacApp/App/AppDelegate.swift`, `ClipboardMac/Sources/ClipboardMacApp/App/AppCoordinator.swift`

---

## ADR-006: Protocol-First Composition with Service Providers

**Date:** 2026-02-04  
**Status:** Accepted

**Context:** Feature code should depend on scoped interfaces, not broad concrete service graphs.

**Options Considered:**
1. Concrete service access everywhere
2. Provider protocol boundaries + composition container

**Decision:** `AppServiceContainer` + scoped provider protocols.

**Rationale:**
- Keeps dependency direction explicit.
- Supports test doubles and incremental refactors.
- Limits surface area exposed to each workflow.

**Consequences:**
- ✅ Better DIP/ISP adherence.
- ✅ Easier test setup for coordinators/view models.
- ❌ Requires maintenance of protocol boundaries.

**References:** `ClipboardMac/Sources/ClipboardMacApp/App/AppServiceContainer.swift`

---

## ADR-007: Clipboard Monitoring by Polling with Adaptive Intervals

**Date:** 2026-01-09  
**Status:** Accepted

**Context:** macOS does not provide reliable push-style clipboard change notifications for this use case.

**Options Considered:**
1. Polling `NSPasteboard.changeCount`
2. Event taps / indirect copy detection

**Decision:** Polling in `PasteboardMonitor` with adaptive intervals.

**Rationale:**
- Reliable across copy sources (keyboard, menu, programmatic).
- Simple and controllable behavior.
- Adaptive intervals reduce idle overhead.

**Current interval defaults:**
- Active: 0.4s (`fastPollInterval`)
- Idle: 1.5s (`idlePollInterval`)
- Idle threshold: 5.0s

**Consequences:**
- ✅ Reliable capture behavior.
- ✅ Bounded CPU overhead with adaptive polling.
- ❌ Polling latency is inherent.

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/PasteboardMonitor.swift`

---

## ADR-008: Split Capture Extraction/Filtering/Classification

**Date:** 2026-02-04  
**Status:** Accepted

**Context:** Capture policy and payload formation should be extensible and testable without a monolithic extractor.

**Options Considered:**
1. Single extractor with embedded policy/classification logic
2. Split extraction pipeline components

**Decision:** Split into:
- `PasteboardRepresentationExtractor`
- `ClipboardContentFilter`
- `ItemTypeClassifier`
with `PasteboardExtractor` as composition shell.

**Rationale:**
- Better SRP boundaries.
- Isolated unit testing.
- Clear extension points for new representation types or policy behavior.

**Consequences:**
- ✅ Cleaner capture architecture.
- ✅ Easier maintainability and testing.
- ❌ More component wiring.

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/`

---

## ADR-009: Repository/Service Layer in ClipboardCore

**Date:** 2026-02-04  
**Status:** Accepted

**Context:** Domain logic needed clearer separation between CRUD, usage, retention, assets, and search concerns.

**Options Considered:**
1. Single catch-all store/repository implementation
2. Dedicated services + facade boundaries

**Decision:** Keep a thin `ClipItemStore` facade over dedicated repository/services with protocol boundaries.

**Rationale:**
- Operations are grouped by responsibility (`ClipItemRepository`, retention, usage, assets, search, pinboards).
- Callers can consume protocol boundaries (`ClipItemStoring`, `ClipItemRepositoryProtocol`, etc.).

**Consequences:**
- ✅ Cleaner domain partitioning.
- ✅ Better testability and substitution.
- ❌ More abstractions to maintain.

**References:** `ClipboardCore/Sources/BusinessRules/ClipItemStore.swift`, `ClipboardCore/Sources/BusinessRules/Protocols/`

---

## ADR-010: Synthetic Cmd+V Paste Engine

**Date:** 2026-01-10  
**Status:** Accepted

**Context:** Selecting an item should immediately paste into the previously active app with minimal friction.

**Options Considered:**
1. Clipboard write only (manual user paste)
2. Synthetic Cmd+V after clipboard write

**Decision:** Use synthetic Cmd+V with activation checks/retries in `PasteEngine`.

**Rationale:**
- Preserves utility speed and expected UX.
- Works across target apps that support standard paste shortcuts.
- Current engine includes target activation checks and validation events.

**Consequences:**
- ✅ Fast one-step paste workflow.
- ✅ Works with preserved/plain-text modes and stack paste.
- ❌ Requires Accessibility permission and robust failure handling.

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/PasteEngine/PasteEngine.swift`

---

## ADR-011: Hybrid Asset Storage Threshold

**Date:** 2026-01-09  
**Status:** Accepted

**Context:** Large payloads in Core Data can degrade DB performance.

**Options Considered:**
1. Store all payloads in Core Data blobs
2. Store all payloads in files
3. Hybrid threshold approach

**Decision:** Hybrid approach with 256KB threshold.

**Rationale:**
- Small payloads stay inline for fast fetches.
- Large payloads move to asset storage for DB health and sync handling.

**Consequences:**
- ✅ Better DB size/performance profile.
- ✅ Better handling for large binary data.
- ❌ Requires asset lifecycle cleanup.

**References:** `ClipboardCore/Sources/BusinessRules/ClipItemRepository.swift`, `ClipboardCore/Sources/Assets/AssetStore.swift`

---

## ADR-012: Privacy-First Optional Apple Intelligence

**Date:** 2026-02-03  
**Status:** Accepted

**Context:** Users requested text transformation tools without cloud data egress.

**Options Considered:**
1. External LLM API integration
2. On-device Apple Intelligence only
3. No AI features

**Decision:** Optional on-device Apple Intelligence transformations only.

**Rationale:**
- Keeps clipboard content local.
- Avoids API key, billing, and network-data handling complexity.
- Graceful unavailability states are explicit in API (`AppleIntelligenceAvailability`).

**Consequences:**
- ✅ Strong privacy posture.
- ✅ No third-party AI dependencies.
- ❌ Feature availability depends on device/OS capability.

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/AppleIntelligence/`

---

## ADR-013: Locked Pinboards via LocalAuthentication Gate

**Date:** 2026-02-03  
**Status:** Accepted

**Context:** Users need quick privacy controls for selected pinboards.

**Options Considered:**
1. LocalAuthentication gate for access
2. Encrypted per-pinboard storage
3. No lock feature

**Decision:** LocalAuthentication access gate with unlock duration policy.

**Rationale:**
- Practical privacy gain with lower implementation complexity.
- Uses native macOS auth flows (Touch ID/password).

**Consequences:**
- ✅ Fast, familiar UX.
- ✅ Good privacy control for interactive use.
- ❌ Not equivalent to encrypted-at-rest partitioning.

**References:** `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/PinboardLockController.swift`, `ClipboardMac/Sources/ClipboardMacApp/App/PinboardSecuritySettings.swift`

---

## ADR-014: Screen Sharing Mode for Overlay Visibility

**Date:** 2026-02-03  
**Status:** Accepted

**Context:** Clipboard overlays can expose sensitive history while presenting.

**Options Considered:**
1. User-controlled screen sharing mode with visibility preference
2. Always hide overlay
3. No behavior change

**Decision:** Dedicated mode + preference (`showDuringScreenSharing`).

**Rationale:**
- Gives explicit quick control with predictable behavior.
- Supports different user preferences.

**Consequences:**
- ✅ Better presentation privacy controls.
- ✅ Deterministic behavior and clear settings surface.
- ❌ Adds global state that must be reflected in UI and menu bar.

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/ScreenSharing/ScreenSharingManager.swift`, `ClipboardMac/Sources/ClipboardMacApp/App/MenuBarController.swift`

---

## ADR-015: Menu Bar Accessory App Presentation

**Date:** 2026-01-10  
**Status:** Accepted

**Context:** Primary workflow is hotkey/menu-bar driven utility usage.

**Options Considered:**
1. Menu bar accessory app (`LSUIElement` style behavior)
2. Dock-first app
3. Dual-mode presentation

**Decision:** Menu bar utility presentation with overlay window and settings window.

**Rationale:**
- Matches clipboard utility interaction model.
- Reduces Dock clutter and keeps always-available status controls.

**Consequences:**
- ✅ Fast utility-style access pattern.
- ✅ Clean background presence.
- ❌ Discoverability relies on onboarding and shortcuts.

**References:** `ClipboardMac/Sources/ClipboardMacApp/App/AppCoordinator.swift`, `ClipboardMac/Sources/ClipboardMacApp/App/MenuBarController.swift`

---

## ADR-016: OCR Text Capture via Selection Overlay + Vision OCR

**Date:** 2026-02-04  
**Status:** Accepted

**Context:** Users need a direct "capture text from screen region" workflow from menu/shortcut, including multi-language support and predictable behavior for static vs live screen capture.

**Options Considered:**
1. Route OCR through existing clipboard monitor capture pipeline
2. Add a dedicated OCR pipeline with selection overlay, screen capture service, and Vision recognizer
3. Use third-party OCR SDK/service

**Decision:** Add a dedicated OCR pipeline in `ClipboardMacApp` + `ClipboardMacServices` using AppKit overlay selection and Apple Vision OCR.

**Rationale:**
- OCR selection/capture is interactionally different from clipboard polling and should remain isolated.
- Keeps module boundaries intact: orchestration/UI in app target, system/OCR engines in services target.
- Uses Apple Vision language support with auto-detect first and optional preferred-language fallback.
- Keeps privacy posture aligned with project standards (metadata-only logging; no recognized text logging).

**Consequences:**
- ✅ Menu item + global hotkey can trigger OCR capture without coupling to clipboard monitor internals.
- ✅ Supports two modes (static snapshot and live screen) with explicit user/default setting.
- ✅ Better testability via protocol boundaries (`TextRecognizing`, `ScreenImageCapturing`, settings providers).
- ❌ Requires Screen Recording permission for OCR flows and user guidance when denied.

**References:** `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/OCRCaptureCoordinator.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/OCR/OCRSelectionOverlayController.swift`, `ClipboardMac/Sources/ClipboardMacServices/Services/OCR/`, `ClipboardMac/Sources/ClipboardMacServices/Services/Settings/OCRSettingsProviding.swift`

---

## ADR-017: First-Launch Starter Content Seeding

**Date:** 2026-02-08  
**Status:** Accepted

**Context:** New users need immediate orientation and realistic sample content without requiring manual setup.

**Options Considered:**
1. Empty first launch
2. Starter content seeded on first launch
3. Remote-config driven templates

**Decision:** Seed local starter pinboards/cards on first launch, gated by app settings and existing-user checks.

**Rationale:**
- Reduces first-use friction and improves discoverability of pinboards/workflows.
- Keeps data local and deterministic (no backend dependency).
- Can be tested with coordinator-level tests.

**Consequences:**
- ✅ Better out-of-box onboarding experience.
- ✅ No external service dependency.
- ❌ Requires careful idempotence/partial-failure handling in seeding logic.

**References:** `ClipboardMac/Sources/ClipboardMacApp/App/Coordinators/FirstLaunchContentSeeder.swift`, `ClipboardMac/Tests/ClipboardMacAppTests/FirstLaunchContentSeederTests.swift`

---

## ADR-018: Native Drag Pipeline for Item Cards

**Date:** 2026-02-08  
**Status:** Accepted

**Context:** Drag interactions across pinboards/apps needed native behavior with visual fidelity and explicit control over drag lifecycle.

**Options Considered:**
1. SwiftUI-only drag/drop abstractions
2. Dedicated native drag pipeline with AppKit-backed preview/source handling

**Decision:** Use a dedicated native drag pipeline (`NativeDragSource`, `DragCoordinator`, `DragPreviewWindow`, drag types).

**Rationale:**
- Better control over preview rendering, hit-testing, and interaction timing.
- Clear separation between overlay UI state and drag transport mechanics.
- Easier to evolve drag capabilities without overloading item-card views.

**Consequences:**
- ✅ More predictable drag behavior and improved preview quality.
- ✅ Better extensibility for advanced drag scenarios.
- ❌ Added AppKit coordination complexity and more moving parts.

**References:** `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/NativeDragSource.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/DragCoordinator.swift`, `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/DragPreviewWindow.swift`

---

## ADR-019: Inbound Sync Timeout Guard

**Date:** 2026-02-08  
**Status:** Accepted

**Context:** Long or stalled CloudKit fetches can block inbound sync completion and degrade reliability perception.

**Options Considered:**
1. Rely only on CloudKit operation-level timeouts
2. Add engine-level timeout guard around fetch execution

**Decision:** Add explicit engine-level timeout guard (`withFetchTimeout`) in `InboundSyncEngine`.

**Rationale:**
- Ensures inbound sync returns control in bounded time.
- Provides deterministic failure mode for retry/status handling.
- Simplifies testing of timeout behavior in sync unit tests.

**Consequences:**
- ✅ Improved operational resilience and diagnosability.
- ✅ Better user-facing responsiveness in degraded network conditions.
- ❌ Introduces additional timeout tuning responsibility.

**References:** `ClipboardCore/Sources/Sync/InboundSyncEngine.swift`, `ClipboardCore/Tests/ClipboardCoreTests/InboundSyncEngineTests.swift`

---

## Changelog

**Beta Readiness Update** (2026-02-09)
- Added ADR for first-launch starter content seeding.
- Added ADR for native drag pipeline architecture.
- Added ADR for inbound sync timeout guard.
- Updated metadata and references for beta readiness documentation pass.

**1.3.0** (2026-02-04)
- Refreshed ADR metadata and references for post-refactor architecture.
- Added ADRs for lifecycle orchestration, composition/provider boundaries, and split capture pipeline.
- Updated polling interval details and current implementation references.
- Added ADR for OCR text capture (selection overlay, mode split, Vision-based recognition, and permission gating).

**1.0.0** (2026-02-02)
- Initial ADR set.

---

**Maintained By:** Engineering Team  
**Last Updated:** 2026-02-09
