# Architecture Overview
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.2.0
- **Last Updated:** 2026-01-16
- **Status:** Active
- **Owner:** Engineering Team
- **Related Specs:** All specifications depend on this document

---

## 1. Purpose and Scope

This document defines the high-level system architecture for the Paste Clipboard Manager application. It establishes the module structure, data flow patterns, and integration points that all other specifications must adhere to.

### 1.1 Architecture Goals

1. **Cross-platform core**: Maximize code sharing between macOS, iOS, and watchOS
2. **Sync-first design**: Build with iCloud synchronization as a foundational requirement
3. **Performance**: Sub-100ms UI response time for clipboard operations
4. **Reliability**: Zero data loss during sync conflicts or system crashes
5. **Privacy**: Local-first processing with explicit sync opt-in

---

## 2. System Architecture

### 2.1 Module Overview

```
┌─────────────────────────────────────────────────────────┐
│ Application Layer │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │
│ │ ClipboardMac │ │ ClipboardiOS │ │ClipboardWatch│ │
│ │ (macOS) │ │ (Future) │ │ (Future) │ │
│ └──────────────┘ └──────────────┘ └──────────────┘ │
└─────────────────────────────────────────────────────────┘
 │
┌─────────────────────────────────────────────────────────┐
│ ClipboardCore (Swift Package) │
│ ┌────────────────────────────────────────────────────┐ │
│ │ Data Model & Persistence │ │
│ ├────────────────────────────────────────────────────┤ │
│ │ Search & Indexing Engine │ │
│ ├────────────────────────────────────────────────────┤ │
│ │ Sync Coordinator (CloudKit) │ │
│ ├────────────────────────────────────────────────────┤ │
│ │ Business Rules (Dedupe, Retention, Privacy) │ │
│ ├────────────────────────────────────────────────────┤ │
│ │ Asset Management │ │
│ └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
 │
┌─────────────────────────────────────────────────────────┐
│ Platform Services │
│ • Core Data / SQLite │
│ • CloudKit │
│ • FileManager (Asset Storage) │
│ • NSPasteboard / UIPasteboard │
│ • Keychain Services │
└─────────────────────────────────────────────────────────┘
```

---

## 3. Core Modules

### 3.1 ClipboardCore (Swift Package)

**Responsibility:** Platform-agnostic business logic and data management

**Sub-modules:**

1. **DataModel**
 - Core Data entities and relationships
 - See: `Data-Model-Spec.md`

2. **PersistenceLayer**
 - Core Data stack management
 - Migration coordination
 - Transaction handling

3. **SyncEngine**
 - CloudKit integration
 - Conflict resolution
 - Change token management
 - See: `Cloud-Schema-Spec.md`

4. **BusinessRules**
 - Deduplication logic
 - Retention policy enforcement
 - Privacy filtering
 - Content classification

5. **SearchIndex**
 - Full-text search indexing
 - Query processing
 - Relevance ranking

6. **AssetManager**
 - File-based asset storage
 - Thumbnail generation
 - Cache management
 - Orphan cleanup

### 3.2 ClipboardMacServices (macOS Services Module)

**Responsibility:** macOS services shared by the app and validation tooling

**Components:**

1. **PasteboardMonitor**
 - NSPasteboard polling
 - Change detection
 - See: `macOS-Services-Spec.md`

2. **PasteboardExtractor**
 - Representation extraction (text/RTF/HTML/images/URLs)
 - Type detection
 - See: `macOS-Services-Spec.md`

3. **HotkeyManager**
 - Global hotkey registration (Carbon)
 - See: `macOS-Services-Spec.md`

4. **ThumbnailGenerator**
 - Image thumbnail generation for previews
 - See: `macOS-Services-Spec.md`

5. **Loggers**
 - App, pasteboard, hotkey, retention log channels

### 3.3 ClipboardMac (macOS App Target)

**Responsibility:** macOS-specific UI and system integration

**Components:**

1. **OverlayWindow**
 - Custom NSPanel management
 - Keyboard navigation
 - Focus handling
 - See: `UI-Contract-Spec.md`

