# Paste App — Comprehensive Audit Report
**Date:** 2026-02-08
**Commit:** 5e3dd95 (main)

---

## EXECUTIVE SUMMARY

Four parallel audits covered: (1) CoreData & persistence, (2) UI architecture & SwiftUI, (3) services, security & concurrency, (4) drag-drop, performance & lifecycle.

**Total findings:** 42 issues identified across all modules
**Fixes implemented in this session:** 6 (all verified, build passes)

---

## FIXES IMPLEMENTED (This Session)

| # | Fix | File | Impact |
|---|-----|------|--------|
| 1 | Added `viewContext.refresh()` after background saves in `deleteItem()` and `renameItem()` | ClipItemRepository.swift | Prevents stale objects in UI after delete/rename |
| 2 | Replaced `orderOut(nil)` with `close()` in drag window cleanup | DragCoordinator.swift | Prevents NSWindow accumulation/memory leak |
| 3 | Extracted `pinboardSignature()` from 3 duplicate locations to shared utility | DragTypes.swift, ItemCardRow, ItemCompactColumn, ItemCard | Eliminates code duplication |
| 4 | Replaced `refcon!` force unwrap with `guard let` in event tap callback | HotkeyManager.swift | Prevents potential crash |
| 5 | Added 120-iteration safety cap to centering animation timer | ItemCardRow.swift | Prevents infinite timer firing |
| 6 | Extracted `DragState`, `PinboardDropTarget`, `captureCardSnapshot` to shared DragTypes.swift | DragTypes.swift (previous session, verified) | Eliminates duplicate types |

---

## REMAINING FINDINGS — PRIORITIZED ROADMAP

### Phase 1: Critical (Next Sprint)

#### P1.1 — Async Continuation Leak in OutboundSyncEngine
**File:** `ClipboardCore/Sources/Sync/OutboundSyncEngine.swift:225-239`
**Issue:** `flushCompletionContinuation` can be stored without being resumed on all error paths, causing callers to hang indefinitely.
**Fix:** Use a queue of continuations or add timeout to `withCheckedContinuation`.
**Effort:** Medium (4-6h)

#### P1.2 — Missing Fetch Indexes on High-Frequency Queries
**File:** CoreData model (PasteV2.xcdatamodel)
**Issue:** No indexes on `needsLinkPreview`, `fetchFailed`, Pinboard items relationship.
**Fix:** Add compound fetch indexes: `(needsLinkPreview, linkPreview, createdAt)`, `(fetchFailed, fetchedAt)`.
**Effort:** Low (1-2h)

#### P1.3 — PasteboardMonitor Thread Safety
**File:** `ClipboardMacServices/Services/PasteboardMonitor/PasteboardMonitor.swift`
**Issue:** 6 mutable properties accessed from `checkForChanges()` and API methods without synchronization.
**Fix:** Wrap state in NSLock or DispatchQueue.
**Effort:** Medium (3-4h)

### Phase 2: High Priority (This Month)

#### P2.1 — ItemCompactColumn Lacks Pagination
**File:** `ItemCompactColumn.swift`
**Issue:** Renders ALL items in LazyVStack. For 500+ items, causes layout thrashing during drag.
**Fix:** Implement pagination similar to `ItemCardRowPagination`.
**Effort:** Medium (4-6h)

#### P2.2 — No Thumbnail Cache
**Issue:** Each thumbnail loaded from disk + NSImage conversion on every card display. 100 items = 100 concurrent file reads.
**Fix:** Add `NSCache<NSString, NSImage>` for thumbnails, like `AppIconCache`.
**Effort:** Medium (3-4h)

#### P2.3 — Orphaned StackEntry Records on ClipItem Delete
**File:** CoreData model — `ClipItem.stackEntries` uses `Nullify` delete rule.
**Issue:** When ClipItem deleted, StackEntry records persist with null clipItem reference.
**Fix:** Add cascade delete or manual cleanup in `deleteItem()`.
**Effort:** Low (1-2h)

#### P2.4 — N+1 Query in fetchRecentItems
**File:** `ClipItemRepository.swift:227-244`
**Fix:** Add `returnsObjectsAsFaults = false` and extended `relationshipKeyPathsForPrefetching`.
**Effort:** Low (30min)

