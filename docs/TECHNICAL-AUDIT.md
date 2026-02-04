# Paste – Comprehensive Technical Audit (SOLID / DI / Architecture)

**Repository:** Paste (macOS clipboard manager with iCloud sync)

**Audit date:** 2026-02-03

---

## 1. Scope & Method

### Scope

This audit covers the entire SwiftPM-based codebase:

- `ClipboardCore` (domain + Core Data + CloudKit sync)
- `ClipboardMacServices` (macOS system integration: pasteboard monitor, hotkeys, paste engine, permissions)
- `ClipboardMacApp` (SwiftUI/AppKit UI + coordinators)
- UI surfaces: Overlay window, Item Editor window, Settings window, Onboarding window, Menu bar UI

### Method

- Inventory of components from `docs/INDEX.md` and `docs/CODEBASE.md`
- Static architecture reading (composition roots, coordinators, repositories/services)
- Inter-component communication mapping (Combine, NotificationCenter, Core Data bindings, closures)
- SOLID evaluation per module and per major component
- Lightweight code-quality metrics (LOC and file-size distribution)

---

## 2. Current State Summary

### 2.1 High-level architecture

- **Layering is generally clean**:
  - `ClipboardCore` is SwiftUI-free and platform-agnostic.
  - `ClipboardMacServices` is where AppKit / CGEvent / NSPasteboard live.
  - `ClipboardMacApp` is the composition/UI layer.
- **Patterns used consistently**:
  - Repository/service layer in `ClipboardCore`
  - Coordinator pattern for capture/hotkeys/onboarding
  - Protocol-based settings providers to avoid SwiftUI wrappers in services
  - Combine + environment injection for lightweight eventing

### 2.2 UI surface inventory (Windows / Panels)

- **Overlay panel** (main UI): `ClipboardMacApp/UI/Overlay/OverlayWindow.swift`
- **Item Editor panel**: `ClipboardMacApp/UI/Overlay/ItemEditorWindow.swift`
- **Settings window** (SwiftUI Window scene): `ClipboardMacApp/App/ClipboardMacApp.swift` + `ClipboardMacApp/UI/Settings/SettingsView.swift`
- **Onboarding window**: `ClipboardMacApp/App/Coordinators/OnboardingCoordinator.swift`
- **Menu bar**: `ClipboardMacApp/App/MenuBarController.swift`

### 2.3 Primary data / control flows

#### Capture pipeline

1. `PasteboardMonitor` polls `NSPasteboard`.
2. `CaptureCoordinator` extracts payload via `PasteboardExtractor`.
3. `ClipItemStore` persists to Core Data (via repository/services).
4. Optional: thumbnails, link previews.
5. Sync: `OutboundSyncEngine` observes saves and uploads.

#### Paste pipeline

1. Hotkey toggles overlay via `HotkeyCoordinator`.
2. User selects items in overlay.
3. `OverlayViewModel` calls `PasteEngine` to write pasteboard + inject Cmd+V.
4. Event bus publishes `.clipboardWillWrite` to suppress recapture.

#### Sync pipeline

1. `SyncCoordinator` composes CloudKit manager + inbound/outbound engines.
2. Push notifications are forwarded from `AppDelegate`.
3. Sync status is surfaced to UI (Settings + indicators).

---

## 3. Code Quality Metrics (Current)

### 3.1 Size distribution

- **Swift files:** 234
- **Total LOC (Swift):** 36,285
- **LOC breakdown:**
  - `ClipboardCore/Sources`: 7,467 LOC (51 files)
  - `ClipboardCore/Tests`: 4,454 LOC (27 files)
  - `ClipboardMac/Sources`: 21,109 LOC (114 files)
  - `ClipboardMac/Tests`: 3,175 LOC (40 files)

### 3.2 Largest files (risk of SRP erosion)

The following files are significantly larger than the “keep under ~400–500 lines” guideline (see `docs/BEST-PRACTICES.md`), suggesting consolidation of multiple responsibilities:

- `ClipboardMacApp/UI/Overlay/ItemEditorContentView.swift` (~1689 LOC)
- `ClipboardMacApp/UI/Overlay/OverlayShellView.swift` (~1274 LOC)
- `ClipboardMacApp/UI/Overlay/ItemCard.swift` (~1225 LOC)
- `ClipboardMacApp/UI/Overlay/PinboardTabBar.swift` (~950 LOC)
- `ClipboardMacServices/Services/PasteEngine/PasteEngine.swift` (~605 LOC)
- `ClipboardCore/Sources/Sync/SyncCoordinator.swift` (~617 LOC)

### 3.3 Dependency / constructability signals (rough)

