# Paste — Comprehensive Technical Audit

**Repository:** Paste (macOS clipboard manager with iCloud sync)

**Audit date:** 2026-02-02

This report audits the Paste codebase from `docs/INDEX.md` outward, covering module boundaries, UI windows/components, inter-component communication, SOLID conformance, dependency injection patterns, and refactoring recommendations across presentation, business logic, and data access.

---

## 1. Executive Summary

### 1.1 Strengths

- **Clear macro-architecture:** A pragmatic 3-layer split: `ClipboardCore` (domain/persistence/sync), `ClipboardMacServices` (system integrations), and `ClipboardMacApp` (SwiftUI/AppKit UI composition). This aligns with Clean Architecture goals without over-abstraction.
- **Strong testing footprint:** The repo includes substantial unit/integration coverage (see Metrics) and platform-specific UI tests.
- **Protocol-driven seams where it matters:** The paste pipeline (`PasteEngine`) and sync (`SyncCoordinator`) already use protocol abstractions and injected collaborators in key areas.
- **Good eventing primitive:** `ClipboardEventBroadcaster` provides a small, explicit channel for cross-module UI/service coordination.

### 1.2 Primary Architectural Risks

- **Overgrown UI composition & “mega-views”:** A few SwiftUI/AppKit bridge files exceed 1k LOC, accumulating state, rendering, user interaction handling, window coordination, persistence access, and feature logic in one place.
- **Composition root drift:** `AppDelegate` is doing both composition and runtime orchestration for many workflows, becoming a "god object".
- **Inconsistent dependency injection:** Some components rely on DI (`AppServiceContainer`, protocol seams), while others create concrete dependencies internally (`ClipItemStore()` in views/controllers). This increases coupling and makes tests/variants harder.
- **UI framework leakage into services:** `PasteboardExtractor` and `ScreenSharingManager` use `@AppStorage` (SwiftUI), which couples non-UI modules to SwiftUI + UserDefaults and complicates reuse.

### 1.3 Top Refactor Targets (high impact / moderate risk)

1. **Split `OverlayRootView.swift`** into smaller feature views + extracted coordinators (P0).
2. **Introduce a settings/provider abstraction** to remove `@AppStorage` from services (P0).
3. **Narrow and formalize DI boundaries** (split `AppServiceProviding`, stop direct `ClipItemStore()` instantiation in UI) (P0/P1).
4. **Extract coordinators from `AppDelegate`** (capture, onboarding, hotkey wiring) (P1).

---

## 2. Current State Analysis

### 2.1 Repository structure (as shipped)

- `ClipboardCore/` — platform-agnostic business rules, persistence, CloudKit sync
- `ClipboardMac/`
  - `Sources/ClipboardMacServices/` — macOS system services (pasteboard polling/extraction, paste engine, hotkeys, permissions)
  - `Sources/ClipboardMacApp/` — SwiftUI views + AppKit windowing/menu-bar + composition
- `docs/` — documentation & ADRs

### 2.2 Code quality baseline metrics (measured)

Metrics were computed from the working tree (excluding `/.build`, `/DerivedData`, `/.git`).

- **Swift files:** 182
  - `ClipboardCore`: 45
  - `ClipboardMacApp`: 59
  - `ClipboardMacServices`: 19
  - `Tests`: 57
  - Other: 2
- **Swift LOC (raw lines):** 30,021
- **Test surface (static count):** ~297 `func test…` declarations across ~49 `XCTestCase` references

### 2.3 Largest files / complexity hot spots

The following files are likely to be both maintenance and SOLID-risk hot spots due to size and mixed responsibilities:

1. `ClipboardMacApp/UI/Overlay/ItemEditorWindow.swift` (~1500 LOC)
2. `ClipboardMacApp/UI/Overlay/OverlayRootView.swift` (~1446 LOC)
3. `ClipboardMacApp/UI/Overlay/ItemCard.swift` (~1217 LOC)
4. `ClipboardMacApp/UI/Overlay/OverlayItemPreview.swift` (~1065 LOC)
5. `ClipboardCore/BusinessRules/ClipItemStore.swift` (~1047 LOC)
6. `ClipboardMacApp/UI/Overlay/ItemCardRow.swift` (~904 LOC)
7. `ClipboardMacApp/UI/Overlay/PinboardTabBar.swift` (~867 LOC)

