# Paste Clipboard Manager - Documentation Index

**Project:** Paste - Clipboard Manager for macOS  
**Version:** 1.0.0  
**Last Updated:** 2026-01-10

---

## 📚 Documentation Structure

```
docs/
├── INDEX.md                    ← You are here
├── starter.md                  Original product requirements
├── phase-2-plan.md             Phase 2 execution plan and checklist
└── specs/                      Engineering specifications
    ├── README.md               Specs overview and navigation guide
    ├── Architecture-Overview.md
    ├── Data-Model-Spec.md
    ├── Cloud-Schema-Spec.md
    ├── UI-Contract-Spec.md
    ├── macOS-Services-Spec.md
    ├── Privacy-Security-Spec.md
    └── Testing-Strategy.md
```

---

## 🎯 Quick Start

### I'm a Developer
**Start here:** [`specs/Architecture-Overview.md`](./specs/Architecture-Overview.md)
- Understand system architecture
- Learn module structure
- Review phase roadmap
- Then dive into specific specs based on your work

### I'm a Product Manager
**Start here:** [`starter.md`](./starter.md)
- Complete product requirements
- Feature descriptions
- UI screenshots references
- Then check [`specs/UI-Contract-Spec.md`](./specs/UI-Contract-Spec.md) for implementation details

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

## 📖 Document Descriptions

### Original Requirements
**[starter.md](./starter.md)** (897 lines)
- Original technical specification and development documentation
- Product scope and goals
- Functional capabilities
- Reference for UI screenshots
- Basis for all detailed specs

### Engineering Specifications
**[specs/README.md](./specs/README.md)**
- Overview of all engineering specs
- Dependency diagram
- Implementation roadmap
- How to use the specs

**[phase-2-plan.md](./phase-2-plan.md)**
- Phase 2 execution plan (tasks, owners, estimates)
- Phase 2 checklist and dependencies

**[specs/Architecture-Overview.md](./specs/Architecture-Overview.md)** (850 lines)
- System architecture
- Module structure and responsibilities
- Data flow diagrams
- Technology choices
- Phase-by-phase roadmap
- Cross-cutting concerns

**[specs/Data-Model-Spec.md](./specs/Data-Model-Spec.md)** (1,100 lines)
- Core Data entities (7 entities defined)
- Relationships and cascade rules
- Indexes and performance optimization
- Retention policies
- Asset management strategy
- Search implementation

**[specs/Cloud-Schema-Spec.md](./specs/Cloud-Schema-Spec.md)** (1,200 lines)
- CloudKit record types
- Sync engine architecture
- Conflict resolution policies
- Asset upload/download
- Deletion propagation
- Error handling and quotas

**[specs/UI-Contract-Spec.md](./specs/UI-Contract-Spec.md)** (1,400 lines)
- Complete UI specification
- Overlay window behavior
- All UI components (pinboards, cards, search)
- Settings window (4 tabs)
- Onboarding flow
- Design system (typography, colors, spacing)
- Accessibility requirements

**[specs/macOS-Services-Spec.md](./specs/macOS-Services-Spec.md)** (1,300 lines)
- Pasteboard monitoring (polling strategy)
- Capture pipeline
- Pasting engine (synthetic events)
- Hotkey management
- Login item integration
- Permission handling

**[specs/Privacy-Security-Spec.md](./specs/Privacy-Security-Spec.md)** (1,000 lines)
- Ignored applications
- Confidential content detection (passwords, OTP, credit cards, API keys)
- Transient content filtering
- Link preview privacy
- Screen sharing mode
- Data encryption
- Compliance (GDPR, CCPA)

**[specs/Testing-Strategy.md](./specs/Testing-Strategy.md)** (900 lines)
- Test pyramid (unit, integration, UI tests)
- Performance testing
- CloudKit sync testing
- Platform compatibility
- Manual testing protocols
- CI/CD setup

---

## 🗺️ Implementation Phases

### Phase 1: Core Foundation (Weeks 1-3)
**Goal:** Basic clipboard capture and storage

**Key Specs:**
- Architecture Overview
- Data Model Spec

**Deliverables:**
- ClipboardCore Swift package
- Core Data model with text-only capture
- Basic overlay UI

**Out of Scope (Explicitly Deferred):**
- CloudKit sync (Phase 5)
- Privacy filters / classifiers (Phase 4)
- Paste-to-app behaviors (Phase 3)
- Rich content capture (Phase 2)

**Phase 1 Implementation Checklist:**

**Foundation & Package Setup**
- [x] Create `ClipboardCore` Swift package structure
- [x] Set up basic module boundaries (Core Data + services + UI host)

**Data Model & Persistence** (Data-Model-Spec.md §8)
- [x] Define Core Data model file (`Paste.xcdatamodeld`)
- [x] Create `ClipItem`, `ClipRepresentation`, and `Pinboard` entities
- [x] Set up Core Data stack with SQLite backend
- [x] Implement basic CRUD operations
- [x] Add text-only item creation flow
- [x] Implement canonical hash + contentHash-based deduplication
- [x] Add basic retention policy (day/week/month)

