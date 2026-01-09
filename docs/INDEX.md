# Paste Clipboard Manager - Documentation Index

**Project:** Paste - Clipboard Manager for macOS  
**Version:** 1.0.0  
**Last Updated:** 2026-01-09

---

## 📚 Documentation Structure

```
docs/
├── INDEX.md                    ← You are here
├── starter.md                  Original product requirements
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
- [ ] Create `ClipboardCore` Swift package structure
- [ ] Set up basic module boundaries (Core Data + services + UI host)

**Data Model & Persistence** (Data-Model-Spec.md §8)
- [ ] Define Core Data model file (`Paste.xcdatamodeld`)
- [ ] Create `ClipItem`, `ClipRepresentation`, and `Pinboard` entities
- [ ] Set up Core Data stack with SQLite backend
- [ ] Implement basic CRUD operations
- [ ] Add text-only item creation flow
- [ ] Implement canonical hash + hash-based deduplication
- [ ] Add basic retention policy (day/week/month)

**Pasteboard Capture** (macOS-Services-Spec.md §10)
- [ ] Implement `PasteboardMonitor` with polling
- [ ] Detect text changes only
- [ ] Extract plain text from pasteboard
- [ ] Prevent feedback loops when app writes to pasteboard
- [ ] Add basic logging for capture events

**Minimal Overlay UI** (UI-Contract-Spec.md §15)
- [ ] Create basic SwiftUI overlay window
- [ ] Render a simple list of text items
- [ ] Add open/close animation
- [ ] Register a global hotkey to toggle the overlay

**Testing** (Testing-Strategy.md §10)
- [ ] Set up XCTest target
- [ ] Create in-memory Core Data stack for tests
- [ ] Write tests for ClipItem entity
- [ ] Write tests for hashing logic
- [ ] Write tests for deduplication
- [ ] Write tests for basic retention
- [ ] Achieve 70% code coverage for Phase 1

**Phase 1 Exit Criteria:**
- Capture and display text from pasteboard
- Items persist across app restarts
- Duplicate detection works for identical text
- Pasteboard monitor detects changes within 500ms
- CPU usage < 1% when idle
- Insert 1000 items in <1s; fetch 100 items in <50ms
- Overlay opens in <500ms and renders 100 items without lag

**Phase 1 Code Deliverables (Core Data):**
```
ClipboardCore/Sources/DataModel/
  ├── Paste.xcdatamodeld
  ├── ClipItem+CoreDataClass.swift
  ├── ClipItem+CoreDataProperties.swift
  ├── ClipRepresentation+CoreDataClass.swift
  ├── Pinboard+CoreDataClass.swift
  ├── PersistenceController.swift
  └── Enums/
      ├── ItemType.swift
      └── RepresentationKind.swift
```

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
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos)
- [SF Symbols](https://developer.apple.com/sf-symbols/)

**Testing:**
- [XCTest Documentation](https://developer.apple.com/documentation/xctest)

---

## ✅ Status

**Documentation:** ✅ Complete (Version 1.0.0)  
**Implementation:** 🔜 Ready to begin Phase 1

All engineering specifications are complete and ready for development kickoff!

---

**Last Updated:** 2026-01-09  
**Maintained By:** Engineering Team  
**Questions?** See [`specs/README.md`](./specs/README.md) for contact information