#### P2.5 — No Timeout on CloudKit Sync Operations
**File:** `InboundSyncEngine.swift:83-89`
**Fix:** Add timeout wrapper to all CloudKit operations.
**Effort:** Medium (3-4h)

### Phase 3: Medium Priority (Next Quarter)

#### P3.1 — OverlayShellView State Explosion
**File:** `OverlayShellView.swift` — 40+ `@State` properties, 15 `onChange` handlers
**Fix:** Group related state into structs (`PinboardRenameState`, `VerticalPinboardCreateState`). Extract lifecycle modifiers into ViewModifier.
**Effort:** High (8-12h)

#### P3.2 — Excessive Closure Capture in ForEach
**Files:** `ItemCardRow.swift:250-298`, `ItemCompactColumn.swift:75-125`
**Issue:** 12-15 closures per item in ForEach. With 100 items = 1200+ allocations per render.
**Fix:** Use delegate/coordinator pattern or pass item as parameter to shared handler.
**Effort:** High (8-12h)

#### P3.3 — GeometryReader Inside ScrollViews
**File:** `ItemCardRow.swift:73` — GeometryReader wraps entire scroll view.
**Fix:** Cache size via `.onChange(of: geometry.size)` instead of re-reading every frame.
**Effort:** Medium (2-3h)

#### P3.4 — Asset Orphaning on Delete
**File:** `AssetStore.swift`, `AssetManagementService.swift`
**Issue:** No cleanup mechanism for orphaned asset files if CoreData transaction rolls back after file delete.
**Fix:** Implement periodic orphan scan or soft-delete mechanism.
**Effort:** Medium (4-6h)

#### P3.5 — ItemGridSection 48-Parameter Forwarding
**File:** `ItemGridSection.swift`
**Fix:** Create parameter struct to reduce init complexity.
**Effort:** Medium (4-6h)

### Phase 4: Low Priority (Backlog)

#### P4.1 — AnyView in PinboardTabBar
Replace `AnyView` in `createPopoverContent` with generic type parameter.

#### P4.2 — Observer Double-Removal in OverlayWindowController
**File:** `OverlayWindow.swift:280-287` — removes observer from both NotificationCenter AND workspaceNC.

#### P4.3 — External Monitor Support
**File:** `OverlayWindowController.show()` — always uses `NSScreen.main`.
Listen to `NSApplication.didChangeScreenParametersNotification`.

#### P4.4 — SoundEffectPlayer Thread Safety
**File:** `SoundEffectPlayer.swift` — `@unchecked Sendable` with unprotected dictionary.
Consider making `@MainActor`.

#### P4.5 — Missing Audit Logging for Sensitive Deletions
**File:** `ClipItemRepository.deleteAllItems()` — no logging of what was deleted.

---

## SECURITY SUMMARY

| Area | Status |
|------|--------|
| Hardcoded credentials | None found |
| Input validation (pasteboard UTIs) | Adequate |
| Keystroke injection (PasteEngine) | Properly gated by Accessibility permission |
| Sensitive data classification | Comprehensive (passwords, API keys, credit cards, SSN, private keys) |
| Screen sharing protection | Manual toggle only (no auto-detection) |
| Force unwraps | Fixed (HotkeyManager); 1 remaining in AssetStore base URL |
| Concurrency safety | PasteboardMonitor needs synchronization |

---

## ARCHITECTURE QUALITY

| Aspect | Rating | Notes |
|--------|--------|-------|
| Package structure | Good | Clean SPM split: ClipboardCore / ClipboardMacServices / ClipboardMacApp |
| SwiftUI patterns | Good | Callback closures, non-reactive FrameCoordinator |
| CoreData usage | Good | Proper background contexts, merge policies |
| Drag & Drop system | Good | Two-layer preview, native drag handoff |
| State management | Needs work | OverlayShellView has 40+ @State vars |
| Code duplication | Improved | pinboardSignature + DragState extracted; ForEach closures remain |
| Test coverage | Needs work | 2 test files don't compile; limited UI test coverage |
