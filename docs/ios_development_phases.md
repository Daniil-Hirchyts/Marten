# Marten iOS Delivery Spec (4 Phases, Multi-Agent Ready)

This is the single source of truth for iOS delivery.
It supersedes the deleted `docs/ios_features.md` and includes all required feature scope.

## 1. Current Baseline (Verified 2026-02-11)

- `MartenIOS` now includes full Phase 1 foundation, full Phase 2 productivity/search parity scope, and full Phase 3 collaboration/integrations scope.
- `MartenIOSWrapper` still launches `MartenIOSRootView` through `ContentView` (stable entrypoint contract preserved).
- `MartenCore` remains reused with no schema migration introduced by Phase 3.
- Deployment baseline is iOS 26.2 in `MartenIOSWrapper`.
- Phase 1 packages `P1-01` through `P1-07` are implemented and validated.
- Phase 2 packages `P2-01` through `P2-08` are implemented and validated.
- Phase 3 packages `P3-01` through `P3-06` are implemented and validated.

## 2. Skill-Derived Engineering Contract (Mandatory)

### 2.1 SwiftUI Expert + UI Patterns

- Use modern SwiftUI APIs only (`NavigationStack`, modern `Tab`, `foregroundStyle`, `clipShape(.rect(cornerRadius:))`).
- Use `@Observable` for new shared state and keep view-owned state as `@State private`.
- Prefer `.sheet(item:)` for model-driven sheets.
- Keep views small and composable; avoid large monolithic screens.
- Avoid `GeometryReader` unless required; prefer relative layout APIs.

### 2.2 Swift Concurrency

- Prefer structured concurrency (`async let`, task groups) over unstructured `Task`.
- Do not apply blanket `@MainActor`; isolate only UI-bound state and flows.
- Before concurrency-sensitive changes, inspect project settings for isolation/checking mode:
  - `Package.swift` (`swift-tools-version`, strict concurrency flags, default isolation),
  - `project.pbxproj` (`SWIFT_DEFAULT_ACTOR_ISOLATION`, `SWIFT_STRICT_CONCURRENCY`, upcoming features).
- Define actor/isolation boundaries before implementation for each package.
- Any `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` use must include:
  - explicit invariant comment,
  - tracking task to remove.

### 2.3 SwiftUI Performance

- No heavy work in `body` (sort/filter/format/decode must be precomputed).
- Use stable identity in list/grid rendering.
- Downsample large images before rendering.
- Scope observable dependencies tightly to avoid invalidation storms.
- Performance target for core screens: smooth 60fps on current iPhone baseline device.

### 2.4 SwiftUI Animation

- Motion must communicate state changes, not decorate randomly.
- Default interaction timing: 150-350ms.
- Prefer explicit `withAnimation` and spring presets (`.snappy`, `.smooth`, `.bouncy`) with restraint.
- All important interactions must remain usable if motion is reduced.

### 2.5 Liquid Glass (iOS 26+)

- Use native APIs only: `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`.
- Apply glass after layout/appearance modifiers.
- Use `.interactive()` only for tappable/focusable elements.
- Provide non-glass fallback UI with `#available(iOS 26, *)` checks.
- Keep shape language consistent across dashboard cards, chips, and action surfaces.

## 3. Multi-Agent Execution Model

### 3.1 Agent Roles

| Agent | Responsibility |
|---|---|
| A1 Core Integration | `MartenCore` reuse, repositories, app composition, data contracts |
| A2 UI Foundation | navigation shell, dashboard layout, pinboard navigation, base components |
| A3 Interaction + Editors | selection mode, context menus, drag/drop, rich text/image/code flows |
| A4 Search + Intelligence | search pipeline, filters, Siri suggestions, quick results |
| A5 Collaboration + Integrations | shared pinboards, share extension, keyboard extension, widgets, shortcuts |
| A6 Quality + Release | tests, performance audits, accessibility, TestFlight/App Store readiness |

### 3.2 Parallelization Rules

- One package per branch, one owner agent per package.
- Branch naming: `codex/ios-p<phase>-<package-id>-<agent>`.
- Keep each PR scoped to a single package when possible.
- If two packages need same file, resolve by sequencing dependency order rather than parallel edits.
- Required handoff artifact for each package:
  - package summary,
  - changed files list,
  - validation command outputs,
  - known risks.