- Protocol count (repo-wide): ~35
- `@MainActor` occurrences: ~115 (good isolation intent)
- `@unchecked Sendable` appears in multiple key types (requires targeted safety review)

---

## 4. Inter-Component Communication Audit

### 4.1 Communication mechanisms in use

1. **Direct dependency injection (initializers)**
   - Example: `CaptureCoordinator` receives `PasteboardMonitor`, `ClipItemStore`, etc.
2. **Combine-based event bus**
   - `ClipboardEventBroadcaster` publishes `.clipboardWillWrite`, `.overlayDidShow`, paste validation failures.
3. **NotificationCenter**
   - `UserDefaults.didChangeNotification` is used to reload hotkeys and schedule link preview fetches.
4. **Core Data reactivity**
   - Overlay uses `@FetchRequest` for live lists.
5. **Closures for cross-layer callbacks**
   - Overlay close/hide callbacks passed to view models/coordinators.

### 4.2 Findings

#### Finding A: Event bus default instantiation can silently fork the “global” bus

- File: `ClipboardMacApp/UI/Utilities/ClipboardEventBroadcasterEnvironment.swift`
- Current code:

```swift
private struct ClipboardEventBroadcasterKey: EnvironmentKey {
    static let defaultValue: any ClipboardEventBroadcaster = ClipboardEventBroadcasterImpl()
}
```

**Risk**

- If a view tree forgets to inject `.environment(\.clipboardEventBroadcaster, ...)`, it still compiles and runs, but uses a brand-new broadcaster instance.
- This creates “it works in most places, but not in some views/tests” failure modes.

**Recommendation (P0)**

- Make the default a **sentinel** that traps in debug (or logs a fault) if used, forcing correct injection.

#### Finding B: A mix of Combine and direct calls is fine, but ownership boundaries are slightly blurry

- Example: `OverlayWindowController` both publishes events and constructs view model + root view.
- Recommendation: keep eventing (Combine) in services/coordinators, and keep view-tree creation in a single “composition root” factory.

---

## 5. SOLID Evaluation (by Module)

### 5.1 `ClipboardCore` (Domain / Persistence / Sync)

#### Strengths

- **Good separation of concerns** between:
  - persistence stack (`PersistenceController`)
  - domain services (dedupe/retention/usage/assets/search)
  - sync subsystem (inbound/outbound engines, mappers, conflict resolver)
- **Few UI dependencies** (no `SwiftUI` imports).

#### SOLID issues & recommendations

##### SRP: `ClipItemStore` is both a façade *and* a composition root

- File: `ClipboardCore/Sources/BusinessRules/ClipItemStore.swift`
- Current:
  - Initializes repositories/services internally and exposes many unrelated operations.

**Why it matters**

- Makes unit testing harder (you must accept its internal wiring).
- Tightens coupling to concrete implementations.

**Before (current pattern)**

```swift
public final class ClipItemStore {
    public init(persistence: PersistenceController = .shared, assetStore: AssetStore = .shared) {
        let pinboardRepository = PinboardRepository(persistence: persistence)
        let searchService = SearchService(persistence: persistence)
        // ... constructs multiple services
        self.repository = ClipItemRepository(...)
    }
}
```

**After (recommended direction)**

```swift
public protocol ClipItemStoring {
    func createItem(payload: ClipItemPayload, sourceApp: SourceAppInfo?, isUserCreated: Bool) throws -> ClipItem
    func deleteItem(objectID: NSManagedObjectID) throws
    // narrow interface (expand only as needed)
}

public final class ClipItemStore: ClipItemStoring {
    public init(
        repository: any ClipItemRepositoryProtocol,
        retentionService: any ClipItemRetentionServicing,
        usageService: any ClipItemUsageServicing,
        assetManagementService: any AssetManagementServicing,
        pinboardRepository: any PinboardRepositoryProtocol,
        searchService: any SearchServicing
    ) { /* store references */ }
}
```

**Priority**: P1 (high leverage, but touches many call sites).

##### DIP: `ClipItemRepository` and `ClipItemStore` strongly prefer concrete types and singletons

- Files:
  - `ClipboardCore/Sources/BusinessRules/ClipItemRepository.swift`
  - `ClipboardCore/Sources/BusinessRules/ClipItemStore.swift`

**Recommendation**

- Introduce narrow protocols (`ClipItemRepositoryProtocol`, etc.) and keep singletons at the app composition layer.

##### OCP: Representation-type handling is centralized in large switches

- Example: `PasteboardExtractor.deriveItemType(...)` in services layer (see section 5.2).

**Recommendation**

