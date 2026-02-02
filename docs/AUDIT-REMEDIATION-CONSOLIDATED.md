# Paste — Audit Remediation (Consolidated)

**Document ID:** PASTE-AUD-REM-001  
**Repository:** Paste (macOS clipboard manager with iCloud sync)  
**Last Updated:** 2026-02-02  
**Status:** Draft — requires peer review + security framework validation before publication  
**Supersedes:** `docs/IMPLEMENTATION-GUIDE.md`, `docs/AUDIT-REMEDIATION-REPORT.md` (contents consolidated)

## Document Control

| Field | Value |
|---|---|
| Owner | Engineering |
| Audience | Engineering, Security, Compliance, QA |
| Classification | Internal |
| Revision | 1.0 (Draft) |
| Approval State | Pending |

## Revision History

| Revision | Date | Summary |
|---:|---|---|
| 1.0 | 2026-02-02 | Initial consolidation and cleanup of prior remediation documents |

---

## 1. Executive Summary (Findings)

This consolidated deliverable replaces the prior “implementation guide” and “remediation report” with a single source of truth that:

- Records **what was actually remediated** and **what remains**.
- Removes redundant and non-actionable content.
- Establishes **security and compliance guardrails** aligned to recognized secure SDLC guidance.

### 1.1 Key outcomes completed

- Removed `SwiftUI/@AppStorage` usage from non-UI services via injected settings providers.
- Eliminated UI-side `ClipItemStore()` construction by introducing an injected editor/store abstraction.
- Reduced the “mega-view” surface area by converting `OverlayRootView.swift` into a composition wrapper.
- Extracted startup responsibilities out of `AppDelegate` into dedicated coordinators/services.
- Replaced remaining `print()` calls in production targets with structured `OSLog` logging.
- Refactored `ClipboardCore` persistence entry point: `ClipItemStore` is now a small façade delegating directly to `ClipItemRepository`.

### 1.2 Primary residual risks

- Several overlay/editor files remain large and may continue to concentrate responsibilities (maintenance risk).
- Some debug logging is noisy; production logging policy should be explicitly enforced (privacy + operational quality).
- UI tests exist but require an Xcode host runner (SwiftPM `swift test` skips those tests).

---

## 2. Current Remediation Status

### 2.1 Completed work items

| ID | Area | Outcome | Evidence (code) |
|---:|------|---------|----------------|
| P0-1 | Services settings | Removed `@AppStorage` from services, injected providers | `ClipboardMacServices/Services/Settings/*Providing.swift` |
| P0-2 | UI DI | Removed direct `ClipItemStore()` creation in UI code paths | `ClipboardMacApp/UI/Overlay/ClipItemEditing.swift` |
| P0-3 | Overlay composition | `OverlayRootView` became a small composition wrapper | `ClipboardMacApp/UI/Overlay/OverlayRootView.swift` |
| P1-4 | AppDelegate SRP | Startup logic extracted into coordinators/services | `ClipboardMacApp/App/Coordinators/*` |
| P1-5 | Core SRP | `ClipItemStore` reduced to a thin façade over `ClipItemRepository` (removed pass-through services) | `ClipboardCore/Sources/BusinessRules/*` |
| P2-6 | Logging hygiene | `print()` removed; backup Swift file removed | overlay/editor sources |
| Add-10 | Sync decoupling | Entitlement and “sync enabled” lookup moved to composition layer | `SyncConfigurationProviding.swift` |
| Ops-Perf | SwiftUI churn | Coalesced frequent `ItemFrameKey` updates to reduce “multiple times per frame” warnings | `ItemCardRow.swift` |

### 2.2 Remaining recommended work (priority-ranked)

| Priority | Recommendation | Why it matters | Suggested verification |
|:--:|---|---|---|
| P0 | Continue decomposing overlay/editor mega-files by feature slices | Reduces regression risk, improves testability | Unit tests for extracted coordinators + targeted UI tests |
| P1 | PasteEngine SRP improvements (activation retry policy, keystroke sequence extraction) | Better reliability + deterministic testing | Unit tests with deterministic timing + event assertions |
| P1 | HotkeyManager split (registry vs runtime event handler) | Smaller APIs, easier testing of mappings | Unit tests for registry mapping + integration smoke |
| P2 | Settings access normalization (reduce scattered `UserDefaults.standard`) | Centralized config, fewer hidden coupling points | Compile-time-only + unit tests with fakes |
| P2 | Logging policy hardening (debug vs release, privacy defaults) | Prevents accidental sensitive logging | Release build log review + static grep guard |

---

## 3. Removed / Archived Content (with justification)

The following content was removed from the two prior documents because it was redundant, non-verifiable as written, or better represented as process requirements rather than “completed facts”.

| Removed item | Source | Justification |
|---|---|---|
| Duplicated “summary/status” narratives | `IMPLEMENTATION-GUIDE.md` + `AUDIT-REMEDIATION-REPORT.md` | Consolidated into one status table to avoid drift.
| Procedural claims that imply completion (e.g., “validated against latest security framework”) without recorded evidence | Both docs | Replaced with an explicit “requires sign-off” section and a checklist requiring evidence.
| Repeated build/test instructions across sections | `IMPLEMENTATION-GUIDE.md` | Centralized into a single compliance checklist.
| Vague, non-auditable language (e.g., “validate volume is reasonable”) | `IMPLEMENTATION-GUIDE.md` | Replaced with measurable acceptance criteria and explicit verification steps.
| Full per-item implementation playbooks and rollback prose | `IMPLEMENTATION-GUIDE.md` | Archived to minimize duplication; the current remediation plan is now driven by status + prioritized recommendations.
| “Implemented work items” bullet lists duplicated across files | `AUDIT-REMEDIATION-REPORT.md` | Replaced with a single “Completed work items” table with evidence pointers.