2. **PasteEngine**
 - Active app tracking
 - Synthetic paste injection
 - Accessibility integration
 - See: `macOS-Services-Spec.md`

3. **SettingsUI**
 - SwiftUI-based preferences
 - Shortcut recorder
 - App picker for ignore list

4. **MenuBarApp**
 - NSStatusItem management
 - Quick actions menu
 - Status indicators

6. **HotkeyManager**
 - Global hotkey registration
 - Event monitoring
 - Action dispatch

### 3.3 Future: ClipboardiOS & ClipboardWatch

**ClipboardiOS:** Browse-and-copy interface for synced items
**ClipboardWatch:** Lightweight item viewer with handoff support

---

## 4. Data Flow

### 4.1 Capture Flow (macOS)

```
NSPasteboard Change
 
PasteboardMonitor detects (polling)
 
Extract available UTIs
 
Normalize to ClipItem candidate
 
Apply Privacy Filters
 
Compute canonical hash
 
Check for duplicates
 
Persist to Core Data
 
Store assets to filesystem
 
Update search index
 
Enqueue for sync (if enabled)
 
Notify UI observers
```

### 4.2 Paste Flow (macOS)

```
User selects item in overlay
 
Retrieve ClipItem and representations
 
Apply Plain Text mode (if active)
 
Write to NSPasteboard.general
 
[If paste-to-active-app mode:]
 
Re-activate recorded frontmost app
 
Send synthetic Command+V
 
Close overlay
 
Play sound effect (if enabled)
```

### 4.3 Sync Flow (Bidirectional)

```
Local change occurs
 
SyncCoordinator observes
 
Batch changes (debounce 2s)
 
[Outbound:]
Upload CKRecords + CKAssets
 
[Inbound:]
Fetch zone changes with token
 
Apply conflict resolution
 
Merge into local store
 
Download assets (on-demand or eager)
 
Update UI
```

---

## 5. Technology Stack

### 5.1 Languages and Frameworks

| Component | Technology | Justification |
|-----------|------------|---------------|
| Core Logic | Swift 5.9+ | Type safety, cross-platform |
| UI (macOS) | SwiftUI + AppKit | Modern UI with AppKit bridges for advanced features |
| Persistence | Core Data | CloudKit integration, mature tooling |
| Sync | CloudKit | Native Apple platform integration |
| Hotkeys | CGEvent / NSEvent | Required for global shortcuts |
| Search | NSPredicate + Custom indexing | Fast in-memory search with persistent index |

### 5.2 Third-Party Dependencies

**Goal:** Minimize external dependencies

**Acceptable:**
- None required for MVP

**Under Consideration:**
- KeyboardShortcuts (MIT) for hotkey recording UI
- Sparkle (MIT) for non-MAS distribution updates

---

## 6. Phase Roadmap

### Phase 1: Core Foundation Spec Complete
**Target:** Weeks 1-3 
**Deliverables:**
- [x] `ClipboardCore` Swift package structure
- [x] Core Data model implementation (see Data-Model-Spec.md)
- [x] Basic persistence layer with SQLite backend
- [x] Text-only pasteboard monitor
- [x] Minimal SwiftUI overlay listing recent items
- [x] Canonical hash implementation
- [x] Basic retention policy (day/week/month)

**Success Criteria:**
- Can capture and display text from pasteboard
- Items persist across app restarts
- Duplicate detection works for identical text

**Status Notes:**
- Pasteboard latency and idle CPU validated (avg 0.382s, max 0.403s; CPU 0.22%)
- Persistence across restarts validated via XCTest
- DB insert/fetch and UI overlay performance still unvalidated

---

### Phase 2: Full Capture & UI Parity Implemented
**Target:** Weeks 4-6 
**Deliverables:**
- [x] Rich text (RTF, HTML) capture
- [x] Image capture with thumbnail generation
- [x] File URL capture
- [x] Multi-representation support per item
- [x] Pinboard data model and UI
- [x] Pinboard tab bar component
- [x] Item card component with previews
- [x] Search mode UI and indexing
- [x] Menu bar icon and menu

**Success Criteria:**
- All content types display correctly
- Pinboards can be created/renamed/deleted
- Search returns relevant results in <100ms
- UI matches design reference

