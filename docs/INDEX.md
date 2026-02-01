# Paste Clipboard Manager - Documentation Index

**Project:** Paste - Clipboard Manager for macOS 
**Version:** 1.3.0 
**Last Updated:** 2026-01-16

---

## Documentation Structure

```
docs/
├── INDEX.md You are here
└── specs/ Engineering specifications
 ├── README.md Specs overview and navigation guide
 ├── Architecture-Overview.md
 ├── Data-Model-Spec.md
 ├── Cloud-Schema-Spec.md
 ├── UI-Contract-Spec.md
 ├── macOS-Services-Spec.md
 ├── Privacy-Security-Spec.md
 └── Testing-Strategy.md
```

---

## Quick Start

### I'm a Developer
**Start here:** [`specs/Architecture-Overview.md`](./specs/Architecture-Overview.md)
- Understand system architecture
- Learn module structure
- Review phase roadmap
- Then dive into specific specs based on your work

### I'm a Product Manager
**Start here:** [`specs/UI-Contract-Spec.md`](./specs/UI-Contract-Spec.md)
- Complete UI specification
- Visual design system
- Component definitions
- Interaction patterns
- Accessibility requirements

### I'm a Designer
**Start here:** [`specs/UI-Contract-Spec.md`](./specs/UI-Contract-Spec.md)
- Complete UI specification
- Visual design system
- Component definitions
- Interaction patterns
- Accessibility requirements

### I'm a QA Engineer
**Start here:** [`specs/Testing-Strategy.md`](./specs/Testing-Strategy.md)
- Testing approach
- Test scenarios
- Manual testing checklists
- Performance metrics

### I'm a Security Reviewer
**Start here:** [`specs/Privacy-Security-Spec.md`](./specs/Privacy-Security-Spec.md)
- Privacy controls
- Security measures
- Data protection
- Compliance considerations

---

## Document Descriptions

### Engineering Specifications
**[specs/README.md](./specs/README.md)**
- Overview of all engineering specs
- Dependency diagram
- Implementation roadmap
- How to use the specs

**[specs/Architecture-Overview.md](./specs/Architecture-Overview.md)**
- System architecture
- Module structure and responsibilities
- Data flow diagrams
- Technology choices
- Phase-by-phase roadmap
- Cross-cutting concerns

**[specs/Data-Model-Spec.md](./specs/Data-Model-Spec.md)**
- Core Data entities (7 entities defined)
- Relationships and cascade rules
- Indexes and performance optimization
- Retention policies
- Asset management strategy
- Search implementation

**[specs/Cloud-Schema-Spec.md](./specs/Cloud-Schema-Spec.md)**
- CloudKit record types
- Sync engine architecture
- Conflict resolution policies
- Asset upload/download
- Deletion propagation
- Error handling and quotas

**[specs/UI-Contract-Spec.md](./specs/UI-Contract-Spec.md)**
- Complete UI specification
- Overlay window behavior
- All UI components (pinboards, cards, search)
- Settings window (4 tabs)
- Onboarding flow
- Design system (typography, colors, spacing)
- Accessibility requirements

**[specs/macOS-Services-Spec.md](./specs/macOS-Services-Spec.md)**
- Pasteboard monitoring (polling strategy)
- Capture pipeline
- Pasting engine (synthetic events)
- Hotkey management
- Login item integration
- Permission handling

**[specs/Privacy-Security-Spec.md](./specs/Privacy-Security-Spec.md)**
- Ignored applications
- Confidential content detection (passwords, OTP, credit cards, API keys)
- Transient content filtering
- Link preview privacy
- Screen sharing mode
- Data encryption
- Compliance (GDPR, CCPA)

**[specs/Testing-Strategy.md](./specs/Testing-Strategy.md)**
- Test pyramid (unit, integration, UI tests)
- Performance testing
- CloudKit sync testing
- Platform compatibility
- Manual testing protocols
- CI/CD setup