**Pasteboard Capture** (macOS-Services-Spec.md §10)
- [x] Implement `PasteboardMonitor` with polling
- [x] Detect text changes only
- [x] Extract plain text from pasteboard
- [x] Prevent feedback loops when app writes to pasteboard (suppression integrated via `.clipboardWillWrite`)
- [x] Add basic logging for capture events

**Minimal Overlay UI** (UI-Contract-Spec.md §15)
- [x] Create basic SwiftUI overlay window
- [x] Render a simple list of text items
- [x] Add open/close animation
- [x] Register a global hotkey to toggle the overlay

**Testing** (Testing-Strategy.md §10)
- [x] Set up XCTest target
- [x] Create in-memory Core Data stack for tests
- [x] Write tests for ClipItem entity
- [x] Write tests for hashing logic
- [x] Write tests for deduplication
- [x] Write tests for basic retention
- [x] Achieve 70% code coverage for Phase 1 (ClipboardCore line coverage 77.78%)

**Phase 1 Exit Criteria:**
- Capture and display text from pasteboard
- Items persist across app restarts
- Duplicate detection works for identical text
- Pasteboard monitor detects changes within 500ms
- CPU usage < 1% when idle
- Insert 1000 items in <1s; fetch 100 items in <50ms
- Overlay opens in <500ms and renders 100 items without lag
  
**Exit Criteria Validation Notes:**
- Pasteboard latency validated: avg 0.394s, max 0.409s (poll interval 0.4s)
- Idle CPU usage validated: 0.20% in validation run
- Persistence across restarts validated via XCTest
- Feedback-loop suppression validated in monitor + `.clipboardWillWrite` integration
- Unvalidated: DB perf targets (1000 inserts, 100 fetch), overlay open/render timing

**Phase 1 Code Deliverables (Core Data):**
```
ClipboardCore/Sources/DataModel/
  ├── Paste.xcdatamodeld
  ├── Paste.momd
  ├── ClipItem+CoreDataClass.swift
  ├── ClipItem+CoreDataProperties.swift
  ├── ClipRepresentation+CoreDataClass.swift
  ├── Pinboard+CoreDataClass.swift
  ├── PersistenceController.swift
  └── Enums/
      ├── ItemType.swift
      └── RepresentationKind.swift
```

**Phase 1 Status (Current Progress)**
- ✅ ClipboardCore package with Core Data model, persistence, hashing/dedupe, retention, and CRUD
- ✅ ClipboardMac app package with pasteboard polling, global hotkey, and minimal overlay list
- ✅ Unit tests for hashing, deduplication, retention, and ClipItem insertions
- ⚠️ Temporary: Core Data model is compiled manually to `Paste.momd` for SwiftPM; no automated build step yet
- ⚠️ Temporary: Global hotkey uses Carbon `RegisterEventHotKey` (modern replacement deferred to later phase)
- ⚠️ Performance budgets for DB/UI remain unvalidated (see exit criteria notes)

**Phase 1 Changes from Spec (Recorded)**
- `hash` attribute renamed to `contentHash` to avoid `NSObject.hash` collision
- In-memory Core Data store disables history tracking/remote change notifications for test stability
- Persistence model lookup targets `DataModel/Paste.momd` bundle path with fallbacks

**Known Issues / Notes**
- SwiftPM test runs can warn about user cache permissions; safe to ignore
- Feedback-loop suppression validated; full paste-to-app loop pending

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

**Execution Plan:**
- See [`phase-2-plan.md`](./phase-2-plan.md) for tasks, owners, estimates, and dependencies

**Phase 2 Execution Checklist (tracking in `phase-2-plan.md`):**
- [x] P2-G1..P2-G5: Close Phase 1 validation gaps
- [x] P2-01: Data model audit
- [x] P2-02: Asset storage subsystem
- [x] P2-03: Rich capture pipeline + type detection
- [x] P2-04: Multi-representation normalization
- [x] P2-05: Thumbnail generation pipeline
- [x] P2-06: Pinboard CRUD + UI binding
- [x] P2-07: Card UI + preview variants
- [x] P2-08: Search indexing + search UI
- [x] P2-09: Menu bar app + new text sheet
- [x] P2-10: Tests for new capture/UI work
- [x] P2-11: Phase 2 performance validation (UI rendering still unbenchmarked)

**Phase 2 Validation Notes:**
- Search latency validated: avg 1.0ms, max 1.4ms (1000-item dataset)
- Capture throughput validated: 1103.5 items/sec (500-item run)
- UI frame lifetime avg 16.81ms (p99 26.75ms), 1 hitch at 133.33ms (Animation Hitches trace)
- ClipboardCore line coverage: 86.63% (Phase 2 run); ClipboardMac coverage not measured

**Phase 2 Status (Current Progress)**
- ✅ Phase 2 implementation complete; UI rendering perf benchmarked

---

### Phase 3: Paste Behaviors (Weeks 7-8)
**Goal:** Pasting, shortcuts, paste stack

