# Paste Clipboard Manager - Documentation Index

**Project:** Paste - Clipboard Manager for macOS 
**Version:** 1.1.0 
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
- Note: Manual validation tasks moved to Phase 4 (see Testing-Strategy.md)

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
- Sound effects toggle
- Copy mode toggle (optional)
- Manual validation of Phase 3 paste behaviors (10+ apps, sleep/wake, Quick Paste latency)

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

**Documentation:** Complete (Version 1.1.0) 
**Implementation:** Phase 3 COMPLETE - Ready for Phase 4

All engineering specifications are complete. Phase 3 implementation is fully done; manual validation tasks have been moved to Phase 4 scope.

---

**Last Updated:** 2026-01-16
**Maintained By:** Engineering Team 
**Questions?** See [`specs/README.md`](./specs/README.md) for contact information
