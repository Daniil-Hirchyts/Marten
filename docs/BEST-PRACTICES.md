# Paste - Development Best Practices

**Last Updated:** 2026-02-04  
**Audience:** All contributors  
**Status:** Active guidelines

These standards reflect the current post-refactor architecture (`ClipboardCore` + `ClipboardMacServices` + `ClipboardMacApp`) and the privacy requirements of a clipboard manager.

---

## 1. Security & Privacy

### 1.1 Never Log Clipboard Content

Clipboard data is sensitive by default.

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

- Use `OSLog` categories from `ClipboardMacServices/Services/Logging/Loggers.swift`.
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

### 1.4 Sensitive Content Filtering Rules

Capture filtering is split into dedicated components and should stay that way:

- `PasteboardRepresentationExtractor` - extraction only
- `ClipboardContentFilter` - transient/confidential filtering policy
- `ItemTypeClassifier` - classification only

Do not collapse these responsibilities into a single monolith.

---

## 2. Architecture & Code Organization

### 2.1 Module Boundaries

Current module layering is strict:

1. **ClipboardCore** - persistence, domain services, sync engines
2. **ClipboardMacServices** - AppKit/system integrations
3. **ClipboardMacApp** - lifecycle orchestration and UI composition

Rules:
- `ClipboardCore` and `ClipboardMacServices` must remain SwiftUI-free.
- App-level wiring belongs in `AppCoordinator` and `AppServiceContainer`.
- UI code should depend on protocols/handlers, not deep concrete service construction.

### 2.2 Lifecycle and Composition

- Keep `AppDelegate` thin (forward lifecycle only).
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

Avoid constructing heavyweight services directly in views when wiring can happen in the composition root.

### 2.4 Overlay Dependency Pattern

Use `OverlayDependencies` to pass operational collaborators into overlay UI:

- `any ClipItemStoring`
- `any ItemOperating`
- `any PinboardManaging`
- `OverlayPreviewCoordinator`
- `any AppleIntelligenceTextServicing`

This keeps `OverlayShellView` focused on UI state and interaction.

### 2.5 Event Bus Injection Safety

`clipboardEventBroadcaster` uses a sentinel default (`MissingClipboardEventBroadcaster`) that asserts when not injected.

Rule: always inject `.environment(\.clipboardEventBroadcaster, services.eventBroadcaster)` at the root where overlay/content trees are built.

### 2.6 SOLID in Practice

- **SRP:** keep extraction, filtering, classification, orchestration, and rendering as separate units.
- **DIP:** prefer interfaces like `PasteEngineProtocol`, `ClipItemStoring`, `SyncCoordinating`.
- **ISP:** favor narrow protocols (`CaptureSettingsProviding`, `PasteSettingsProviding`, etc.).
- **OCP:** extend by adding extractor/classifier strategies, not rewriting central switch blocks.

### 2.7 File Size and Decomposition

Target guidance (not hard limits):
- Coordinators: < 350 lines
- Services/repositories: < 600 lines
- SwiftUI views: < 450 lines

When larger files are unavoidable, split by concern into focused extensions/files (current overlay shell pattern is the model).

---

## 3. Concurrency & Isolation

### 3.1 Actor/MainActor Discipline

- UI state owners should be `@MainActor` (`AppCoordinator`, view models, controllers with UI state).
- Async pipelines should avoid unnecessary main-thread work.
- Use detached work only for true background boundaries (for example, async link-preview fetches).

### 3.2 `Sendable` and `@unchecked Sendable`

`@unchecked Sendable` is present in several types for pragmatic reasons.

Rules:
- Add a safety comment explaining why unchecked conformance is valid.
- Ensure mutable shared state is synchronized (lock/queue/actor confinement).
- Prefer true `Sendable` designs for new components.

---

## 4. Settings Access Pattern

Services must not use SwiftUI property wrappers.

Use provider protocols in `ClipboardMacServices/Services/Settings/`:
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

- `swift test` in `ClipboardCore`
- `swift test` in `ClipboardMac`
- Run Xcode-hosted UI tests when UI behavior changes (`ClipboardMacUITests`)

### 5.2 Test Strategy

- Unit-test repositories/services with controlled persistence contexts.
- Unit-test coordinators and handlers with injected fakes.
- Use `ClipboardMacValidation` for non-UI validation and performance sanity checks.

### 5.3 Regression Rules

- Bug fixes require a failing test or a clear reason a test cannot be added.
- If behavior changed intentionally, update both tests and docs in the same PR.

---

## 6. Code Review Checklist

- [ ] No clipboard content leakage in logs
- [ ] No `print()` in production targets
- [ ] Correct module boundaries maintained
- [ ] Dependencies injected through protocols/containers
- [ ] UI lifecycle logic stays in `AppCoordinator`/coordinators
- [ ] Capture extractor/filter/classifier responsibilities remain separated
- [ ] Tests added/updated for behavior changes
- [ ] Build/test commands pass locally
- [ ] Docs updated when architectural behavior changes

---

## 7. References

- [`CODEBASE.md`](./CODEBASE.md)
- [`FILE-INVENTORY.md`](./FILE-INVENTORY.md)
- [`ARCHITECTURE-DECISIONS.md`](./ARCHITECTURE-DECISIONS.md)
- [`SETUP.md`](./SETUP.md)

---

## 8. Enforcement

These practices are enforced via:

1. Code review against the checklist
2. Local build/test validation
3. Ongoing architecture documentation maintenance
4. Release hardening passes

**Next Review:** 2026-06-01 (quarterly)