- Prefer a “type classifier registry” so adding a new representation kind does not require editing multiple switches.

---

### 5.2 `ClipboardMacServices` (System integration)

#### Strengths

- **Excellent protocol hygiene** in `PasteEngine`:
  - `PasteEngineProtocol`, `ActiveAppTracking`, `AccessibilityPermissionChecking`, `PasteKeystrokeSending`, `TargetActivationChecking`.
  - Easy to test and swap system components.

#### SOLID issues & recommendations

##### OCP: `PasteboardExtractor` has a fixed extractor list

- File: `ClipboardMacServices/Services/PasteboardMonitor/PasteboardExtractor.swift`
- Current:

```swift
private let extractors: [PasteboardTypeExtractor] = [
    StringExtractor(), RTFExtractor(), HTMLExtractor(), URLExtractor(), ImageExtractor(),
]
```

**Impact**

- Adding new formats requires editing this file.

**Recommendation (P2)**

- Allow injection of extractors via initializer, keeping a default list:

```swift
public init(
    settings: any CaptureSettingsProviding = UserDefaultsCaptureSettingsProvider(),
    extractors: [any PasteboardTypeExtractor] = PasteboardExtractor.defaultExtractors
) { ... }
```

##### SRP: `PasteboardExtractor` handles extraction + filtering + item-type classification

**Recommendation (P2)**

- Split into:
  - `PasteboardRepresentationExtracting`
  - `ClipboardFiltering` (transient/sensitive)
  - `ItemTypeClassifying`

This reduces “one file owns all policy” and supports feature flags or future classifiers.

---

### 5.3 `ClipboardMacApp` (UI / Composition)

#### Strengths

- Coordinator pattern is used to keep `AppDelegate` slimmer than a fully monolithic delegate.
- Overlay view model depends on `PasteEngineProtocol` (good DIP).

#### SOLID issues & recommendations

##### SRP: `AppDelegate` is still a multi-responsibility “god object”

- File: `ClipboardMacApp/App/AppDelegate.swift`
- Responsibilities currently include:
  - crash reporting setup
  - UserDefaults registration
  - wiring overlay/editor/menu bar
  - starting capture/hotkey/onboarding/integrity
  - listening to defaults changes
  - retention scheduling
  - push registration / entitlement inspection
  - remote notification dispatch to sync

**Recommendation (P0/P1)**

- Keep `AppDelegate` as a thin host that:
  - constructs a single `AppCoordinator`
  - forwards lifecycle callbacks