**Dependencies:**
- Phase 1 complete
- UI-Contract-Spec.md finalized

**Status Notes:**
- Search validation: avg 1.0ms, max 1.4ms for 1000-item dataset (ClipboardMacValidation run)
- Capture throughput validation: 1103.5 items/sec (ClipboardMacValidation run)
- UI frame lifetime avg 16.81ms (p99 26.75ms), 1 hitch at 133.33ms (Animation Hitches trace)

---

### Phase 3: Paste Behaviors - COMPLETE
**Target:** Weeks 7-8 
**Status:** Implementation complete; manual validation tracked outside phases

**Deliverables:**
- [x] Frontmost app tracking (`ActiveAppTracker`)
- [x] Accessibility-based paste injection (`PasteEngine` with CGEvent)
- [x] Plain text mode with modifier key (`ClipItem.plainTextContent`, Shift detection)
- [x] Quick Paste (Cmd+1-9) mapping (`HotkeyDefinitions.quickPaste()`)
- [x] Paste Stack data model (Core Data: `StackSession`, `StackEntry`)
- [x] Paste Stack sequential paste logic (`PasteEngine.pasteStack()`)
- [x] System sound integration (`SoundEffectPlayer`)
- [x] Modifier key monitoring (`ModifierKeyMonitor`)
- [x] Copy action available via context menu (text-only)
- [x] Drag-out-to-paste behavior
- [x] Accessibility permission handling (alert + System Settings link)

**Implementation Details:**
- **Paste Engine:** `ClipboardMac/Sources/ClipboardMacServices/Services/PasteEngine/`
  - Active app tracking with fallback to last external app
  - Retry logic for target activation (configurable attempts/timeout)
  - Plain text conversion via `ClipItem.plainTextContent` (RTF/HTML → string)
- **Hotkey Manager:** `ClipboardMac/Sources/ClipboardMacServices/Services/HotkeyManager/`
  - Event tap-based system (replaces Carbon)
  - Auto-recovery on tap disabled
  - Default bindings: Cmd+Shift+V (overlay), Cmd+Shift+C (stack), Cmd+1-9 (quick paste)
- **Paste Stack:** `ClipboardCore/Sources/BusinessRules/StackSessionStore.swift`
  - Sequential and combined modes with separator
  - Debounced selection sync (20ms)
  - Multi-select with Shift/Cmd modifiers
- **Sound Effects:** `ClipboardMac/Sources/ClipboardMacServices/Services/SoundEffects/`
  - Preloaded sounds: "Pop" (capture), "Submarine" (paste), "Glass" (delete)

**Success Criteria:**
- Paste-to-active-app implementation complete
- Plain text conversion tested (RTF/HTML → string)
- Paste Stack handles 20+ items
- Note: Manual validation (paste success in 10+ apps, hotkey reliability after sleep/wake, Quick Paste latency <50ms) lives in `docs/VALIDATION.md`

**Dependencies:**
- Phase 2 complete
- macOS-Services-Spec.md finalized

**Status Notes:**
- All automated tests passing (68 tests: 32 ClipboardCore + 36 ClipboardMac)
- Accessibility prompt handled in overlay; onboarding deferred to Phase 4
- Event tap hotkey manager provides better reliability than Carbon
- Manual validation tasks tracked outside phases

---

### Phase 4: Privacy & Settings - COMPLETE
**Target:** Weeks 9-10
**Status:** Implementation complete; all deliverables implemented

**Deliverables:**
- [x] Settings window with 3 tabs (General/Privacy/Shortcuts)
- [x] Purchase / licensing UI tracked as a later phase
- [x] Ignore apps list with picker
- [x] Confidential content classifier
- [x] Transient content detection
- [x] Link preview fetching with LPMetadataProvider
- [x] Screen sharing detection
- [x] Open-at-login integration (SMAppService)
- [x] Sound effects toggle in settings
- [x] Onboarding flow (4 screens)
- [x] Hotkey preferences with customization UI

**Implementation Details:**