**Key Specs:**
- macOS Services Spec (pasting)
- UI Contract Spec (paste stack UI)

**Deliverables:**
- Paste-to-active-app
- Global hotkeys
- Quick Paste (⌘1-9)
- Paste stack

**Phase 3 Status (Current Progress)**
- ✅ Paste engine with ActiveAppTracker, CGEvent paste injection, and plain-text conversion
- ✅ Paste stack Core Data model + selection UI + sequential paste workflow
- ✅ Event tap hotkey manager with default hotkeys + Quick Paste (⌘1-9)
- ✅ Accessibility prompt surfaced from overlay + quick paste fallback
- ✅ Paste stack UI: multi-select, footer actions, quick-paste badges, plain-text indicator
- ⚠️ Unvalidated: paste success rate across 10+ apps, Quick Paste latency target, hotkey reliability after sleep

---


### Phase 4: Privacy & Settings (Weeks 9-10)
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

---

### Phase 5: CloudKit Sync (Weeks 11-14)
**Goal:** iCloud synchronization

**Key Specs:**
- Cloud Schema Spec

**Deliverables:**
- CloudKit schema
- Sync engine (bi-directional)
- Conflict resolution
- Sync status UI

---

### Phase 6: Hardening & Performance (Weeks 15-16)
**Goal:** Polish, optimization, testing

**Key Specs:**
- Testing Strategy

**Deliverables:**
- Performance optimization
- Full test coverage
- Accessibility audit
- Beta testing

---

## 📊 Documentation Statistics

| Document | Lines | Size | Status |
|----------|-------|------|--------|
| starter.md | 897 | ~35 KB | ✅ Complete |
| Architecture Overview | 850 | ~32 KB | ✅ Complete |
| Data Model Spec | 1,100 | ~48 KB | ✅ Complete |
| Cloud Schema Spec | 1,200 | ~52 KB | ✅ Complete |
| UI Contract Spec | 1,400 | ~64 KB | ✅ Complete |
| macOS Services Spec | 1,300 | ~56 KB | ✅ Complete |
| Privacy & Security Spec | 1,000 | ~44 KB | ✅ Complete |
| Testing Strategy | 900 | ~40 KB | ✅ Complete |
| **Total** | **~8,650** | **~370 KB** | ✅ **100%** |

---

## 🔍 Finding Information

### By Topic

**Architecture & Design:**
- System design → Architecture Overview
- Module structure → Architecture Overview
- Data relationships → Data Model Spec
- UI components → UI Contract Spec

**Implementation:**
- Data persistence → Data Model Spec
- Clipboard capture → macOS Services Spec
- Pasting logic → macOS Services Spec
- Sync logic → Cloud Schema Spec

**User Experience:**
- UI behavior → UI Contract Spec
- Settings → UI Contract Spec, Privacy & Security Spec
- Onboarding → UI Contract Spec
- Accessibility → UI Contract Spec

**Quality & Security:**
- Testing approach → Testing Strategy
- Privacy controls → Privacy & Security Spec
- Security measures → Privacy & Security Spec
- Performance → Architecture Overview, Testing Strategy

### By Question

**"How does clipboard capture work?"**
→ macOS Services Spec > Pasteboard Monitoring

**"What data is stored?"**
→ Data Model Spec > Entities

**"How does sync work?"**
→ Cloud Schema Spec > Sync Engine

**"What are the privacy controls?"**
→ Privacy & Security Spec > All sections

**"How do we test this?"**
→ Testing Strategy > Relevant test type

**"What does the UI look like?"**
→ UI Contract Spec > UI components

**"How are conflicts resolved?"**
→ Cloud Schema Spec > Conflict Resolution

**"What performance targets do we have?"**
→ Architecture Overview > Performance Budgets

---

## 🚀 Getting Started with Development

1. **Read** [`specs/Architecture-Overview.md`](./specs/Architecture-Overview.md)
   - Understand the big picture
   - Review technology choices
   - Note phase roadmap

2. **Review** relevant specs for your phase
   - Phase 1? → Data Model Spec, macOS Services Spec (capture only)
   - Phase 2? → UI Contract Spec, macOS Services Spec (full capture)
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

## 📝 Contributing to Documentation

### Updating Existing Docs

1. Identify which spec needs updating
2. Make changes
3. Increment version number
4. Update changelog
5. Update "Last Updated" date
6. Create pull request

### Adding New Documentation

New docs should go in appropriate directories:
- Engineering specs → `specs/`
- API docs → `api/` (create if needed)
- User guides → `guides/` (create if needed)
- Architecture decisions → `decisions/` (create if needed)

---

## 🔗 External References

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

## ✅ Status

**Documentation:** ✅ Complete (Version 1.0.0)  
**Implementation:** ✅ Phase 1 Core Foundation implemented (validation + automation pending)

All engineering specifications are complete; Phase 1 core foundation is implemented with notes above.

---

**Last Updated:** 2026-01-10
**Maintained By:** Engineering Team  
**Questions?** See [`specs/README.md`](./specs/README.md) for contact information