**[VALIDATION.md](./VALIDATION.md)**
- Release smoke test checklist
- Paste behaviors manual validation (target app matrix + scenarios)

---

## Implementation Phases

### Phase 1: Core Foundation (Weeks 1-3)
**Goal:** Basic clipboard capture and storage

**Key Specs:**
- Architecture Overview
- Data Model Spec

**Deliverables:**
- ClipboardCore Swift package
- Core Data model with text-only capture
- Basic overlay UI

**Phase 1 Status (Current Progress)**
- ClipboardCore package with Core Data model, persistence, hashing/dedupe, retention, and CRUD
- ClipboardMac app package with pasteboard polling, global hotkey, and minimal overlay list
- Unit tests for hashing, deduplication, retention, and ClipItem insertions
- Feedback-loop suppression validated
- Persistence across restarts validated

---

### Phase 2: Full Capture & UI Parity (Weeks 4-6)
**Goal:** All content types and complete UI

**Key Specs:**
- UI Contract Spec
- macOS Services Spec

**Deliverables:**
- Rich text, images, files support
- Pinboards with tab bar
- Search functionality
- Menu bar app

**Phase 2 Status (Current Progress)**
- Phase 2 implementation complete; UI rendering perf benchmarked
- All content types (Text, Rich Text, Image, File, URL, Code) supported
- Pinboard system fully implemented
- Search with highlighting and scoping
- Thumbnail generation pipeline active

---

### Phase 3: Paste Behaviors (Weeks 7-8) - COMPLETE
**Goal:** Pasting, shortcuts, paste stack

**Key Specs:**
- macOS Services Spec (pasting)
- UI Contract Spec (paste stack UI)

**Deliverables:**
- Paste-to-active-app
- Global hotkeys
- Quick Paste (1-9)
- Paste stack

**Phase 3 Status: COMPLETE**
- Paste engine with ActiveAppTracker, CGEvent paste injection, and plain-text conversion
- Paste stack Core Data model + selection UI + sequential paste workflow
- Event tap hotkey manager with default hotkeys + Quick Paste (1-9)
- Accessibility prompt surfaced from overlay + quick paste fallback
- Paste stack UI: multi-select, footer actions, quick-paste badges, plain-text indicator
- Sound effects wired for paste actions
- Drag-out-to-paste behavior implemented
- Context menu "Copy" action (text-only)
- Unit tests for plain text conversion (RTF/HTML → string)
- All automated tests passing (68 tests: 32 ClipboardCore + 36 ClipboardMac)
- Note: Manual validation lives in VALIDATION.md (outside implementation phases)

---

### Phase 4: Privacy & Settings (Weeks 9-10) - COMPLETE
**Goal:** Privacy features and settings

**Key Specs:**
- Privacy & Security Spec
- UI Contract Spec (settings)

**Deliverables:**
- Ignored apps
- Confidential content filtering
- Link previews
- Complete settings window
- Onboarding
- Sound effects toggle
- Copy mode toggle (optional)

**Phase 4 Status: COMPLETE**
- **Ignored Apps:** IgnoredAppsManager with persistent storage, default password managers, integration in PasteboardMonitor
- **Confidential Content Detection:** ConfidentialContentClassifier detecting passwords (entropy-based), OTP codes, credit cards (Luhn), API keys (JWT, GitHub, AWS), private keys, SSN
- **Transient Content Filtering:** TransientContentClassifier filtering promised files, small content, dynamic UTIs
- **Link Previews:** LinkPreviewFetcher using LinkPresentation framework, async fetching with user preference control
- **Settings Window:** Complete 3-tab settings (General/Privacy/Shortcuts) with all required toggles and preferences
  - General: Open at login, paste behavior, plain text mode, sound effects, retention policy, erase history
  - Privacy: Screen sharing visibility, link preview toggle, confidential content toggle, transient content toggle, ignored apps list with add/remove
  - Shortcuts: Global hotkey customization with recorder UI, reset to defaults, Quick Paste info