**Settings Window:** `ClipboardMac/Sources/ClipboardMacApp/UI/Settings/`
- **GeneralTab.swift:** Open at login (SMAppService), paste behavior toggle, plain text mode, sound effects, retention policy (day/week/month/year/forever), erase history with confirmation
- **PrivacyTab.swift:** Screen sharing visibility, link preview toggle, confidential content toggle, transient content toggle, ignored apps list with add/remove UI
- **ShortcutsTab.swift:** Global hotkey customization with HotkeyRecorder, reset to defaults, Quick Paste info (Cmd+1-9), modifier key info
- **HotkeyRecorder.swift:** Interactive shortcut recording component
- **IgnoredAppsViewModel.swift:** Manages ignored apps with file picker integration

**Privacy Features:** `ClipboardCore/Sources/BusinessRules/`
- **IgnoredAppsManager.swift:** Persistent storage in UserDefaults, default password managers (Keychain Access, 1Password, LastPass, Dashlane, Bitwarden), add/remove functionality
- **Classifiers/ConfidentialContentClassifier.swift:** Detects passwords (entropy-based 8-64 chars), OTP codes (6-8 digits), credit cards (Luhn validation), API keys (JWT, GitHub ghp_/gho_/ghs_, AWS AKIA*), private keys (RSA/OpenSSH/EC/DSA/PGP), SSN
- **Classifiers/TransientContentClassifier.swift:** Filters promised file URLs, very small content (<10 bytes), dynamic UTI types
- **LinkPreviewFetcher.swift:** Uses LinkPresentation framework, async preview fetching with title/site/summary/image/icon, HTTP/HTTPS validation, AppStorage preference control

**Onboarding Flow:** `ClipboardMac/Sources/ClipboardMacApp/UI/Onboarding/`
- **OnboardingFlow.swift:** Main flow controller with hasCompletedOnboarding tracking
- **OnboardingScreens.swift:** 4 screens (Welcome, Permissions with live status check, How to Use with keyboard tutorial, Complete)
- Permission screen includes live monitoring (1s interval), "Open System Settings" deep link, skip option, green checkmark when granted

**System Integration:**
- **ScreenSharingManager.swift:** `ClipboardMac/Sources/ClipboardMacServices/Services/ScreenSharing/`
  - ObservableObject with published state, menu bar toggle (Cmd+Shift+P), shouldShowOverlay computed property
- **HotkeyPreferences.swift:** `ClipboardMac/Sources/ClipboardMacApp/App/`
  - HotkeyPreference struct (key code + modifiers), HotkeyPreferencesStore with UserDefaults persistence
  - Default hotkeys: Cmd+Shift+V (overlay), Cmd+Shift+C (paste stack)
  - Dynamic reload in AppDelegate when preferences change
- **SoundEffectPlayer.swift:** Already in `ClipboardMac/Sources/ClipboardMacServices/Services/SoundEffects/`
  - Three preloaded NSSound instances: "Pop" (capture), "Submarine" (paste), "Glass" (delete)
  - Linked to soundEffectsEnabled AppStorage key

**Integration Points:**
- PasteboardMonitor checks IgnoredAppsManager before capture (lines 109-113)
- PasteboardExtractor applies ConfidentialContentClassifier and TransientContentClassifier (lines 149-159)
- AppDelegate schedules link preview fetching in background (lines 198-239)
- OverlayViewModel uses pasteToActiveApp setting (lines 155, 187)
- MenuBarController provides screen sharing toggle (lines 63-78, 96-98)

**Success Criteria:**
- [x] Ignored apps are not captured (tested in IgnoredAppsManagerTests)
- [x] Passwords/tokens are filtered when enabled (tested in ConfidentialContentClassifierTests with 13 test cases)
- [x] Link previews fetch metadata and images (tested in LinkPreviewStoreTests)
- [x] Settings persist correctly (tested in HotkeyPreferencesTests)

**Tests:** 28 automated tests
- IgnoredAppsManagerTests.swift: 6 tests (add, remove, persistence, defaults)
- ConfidentialContentClassifierTests.swift: 13 tests (passwords, OTP, credit cards, API keys, private keys, SSN, edge cases)
- TransientContentClassifierTests.swift: 4 tests (promised files, small content, dynamic UTIs)
- LinkPreviewStoreTests.swift: 6 tests (preview persistence, failures, pending targets, cleanup)
- HotkeyPreferencesTests.swift: 5 tests (save/load, defaults, reset, display strings)