---

## 4. Updated Implementation Guidelines (Current Best Practices)

### 4.1 Security + privacy guardrails

- Do not log clipboard content. Treat clipboard payloads and derived text as sensitive by default.
- Use structured logging (`OSLog`) and apply privacy redaction:
  - `privacy: .private` by default for user-originated strings
  - `privacy: .public` only for safe metadata (counts, durations, sizes, booleans)
- Prefer dependency injection for:
  - settings access (`UserDefaults` behind provider protocols)
  - persistence/store usage (inject store/editor abstractions)
  - entitlement gates (composition layer only)

### 4.2 Architecture + maintainability

- Keep non-UI modules free of SwiftUI-specific property wrappers (`@AppStorage`, `@Environment`, etc.).
- Prefer narrow protocols for consumers (ISP) to avoid “kitchen sink” service containers.
- Keep file size and responsibility boundaries enforceable:
  - prefer extracted coordinators/view models for behavior
  - keep SwiftUI view files focused on rendering + user interaction wiring

### 4.3 Testing + verification

- `swift build` and `swift test` must pass for `ClipboardCore` and `ClipboardMac`.
- UI tests must be executed via Xcode (host runner) when UI is impacted.
- Where behavior changes, add regression tests; where refactors are mechanical, justify why tests are unchanged.

Optional (when applicable):

- Use `ClipboardMacValidation` for stress/regression runs when validating capture/paste/sync behavior.

### 4.4 Operational quality

- Avoid high-volume logs in normal usage; use `.debug` for noisy instrumentation.
- Prefer explicit performance targets for UX-critical flows (overlay open, capture, search).
- Treat OS/system logs (entitlement warnings, XPC noise) as non-actionable unless correlated with failures.

---

## 5. Revised Remediation Recommendations (Prioritized)

### P0 — Must-do (risk reduction)

1. **Continue breaking up overlay/editor mega-files by feature**
   - Target: isolate keyboard, preview, drag, and editor flows into focused units.
   - Acceptance: large files reduced; extracted units have unit tests.

2. **Harden logging policy**
   - Target: debug-only for noisy lifecycle logs; privacy defaults enforced.
   - Acceptance: grep-based guard prevents new `print()` and flags risky logs.

### P1 — Should-do (robustness + testability)

3. **PasteEngine SRP improvements**
   - Target: separate retry policy and keystroke sequencing.
   - Acceptance: deterministic unit tests for retry behavior.

4. **HotkeyManager responsibilities split**
   - Target: registry of mappings + runtime tap handler.
   - Acceptance: mapping tests; minimized hotkey reload churn.

### P2 — Nice-to-have (consistency)

5. **Settings access normalization**
   - Target: reduce ad-hoc `UserDefaults.standard` reads; prefer injected providers.
   - Acceptance: updated call sites; tests use fakes.

---

## 6. Compliance Checklist

### 6.1 Build and tests

- [ ] `ClipboardCore`: `swift build` passes
- [ ] `ClipboardCore`: `swift test` passes
- [ ] `ClipboardMac`: `swift build` passes
- [ ] `ClipboardMac`: `swift test` passes
- [ ] `ClipboardMacUITests`: executed via Xcode runner when UI changed

### 6.2 Logging + privacy

- [ ] No `print()` in production targets
- [ ] No clipboard content logged (review `Logger.*` calls in capture/paste paths)
- [ ] Log levels appropriate (high-volume logs are `.debug`)

### 6.3 Permissions + entitlements

- [ ] Accessibility permission required only for paste injection and is handled gracefully
- [ ] Input Monitoring permission required only for global hotkeys
- [ ] CloudKit/push code paths are gated by entitlement checks in composition layer

### 6.4 Security framework validation (evidence-based)

- [ ] Secure SDLC practices mapped to SSDF (PO/PS/PW/RV)
- [ ] Threat model / abuse cases reviewed for paste injection surface
- [ ] Data protection reviewed for stored clipboard artifacts (at rest)

---

## 7. Peer Review and Approval (Required)

This document is a draft until the sign-off below is completed.

| Role | Name | Date | Decision |
|---|---|---|---|
| Engineering Owner |  |  |  |
| Security Reviewer |  |  |  |
| Privacy/Compliance Reviewer |  |  |  |
| QA / Release Manager |  |  |  |

---

## 8. Security Framework Reference (Validation Target)

Validation for this deliverable should be performed against a recognized secure SDLC framework and recorded with evidence.

- **NIST SSDF** — SP 800-218 (and latest available revision / draft at time of review) as the baseline for secure development practices. Source: https://csrc.nist.gov/pubs/sp/800/218/final
- **NIST SSDF Rev. 1 (IPD)** — newer draft guidance published 2025-12-17. Source: https://csrc.nist.gov/pubs/sp/800/218/r1/ipd
