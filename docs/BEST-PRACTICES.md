# Marten - Development Best Practices

**Last Updated:** 2026-02-09  
**Audience:** All contributors  
**Status:** Active guidelines

These standards reflect the beta-ready architecture (`MartenCore` + `MartenMacServices` + `MartenMacApp`) and privacy requirements for a clipboard manager.

---

## 1. Security & Privacy

### 1.1 Never Log Marten Content

Marten data is sensitive by default.

- Do not log copied text, URL strings, file paths, HTML payloads, or image bytes.
- Log metadata only (counts, durations, state transitions).

```swift
import OSLog

// BAD
Logger.pasteboard.info("Captured text: \(text)")

// GOOD
Logger.pasteboard.info("Captured item (type=\(itemType.rawValue, privacy: .public), bytes=\(byteCount, privacy: .public))")
```

### 1.2 Logging Policy

- Use `OSLog` categories from `MartenMacServices/Services/Logging/Loggers.swift`.
- Never ship `print()` in production targets.
- Use privacy annotations:
  - `.private` for user-originated strings and app identifiers
  - `.public` only for safe operational metadata

### 1.3 Permission-Gated Behavior

- **Accessibility** gates paste injection (`PasteEngine`).
- **Input Monitoring** gates global hotkeys (`HotkeyManager`).
- **Screen Recording** gates OCR text capture workflows.
- Request permissions only when the feature is needed.
- Provide graceful degraded behavior when denied.

### 1.4 Screen Sharing Protection

- Keep screen-sharing behavior centralized in `AppCoordinator` + `ScreenSharingManager`.
- When screen-sharing mode is active, window capture policy must be applied consistently for newly visible windows.
- Never apply ad-hoc per-view hiding logic that bypasses central policy.

---

## 2. Architecture & Code Organization

### 2.1 Module Boundaries

Current module layering is strict:

1. **MartenCore** - persistence, domain services, sync engines
2. **MartenMacServices** - AppKit/system integrations
3. **MartenMacApp** - lifecycle orchestration and UI composition

Rules:
- `MartenCore` and `MartenMacServices` remain SwiftUI-free.
- App-level wiring belongs in `AppCoordinator` and `AppServiceContainer`.
- UI code depends on protocols/handlers, not deep concrete service construction.

### 2.2 Lifecycle and Composition

- Keep `AppDelegate` thin (lifecycle forwarding only).
- Keep startup orchestration in `AppCoordinator`.
- Keep service construction in `AppServiceContainer`.

Preferred app boundary protocols:
- `AppServiceProviding`
- `CaptureServicesProviding`
- `PasteServicesProviding`
- `OverlayServicesProviding`
- `SyncServicesProviding`

### 2.3 Dependency Injection

Inject dependencies with protocol-first interfaces.

```swift
@MainActor
protocol ClipItemStoring {
    @discardableResult
    func createItem(payload: ClipItemPayload, sourceApp: SourceAppInfo?, isUserCreated: Bool) throws -> ClipItem
}

struct ExampleView {
    private let store: any ClipItemStoring

    init(store: any ClipItemStoring) {
        self.store = store
    }
}
```

Avoid constructing heavyweight services in views when wiring can happen in the composition root.

### 2.4 Overlay Dependency Pattern

Use `OverlayDependencies` to pass operational collaborators into overlay UI:

- `any ClipItemStoring`
- `any ItemOperating`
- `any PinboardManaging`
- `OverlayPreviewCoordinator`
- `any AppleIntelligenceTextServicing`
- `ScreenSharingManager`
- `PasteboardMonitor`

### 2.5 Event Bus Injection Safety

`clipboardEventBroadcaster` uses a sentinel default (`MissingMartenEventBroadcaster`) that asserts when not injected.

Rule: always inject `.environment(\.clipboardEventBroadcaster, services.eventBroadcaster)` at the app root for overlay/content trees.

### 2.6 First-Launch Seeding Rules

Starter content seeding must be:
- **Idempotent** (safe on repeated app starts)
- **Atomic** (avoid partial pinboard/item states)
- **Explicitly tracked** with dedicated app settings keys