**Dependencies:**
- Phase 3 complete ✅
- Privacy-Security-Spec.md finalized ✅

**Status Notes:**
- All 28 Phase 4 tests passing
- UI components fully implemented with SwiftUI + AppKit integration
- Privacy filters integrated into capture pipeline
- Settings persist via AppStorage and UserDefaults
- Onboarding triggered automatically on first launch

---

### Phase 5: CloudKit Sync Spec Pending
**Target:** Weeks 11-14 
**Deliverables:**
- [ ] CloudKit container and custom zone setup
- [ ] Cloud schema deployment (CKClipItem, CKClipRepresentation, CKPinboard, etc.)
- [ ] SyncCoordinator implementation
- [ ] Outbound change tracking and upload
- [ ] Inbound change fetch with tokens
- [ ] Conflict resolution (last-writer-wins for mutable, append-only for clips)
- [ ] Asset upload/download with CKAsset
- [ ] Deletion propagation
- [ ] Sync status UI ("Synced now" indicator)
- [ ] Sync toggle in settings

**Success Criteria:**
- Items sync across two Macs within 10s
- Assets download on-demand without UI blocking
- Conflicts resolve deterministically
- No data loss during network interruptions

**Dependencies:**
- Phase 4 complete
- Cloud-Schema-Spec.md finalized
- CloudKit entitlements configured

---

### Phase 6: Hardening & Performance - IN PROGRESS
**Target:** Weeks 15-16 
**Status:** Implementation in progress

**Deliverables:**
- [ ] Performance profiling (Instruments)
  - [ ] Create PerformanceTests.swift for database benchmarks
  - [ ] Create UIPerformanceTests.swift for render benchmarks
  - [ ] Create CapturePerformanceTests.swift for pipeline benchmarks
- [ ] Database indexing optimization
  - [ ] Add composite index on createdAt + itemType
  - [ ] Add index on searchableText
  - [ ] Benchmark with 10,000 items
- [ ] Memory usage audit (<50MB idle)
  - [ ] Profile with Instruments Allocations
  - [ ] Implement image cache size limits
  - [ ] Add memory pressure handling
- [ ] Database migration strategy
  - [ ] Enable automatic lightweight migration
  - [ ] Create versioned .xcdatamodeld bundles
  - [ ] Write migration tests
- [ ] Crash reporting integration
  - [ ] Enable symbolication for release builds
  - [ ] Add structured OSLog logging
  - [ ] Implement startup data integrity checks
- [ ] Automated UI tests
  - [ ] Set up ClipboardMacUITests target
  - [ ] Add accessibility identifiers to all elements
  - [ ] Write critical path UI tests
- [ ] CloudKit production migration
  - [ ] Create production container
  - [ ] Deploy schema to production
  - [ ] Update CloudKitConfiguration for environment switching
- [ ] Accessibility audit
  - [ ] VoiceOver testing
  - [ ] Keyboard navigation verification
  - [ ] Accessibility label review

**Performance Budgets:**
| Operation | Target | Maximum |
|-----------|--------|---------|
| App launch | <1s | 2s |
| Overlay open | <200ms | 500ms |
| Capture latency | <50ms | 100ms |
| Search (1K items) | <100ms | 250ms |
| Item card render | <16ms | 33ms |
| Thumbnail generation | <500ms | 2s |
| Database query (10K items) | <500ms | 1s |
| Memory (idle) | <50MB | 100MB |

**Success Criteria:**
- 10,000 items load in <500ms
- Zero crashes in 7-day stress test
- 80% code coverage achieved
- VoiceOver accessibility verified

**Dependencies:**
- Phase 5 complete ✅
- Testing-Strategy.md finalized ✅

**Current Test Coverage:** 254 automated tests (180 ClipboardCore + 74 ClipboardMac)

---

### Phase 7: Beta Testing & Polish
**Target:** Weeks 17-18
**Status:** Not started

