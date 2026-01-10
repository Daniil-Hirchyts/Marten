# Paste Clipboard Manager - Engineering Specifications

**Version:** 1.0.0  
**Last Updated:** 2026-01-09  
**Status:** Complete

---

## Overview

This directory contains the complete versioned engineering documentation for the Paste Clipboard Manager macOS application. These specifications serve as the authoritative technical reference for the entire development lifecycle.

---

## Document Structure

### 1. [Architecture Overview](./Architecture-Overview.md) 📐
**Status:** ✅ Complete  
**Purpose:** High-level system architecture, module structure, data flows, and implementation roadmap

**Key Contents:**
- Module hierarchy (ClipboardCore, ClipboardMac, future iOS/watchOS)
- Data flow diagrams
- Technology stack decisions
- 6-phase implementation plan
- Cross-cutting concerns (error handling, logging, performance)
- Dependencies between all specifications

**Read this first** to understand the overall system design.

---

### 2. [Data Model Specification](./Data-Model-Spec.md) 🗄️
**Status:** ✅ Complete  
**Purpose:** Complete local data model using Core Data

**Key Contents:**
- 7 Core Data entities (ClipItem, ClipRepresentation, Pinboard, etc.)
- Entity relationships and cascade rules
- Indexes and performance optimization
- Retention policies
- Asset management (file-based storage)
- Search implementation
- Migration strategy

**Dependencies:** None (foundational)

---

### 3. [Cloud Schema Specification](./Cloud-Schema-Spec.md) ☁️
**Status:** ✅ Complete  
**Purpose:** CloudKit synchronization architecture

**Key Contents:**
- CloudKit record types (CKClipItem, CKClipRepresentation, etc.)
- Sync engine architecture (outbound/inbound)
- Conflict resolution policies
- Asset upload/download with CKAsset
- Deletion propagation
- Error handling and retry logic
- Quotas and limits

**Dependencies:** Data Model Spec (mapping local to cloud)

---

### 4. [UI Contract Specification](./UI-Contract-Spec.md) 🎨
**Status:** ✅ Complete  
**Purpose:** Complete user interface specification

**Key Contents:**
- Overlay window behavior (NSPanel + SwiftUI)
- Pinboard tab bar component
- Item card row (carousel with snap behavior)
- Search mode UI
- Paste stack mode
- Settings window (4 tabs)
- Menu bar integration
- Onboarding flow
- Accessibility (VoiceOver, keyboard navigation)
- Design system (typography, colors, spacing)

**Dependencies:** Data Model Spec (data displayed in UI)

---

### 5. [macOS Services Specification](./macOS-Services-Spec.md) ⚙️
**Status:** ✅ Complete  
**Purpose:** macOS-specific system integrations

**Key Contents:**
- Pasteboard monitoring (polling strategy, adaptive intervals)
- Capture pipeline (content extraction, normalization)
- Pasting engine (paste-to-active-app, synthetic events)
- Hotkey management (global shortcuts, event tap)
- Login item management (SMAppService)
- Sound effects
- Permissions (Accessibility, Input Monitoring)

**Dependencies:** Data Model Spec (captured data), UI Contract Spec (triggers)

---

### 6. [Privacy & Security Specification](./Privacy-Security-Spec.md) 🔒
**Status:** ✅ Complete  
**Purpose:** Privacy controls and security measures

**Key Contents:**
- Ignored applications (bundle ID filtering)
- Confidential content detection (passwords, OTP, credit cards, API keys)
- Transient content filtering
- Link preview privacy (network disclosure)
- Screen sharing visibility control
- Data encryption (at rest and in transit)
- Compliance (GDPR, CCPA, App Store privacy labels)
- Privacy policy guidance

**Dependencies:** macOS Services Spec (filtering in capture)

---

### 7. [Testing Strategy](./Testing-Strategy.md) 🧪
**Status:** ✅ Complete  
**Purpose:** Comprehensive testing approach