### 2.4 Application entry points (composition & lifecycle)

- **SwiftUI entry:** `ClipboardMacApp/App/ClipboardMacApp.swift`
- **Composition root (effective):** `ClipboardMacApp/App/AppDelegate.swift` creates the UI controllers, starts services, wires event streams, registers hotkeys, and performs integrity checks.
- **DI container:** `ClipboardMacApp/App/AppServiceContainer.swift` owns concrete service instances.

---

## 3. Component Inventory (UI windows, services, and core modules)

### 3.1 UI windows & major UI components

- **Settings window (SwiftUI Scene)**
  - `ClipboardMacApp.swift` creates the scene and injects dependencies.
  - `UI/Settings/SettingsView.swift` and tabs (`GeneralTab`, `PrivacyTab`).

- **Overlay window (NSPanel + SwiftUI host)**
  - `UI/Overlay/OverlayWindow.swift` (`OverlayWindowController`, `OverlayPanel`) hosts `OverlayRootView` and manages key handling.
  - `UI/Overlay/OverlayRootView.swift` is the primary overlay feature hub (rendering, search, pinboards, selection, item operations, window coordination).

- **Item editor window (NSPanel + SwiftUI host)**
  - `UI/Overlay/ItemEditorWindow.swift` manages editing across item types (text/rich text/image/file) and contains persistence interactions.

- **Drag preview windows**
  - `UI/Overlay/DragPreviewWindow.swift`, `UI/Overlay/DragCoordinator.swift`.

- **Onboarding window**
  - `UI/Onboarding/OnboardingFlow.swift`, created/presented by `AppDelegate`.

- **Menu bar integration**
  - `App/MenuBarController.swift` builds an `NSStatusItem` menu and triggers overlay/settings actions.

### 3.2 macOS system services (`ClipboardMacServices`)

- **Capture pipeline:** `PasteboardMonitor` → `PasteboardExtractor` → payload to core store
- **Paste pipeline:** `PasteEngine` (clipboard write + activation + CGEvent Cmd+V)
- **Global hotkeys:** `HotkeyManager`
- **Permissions:** `PermissionManager`
- **Cross-cutting event bus:** `ClipboardEventBroadcaster`

### 3.3 Core modules (`ClipboardCore`)

- **Persistence:** `PersistenceController` and Core Data model/entities
- **Business rules repository:** `ClipItemStore` (CRUD, dedupe, marking used, retention, metadata)
- **Sync:** `SyncCoordinator`, engines, mapping, conflict resolution, CloudKit manager

---

## 4. Inter-Component Communication & Data Flows

### 4.1 Primary runtime flows

**Capture**

1. `PasteboardMonitor` polls `NSPasteboard.changeCount`.
2. On change, `AppDelegate` receives callback and calls `handlePasteboardChange`.
3. `PasteboardExtractor` builds a `ClipItemPayload`.
4. `ClipItemStore.createItem(payload:)` persists the item and representations.
5. Sync coordinator (if enabled) picks up changes for outbound sync.

**Paste**

1. Overlay selects one or more items.
2. `OverlayViewModel` calls `PasteEngine`.
3. `PasteEngine` writes to pasteboard and synthesizes Cmd+V via `CGEvent`.

### 4.2 Communication mechanisms used

- **Combine publisher (explicit):** `ClipboardEventBroadcaster.events` propagates paste/overlay lifecycle events.
- **NotificationCenter publisher (implicit global):** `UserDefaults.didChangeNotification` triggers hotkey reload and preview scheduling.
- **SwiftUI environment injection:** `environmentObject` for view models, custom EnvironmentKey for broadcaster.
- **Core Data fetch requests:** SwiftUI views read model state via `@FetchRequest`.

### 4.3 Observed coupling points

- UI-level code directly touches persistence and stores in several places, bypassing the DI container.
- Some services depend on SwiftUI storage wrappers (`@AppStorage`), creating a UI-framework dependency from non-UI layers.

---

## 5. SOLID Principles Evaluation (by layer)

This section lists both positive conformance and concrete violations with examples.

### 5.1 Presentation Layer (SwiftUI/AppKit)

**Single Responsibility Principle (SRP)**

