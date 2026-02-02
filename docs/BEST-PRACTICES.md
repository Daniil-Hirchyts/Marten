# Paste - Development Best Practices

**Last Updated:** 2026-02-03
**Audience:** All developers and contributors
**Status:** Active guidelines

This document establishes security, architecture, and quality standards for the Paste codebase. These practices reflect the current application architecture and the security/privacy requirements of a clipboard manager.

---

## 1. Security & Privacy

### 1.1 Clipboard Content Protection

**Rule:** Never log clipboard content or derived text.

Clipboard payloads must be treated as sensitive by default. Do not include clipboard text, file paths, URLs, or derived content in logs, error messages, or debug output.

**Examples:**
```swift
import OSLog

// ❌ BAD - logs clipboard content
Logger.pasteboard.info("Captured text: \(clipboardText)")

// ✅ GOOD - log metadata only
Logger.pasteboard.info("Captured text item (length=\(clipboardText.count, privacy: .public))")
```

### 1.2 Logging Policy

**Rule:** Use OSLog with privacy redaction. Never use `print()` in production code.

**Privacy Defaults:**
- `privacy: .private` — for all user-originated strings, file paths, URLs
- `privacy: .public` — only for safe metadata (counts, durations, sizes, booleans, enums)

**Log Levels:**
- `.debug` — high-volume instrumentation, noisy lifecycle events
- `.info` — normal operational events (capture, paste, sync)
- `.error` — failures requiring investigation
- `.fault` — critical failures (data loss, corruption)

**Examples:**
```swift
import OSLog

// ❌ BAD - uses print()
print("Pasteboard changed: \(changeCount)")

// ❌ BAD - logs sensitive data as public
Logger.pasteboard.info("Captured URL: \(url)")

// ✅ GOOD - logs safe metadata
Logger.pasteboard.info("Pasteboard changed (changeCount=\(changeCount, privacy: .public))")

// ✅ GOOD - redacts sensitive data
Logger.pasteboard.info("Captured URL: \(url, privacy: .private)")
Logger.pasteboard.info("Captured URL host: \(url.host ?? "unknown", privacy: .private)")
```

**Enforcement:**
- No `print()` statements allowed in production targets
- Use static analysis (grep) to prevent introduction of risky logging

### 1.3 Settings Access

**Rule:** Never use SwiftUI property wrappers in non-UI modules.

Services and business logic must not depend on `@AppStorage`, `@Environment`, or other SwiftUI-specific APIs. Use protocol-based settings providers instead.

**Before (❌ BAD):**
```swift
import SwiftUI

public final class PasteboardExtractor {
    @AppStorage("ignoreConfidentialContent") private var ignoreConfidentialContent = true
    @AppStorage("ignoreTransientContent") private var ignoreTransientContent = true
}
```

**After (✅ GOOD):**
```swift
public protocol CaptureSettingsProviding {
    var ignoreConfidentialContent: Bool { get }
    var ignoreTransientContent: Bool { get }
}

public struct UserDefaultsCaptureSettingsProvider: CaptureSettingsProviding {
    private let userDefaults: UserDefaults
    public init(userDefaults: UserDefaults = .standard) { self.userDefaults = userDefaults }

    public var ignoreConfidentialContent: Bool { userDefaults.bool(forKey: "ignoreConfidentialContent") }
    public var ignoreTransientContent: Bool { userDefaults.bool(forKey: "ignoreTransientContent") }
}

public final class PasteboardExtractor {
    private let settings: CaptureSettingsProviding

    public init(settings: CaptureSettingsProviding = UserDefaultsCaptureSettingsProvider()) {
        self.settings = settings
    }
}
```

**Benefits:**
- Testable (inject fake settings in tests)
- No SwiftUI dependency in non-UI code
- Explicit dependencies

### 1.4 Permissions & Entitlements

**Required Permissions:**
- **Accessibility** — Required for paste injection (CGEvent Cmd+V synthesis)
- **Input Monitoring** — Required for global hotkey capture
- **Screen Recording** — Optional, for screen sharing mode

**Rules:**
- Request permissions only when features are first used (not at launch)
- Provide graceful fallbacks when permissions denied
- Gate CloudKit/push code paths at composition layer only (not in core)

**Examples:**
```swift
// ✅ GOOD - check permission before paste
guard await permissionManager.hasAccessibilityPermission() else {
    logger.warning("Accessibility permission denied, cannot paste")
    throw PasteError.permissionDenied
}

// ✅ GOOD - graceful fallback for hotkeys
guard hotkeyManager.canRegisterHotkeys else {
    logger.info("Input Monitoring permission not granted, hotkeys disabled")
    return
}
```

---

## 2. Architecture & Code Organization

### 2.1 Dependency Injection

**Rule:** Inject dependencies via initializers. Avoid direct instantiation of services in views/controllers.

**Before (❌ BAD):**
```swift
private struct ItemEditorContentView: View {
    private let store = ClipItemStore()  // ❌ Hidden dependency
}
```