**Before (current pattern)**

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(...) {
        CrashReporter.shared.setup...
        overlayController = OverlayWindowController(...)
        captureCoordinator = CaptureCoordinator(...)
        hotkeyCoordinator = HotkeyCoordinator(...)
        scheduleRetentionCleanup()
        // ... many more
    }
}
```

**After (recommended direction)**

```swift
@MainActor
final class AppCoordinator {
    init(services: AppServiceProviding) { ... }
    func start() { ... }
    func stop() { ... }
    func handleRemoteNotification() async { ... }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator: AppCoordinator
    func applicationDidFinishLaunching(...) { coordinator.start() }
}
```

##### DIP: UI types sometimes construct services directly

Examples:

- `OverlayShellView.init(...)` constructs `AppleIntelligenceTextService()` and `ItemEditorWindowController` directly.
- `OverlayWindowController` has default parameters that construct concrete services (`PasteEngine()`, `PermissionManager()`, `ClipboardEventBroadcasterImpl()`).

**Impact**

- Hidden dependencies and surprise global state.
- Harder to write deterministic tests.

**Recommendation (P0)**

- Treat UI as consumers of injected dependencies only.
- Move all service creation to a single composition root (`AppServiceContainer` + UI factories).

##### ISP: `AppServiceProviding` repeats and re-exposes everything

- File: `ClipboardMacApp/App/AppServiceContainer.swift`
- `AppServiceProviding` inherits multiple provider protocols but then re-declares all properties.

**Recommendation (P1)**

- Remove the duplicate re-declarations and use a `typealias` to compose provider protocols.
- Prefer returning protocol types (e.g., `any PasteEngineProtocol`) rather than concrete types.

---

## 6. Component-by-Component Findings & Refactoring Recommendations

### 6.1 Composition / DI

#### AppServiceContainer

- File: `ClipboardMacApp/App/AppServiceContainer.swift`

**Findings**

- Good: dedicated composition object for app-level wiring.
- Concern: returns concrete types for many services, limiting substitutability.

**Refactor recommendations**

- Change exposed types to protocols:
  - `pasteEngine: any PasteEngineProtocol`
  - `permissionManager: any AccessibilityPermissionChecking` (or a dedicated UI-safe protocol)
- Split container into scoped containers:
  - `CaptureContainer`, `OverlayContainer`, `SettingsContainer`.

### 6.2 Overlay UI

#### OverlayShellView

- File: `ClipboardMacApp/UI/Overlay/OverlayShellView.swift`

**Findings**

- Multiple responsibilities in one view:
  - data sourcing (`@FetchRequest`), search state, selection, drag, pinboard editing, lock state
  - window coordination
  - editor window creation
  - extensive event handling

**Refactor recommendations (P0/P1)**

- Extract dependencies to a `OverlayDependencies` value:

```swift
struct OverlayDependencies {
    let clipItemStore: ClipItemStoring
    let itemOperations: ItemOperating
    let pinboards: PinboardManaging
    let previewCoordinator: OverlayPreviewCoordinating
}
```

- Split into subviews:
  - `OverlayHeaderView`, `OverlayPinboardPicker`, `OverlayItemGrid`, `OverlaySearchBar`.
- Keep all “handlers” as `@MainActor` view-model objects or coordinator objects.

#### OverlayWindowController

- File: `ClipboardMacApp/UI/Overlay/OverlayWindow.swift`

**Findings**

- Controller mixes:
  - window/panel behavior (correct place)
  - view model creation + view tree wiring

**Refactor recommendations (P1)**

- Introduce an `OverlayRootViewFactory` that builds the SwiftUI root view and environment.
- Keep `OverlayWindowController` focused on panel lifecycle and positioning.

### 6.3 Capture pipeline

#### CaptureCoordinator

- File: `ClipboardMacApp/App/Coordinators/CaptureCoordinator.swift`

**Findings**

- Orchestrates extraction, persistence, thumbnails, sound effects, and link preview scheduling.

**Refactor recommendations (P2)**

- Split into separate injected steps:
  - `CapturePersisting` (payload → store)
  - `CapturePostProcessing` (thumbnails/link previews/sounds)

### 6.4 Sync

#### SyncCoordinator

- File: `ClipboardCore/Sources/Sync/SyncCoordinator.swift`

**Findings**

- Coordinator is large but conceptually an orchestrator (reasonable).

**Refactor recommendations (P2)**

- Extract smaller internal helpers:
  - `PeriodicSyncScheduler`
  - `SyncStateMachine` (idle/syncing/synced/error)

### 6.5 Menu Bar

#### MenuBarController

- File: `ClipboardMacApp/App/MenuBarController.swift`

**Findings**

- Good SRP boundary: owns `NSStatusItem` and menu items.
- However, it has a **hard reference to `AppDelegate`** via selector call:

```swift
NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
```

**SOLID impact**

- **DIP violation**: `MenuBarController` depends on a concrete app delegate type.
- **OCP friction**: changing settings-opening behavior requires editing menu bar code.

**Refactor recommendation (P1)**

- Inject a narrow interface:

```swift
protocol SettingsOpening { func openSettings() }
```

and pass an implementation from the composition root.

### 6.6 Settings UI

#### SettingsView

- Files: `ClipboardMacApp/App/ClipboardMacApp.swift`, `ClipboardMacApp/UI/Settings/SettingsView.swift`

**Findings**

- Settings UI composes tabs cleanly and avoids service construction.
- It depends on concrete `SyncCoordinator?`.

**SOLID impact**

- **DIP improvement opportunity**: `ClipboardCore` already defines `SyncCoordinating`; UI can depend on that protocol instead.

**Refactor recommendation (P0/P1)**

- Replace `SyncCoordinator?` with `(any SyncCoordinating)?` at the UI boundary.

### 6.7 Hotkeys

#### HotkeyCoordinator

- File: `ClipboardMacApp/App/Coordinators/HotkeyCoordinator.swift`

**Findings**

- Good: injected `PasteSettingsProviding` keeps UserDefaults out of coordinator logic.
- Mixed: depends on concrete `PasteEngine` rather than `PasteEngineProtocol`.

**SOLID impact**

- **DIP**: coordinator can be made more testable by taking `any PasteEngineProtocol`.

**Refactor recommendation (P1)**

- Change coordinator dependency to `any PasteEngineProtocol` and update the service container.

### 6.8 Logging / Crash Reporting

#### CrashReporter

- File: `ClipboardMacServices/Services/CrashReporter.swift`

**Findings**

- Centralized crash/event recording is appropriate for a privacy-sensitive app.
- `CrashReporter.shared` is used across app and services.

**SOLID impact**

- **SRP**: likely OK as a dedicated cross-cutting service.
- **DIP**: heavy `.shared` usage makes testing more difficult.

**Refactor recommendation (P2)**

- Introduce a lightweight protocol (e.g., `CrashReporting`) and inject it into coordinators/services where tests need determinism.

### 6.9 Validation Executable

#### ClipboardMacValidation

- File: `ClipboardMacValidation/main.swift`

**Findings**

- A dedicated harness is a strong practice (regression + performance validation without UI).

**Recommendations**

- Expand it into an “architecture guard” tool (P3): run checks like “no `ClipboardEventBroadcasterImpl()` defaults in UI”.

---

## 7. Roadmap (Prioritized Implementation Plan)

### P0 (High impact / Low risk)

- **Prevent accidental event-bus forking** by removing `ClipboardEventBroadcasterImpl()` as an environment default.
- **Stop constructing services inside views** (start with `OverlayShellView.init` and `OverlayWindowController` defaults).
- **Centralize “open settings” behavior** (avoid key-event injection where possible; prefer a dedicated Settings window controller or a clean open-window bridge).

### P1 (High impact / Medium risk)

- Introduce protocol-based interfaces for:
  - `ClipItemStore` (split edit/search/pinboard responsibilities)
  - `PinboardManager`, `ItemOperationsHandler` (UI-layer “use cases”)
- Restructure `AppDelegate` into a thin wrapper with a new `AppCoordinator`.
- Reduce `AppServiceProviding` duplication and expose protocol types.

### P2 (Medium impact / Medium risk)

- Split `PasteboardExtractor` responsibilities and make extractor list injectable.
- Extract large SwiftUI views into smaller subviews + model objects to improve readability and testability.
- Tighten concurrency correctness: audit `@unchecked Sendable` usage and replace with safe isolation where possible.

### P3 (Longer-term)

- Adopt a small internal “architecture testing” suite:
  - enforce “no service construction in views”
  - enforce “no SwiftUI imports outside ClipboardMacApp”
  - enforce “no default event-bus instantiation outside composition root”

---

## 8. Concrete Before/After Refactor Examples

### Example 1: Fixing Environment default event broadcaster (P0)

**Before** (`ClipboardEventBroadcasterEnvironment.swift`)

```swift
static let defaultValue: any ClipboardEventBroadcaster = ClipboardEventBroadcasterImpl()
```

**After (recommended)**

```swift
final class MissingClipboardEventBroadcaster: ClipboardEventBroadcaster {
    var events: AnyPublisher<ClipboardEvent, Never> { Empty().eraseToAnyPublisher() }
    func publish(_ event: ClipboardEvent) {
        assertionFailure("clipboardEventBroadcaster not injected")
    }
}