- ✅ `OverlayWindowController` is conceptually a window host and dependency injector.
- ❌ `OverlayRootView` acts as a feature-composition root and also contains:
  - state coordination, persistence fetches, search/pinboard logic, keyboard handling hooks, drag/drop orchestration, and window coordination.
  - It constructs concrete managers internally:
    - `ItemOperationsHandler()`, `PinboardManager()`, `PasteStackManager()`, `ItemEditorWindowController()`.
  - This creates multiple reasons to change in one file.

**Examples**

- `OverlayRootView.swift` has many responsibilities and internal concretes (e.g. internal manager construction).
- `ItemEditorWindow.swift` mixes AppKit windowing + multiple editor modes + persistence operations.

**Open/Closed Principle (OCP)**

- ❌ Adding a new overlay feature often requires editing `OverlayRootView` rather than composing new independent views/controllers.
- ✅ Some extensibility exists via dedicated feature view models (e.g., search view model), but the composition remains centralized.

**Dependency Inversion Principle (DIP)**

- ✅ `OverlayViewModel` depends on `any PasteEngineProtocol`.
- ❌ UI components sometimes instantiate concrete repositories directly:
  - `ItemEditorContentView` contains `private let store = ClipItemStore()`.

**Interface Segregation Principle (ISP)**

- ❌ `AppServiceProviding` is broad. Many consumers likely need only a small subset, but must depend on the full surface.

### 5.2 Platform Services Layer (`ClipboardMacServices`)

**SRP**

- ✅ `PasteEngine` is focused on paste/activation/keystroke sending.
- ❌ `PasteboardExtractor` combines:
  - extraction, classification, filtering decisions, settings lookup, and type derivation.

**DIP / layering**

- ✅ Extractors are separated into `PasteboardTypeExtractor` implementations.
- ❌ `PasteboardExtractor` imports `SwiftUI` and reads `@AppStorage` keys, which are UI layer concepts:
  - `@AppStorage("ignoreConfidentialContent")`
  - `@AppStorage("ignoreTransientContent")`

**Interface Segregation Principle (ISP)**

- ⚠️ Services generally have focused APIs, but settings/config access is inconsistent (some services read SwiftUI storage directly, others rely on injection). This causes consumers to depend on more implementation detail than necessary.

**OCP**

- ❌ New extractors require modifying a fixed array inside `PasteboardExtractor` (constructor-level change). This is acceptable at small scale, but is not OCP-friendly long-term.

### 5.3 Core / Domain / Data Access (`ClipboardCore`)

**SRP**

- ✅ `PersistenceController` encapsulates the Core Data stack.
- ⚠️ `ClipItemStore` behaves like a repository plus several workflow utilities (dedupe, retention, marking usage, derived searchable text, asset thresholding). It is large (~1k LOC) and likely to keep accumulating features.

**DIP**

- ⚠️ `ClipItemStore` depends on concrete `PersistenceController` and `AssetStore` by default (`.shared`). This makes the dependency graph implicit.
- ✅ It allows explicit injection via initializer parameters.

**Liskov Substitution Principle (LSP)**

- The codebase uses relatively little class inheritance for behavior polymorphism; most polymorphism is via protocols (`PasteEngineProtocol`, broadcaster, sync coordinating). LSP risk is therefore low and mainly applies to protocol conformers; current protocol use is straightforward.

**OCP**

- Sync is structured into multiple components (coordinator + engines + mapper), which is generally more extensible than a monolith.

---

## 6. Programming Practices Review

### 6.1 What’s working well

- **Use of OSLog categories** and structured logging in core flows.
- **Concurrency patterns are mostly explicit** (Task boundaries, @MainActor where appropriate).
- **Clear subsystem boundaries** with separate Swift packages.

### 6.2 Practices to improve

- **Leftover debug artifacts:** A file ending in `.swift.backup` exists in the overlay folder. This should not ship.
- **`print()` usage in shipping code:** Several overlay/editor files use `print()` instead of OSLog.
- **Settings access is inconsistent:** some parts use `@AppStorage`, others use `UserDefaults.standard` directly.

---

## 7. Refactoring Recommendations (by component)

### 7.1 Composition & lifecycle

**Component:** `AppDelegate`

- **Issues:** SRP violation, orchestration and composition mixed, broad knowledge of many subsystems.
- **Recommendation:** Introduce dedicated coordinators and keep `AppDelegate` as a thin shell.
  - `CaptureCoordinator` (monitor + extractor + store)
  - `HotkeyCoordinator` (registration/reload)
  - `OnboardingCoordinator` (window creation/presentation)
  - `IntegrityCheckService` (startup checks)