### 3.3 Shared Definition of Done (All Packages)

- Build passes for affected targets.
- Tests added/updated for new logic.
- Accessibility labels/roles for interactive controls.
- Concurrency safety reviewed (isolation + cancellation).
- Performance sanity validated on changed screens.
- Liquid Glass usage (if added) includes fallback path.

### 3.4 File Ownership Boundaries (Conflict Control)

- A1 owns:
  - `MartenIOS/Sources/MartenIOSApp/*Bootstrap*`
  - shared app wiring and data contracts.
- A2 owns:
  - navigation shell, dashboard and pinboard UI surfaces.
- A3 owns:
  - editors, item interactions, drag/drop interaction layers.
- A4 owns:
  - search/filter/relevance and suggestions surfaces.
- A5 owns:
  - extension, widget, shortcut, and collaboration-specific targets/files.
- A6 owns:
  - test targets, test fixtures, performance scripts, release checklists.

If a package requires editing files outside owner scope, add a dependency note and sequence it after the owning package merges.

## 4. Global Feature Inventory (Complete Scope)

The following feature list is fully in scope and must be complete by Phase 4:

- Dashboard: two-column efficient grid; card footer includes source app metadata, date, and title.
- Item types: plain/rich text, links (favicon/title/description), images, files, colors, code.
- Pinboards: colored indicators, quick switch control, special "Clipboard History" pinboard.
- Pinboard management: create/edit/rename/delete, lock behavior support.
- Item operations: selection mode batch actions (copy/move/share/delete), long-press context menus, drag/drop.
- Creation flows: quick add, new text, scan document (VisionKit/Camera), paste from clipboard.
- Editors/viewers: rich text toolbar (bold/italic/lists/headers), image zoom viewer, code viewer.
- Search: text search, voice dictation, quick results strip, Siri suggestions, advanced filters.
- Filters: date ranges (today/yesterday/7d/30d), content type, source app, source device.
- Sharing: iCloud shared pinboards (owner/editor/viewer, participant list, leave share).
- Integrations: share sheet action extension, keyboard extension, home/lock widgets, Siri shortcuts.
- Settings: iCloud sync, subscription, appearance.
- Privacy: collection mode (foreground active / keyboard active), ignored apps, sensitive-content filtering.

## 5. 4-Phase Plan

### 5.1 Phase Progress Snapshot (Updated 2026-02-11)

| Phase | Status | Notes |
|---|---|---|
| Phase 1 | Complete | `P1-01` to `P1-07` implemented and validated in `MartenIOS` + `MartenIOSWrapper` unsigned build |
| Phase 2 | Complete | `P2-01` to `P2-08` implemented and validated in `MartenCore` + `MartenIOS` + `MartenIOSWrapper` unsigned build |
| Phase 3 | Complete | `P3-01` to `P3-06` implemented and validated in `MartenCore` + `MartenIOS` + `MartenIOSWrapper` unsigned build |
| Phase 4 | Complete | `P4-01` to `P4-05` implemented and validated |

### Phase 1: Foundation + Core Experience (Complete)

### Objective

Deliver a complete single-user local app foundation with reusable architecture and initial Liquid Glass visual system.

### Packages

| ID | Owner | Scope | Depends On |
|---|---|---|---|
| P1-01 | A1 | App composition root for iOS (`MartenCore` repositories/services wiring) | - |
| P1-02 | A2 | Navigation shell + dashboard container + pinboard switch UI | P1-01 |
| P1-03 | A2 | Item card system for text/link/image/file/color/code + metadata footer | P1-02 |
| P1-04 | A2 | Pinboard management sheet (create/edit/rename/delete/lock hook) | P1-02 |
| P1-05 | A3 | Quick Add flows: new text, paste clipboard, scan document entry path | P1-01 |
| P1-06 | A2 | Settings baseline: sync toggle/status, appearance, subscription placeholder | P1-01 |
| P1-07 | A2 | Liquid Glass design primitives + non-glass fallback component set | P1-02 |

### Exit Gate