**After (✅ GOOD):**
```swift
protocol ClipItemStoring {
    func updateText(objectID: NSManagedObjectID, text: String) throws
}

extension ClipItemStore: ClipItemStoring {}

private struct ItemEditorContentView: View {
    private let store: ClipItemStoring  // ✅ Injected dependency

    init(item: ClipItem, store: ClipItemStoring, onCancel: @escaping () -> Void) {
        self.store = store
        // ...
    }
}
```

**Benefits:**
- Dependencies are explicit
- Testable (inject mocks/fakes)
- Reduces coupling

**Avoid:**
- `.shared` singletons in production code (except for true app-wide singletons)
- Direct `ClipItemStore()` construction in views
- Hidden `UserDefaults.standard` access scattered throughout code

### 2.2 SOLID Principles

#### Single Responsibility Principle (SRP)
**Rule:** Each file/class should have one clear responsibility.

**Examples:**
- ✅ `PasteEngine` — focused on paste/activation/keystroke sending
- ✅ `PersistenceController` — encapsulates Core Data stack
- ❌ `AppDelegate` doing composition + orchestration + startup checks (split into coordinators)

**Target:** Keep files under 400 lines when possible. Extract coordinators/services when responsibilities grow.

#### Dependency Inversion Principle (DIP)
**Rule:** Depend on protocols, not concrete types.

**Examples:**
```swift
// ✅ GOOD - depends on protocol
class OverlayViewModel {
    private let pasteEngine: any PasteEngineProtocol

    init(pasteEngine: any PasteEngineProtocol) {
        self.pasteEngine = pasteEngine
    }
}

// ❌ BAD - depends on concrete type
class OverlayViewModel {
    private let pasteEngine = PasteEngine()  // Hard dependency
}
```

#### Interface Segregation Principle (ISP)
**Rule:** Create narrow protocols for specific use cases. Avoid "kitchen sink" protocols.

**Before (❌ BAD):**
```swift
protocol AppServiceProviding {
    var persistence: PersistenceController { get }
    var clipItemStore: ClipItemStore { get }
    var pasteboardMonitor: PasteboardMonitor { get }
    var pasteEngine: PasteEngine { get }
    var syncCoordinator: SyncCoordinator? { get }
    // ... 10 more properties
}
```

**After (✅ GOOD):**
```swift
protocol CaptureServicesProviding {
    var pasteboardMonitor: PasteboardMonitor { get }
    var clipItemStore: ClipItemStore { get }
}

protocol PasteServicesProviding {
    var pasteEngine: PasteEngine { get }
    var permissionManager: PermissionManager { get }
}

// Compose at app root only
typealias AppServiceProviding = CaptureServicesProviding & PasteServicesProviding
```

### 2.3 File Size Guidelines

**Targets:**
- SwiftUI views: < 400 lines (composition may exceed, but extract logic)
- Services/repositories: < 500 lines
- Coordinators: < 300 lines

**When to extract:**
- File exceeds target and has multiple responsibilities
- Logic can be tested independently
- Code would be reused elsewhere

**Tools:**
- Use `MARK:` sections for navigation in larger files
- Extract view models, coordinators, or services when views grow

### 2.4 Module Boundaries

**3-Layer Architecture:**
1. **ClipboardCore** — platform-agnostic business rules, persistence, sync
2. **ClipboardMacServices** — macOS system integrations (pasteboard, paste engine, hotkeys)
3. **ClipboardMacApp** — SwiftUI/AppKit UI composition

**Rules:**
- Keep non-UI modules free of SwiftUI imports
- Core should not depend on Services or App
- Services should not depend on App

---

## 3. Testing & Verification

### 3.1 Test Requirements

**Build Requirements:**
- `swift build` must pass for `ClipboardCore` and `ClipboardMac`
- `swift test` must pass for all unit tests
- No compiler warnings in production builds

**UI Test Requirements:**
- UI tests must be executed via Xcode when UI changes are made
- SwiftPM `swift test` skips UI tests (Xcode host runner required)

**Test Coverage:**
- Add regression tests for bug fixes
- Add unit tests for new services/coordinators
- Justify why tests are unchanged for mechanical refactors

### 3.2 Performance Targets

**UX-Critical Flows:**
| Flow | Target | Measurement |
|------|--------|-------------|
| Overlay open | < 500ms | Time from hotkey to first render |
| Capture | < 50ms | Pasteboard poll to store write |
| Search | < 100ms | Keystroke to filtered results |
| Hashing (dedupe) | < 1ms | SHA-256 of typical text payload |

**Enforcement:**
- Profile with Instruments when performance degrades
- Add performance regression tests for critical paths

### 3.3 Testing Best Practices

**Unit Tests:**
```swift
// ✅ GOOD - tests with injected fake
func testCaptureWithConfidentialContentIgnored() {
    let fakeSettings = FakeCaptureSettings(ignoreConfidentialContent: true)
    let extractor = PasteboardExtractor(settings: fakeSettings)
    // ...
}

// ❌ BAD - tests with real UserDefaults
func testCapture() {
    UserDefaults.standard.set(true, forKey: "ignoreConfidentialContent")
    let extractor = PasteboardExtractor()
    // ...
}
```