- **Onboarding Flow:** 4-screen onboarding (Welcome, Permissions, How to Use, Complete) with live permission monitoring
- **Sound Effects:** SoundEffectPlayer with 3 sounds (capture/paste/delete), toggle in General settings
- **Copy Mode Toggle:** "Paste to active app" vs "To clipboard" setting integrated throughout paste flow
- **Screen Sharing Mode:** ScreenSharingManager with menu bar toggle (Cmd+Shift+P) and privacy setting
- **Hotkey Preferences:** HotkeyPreferencesStore with persistent storage, customizable shortcuts, reset to defaults
- **Tests:** 28 tests covering ignored apps (6), confidential content (13), transient content (4), link previews (6), hotkey preferences (5)
- All automated tests passing

---

### Phase 5: CloudKit Sync (Weeks 11-14) - COMPLETE
**Goal:** iCloud synchronization

**Key Specs:**
- Cloud Schema Spec

**Deliverables:**
- CloudKit schema
- Sync engine (bi-directional)
- Conflict resolution
- Sync status UI

**Phase 5 Status: COMPLETE**

**CloudKit Infrastructure:**
CloudKitManager handles all CloudKit container operations including initialization, custom zone creation in the private database, and zone subscription setup for remote change notifications. The manager monitors iCloud account status and provides appropriate error handling for account-related issues. SyncTokenManager persists CKServerChangeToken objects to track sync state, enabling incremental sync by fetching only changes since the last successful sync. Tokens are cached in memory and persisted to UserDefaults with per-zone granularity. CloudKitConfiguration centralizes all sync settings including container identifier, zone name, timing parameters, and debug logging flags.

**Cloud Record Mapping:**
CloudRecordMapper provides bidirectional conversion between Core Data entities and CloudKit records. It maps ClipItem, ClipRepresentation, Pinboard, PinboardMembership, and LinkPreview entities to their corresponding CKRecord types (CKClipItem, CKClipRepresentation, CKPinboard, CKPinboardMembership, CKLinkPreview). The mapper handles all field transformations including UUID encoding, date formatting, enum value conversion, and parent reference setup for cascade deletes. CKRecordExtensions provides type-safe field accessors and validation methods to ensure data integrity during sync operations.

**Outbound Sync (Local to Cloud):**
OutboundSyncEngine observes Core Data save notifications to detect local changes. When changes occur, inserted, updated, and deleted objects are queued for upload. A configurable debounce interval (default 2 seconds) batches rapid changes to minimize network requests. Records are uploaded in batches of up to 400 (CloudKit limit). The engine implements retry logic with exponential backoff for transient failures and delegates conflict resolution to OutboundConflictResolving. Upload status is tracked per-record and exposed for UI feedback.

**Inbound Sync (Cloud to Local):**
InboundSyncEngine fetches zone changes from CloudKit using CKServerChangeToken for incremental fetching. Changed records are processed in batches and merged into the local Core Data store. When a token expires (indicating server-side data loss), the engine automatically clears the token and performs a full re-sync. Deletions from other devices propagate to the local database with proper cascade handling for related entities.

**Conflict Resolution:**
ConflictResolver implements deterministic conflict policies based on entity type. Mutable entities like Pinboard use last-writer-wins based on modifiedAt timestamps. ClipItem uses an append-only policy where older records take precedence (based on createdAt). When timestamps match, record names provide a tiebreaker. The deleted-wins policy ensures that deletions propagate correctly across devices.

**Asset Synchronization:**
AssetSyncManager handles CKAsset upload and download for large binary content (images, files). Assets are validated against configurable size limits (per-asset and total session budget). The manager uses content-based hashing for deduplication to avoid redundant uploads. Download operations include retry logic with exponential backoff and progress tracking via Combine publishers. Orphaned assets (no longer referenced by any record) are cleaned up according to the retention policy.

