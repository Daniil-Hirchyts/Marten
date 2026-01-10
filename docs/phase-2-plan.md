# Phase 2 Execution Plan (Full Capture & UI Parity)

**Goal:** Deliver rich content capture and UI parity while closing Phase 1 validation gaps.  
**Scope window:** Weeks 4-6 (estimate)  
**Last Updated:** 2026-01-10

---

## Phase 1 Validation Close-Out (Pre-Phase 2 Gate)

- [x] P2-G1: Validate pasteboard polling latency <= 500ms (avg 0.394s, max 0.409s)
- [x] P2-G2: Measure idle CPU usage <= 1% (measured 0.20% in validation run)
- [x] P2-G3: Verify persistence across restart (added XCTest; passes)
- [x] P2-G4: Exercise feedback-loop prevention in pasteboard monitor (PASS via validation run)
- [x] P2-G5: Measure code coverage baseline (ClipboardCore line coverage 77.78%)

---

## Workstreams and Tasks

| ID | Task | Owner | Estimate | Dependencies |
| --- | --- | --- | --- | --- |
| P2-01 | Data model audit: confirm Phase 2 fields/entities, indexes, and representation rules | Core | 1-2d | P2-G3 |
| P2-02 | Asset storage subsystem (file-backed assets + cleanup hooks) | Core/Services | 3-4d | P2-01 |
| P2-03 | Rich capture pipeline (RTF/HTML, images, file URLs, URLs) + type detection | Services | 3-5d | P2-01 |
| P2-04 | Multi-representation normalization + primary representation selection | Core | 2-3d | P2-03 |
| P2-05 | Thumbnail generation pipeline for images | Services/UI | 2-3d | P2-02, P2-03 |
| P2-06 | Pinboard CRUD + relationship wiring + UI binding | Core/UI | 3-4d | P2-01 |
| P2-07 | UI card components + preview variants (text/image/url/file/code) | UI | 5-7d | P2-04, P2-05 |
| P2-08 | Search indexing + search UI mode + results queries | Core/UI | 3-4d | P2-04, P2-07 |
| P2-09 | Menu bar app shell + "New Text Item" sheet | UI/App | 2-3d | P2-07 |
| P2-10 | Test suite expansion (capture types, assets, thumbnails, pinboards, search) | QA | 3-5d | P2-03..P2-09 |
| P2-11 | Performance validation (search latency, UI rendering, capture throughput) | QA/Perf | 2-3d | P2-07, P2-08 |

---

**Status Notes (Phase 2 Complete):**
- P2-01: Data model audited; `LinkPreview` entity added and `thumbnailPath` confirmed
- P2-02: `AssetStore` with thresholded binary storage + cleanup hooks in `ClipItemStore`
- P2-03: Rich capture extraction for RTF/HTML, images (PNG/JPEG/TIFF/PDF), URL + file URL; type detection includes code
- P2-04: Representation ordering + hash/primary text normalization; searchableText fallback enforced
- P2-05: Thumbnail generation wired for image payloads; thumbnails stored via AssetStore
- P2-06: Pinboard CRUD + move-to-pinboard actions wired to UI
- P2-07: Card previews + snap scroll + empty states + pinboard tab bar + context menus
- P2-08: Core Data search with pinboard scoping + search mode header
- P2-09: Menu bar status item + New Text Item panel
- P2-10: Added tests for extraction, thumbnails, assets, pinboards, search, representation normalization, and capture pipeline; UI overlay toggle test added; ClipboardCore line coverage 86.63%
- P2-11: Perf validation run: search avg 1.0ms (max 1.4ms), capture throughput 1103.5 items/sec; UI frame lifetime avg 16.81ms (p99 26.75ms), 1 hitch at 133.33ms (Animation Hitches trace)

## Spec Updates Needed (Track As You Implement)

- [x] Data Model: clarify Phase 2 entity/field usage; `LinkPreview` added in Phase 2 model  
  (`docs/specs/Data-Model-Spec.md`)
- [x] macOS Services: document new capture types, representation rules, and asset storage details  
  (`docs/specs/macOS-Services-Spec.md`)
- [x] UI Contract: update card/preview behaviors and menu bar UI details to match implementation  
  (`docs/specs/UI-Contract-Spec.md`)
- [x] Testing Strategy: add Phase 2 test cases + perf measurement protocol, update coverage targets  
  (`docs/specs/Testing-Strategy.md`)
- [x] Architecture Overview: update Phase 2 status notes if scope changes  
  (`docs/specs/Architecture-Overview.md`)
- [x] Index: update Phase 2 checklist + validation results as tasks complete  
  (`docs/INDEX.md`)

---

## Dependencies Summary

- P2-02 and P2-05 require asset storage decisions from P2-01.
- P2-07 and P2-08 depend on representation normalization (P2-04).
- P2-10 and P2-11 should not start until core capture and UI work stabilize.

---

## Notes / Assumptions

- Owners are unassigned roles; assign when staffing Phase 2.
- Estimates are initial planning ranges and should be revised after P2-01.