**Key Contents:**
- Test pyramid (60% unit, 30% integration, 10% UI)
- Unit test examples (data model, classifiers, hashing)
- Integration tests (capture pipeline, search, assets)
- UI tests (overlay, settings, onboarding)
- Performance tests (budgets and metrics)
- CloudKit sync tests (mocked and real)
- Platform compatibility testing
- CI/CD setup (GitHub Actions)
- Manual testing protocols

**Dependencies:** All specs (defines tests for all modules)

---

## Implementation Roadmap

### Phase 1: Core Foundation (Weeks 1-3)
**Focus:** Data model, basic capture, minimal UI

**Specs Required:**
- Architecture Overview
- Data Model Spec

**Deliverables:**
- ClipboardCore package with Core Data model
- Text-only pasteboard monitor
- Basic overlay listing items

**Status:** ✅ Implemented (performance validation + automation pending)

---

### Phase 2: Full Capture & UI Parity (Weeks 4-6)
**Focus:** All content types, full UI components

**Specs Required:**
- UI Contract Spec
- macOS Services Spec (capture)

**Deliverables:**
- Rich text, image, file capture
- Card previews with thumbnails
- Pinboards with tab bar
- Search mode
- Menu bar app

**Status:** ✅ Implemented (UI rendering perf benchmarked)

---

### Phase 3: Paste Behaviors (Weeks 7-8)
**Focus:** Pasting, hotkeys, paste stack

**Specs Required:**
- macOS Services Spec (paste engine)
- UI Contract Spec (paste stack UI)

**Deliverables:**
- Paste-to-active-app with Accessibility API
- Quick Paste (Cmd+1-9)
- Plain text mode
- Paste stack sequential logic
- Global hotkeys

**Status:** 📋 Ready to start (Phase 2 complete; Accessibility permission flow pending)

---

### Phase 4: Privacy & Settings (Weeks 9-10)
**Focus:** Privacy features, settings UI

**Specs Required:**
- Privacy & Security Spec
- UI Contract Spec (settings)

**Deliverables:**
- Ignored apps list
- Confidential content classifier
- Link preview fetching
- Screen sharing mode
- Complete settings window
- Onboarding flow

---

### Phase 5: CloudKit Sync (Weeks 11-14)
**Focus:** iCloud synchronization

**Specs Required:**
- Cloud Schema Spec

**Deliverables:**
- CloudKit schema deployed
- Sync engine (outbound/inbound)
- Conflict resolution
- Asset upload/download
- Sync status UI

---

### Phase 6: Hardening & Performance (Weeks 15-16)
**Focus:** Optimization, testing, polish

**Specs Required:**
- Testing Strategy

**Deliverables:**
- Performance profiling and optimization
- Database migration tests
- Accessibility audit
- Full regression test suite
- Beta testing

---

## How to Use These Specifications

### For Developers

1. **Starting a new feature:**
   - Read Architecture Overview for context
   - Find the relevant spec (e.g., UI Contract for UI work)
   - Check phase-specific tasks for your current phase
   - Implement according to the spec
   - Write tests per Testing Strategy

2. **Resolving ambiguity:**
   - Check "Open Questions" section in relevant spec
   - If not documented, propose a decision and update the spec
   - Version the spec when making changes

3. **Adding new features (post-MVP):**
   - Update relevant specs first
   - Increment version number
   - Document in changelog
   - Get approval before implementing

### For Product/Design

1. **Understanding what's built:**
   - Architecture Overview for high-level structure
   - UI Contract Spec for complete UI definition
   - Privacy & Security Spec for user-facing privacy features

2. **Proposing changes:**
   - Identify affected specs
   - Work with engineering to update specs
   - Changes to specs = changes to scope/timeline

### For QA/Testing

1. **Test planning:**
   - Testing Strategy is your primary reference
   - Phase-specific tasks list what to test when
   - Manual testing checklists provided

2. **Bug reporting:**
   - Reference specific spec section when filing bugs
   - Check if behavior matches spec (spec bug vs implementation bug)

---

## Document Versioning

### Version Format

`MAJOR.MINOR.PATCH`

- **MAJOR:** Significant architectural changes (e.g., 1.0 → 2.0)
- **MINOR:** New features or substantial additions (e.g., 1.0 → 1.1)
- **PATCH:** Bug fixes, clarifications, minor updates (e.g., 1.0.0 → 1.0.1)