**Sync Coordination:**
SyncCoordinator is an ObservableObject that orchestrates all sync components. It manages the sync lifecycle including starting sync when enabled, stopping when disabled, and handling app foreground/background transitions. The coordinator triggers outbound sync after local changes and runs periodic inbound sync every 30 seconds when the app is active. Push notifications trigger immediate inbound sync. Manual sync is supported via triggerSyncNow(). Sync status (idle, syncing, synced, error), progress, and last sync timestamp are published for UI binding.

**User Interface:**
SyncStatusIndicator is a SwiftUI component that displays the current sync status with an appropriate icon, status text, and detail information. The icon animates during active sync. Error states show descriptive messages and indicate when user action is required (e.g., not signed into iCloud). GeneralTab in Settings includes an iCloud Sync section with a toggle to enable/disable sync, account status display, the SyncStatusIndicator, and a Sync Now button for manual sync.

**Error Handling:**
CloudKitSyncError provides comprehensive error cases covering all sync failure scenarios: account issues (notSignedIn, accountRestricted), network problems (networkUnavailable), storage limits (quotaExceeded), zone issues (zoneNotFound, userDeletedZone), and operation failures (recordConflict, partialFailure). Each error includes localized descriptions, retry eligibility, and whether user action is required. CloudKitErrorClassifier converts raw CKError codes to domain-specific errors and determines retry delays.

**Test Coverage:** 133 automated tests across 9 test files covering infrastructure, record mapping, sync engines, conflict resolution, asset management, coordination, and UI components

---

### Phase 6: Hardening & Performance (Weeks 15-16) - COMPLETE
**Goal:** Polish, optimization, testing, production readiness

**Key Specs:**
- Testing Strategy

**Deliverables:**
- Performance profiling and optimization
- Automated UI tests
- Accessibility audit (VoiceOver)
- Database migration strategy
- CloudKit production deployment
- Crash reporting integration
- 80% code coverage target

**Phase 6 Status: COMPLETE**

**Current Test Coverage:** 289 automated tests (185 ClipboardCore + 104 ClipboardMac), all passing.

**Performance Profiling:**
Automated performance benchmarks created for critical operations (search, retention cleanup, hashing, dedupe, overlay toggle).
- Search performance: ~4ms for 1k items ✅
- Retention cleanup: ~86ms ✅
- Hashing: ~0.3ms ✅
- Deduped insert: ~3ms ✅
- Overlay toggle: ~0.415s avg ✅

**UI Test Infrastructure:**
ClipboardMacUITests target established with 8 test files covering 10 UI test scenarios.
Accessibility identifiers added to all UI components (Overlay, Settings, Onboarding).
Tests: Overlay open, Item selection, Pinboard switching, Search mode, Settings window, Keyboard navigation.

**Accessibility Audit:**
VoiceOver labels and identifiers added to 90+ UI elements across Overlay (cards, pinboards, search), Settings (tabs, toggles), and Onboarding.
"Paste, N items" announcement on overlay open implemented.

**Database Migration:**
Lightweight migration enabled. V2 model version created.
Migration tests (v1 -> v2) implemented and passing.
Versioned .momd bundle structure configured.

**Crash Reporting:**
OSLog-based CrashReporter service implemented with comprehensive coverage:
- Global exception handler configured at app launch
- Error tracking in critical paths: Capture, Paste, Sync, Database
- Subsystem-specific helpers for detailed error context
- Lifecycle event tracking (launch, termination)
- 16 crash reporter tests added, all passing
- Documentation guide created for log collection and viewing
- Console.app and command-line access instructions provided

**CloudKit Production:**
CloudKitEnvironment enum introduced (development/production).
Configuration supports environment switching with per-environment container IDs.
Default environment set to production.

**Code Coverage:**
289 automated tests provide comprehensive coverage across all major subsystems.
Coverage percentage measurement deferred (can be measured in Xcode IDE if needed).

