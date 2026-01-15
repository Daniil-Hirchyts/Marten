# Architecture Overview
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.1.0
- **Last Updated:** 2026-01-14
- **Status:** Draft
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

### Phase 3: Paste Behaviors Implemented
**Target:** Weeks 7-8 
**Deliverables:**
- [x] Frontmost app tracking
- [x] Accessibility-based paste injection
- [x] Plain text mode with modifier key
- [x] Quick Paste (Cmd+1-9) mapping
- [x] Paste Stack data model
- [x] Paste Stack sequential paste logic
- [x] System sound integration
- [x] Modifier key monitoring
- [ ] Copy-to-clipboard mode (alternative to paste)

**Success Criteria:**
- Paste-to-active-app works in 10 test applications
- Plain text conversion strips formatting correctly
- Quick Paste responds within 50ms
- Paste Stack handles 20+ items

**Dependencies:**
- Phase 2 complete
- macOS-Services-Spec.md finalized

**Status Notes:**
- Accessibility prompt now handled in overlay/quick paste; onboarding still Phase 4
- Event tap hotkey manager replaces Carbon registration
- Unvalidated: paste success rate in 10+ apps, hotkey reliability after sleep, Quick Paste latency

---

### Phase 4: Privacy & Settings Spec Pending
**Target:** Weeks 9-10 
**Deliverables:**
- [ ] Settings window with 4 tabs (General/Privacy/Shortcuts/Purchase)
- [ ] Ignore apps list with picker
- [ ] Confidential content classifier
- [ ] Transient content detection
- [ ] Link preview fetching with LPMetadataProvider
- [ ] Screen sharing detection
- [ ] Open-at-login integration (SMAppService)
- [ ] Sound effects with toggle

**Success Criteria:**
- Ignored apps are not captured
- Passwords/tokens are filtered when enabled
- Link previews display within 3s
- Settings persist correctly

**Dependencies:**
- Phase 3 complete
- Privacy-Security-Spec.md finalized

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

### Phase 6: Hardening & Performance Spec Pending
**Target:** Weeks 15-16 
**Deliverables:**
- [ ] Performance profiling (Instruments)
- [ ] Database indexing optimization
- [ ] Memory usage audit (<50MB idle)
- [ ] Asset cache size limits
- [ ] Database migration strategy
- [ ] Crash reporting integration
- [ ] Data integrity checks on startup
- [ ] Automated UI tests
- [ ] CloudKit development production migration

**Success Criteria:**
- 10,000 items load in <500ms
- Zero crashes in 7-day stress test
- Migration from v1.0 to v1.1 succeeds 100%

**Dependencies:**
- Phase 5 complete
- Testing-Strategy.md finalized

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