- User can capture/create/edit/delete/browse local content across pinboards.
- Dashboard renders all core types with stable scrolling performance.
- Clipboard History pinboard is visible and functional.
- Core navigation/settings are stable and test-covered.
- Validation completed on 2026-02-11:
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenCore`
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOS`
  - `xcodebuild -project /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

### Phase 2: Productivity + Search Parity (Complete)

### Objective

Reach daily-driver productivity for power users with fast interaction, editing, and intelligent retrieval.

### Packages

| ID | Owner | Scope | Depends On |
|---|---|---|---|
| P2-01 | A3 | Selection mode + batch actions (copy/move/share/delete) | P1-03 |
| P2-02 | A3 | Context menus + drag/drop between pinboards | P1-03, P1-04 |
| P2-03 | A3 | Rich text editor parity (toolbar actions) | P1-05 |
| P2-04 | A3 | Image viewer (zoom/pan) + code viewer (syntax highlight, read-only) | P1-03 |
| P2-05 | A4 | Search stack (search bar, voice dictation, quick results strip) | P1-01, P1-03 |
| P2-06 | A4 | Filter system parity: date/type/source app/device | P2-05 |
| P2-07 | A4 | Siri suggestions integration for recommended actions/apps | P2-05 |
| P2-08 | A2 | Liquid Glass interaction polish for search chips, editor toolbars, action bars | P2-01, P2-05 |

### Release Snapshot (2026-02-11)

- `P2-01` shipped: dashboard selection mode, batch action bar, copy/move/share/delete batch flows.
- `P2-02` shipped: per-card context menu + drag/drop between pinboards and drop-to-`All` behavior.
- `P2-03` shipped: rich text editor sheet with bold/italic/list/header actions and RTF persistence.
- `P2-04` shipped: image viewer (zoom/pan/reset) and read-only code viewer with syntax highlighting + copy.
- `P2-05` shipped: debounced search bar, explicit mic start/stop, quick results strip, cancellable search pipeline.
- `P2-06` shipped: date/type/source app/source device filters via `ClipItemSearchRequest` predicate path.
- `P2-07` shipped: Siri suggestions donation layer via `NSUserActivity` (search/open item/open pinboard).
- `P2-08` shipped: glass/fallback polish across search chips, action surfaces, and editor/viewer interactions.

### Exit Gate

- Batch workflows are fast and reliable for large histories.
- Search + filters return correct results and remain responsive.
- Rich text/image/code interactions are production-usable.
- Interaction animations are clear, short, and accessible.
- Validation completed on 2026-02-11:
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenCore`
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOS`
  - `xcodebuild -project /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

### Phase 3: Collaboration + Integrations (Complete)

### Objective

Ship collaboration and iOS ecosystem integrations that make Marten useful outside the main app.

### Packages

| ID | Owner | Scope | Depends On |
|---|---|---|---|
| P3-01 | A5 | CloudKit shared pinboards (invite/roles/participants/leave share) | P1-04, P2-06 |
| P3-02 | A5 | Share extension: save text/link/image/file to Clipboard History or selected pinboard | P1-01, P1-04 |
| P3-03 | A5 | Keyboard extension: browse/search/insert items in text fields | P2-05 |
| P3-04 | A5 | Widgets: Home + Lock screen, recent and selected pinboard entries | P1-03 |
| P3-05 | A5 | Siri Shortcuts: Create Item, Search Marten, Get Recent Item | P2-05 |
| P3-06 | A2 | Integrations onboarding UX (enable extension, keyboard full access) | P3-02, P3-03 |

### Release Snapshot (2026-02-11)

- `P3-01` shipped: iOS sharing repository wiring, share management sheet/view-model/participant rows, CloudKit share acceptance bridge, leave/stop sharing actions.
- `P3-02` shipped: App Group shared storage contract and migration path, share extension target + save flows for text/link/image/file, app-group bootstrap wiring.
- `P3-03` shipped: keyboard extension target + browse/search/insert experience, shared clip query DTO/service layer, keyboard heartbeat onboarding key.
- `P3-04` shipped: widgets extension target with Home + Lock widgets, widget timeline service, deep-link routing for pinboard/item URLs.
- `P3-05` shipped: App Intents shortcuts (`Create Item`, `Search Marten`, `Get Recent Item`) and shortcut provider wiring.
- `P3-06` shipped: integrations settings section, integrations status model, one-time dashboard onboarding cue.