### Change Process

1. Identify spec that needs update
2. Create branch: `spec/feature-name`
3. Update spec with changes
4. Increment version number
5. Add entry to changelog
6. Create pull request for review
7. Merge after approval

---

## Spec Dependencies Diagram

```
Architecture-Overview.md (root)
    ├── Data-Model-Spec.md
    │   ├── Cloud-Schema-Spec.md
    │   └── UI-Contract-Spec.md
    ├── macOS-Services-Spec.md
    │   └── Privacy-Security-Spec.md
    └── Testing-Strategy.md (depends on all)
```

**Reading Order:**
1. Architecture Overview (context)
2. Data Model Spec (foundation)
3. Choose based on your role:
   - **Backend:** Cloud Schema Spec → macOS Services Spec
   - **Frontend:** UI Contract Spec
   - **Security:** Privacy & Security Spec
   - **QA:** Testing Strategy

---

## Key Decisions Captured

### Technology Choices

| Decision | Rationale | Spec |
|----------|-----------|------|
| Core Data | CloudKit integration, mature tooling | Data Model Spec |
| Direct CloudKit (not NSPersistentCloudKitContainer) | Fine-grained control, explicit conflict resolution | Cloud Schema Spec |
| SwiftUI + AppKit | Cross-platform + advanced features | Architecture Overview |
| Polling for pasteboard | Only reliable method | macOS Services Spec |
| Heuristic classifiers | Fast, on-device, no ML required for MVP | Privacy & Security Spec |

### Performance Budgets

| Operation | Target | Spec |
|-----------|--------|------|
| Overlay open | 200ms | UI Contract Spec |
| Capture latency | 50ms | macOS Services Spec |
| Search query | 100ms | Data Model Spec |
| Sync (10 items) | 2s | Cloud Schema Spec |

### Privacy Principles

- Local-first processing
- No telemetry or analytics
- Opt-in iCloud sync
- User data ownership
- Full export and deletion

Detailed in: Privacy & Security Spec

---

## Contributing

### Updating Specifications

When implementation reveals issues or ambiguities:

1. **Don't work around the spec** – update it
2. **Document the decision** – add to changelog
3. **Notify the team** – spec changes affect everyone
4. **Version appropriately** – follow versioning rules

### Spec Review Checklist

Before merging spec changes:

- [ ] Version number incremented
- [ ] Changelog updated
- [ ] "Last Updated" date current
- [ ] Cross-references to other specs updated
- [ ] Phase-specific tasks updated (if applicable)
- [ ] Open questions addressed or added
- [ ] Code examples compile (if included)
- [ ] Reviewed by at least one other team member

---

## Appendix: File Listing

```
docs/specs/
├── README.md                           (this file)
├── Architecture-Overview.md            (32 KB, 850 lines)
├── Data-Model-Spec.md                  (48 KB, 1,100 lines)
├── Cloud-Schema-Spec.md                (52 KB, 1,200 lines)
├── UI-Contract-Spec.md                 (64 KB, 1,400 lines)
├── macOS-Services-Spec.md              (56 KB, 1,300 lines)
├── Privacy-Security-Spec.md            (44 KB, 1,000 lines)
└── Testing-Strategy.md                 (40 KB, 900 lines)

Total: ~330 KB, ~7,750 lines of technical documentation
```

---

## Contact and Support

**Questions about specs:**
- Create an issue: [project-repo]/issues
- Tag with `documentation` label
- Reference specific spec and section

**Requesting spec updates:**
- Propose changes in pull request
- Explain rationale
- Show impact on implementation

---

## Changelog

### Version 1.0.0 (2026-01-09)
- Initial release of all engineering specifications
- Complete coverage of Phases 1-6
- 7 detailed specification documents
- Full implementation roadmap
- Ready for development kickoff

---

**Status:** 🎉 **All specifications complete; Phase 1 implemented with notes in the index!**

Next steps:
1. Review Phase 1 notes and validation gaps
2. Review the Phase 2 execution plan (`docs/phase-2-plan.md`)
3. Decide Phase 2 scope/timeline and assign owners