static let defaultValue: any ClipboardEventBroadcaster = MissingClipboardEventBroadcaster()
```

### Example 2: Removing hidden dependencies from `OverlayShellView` (P0)

**Before** (`OverlayShellView.init`)

```swift
let appleIntelligence = AppleIntelligenceTextService()
let itemEditorWindowController = ItemEditorWindowController(
    clipItemEditor: store,
    appleIntelligence: appleIntelligence
)
_previewCoordinator = StateObject(
    wrappedValue: OverlayPreviewCoordinator(itemEditorWindowController: itemEditorWindowController)
)
```

**After (recommended direction)**

```swift
init(dependencies: OverlayDependencies) {
    self.clipItemEditor = dependencies.clipItemEditor
    self.itemOperationsHandler = dependencies.itemOperations
    self.pinboardManager = dependencies.pinboards
    _previewCoordinator = StateObject(wrappedValue: dependencies.previewCoordinator)
}
```

### Example 3: Making `ClipItemStore` test-friendly (P1)

**Before**

- Store constructs its dependencies internally.

**After**

- Create a `ClipItemStoring` protocol and inject it into UI/coordinators.
- Keep wiring in `AppServiceContainer` only.

---

## 9. Appendix: Key Files (Navigation)

- Architecture and maps: `docs/CODEBASE.md`, `docs/BEST-PRACTICES.md`
- Composition root: `ClipboardMacApp/App/AppServiceContainer.swift`
- Lifecycle root: `ClipboardMacApp/App/AppDelegate.swift`
- Overlay: `ClipboardMacApp/UI/Overlay/OverlayWindow.swift`, `OverlayShellView.swift`, `OverlayViewModel.swift`
- Capture: `ClipboardMacApp/App/Coordinators/CaptureCoordinator.swift`
- Paste: `ClipboardMacServices/Services/PasteEngine/PasteEngine.swift`
- Sync: `ClipboardCore/Sources/Sync/SyncCoordinator.swift`