### Exit Gate

- End-to-end collaboration flow is stable (invite -> shared edit -> role behavior -> leave/remove).
- Extensions and widgets run with shared data model and required entitlements.
- Shortcuts work reliably from Siri/Shortcuts app.
- Validation completed on 2026-02-11:
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenCore`
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOS`
  - `xcodebuild -project /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

### Phase 4: Stabilization + Release (Complete)

### Objective

Convert feature-complete product into release-quality app with measured reliability and performance.

### Packages

| ID | Owner | Scope | Depends On |
|---|---|---|---|
| P4-01 | A6 | Test hardening: unit/integration/UI coverage for critical flows | P1-P3 complete |
| P4-02 | A6 | Performance audit and remediation (scrolling/search/startup/editor) | P1-P3 complete |
| P4-03 | A6 | Sync reliability and conflict/retry validation with collaboration scenarios | P3-01 |
| P4-04 | A6 | Accessibility and localization quality pass (Dynamic Type, VoiceOver, labels) | P1-P3 complete |
| P4-05 | A6 | Release operations: TestFlight ramp, metadata, screenshots, privacy manifest, submission checklist | P4-01, P4-02, P4-03, P4-04 |

### Release Snapshot (2026-02-11)

- `P4-01` shipped: new test files (ClipItemQueryServiceTests, ShareExtensionSaveServiceTests, ImageThumbnailLoaderTests, MartenIOSDefaultsTests), extended existing tests (ClipItemCommandServiceTests, DashboardSearchModelTests, ShareSettingsViewModelTests, MartenIOSAppContainerTests), mock additions in ServiceTestDoubles.
- `P4-02` shipped: performance benchmarks (IOSPerformanceBenchmarks), ItemCardView presentation caching and imageTaskID caching, DashboardSearchModel updateOptions skip-recomputation guard.
- `P4-03` shipped: ConflictScenarioTests (8 tests covering all record type routing), SyncRetryScenarioTests (4 retry/recovery scenarios), AppContainerSyncIntegrationTests, extended ConflictResolverTests.
- `P4-04` shipped: accessibility modifiers on 16 view files (labels, hints, traits, combined elements), @ScaledMetric for Dynamic Type on RichTextEditorSheet and DashboardSearchComponents, Localizable.xcstrings with ~90 strings, Package.swift resources configuration.
- `P4-05` shipped: privacy manifests for app + 3 extensions, RELEASE_CHECKLIST.md, TESTFLIGHT_PLAN.md, spec status update.

### Exit Gate

- No open P0/P1 defects across core capture/create/search/share/sync flows.
- Crash-free and performance metrics meet launch thresholds.
- App Store submission package is complete and approved.
- Validation completed on 2026-02-11:
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenCore`
  - `swift test --package-path /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOS`
  - `xcodebuild -project /Users/hirchytsdaniil/Developer/Work/Marten/MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 6. Cross-Phase Dependency Gates

- CloudKit sharing entitlements must be approved before P3-01.
- App Group and shared container design must be finalized before P3-02/P3-03/P3-04.
- Extension data access contract must be documented before implementation starts.
- Any schema or repository contract changes in `MartenCore` require migration tests before merge.

## 7. Verification Matrix (Agent Runbook)

Run the minimum relevant checks per package:

- Core package tests:
  - `swift test --package-path MartenCore`
- iOS package tests:
  - `swift test --package-path MartenIOS`
- iOS app build (unsigned):
  - `xcodebuild -project MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- iOS app build (signed, optional when provisioning is configured):
  - `xcodebuild -project MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' build`

For Phase 4 performance packages:

- Collect Instruments traces for startup, dashboard scroll, search, and editor interactions.
- Compare before/after frame pacing, CPU, and memory peaks.

## 8. AI-Agent Handoff Template (Use for Every Package)

```text
Package ID:
Owner Agent:
Branch:
Summary of changes:
Files changed:
Dependencies consumed:
Validation commands run:
Known risks or follow-ups:
```

## 9. Completion Definition

The iOS app is finished when all packages P1-01 through P4-05 pass exit gates, required validations complete, and release submission is approved.