Do not infer seeding completion purely from "any data exists" when failures can leave partial content.

### 2.7 SOLID in Practice

- **SRP:** keep extraction, filtering, classification, orchestration, and rendering separate.
- **DIP:** prefer interfaces like `PasteEngineProtocol`, `ClipItemStoring`, `SyncCoordinating`.
- **ISP:** favor narrow protocols (`CaptureSettingsProviding`, `PasteSettingsProviding`, etc.).
- **OCP:** extend by adding extractor/classifier strategies, not rewriting central switch blocks.

### 2.8 File Size and Decomposition

Target guidance (not hard limits):
- Coordinators: < 350 lines
- Services/repositories: < 650 lines
- SwiftUI views: < 500 lines

When larger files are unavoidable, split by concern into focused extensions/files.

---

## 3. Concurrency & Isolation

### 3.1 Actor/MainActor Discipline

- UI state owners should be `@MainActor`.
- Async pipelines should avoid unnecessary main-thread work.
- Use detached/background work only for clear boundaries (thumbnail loading, metadata extraction, link preview fetches).

### 3.2 Async UI Asset Loading

For async preview work (thumbnail/banner/resolution):
- Track request generations or use cancellable tasks.
- Guard UI assignment against stale completion ordering.
- Keep file IO and metadata extraction off the main actor.

### 3.3 `Sendable` and `@unchecked Sendable`

Rules:
- Every `@unchecked Sendable` conformance requires a safety rationale comment.
- Mutable shared state must be synchronized (actor confinement, dedicated queues, or locks).
- Prefer true `Sendable` designs for new components.

---

## 4. Settings Access Pattern

Services must not use SwiftUI property wrappers.

Use provider protocols in `MartenMacServices/Services/Settings/`:
- `CaptureSettingsProviding`
- `LinkPreviewSettingsProviding`
- `OCRSettingsProviding`
- `PasteSettingsProviding`
- `ScreenSharingSettingsProviding`

Inject fake providers in tests instead of mutating global `UserDefaults` directly.

---

## 5. Testing & Verification

### 5.1 Required Local Checks

Before merging behavior changes:

- `swift test` in `MartenCore`
- `swift test` in `MartenMac`
- Run Xcode-hosted UI tests when UI behavior changes (`MartenMacUITests`)

### 5.2 Test Strategy

- Unit-test repositories/services with controlled persistence contexts.
- Unit-test coordinators and handlers with injected fakes.
- Use `MartenMacValidation` for non-UI validation and performance checks.

### 5.3 Regression Rules

- Bug fixes require a failing test, or a clear explanation why a test cannot be added.
- Behavior changes must update tests and docs in the same PR.

### 5.4 Current Validation Baseline

(2026-02-09)
- `MartenCore`: 194 tests executed, 0 failures
- `MartenMac`: 192 tests executed, 0 failures, 10 skipped
- UI skipped tests are host-dependent suites in plain SwiftPM runs

---

## 6. Code Review Checklist

- [ ] No clipboard content leakage in logs
- [ ] No `print()` in production targets
- [ ] Correct module boundaries maintained
- [ ] Dependencies injected through protocols/containers
- [ ] UI lifecycle logic stays in `AppCoordinator`/coordinators
- [ ] Capture extractor/filter/classifier responsibilities remain separated
- [ ] First-launch seeding remains idempotent and atomic
- [ ] Async preview updates are race-safe
- [ ] Tests added/updated for behavior changes
- [ ] Build/test commands pass locally
- [ ] Docs updated when architectural behavior changes

---

## 7. References

- [`INDEX.md`](./INDEX.md)
- [`CODEBASE.md`](./CODEBASE.md)
- [`ARCHITECTURE-DECISIONS.md`](./ARCHITECTURE-DECISIONS.md)
- [`SETUP.md`](./SETUP.md)

---

## 8. Enforcement

These practices are enforced via:

1. Code review against the checklist
2. Local build/test validation
3. Ongoing architecture documentation maintenance
4. Release hardening passes

**Next Review:** 2026-06-15