---

### Phase 7: Beta Testing & Polish (Weeks 17-18)
**Goal:** Internal dogfooding, external beta testing, UI polish

**Deliverables:**
- Internal beta deployment (5-10 users)
- TestFlight external beta (20-50 users)
- UI polish based on feedback
- Bug fixes for known issues

**Beta Testing Focus:**
Deploy to engineering team for 2-week daily usage. Set up TestFlight distribution for external beta testers. Create feedback collection mechanism. Monitor crash reports and sync issues. Weekly bug triage sessions.

**UI Polish Items:**
Pinboard tab bar scroll mask refinement, item card hover state improvements, search field clear button visibility, settings tab alignment, multi-monitor overlay positioning.

**Known Bug Fixes:**
PasteboardMonitor race condition (flag-based suppression may miss changes), ThumbnailGenerator error propagation (silent failures need proper handling), PasteEngine skipped items reporting (partial failures should inform user), OverlayViewModel sync error UI feedback.

---

### Phase 8: App Store Preparation (Weeks 19-20)
**Goal:** Compliance, assets, submission

**Deliverables:**
- App icon (1024×1024 + all sizes)
- App Store screenshots
- Privacy policy
- App Store metadata
- App review submission

**App Store Assets:**
Design 1024×1024 app icon and generate all required sizes (16, 32, 64, 128, 256, 512). Create menu bar icon (16×16 template). Create screenshots for macOS sizes (1280×800, 1440×900, 2560×1600, 2880×1800) showing: overlay with items, pinboard organization, search in action, settings window, paste stack mode. Optional: 15-30 second app preview video.

**Privacy & Compliance:**
Draft and host privacy policy. Key disclosures: no personal data collected, all data stored locally, iCloud sync optional and uses Apple's servers, no third-party analytics. Configure App Store privacy labels (Data Used to Track: None; Data Linked to You: User Content if iCloud enabled). Review sandbox entitlements.

**App Review Preparation:**
Prepare explanation for Accessibility permission (required to paste content into other apps). Create demo iCloud account for reviewer with pre-populated sample clipboard items.

---

### Phase 9: Launch & Post-Launch (Week 21+)
**Goal:** Release, monitoring, support

**Deliverables:**
- App Store release
- Launch marketing
- Post-launch monitoring
- v1.0.1 critical fixes

**Launch Activities:**
Submit final build to App Store. Schedule release date. Prepare marketing website. Configure support email. Prepare social media announcements.

**Post-Launch Monitoring:**
Track crash-free rate (target >99.5%). Monitor user ratings (target >4.5 stars). Track 1-day retention. Respond to support tickets (target <10/week). Reserve v1.0.1 for critical fixes discovered post-launch.

---

### Future Phases (Post-Launch)

**Phase 10: iOS Companion App**
Browse synced clipboard on iPhone/iPad. Read-only access to clipboard history. Copy items to iOS clipboard. Handoff support with Mac app.

**Phase 11: Advanced Features**
Snippets (user-created reusable text snippets). Smart folders (auto-organized pinboards by rules). Third-party integrations (Keyboard Maestro, Alfred, Raycast). Export/import functionality. Spotlight integration.

**Phase 12: Apple Watch App**
View recent clipboard items. Dictation for quick text snippets. Handoff to Mac for paste action.

---

## Documentation Statistics

| Document | Lines | Size | Status |
|----------|-------|------|--------|
| Architecture Overview | 850 | ~32 KB | Complete |
| Data Model Spec | 1,100 | ~48 KB | Complete |
| Cloud Schema Spec | 1,200 | ~52 KB | Complete |
| UI Contract Spec | 1,400 | ~64 KB | Complete |
| macOS Services Spec | 1,300 | ~56 KB | Complete |
| Privacy & Security Spec | 1,000 | ~44 KB | Complete |
| Testing Strategy | 900 | ~40 KB | Complete |
| **Total** | **~7,750** | **~336 KB** | **100%** |