**Integration Tests:**
- Use `ClipboardMacValidation` for stress/regression runs
- Test capture → paste → sync flows end-to-end
- Validate CloudKit sync with real container (manual testing)

---

## 4. Compliance & Quality

### 4.1 Code Review Checklist

Before submitting a PR, verify:

- [ ] No `print()` statements in production code
- [ ] No clipboard content in logs
- [ ] Settings providers used (not `@AppStorage` in services)
- [ ] Dependencies injected (not constructed inline)
- [ ] Tests added/updated for behavior changes
- [ ] `MARK:` sections added for navigation in files > 200 lines
- [ ] File size targets met (or extraction justified)
- [ ] No compiler warnings
- [ ] `swift build` and `swift test` pass

### 4.2 Security Framework Validation

**Secure SDLC Compliance:**
- Map changes to [NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final) (SP 800-218)
- Review threat model for paste injection surface
- Validate data protection for stored clipboard artifacts

**Categories:**
- **PO** (Prepare the Organization) — training, policy, tooling
- **PS** (Protect the Software) — secure repository, build, dependencies
- **PW** (Produce Well-Secured Software) — design, implementation, testing
- **RV** (Respond to Vulnerabilities) — detection, response, recovery

### 4.3 Operational Quality

**Logging in Production:**
- Avoid high-volume logs in normal usage
- Use `.debug` for noisy instrumentation
- Treat OS/system logs (entitlement warnings, XPC noise) as non-actionable unless correlated with failures

**Error Handling:**
- Validate at system boundaries (user input, external APIs)
- Trust internal code and framework guarantees
- Don't add error handling for scenarios that can't happen

**Backwards Compatibility:**
- Delete unused code completely (no `_unused` renames, no `// removed` comments)
- Prefer clean changes over backwards-compatibility hacks

---

## 5. Common Patterns

### 5.1 Settings Provider Pattern

**Use for:** UserDefaults access from services

```swift
// 1. Define protocol
protocol FeatureSettingsProviding {
    var settingName: Bool { get }
}

// 2. Implement with UserDefaults
struct UserDefaultsFeatureSettings: FeatureSettingsProviding {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var settingName: Bool {
        defaults.bool(forKey: "settingName")
    }
}

// 3. Inject in service
class FeatureService {
    private let settings: FeatureSettingsProviding
    init(settings: FeatureSettingsProviding = UserDefaultsFeatureSettings()) {
        self.settings = settings
    }
}

// 4. Test with fake
struct FakeFeatureSettings: FeatureSettingsProviding {
    var settingName: Bool
}
```

### 5.2 Coordinator Pattern

**Use for:** Orchestrating workflows (capture, hotkeys, onboarding)

```swift
@MainActor
final class FeatureCoordinator {
    private let serviceA: ServiceA
    private let serviceB: ServiceB

    init(serviceA: ServiceA, serviceB: ServiceB) {
        self.serviceA = serviceA
        self.serviceB = serviceB
    }

    func start() {
        // Wire services together
        serviceA.onEvent = { [weak self] event in
            self?.serviceB.handle(event)
        }
    }

    func stop() {
        // Cleanup
    }
}
```

### 5.3 Repository Pattern

**Use for:** Abstracting persistence (ClipItemRepository, PinboardRepository)

```swift
protocol ClipItemRepositoryProtocol {
    func create(payload: ClipItemPayload) throws -> ClipItem
    func fetch(objectID: NSManagedObjectID) throws -> ClipItem?
    func delete(objectID: NSManagedObjectID) throws
}

final class ClipItemRepository: ClipItemRepositoryProtocol {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    // CRUD operations
}

// Use thin façade if needed for legacy compatibility
final class ClipItemStore {
    private let repository: ClipItemRepositoryProtocol

    init(repository: ClipItemRepositoryProtocol = ClipItemRepository()) {
        self.repository = repository
    }

    func createItem(payload: ClipItemPayload) throws -> ClipItem {
        try repository.create(payload: payload)
    }
}
```

---

## 6. References

- **[CODEBASE.md](./CODEBASE.md)** — Architecture overview and navigation
- **[ARCHITECTURE-DECISIONS.md](./ARCHITECTURE-DECISIONS.md)** — ADRs explaining key decisions
- **[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)** — Secure Software Development Framework

---

## 7. Enforcement

These practices are enforced through:

1. **Code review** — checklist above applied to all PRs
2. **Static analysis** — grep for `print()`, risky logging patterns
3. **Build validation** — `swift build` and `swift test` must pass
4. **Performance testing** — critical flows measured against targets
5. **Security review** — SSDF validation for releases

**Violations:** Should be addressed in code review or follow-up PRs.

**Exceptions:** Require justification and approval from engineering owner.

---

**Last Updated:** 2026-02-03
**Maintained By:** Engineering Team
**Next Review:** 2026-06-01 (quarterly)