**Deliverables:**
- [ ] Internal beta deployment (5-10 users, 2 weeks)
- [ ] TestFlight external beta (20-50 users)
- [ ] Feedback collection mechanism
- [ ] Bug triage and fixes
- [ ] UI polish based on feedback

**Focus Areas:**
- Pinboard tab bar scroll mask refinement
- Item card hover state improvements
- Search field clear button visibility
- Settings tab alignment
- Multi-monitor overlay positioning
- Known bug fixes (race conditions, error propagation)

**Success Criteria:**
- 2 weeks internal usage without critical bugs
- Beta tester satisfaction >80%
- All P0/P1 bugs fixed

---

### Phase 8: App Store Preparation
**Target:** Weeks 19-20
**Status:** Not started

**Deliverables:**
- [ ] App icon (1024×1024 + all sizes)
- [ ] Menu bar icon (16×16 template)
- [ ] App Store screenshots (4 sizes, 5 scenarios)
- [ ] App preview video (optional, 15-30s)
- [ ] Privacy policy (hosted on website)
- [ ] App Store metadata and description
- [ ] App Store privacy labels configured
- [ ] Sandbox entitlements reviewed
- [ ] App review submission

**Success Criteria:**
- All required assets completed
- Privacy policy published
- App approved by Apple

---

### Phase 9: Launch & Post-Launch
**Target:** Week 21+
**Status:** Not started

**Deliverables:**
- [ ] App Store release scheduled
- [ ] Marketing website live
- [ ] Support email configured
- [ ] Social media announcements
- [ ] Post-launch monitoring setup
- [ ] v1.0.1 reserved for critical fixes

**Post-Launch Metrics:**
| Metric | Target |
|--------|--------|
| Crash-free rate | >99.5% |
| User ratings | >4.5 stars |
| 1-day retention | >50% |
| Support tickets | <10/week |

---

### Future Phases (Post-Launch)

**Phase 10: iOS Companion App**
- Browse synced clipboard on iPhone/iPad
- Read-only access to clipboard history
- Copy items to iOS clipboard
- Handoff support with Mac app

**Phase 11: Advanced Features**
- Snippets (user-created reusable text)
- Smart folders (auto-organized by rules)
- Third-party integrations (Alfred, Raycast)
- Export/import functionality
- Spotlight integration

**Phase 12: Apple Watch App**
- View recent clipboard items
- Dictation for quick text snippets
- Handoff to Mac for paste action

---

## 7. Cross-Cutting Concerns

### 7.1 Error Handling

**Strategy:**
1. **User-facing errors:** Show alerts with actionable messages
2. **Recoverable errors:** Log and retry with exponential backoff
3. **Critical errors:** Preserve data, log to file, prompt user to report

**Error Categories:**
- Pasteboard read failures Skip, log, continue
- Core Data save failures Rollback, alert user
- CloudKit errors Queue for retry, show sync status
- Accessibility permission denied Show onboarding again

### 7.2 Performance Budgets

| Operation | Target | Maximum |
|-----------|--------|---------|
| Pasteboard capture | <50ms | 100ms |
| Item card render | <16ms (60fps) | 33ms |
| Search query | <100ms | 250ms |
| Overlay open | <200ms | 500ms |
| Sync push (batch) | <2s | 5s |
| Thumbnail generation | <500ms | 2s |

### 7.3 Logging and Telemetry

**Principles:**
- No user data in logs
- Local-only logs (no remote telemetry for privacy)
- Structured logging with OSLog
- Log levels: Debug, Info, Error

**Critical Events to Log:**
- Capture events (count, type, but not content)
- Sync operations (success/failure, record count)
- Errors with stack traces
- Performance metrics (timing, memory)

### 7.4 Security Considerations

See: `Privacy-Security-Spec.md`

**Key Requirements:**
- App Sandbox enabled
- Keychain for sensitive settings
- FileVault-aware asset storage
- No plaintext secrets in code

---

## 8. Development Environment

### 8.1 Requirements

- **Xcode:** 15.0+
- **macOS:** 14.0+ (Sonoma) for development
- **Deployment Target:** macOS 13.0+ (Ventura)
- **Swift:** 5.9+
- **Build System:** Xcode Build System (not legacy)