### 7.2 Overlay UI

**Component:** `OverlayRootView`

- **Issues:** mega-view; owns and constructs many managers; high state surface; harder to test.
- **Recommendation:**
  - Extract "feature slices" (Search, Pinboards, Item Grid, Preview, Keyboard Shortcuts, Drag/Drop) into separate view structs and view models.
  - Move non-rendering logic to services/coordinators injected via the environment.

### 7.3 Editor UI

**Component:** `ItemEditorWindow.swift`

- **Issues:** windowing + editing logic + persistence are mixed; direct store construction.
- **Recommendation:**
  - Extract a `ItemEditingService` (save rich text/image/file) with protocol.
  - Inject `ClipItemStore` (or narrower protocol) via environment or initializer.

### 7.4 Capture extraction

**Component:** `PasteboardExtractor`

- **Issues:** imports SwiftUI for `@AppStorage`; settings are pulled from UI framework.
- **Recommendation:** Replace `@AppStorage` with an injected `CaptureSettingsProviding` that reads UserDefaults (or a dedicated settings store) outside SwiftUI.

### 7.5 DI and interface design

**Component:** `AppServiceProviding`

- **Issues:** interface is large; consumers likely need smaller subsets (ISP violation).
- **Recommendation:** Split into smaller protocols:
  - `CaptureServicesProviding`, `PasteServicesProviding`, `SyncServicesProviding`, `OverlayServicesProviding`.
  - Keep `AppServiceProviding` as a typealias/composition for the app root only.

---

## 8. Implementation Roadmap (prioritized)

Priority is defined as:

- **P0:** High value, low-to-moderate risk, unlocks other refactors
- **P1:** High value but touches core flows / moderate risk
- **P2:** Nice-to-have / opportunistic cleanups

| Priority | Work Item | Scope | Expected Benefit | Risk |
|---|---|---|---|---|
| P0 | Remove SwiftUI `@AppStorage` from services via settings provider | Services | Cleaner layering, better testability | Low |
| P0 | Stop direct `ClipItemStore()` creation in UI; inject store/protocol | UI/Core boundary | Better DI consistency, fewer hidden dependencies | Low |
| P0 | Split `OverlayRootView` into feature subviews + coordinators | UI | Reduced cognitive load, easier iteration | Medium |
| P1 | Extract coordinators from `AppDelegate` | App lifecycle | SRP compliance, more testable startup | Medium |
| P1 | Split `ClipItemStore` into repository + domain services | Core | Clearer domain boundaries, smaller units | Medium |
| P2 | Replace `print()` with OSLog + remove `.swift.backup` | Hygiene | Cleaner logs/builds | Low |
| P2 | Break up huge overlay/editor files by feature | UI | Incremental maintainability | Low |

---

## 9. Concrete Before/After Refactoring Examples

### 9.1 Remove SwiftUI `@AppStorage` from `PasteboardExtractor`

**Before (current pattern)**

```swift
import SwiftUI

public final class PasteboardExtractor {
    @AppStorage("ignoreConfidentialContent") private var ignoreConfidentialContent = true
    @AppStorage("ignoreTransientContent") private var ignoreTransientContent = true
}
```

**After (proposed)**

```swift
public protocol CaptureSettingsProviding {
    var ignoreConfidentialContent: Bool { get }
    var ignoreTransientContent: Bool { get }
}

public struct UserDefaultsCaptureSettings: CaptureSettingsProviding {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var ignoreConfidentialContent: Bool { defaults.bool(forKey: "ignoreConfidentialContent") }
    public var ignoreTransientContent: Bool { defaults.bool(forKey: "ignoreTransientContent") }
}

public final class PasteboardExtractor {
    private let settings: CaptureSettingsProviding
    public init(settings: CaptureSettingsProviding = UserDefaultsCaptureSettings()) {
        self.settings = settings
    }
}
```

### 9.2 Inject `ClipItemStore` into editor content view

**Before (current pattern)**

```swift
private struct ItemEditorContentView: View {
    private let store = ClipItemStore()
}
```

**After (proposed)**