---

## Finding Information

### By Topic

**Architecture & Design:**
- System design Architecture Overview
- Module structure Architecture Overview
- Data relationships Data Model Spec
- UI components UI Contract Spec

**Implementation:**
- Data persistence Data Model Spec
- Clipboard capture macOS Services Spec
- Pasting logic macOS Services Spec
- Sync logic Cloud Schema Spec

**User Experience:**
- UI behavior UI Contract Spec
- Settings UI Contract Spec, Privacy & Security Spec
- Onboarding UI Contract Spec
- Accessibility UI Contract Spec

**Quality & Security:**
- Testing approach Testing Strategy
- Privacy controls Privacy & Security Spec
- Security measures Privacy & Security Spec
- Performance Architecture Overview, Testing Strategy

### By Question

**"How does clipboard capture work?"**
 macOS Services Spec > Pasteboard Monitoring

**"What data is stored?"**
 Data Model Spec > Entities

**"How does sync work?"**
 Cloud Schema Spec > Sync Engine

**"What are the privacy controls?"**
 Privacy & Security Spec > All sections

**"How do we test this?"**
 Testing Strategy > Relevant test type

**"What does the UI look like?"**
 UI Contract Spec > UI components

**"How are conflicts resolved?"**
 Cloud Schema Spec > Conflict Resolution

**"What performance targets do we have?"**
 Architecture Overview > Performance Budgets

---

## Getting Started with Development

1. **Read** [`specs/Architecture-Overview.md`](./specs/Architecture-Overview.md)
 - Understand the big picture
 - Review technology choices
 - Note phase roadmap

2. **Review** relevant specs for your phase
 - Phase 1? Data Model Spec, macOS Services Spec (capture only)
 - Phase 2? UI Contract Spec, macOS Services Spec (full capture)
 - Phase 3? macOS Services Spec, UI Contract Spec (pasting & hotkeys)
 - etc.

3. **Set up** project structure
 - Follow structure in Architecture Overview
 - Create ClipboardCore package
 - Create ClipboardMac app target

4. **Implement** phase-specific tasks
 - Each spec has "Phase-Specific Implementation Tasks" sections
 - Follow checklist for your current phase
 - Write tests per Testing Strategy

5. **Update** specs when needed
 - Document decisions
 - Version appropriately
 - Keep specs in sync with implementation

---

## Contributing to Documentation

### Updating Existing Docs

1. Identify which spec needs updating
2. Make changes
3. Increment version number
4. Update changelog
5. Update "Last Updated" date
6. Create pull request

### Adding New Documentation

New docs should go in appropriate directories:
- Engineering specs `specs/`
- API docs `api/` (create if needed)
- User guides `guides/` (create if needed)
- Architecture decisions `decisions/` (create if needed)

---

## External References

**Apple Documentation:**
- [Core Data Programming Guide](https://developer.apple.com/documentation/coredata)
- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Accessibility for macOS](https://developer.apple.com/design/human-interface-guidelines/accessibility)

**Design Resources:**
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [SF Symbols](https://developer.apple.com/sf-symbols/)

**Testing:**
- [XCTest Documentation](https://developer.apple.com/documentation/xctest)

---

## Status

**Documentation:** Complete (Version 1.3.0)
**Implementation:** Phase 6 COMPLETE

All engineering specifications are complete. Phases 1-6 implementation fully complete. CloudKit sync is operational. Phase 6 hardening, performance benchmarks, UI tests, accessibility features, and crash reporting are implemented and verified. Manual validation lives in `docs/VALIDATION.md`.

**Ready for Phase 7:** Beta Testing & Polish

---

**Last Updated:** 2026-01-16
**Maintained By:** Engineering Team 
**Questions?** See [`specs/README.md`](./specs/README.md) for contact information