### 8.2 Project Structure

```
Paste/
├── Paste.xcworkspace
├── ClipboardCore/ # Swift Package
│ ├── Sources/
│ │ ├── DataModel/
│ │ ├── Persistence/
│ │ ├── Sync/
│ │ ├── BusinessRules/
│ │ ├── Search/
│ │ └── Assets/
│ └── Tests/
├── ClipboardMac/ # macOS App Target
│ ├── Sources/
│ │ ├── ClipboardMacApp/
│ │ │ ├── App/
│ │ │ └── UI/
│ │ │ ├── Overlay/
│ │ │ ├── Settings/
│ │ │ └── Components/
│ │ ├── ClipboardMacServices/
│ │ │ └── Services/
│ │ │ ├── Logging/
│ │ │ ├── PasteboardMonitor/
│ │ │ ├── Thumbnails/
│ │ │ └── HotkeyManager/
│ │ └── ClipboardMacValidation/
│ │ └── Resources/
│ └── Tests/
├── ClipboardiOS/ # Future
├── ClipboardWatch/ # Future
└── docs/
 ├── specs/ # Engineering specs (this file)
 ├── api/ # API documentation
 └── decisions/ # Architecture decision records
```

### 8.3 Build Configurations

- **Debug:** Local development, verbose logging
- **Beta:** TestFlight distribution, crash reporting enabled
- **Release:** App Store distribution, minimal logging

---

## 9. Dependencies Between Specifications

```
Architecture-Overview.md (this file)
 ├── Data-Model-Spec.md
 │ └── Required by: All phases
 ├── Cloud-Schema-Spec.md
 │ └── Required by: Phase 5
 ├── UI-Contract-Spec.md
 │ └── Required by: Phase 2, 3, 4
 ├── macOS-Services-Spec.md
 │ └── Required by: Phase 1, 3
 ├── Privacy-Security-Spec.md
 │ └── Required by: Phase 4
 └── Testing-Strategy.md
 └── Required by: Phase 6
```

---

## 10. Open Questions and Risks

### 10.1 High-Priority Decisions Needed

1. **Core Data vs Custom SQLite?**
 - **Recommendation:** Core Data for CloudKit integration
 - **Risk:** Learning curve for team, migration complexity

2. **Asset Storage Strategy?**
 - **Recommendation:** Filesystem with Core Data references
 - **Risk:** Orphan management, backup/restore

3. **Search Technology?**
 - **Recommendation:** Core Data + in-memory index
 - **Alternative:** Core Spotlight integration
 - **Risk:** Performance with 10k+ items

### 10.2 Known Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Accessibility permission denial | High | Fallback to copy-only mode, clear onboarding |
| CloudKit quota limits | Medium | Implement asset size caps, lazy download |
| Pasteboard source app attribution unreliable | Low | Document limitation, best-effort approach |
| Large image capture memory usage | Medium | Stream processing, background threads |

---

## 11. Versioning and Changelog

### Version 1.0.0 (2026-01-09)
- Initial architecture document
- Defined 6-phase implementation plan
- Established module structure and data flows
- Identified key technology choices

---

## 12. Approval and Sign-off

| Role | Name | Date | Status |
|------|------|------|--------|
| Tech Lead | TBD | - | Pending |
| Product Owner | TBD | - | Pending |
| Security Review | TBD | - | Pending |

---

**Next Steps:**
1. Review Phase 1 implementation notes and validation gaps
2. Plan Phase 2 scope/timeline
3. Set up Xcode workspace/project structure (optional; SwiftPM packages exist)
4. Begin Phase 2 implementation

**Related Documents:**
- [Data Model Spec](./Data-Model-Spec.md) - Complete
- [Cloud Schema Spec](./Cloud-Schema-Spec.md) - Complete
- [UI Contract Spec](./UI-Contract-Spec.md) - Complete
- [macOS Services Spec](./macOS-Services-Spec.md) - Complete
- [Privacy & Security Spec](./Privacy-Security-Spec.md) - Complete
- [Testing Strategy](./Testing-Strategy.md) - Complete