```swift
protocol ClipItemStoring {
    func updateText(objectID: NSManagedObjectID, text: String) throws
}

extension ClipItemStore: ClipItemStoring {}

private struct ItemEditorContentView: View {
    private let store: ClipItemStoring

    init(item: ClipItem, store: ClipItemStoring, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.item = item
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draftText = State(initialValue: item.primaryText ?? "")
        // ...
    }
}
```

### 9.3 Split `AppServiceProviding` to improve ISP

**Before (current pattern)**

```swift
protocol AppServiceProviding {
    var persistence: PersistenceController { get }
    var clipItemStore: ClipItemStore { get }
    var pasteboardMonitor: PasteboardMonitor { get }
    var pasteEngine: PasteEngine { get }
    var syncCoordinator: SyncCoordinator? { get }
    // ... many more
}
```

**After (proposed)**

```swift
protocol CaptureServicesProviding {
    var pasteboardMonitor: PasteboardMonitor { get }
    var pasteboardExtractor: PasteboardExtractor { get }
    var clipItemStore: ClipItemStore { get }
}

protocol PasteServicesProviding {
    var pasteEngine: PasteEngine { get }
    var permissionManager: PermissionManager { get }
}

typealias AppServiceProviding = CaptureServicesProviding & PasteServicesProviding
```

### 7.6 Additional component notes

**Component:** `PasteEngine` (services)

- **Current:** Good protocol seams, explicit validation failures, event broadcaster integration.
- **Improve:** Isolate retry/backoff and activation timing into small helpers (SRP), and ensure UI-facing error translation happens in the view model layer.

**Component:** `HotkeyManager` (services)

- **Current:** Centralized hotkey registration and CGEvent handling.
- **Improve:** Consider splitting registration (configuration) from event processing (runtime) to reduce responsibilities and simplify tests.

**Component:** `SyncCoordinator` (core)

- **Current:** Clear coordinator pattern; factory method (`create`) wires container/db and engines.
- **Improve:** Push entitlement/container checks and “sync enabled” settings lookup out of the coordinator factory into the app composition layer to reduce environment coupling.

**Component:** `MenuBarController` (app)

- **Current:** Focused, action-driven API.
- **Improve:** Prefer injected closures (already used) over direct global state access; keep as a thin UI adapter.

---

## 10. Evidence Index (file:line)

The following references are concrete, audit-relevant coupling or SOLID points.

### 10.1 SRP / mega-types

- `ClipboardMacApp/App/AppDelegate.swift:52` — `applicationDidFinishLaunching` orchestrates composition + multiple workflows.
- `ClipboardMacApp/UI/Overlay/OverlayRootView.swift:33-36` — constructs multiple concrete managers inside the view.

### 10.2 DIP / hidden dependencies

- `ClipboardMacApp/UI/Overlay/ItemEditorWindow.swift:139` — `private let store = ClipItemStore()` inside a UI view.
- `ClipboardCore/BusinessRules/ClipItemStore.swift:25` — defaults to `.shared` dependencies.
- `ClipboardCore/Persistence/PersistenceController.swift:5` — singleton shared persistence controller.

### 10.3 UI-layer leakage into services

- `ClipboardMacServices/Services/PasteboardMonitor/PasteboardExtractor.swift:22-23` — `@AppStorage` usage inside a service.
- `ClipboardMacServices/Services/ScreenSharing/ScreenSharingManager.swift:5` — `@AppStorage` usage inside a service.

### 10.4 Settings access inconsistency

- `ClipboardMacApp/App/AppServiceContainer.swift:69` — reads sync enabled via `UserDefaults.standard` closure.
- `ClipboardMacApp/UI/Overlay/OverlayViewModel.swift:95` — reads `alwaysPastePlainText` from `UserDefaults.standard`.

### 10.5 Logging hygiene

- `ClipboardMacApp/UI/Overlay/OverlayWindow.swift:176-183` — `print()` usage in window sizing logic.
- `ClipboardMacApp/UI/Overlay/OverlayItemPreview.swift` — `print()` used for error reporting.
- `ClipboardMacApp/UI/Overlay/ItemEditorWindow.swift` — `print()` used for error reporting.

---

## 11. Closing Notes

---

## 10. Closing Notes

Paste already demonstrates strong practical engineering choices (clear packages, high test count, minimal dependencies). The biggest gains now are in consistency: narrowing interfaces, making dependencies explicit, and decomposing mega-files into smaller, independently testable units.
