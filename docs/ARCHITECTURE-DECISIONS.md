# Architecture Decision Records (ADRs)

**Project:** Paste Clipboard Manager  
**Version:** 1.0.0  
**Last Updated:** 2026-02-03

---

## Purpose

This document records significant architectural decisions made during the development of Paste. Each decision includes context, options considered, decision made, and rationale.

---

## ADR Format

Each ADR includes:
- **Context:** The issue requiring a decision
- **Options Considered:** Alternative approaches evaluated
- **Decision:** What was chosen
- **Rationale:** Why this choice was made
- **Consequences:** Trade-offs and implications

---

## ADR-001: Core Data vs SwiftData

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Need a local persistence layer for clipboard items that supports CloudKit synchronization.

**Options Considered:**
1. **SwiftData** - Modern, declarative, less boilerplate
2. **Core Data** - Mature, CloudKit-compatible, full control
3. **SQLite.swift** - Third-party, lightweight
4. **Realm** - Third-party, sync-capable

**Decision:** Core Data

**Rationale:**
- CloudKit integration requires Core Data (NSPersistentCloudKitContainer or manual CloudKit API)
- SwiftData's CloudKit support is immature (as of macOS 13/14)
- Manual CloudKit with Core Data provides fine-grained control over:
  - Conflict resolution policies
  - Asset management
  - Error handling
  - Sync timing
- Mature tooling and extensive documentation
- No third-party dependencies

**Consequences:**
- ✅ Full control over sync behavior
- ✅ Predictable conflict resolution
- ✅ First-party framework support
- ❌ More boilerplate code (entities, fetch requests)
- ❌ Steeper learning curve than SwiftData

**References:** `ClipboardCore/Sources/DataModel/`, `ClipboardCore/Sources/Sync/`

---

## ADR-002: Direct CloudKit vs NSPersistentCloudKitContainer

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Need to sync clipboard items across devices via iCloud.

**Options Considered:**
1. **NSPersistentCloudKitContainer** - Automatic CloudKit sync
2. **Manual CloudKit API** - Direct control over records and sync
3. **Third-party sync** - Firebase, Realm Sync

**Decision:** Manual CloudKit API

**Rationale:**
- NSPersistentCloudKitContainer limitations:
  - Opaque conflict resolution (limited customization)
  - No control over sync timing (automatic, unpredictable)
  - Limited error handling visibility
  - Asset management constraints
- Manual CloudKit provides:
  - Explicit conflict resolution policies (append-only for ClipItems, last-writer-wins for Pinboards)
  - Controlled sync timing (debounced, batched)
  - Detailed error reporting to user
  - Custom asset upload/download logic
  - Zone subscription management

**Consequences:**
- ✅ Deterministic conflict resolution
- ✅ Explicit error handling
- ✅ Fine-grained asset control
- ✅ Testable sync engine (mockable)
- ❌ More code (~2000 LOC for sync engine)
- ❌ More complexity to maintain

**References:** `ClipboardCore/Sources/Sync/`

---

## ADR-003: Polling vs Notifications for Pasteboard Monitoring

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Need to detect when user copies content to system clipboard.

**Options Considered:**
1. **Polling** - Check NSPasteboard.changeCount on timer
2. **NSPasteboard Notifications** - React to clipboard changes
3. **CGEventTap** - Intercept Cmd+C events

**Decision:** Polling with adaptive intervals

**Rationale:**
- **NSPasteboard does NOT provide change notifications** - No official API exists
- CGEventTap for Cmd+C is unreliable (doesn't catch context menu copies, drag-and-drop, programmatic copies)
- Polling is the only reliable method used by all major clipboard managers
- Adaptive intervals minimize CPU usage:
  - 100ms when app is active (responsive)
  - 1s when app is in background (battery-friendly)

**Consequences:**
- ✅ Reliable capture of all clipboard changes
- ✅ Adaptive intervals balance responsiveness and efficiency
- ✅ Works for all copy methods (keyboard, menu, drag-drop, programmatic)
- ❌ ~100ms latency (acceptable trade-off)
- ❌ Constant background polling (mitigated by adaptive intervals)

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/PasteboardMonitor/`

---

## ADR-004: AppKit + SwiftUI Hybrid vs Pure SwiftUI

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Need to build a macOS app with overlay window, menu bar integration, and system clipboard access.

**Options Considered:**
1. **Pure SwiftUI** - Modern, declarative
2. **Pure AppKit** - Full system control
3. **Hybrid (AppKit + SwiftUI)** - Best of both

**Decision:** Hybrid (NSPanel + NSMenu with SwiftUI content)

**Rationale:**
- SwiftUI limitations for our use case:
  - No way to create NSPanel-style overlay window (frameless, floating)
  - NSPasteboard requires AppKit
  - Menu bar integration requires NSMenu/NSStatusItem
  - Global hotkeys require CGEventTap (AppKit)
- AppKit provides:
  - NSPanel for overlay window behavior
  - NSPasteboard for clipboard access
  - NSMenu for menu bar
  - Full control over window level, key handling
- SwiftUI provides:
  - Declarative UI for content
  - @FetchRequest for Core Data integration
  - Modern layout and animation
  - Faster development for complex UIs

**Consequences:**
- ✅ Best of both frameworks
- ✅ Full system integration (AppKit)
- ✅ Modern UI development (SwiftUI)
- ❌ Mixing paradigms (requires bridging)
- ❌ Some boilerplate (NSViewRepresentable, NSHostingView)

**References:** `ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayWindow.swift`

---

## ADR-005: Heuristic Classifiers vs Machine Learning

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Need to detect confidential content (passwords, credit cards, API keys) to prevent capturing.

**Options Considered:**
1. **Heuristic pattern matching** - Regex, Luhn algorithm, entropy
2. **Machine Learning** - Train model on sensitive data patterns
3. **Third-party service** - API call to detection service

**Decision:** Heuristic pattern matching

**Rationale:**
- ML trade-offs for MVP:
  - Requires training data (sensitive content collection)
  - Model size overhead (storage, memory)
  - Inference latency (slower than heuristics)
  - Privacy concerns (model trained on user data)
- Heuristic advantages:
  - Fast (<1ms per item)
  - On-device (privacy-preserving)
  - Deterministic (predictable behavior)
  - No training data required
  - Sufficient for 99% of cases
- Implementation:
  - Password detection: Shannon entropy > 3.5
  - Credit cards: Luhn algorithm validation
  - OTP codes: 6-digit patterns
  - API keys: JWT, GitHub token, AWS key patterns

**Consequences:**
- ✅ Fast, privacy-preserving, deterministic
- ✅ No model overhead or training required
- ✅ Sufficient accuracy for MVP
- ❌ May miss edge cases (novel patterns)
- ❌ Potential false positives (high-entropy text)
- 🔄 Can add ML in future if needed

**References:** `ClipboardCore/Sources/BusinessRules/Classifiers/`

---

## ADR-006: SHA-256 Hashing for Deduplication

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Need to prevent duplicate clipboard items from being stored.

**Options Considered:**
1. **SHA-256 hashing** - Cryptographic hash of content
2. **Exact string comparison** - Compare primaryText directly
3. **MD5 hashing** - Faster but less collision-resistant
4. **Perceptual hashing** - For images (pHash)

**Decision:** SHA-256 for text/data, exact comparison for small content

**Rationale:**
- SHA-256 advantages:
  - Collision-resistant (practically zero chance of collision)
  - Fixed size (32 bytes) regardless of content size
  - Fast (CryptoKit optimized, ~0.3ms per hash)
  - Standard across all content types
- Core Data index on `contentHash` enables fast lookup
- Normalization before hashing (trim whitespace, lowercase for case-insensitive)

**Consequences:**
- ✅ Reliable deduplication (no false duplicates)
- ✅ Fast lookup via indexed hash
- ✅ Works for all content types
- ✅ Content-based (not metadata-based)
- ❌ Hash computation overhead (~0.3ms, acceptable)
- ❌ Normalized comparison may merge intentionally different items (rare)

**References:** `ClipboardCore/Sources/DataModel/Extensions/Data+SHA256.swift`

---

## ADR-007: Asset Threshold (256KB)

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Need to decide when to store content in Core Data vs external files.

**Options Considered:**
1. **All in Core Data** - Simple, but bloats database
2. **All in files** - Lightweight database, but more file I/O
3. **Hybrid with threshold** - Small in DB, large in files

**Decision:** Hybrid with 256KB threshold

**Rationale:**
- Core Data SQLite has performance degradation with large BLOBs
- File storage for large assets:
  - Keeps Core Data database lightweight
  - Faster backups (database only, assets separate)
  - Easier CloudKit asset management (CKAsset for files)
- Threshold rationale:
  - Most text items: <10KB (fits in DB)
  - Most RTF/HTML: <100KB (fits in DB)
  - Most screenshots: >500KB (goes to files)
  - 256KB is safe middle ground
- Implementation:
  - `ClipRepresentation.data` for <256KB
  - `ClipRepresentation.assetPath` for ≥256KB (stored via AssetStore)

**Consequences:**
- ✅ Database stays small and fast
- ✅ Large assets don't bloat Core Data
- ✅ CloudKit CKAsset for large files (proper resumable uploads)
- ❌ Two storage locations to manage
- ❌ Orphaned assets possible (mitigated by retention cleanup)

**References:** `ClipboardCore/Sources/Assets/AssetStore.swift`

---

## ADR-008: CGEvent Synthetic Paste vs Pasteboard-Only

**Date:** 2026-01-10  
**Status:** Accepted  
**Context:** Need to paste clipboard items into active applications.

**Options Considered:**
1. **CGEvent Cmd+V simulation** - Send synthetic keyboard event
2. **Pasteboard-only** - Copy to pasteboard, user manually pastes
3. **AppleScript** - Script-based paste
4. **Accessibility API** - Direct text insertion

**Decision:** CGEvent Cmd+V simulation (with Accessibility permission)

**Rationale:**
- Pasteboard-only: Poor UX (requires two-step: select item, then Cmd+V)
- AppleScript: Unreliable, slow, requires per-app scripting
- Accessibility API: Limited to text fields, doesn't work for rich content
- CGEvent advantages:
  - Universal (works in all apps that respond to Cmd+V)
  - Fast (<50ms)
  - Supports all content types (text, images, files)
  - Native feel (indistinguishable from real Cmd+V)
- Implementation:
  1. Copy item to pasteboard
  2. Send CGEvent (keyDown + keyUp for Cmd+V)
  3. Wait 100ms for paste completion
  4. Optionally restore previous pasteboard

**Consequences:**
- ✅ Seamless UX (feels like native paste)
- ✅ Works for all content types
- ✅ Works in all apps
- ❌ Requires Accessibility permission
- ❌ May not work in sandboxed apps (fallback to pasteboard-only)
- ❌ 100ms delay to ensure paste completes

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/PasteEngine/`

---

## ADR-009: Menu Bar App vs Dock App

**Date:** 2026-01-10  
**Status:** Accepted  
**Context:** Decide app presentation style (menu bar, dock, or both).

**Options Considered:**
1. **Menu bar only** - No dock icon (LSUIElement = YES)
2. **Dock only** - Traditional app
3. **Both** - Allow user to choose

**Decision:** Menu bar only (LSUIElement = YES)

**Rationale:**
- Clipboard manager is a utility, not a document-based app
- Menu bar apps:
  - Always accessible (no window switching)
  - Don't clutter dock
  - Standard for utilities (Dropbox, Alfred, Bartender)
- Global hotkey is primary access method (not dock icon)
- Menu bar provides:
  - Quick access to recent items
  - Settings shortcut
  - Sync status indicator

**Consequences:**
- ✅ Always accessible via menu bar
- ✅ Doesn't clutter dock
- ✅ Standard utility app pattern
- ❌ Less discoverable for new users (mitigated by onboarding)
- ❌ No dock badge for notifications (not needed for this app)

**References:** `ClipboardMac/Sources/ClipboardMacApp/App/AppDelegate.swift`

---

## ADR-010: Retention Policy Enforcement

**Date:** 2026-01-10  
**Status:** Accepted  
**Context:** Decide when and how to delete old clipboard items.

**Options Considered:**
1. **Manual only** - User deletes items themselves
2. **Fixed retention** - Auto-delete after 30 days
3. **User-configurable retention** - User chooses policy
4. **Unlimited** - Keep everything forever

**Decision:** User-configurable retention with background cleanup

**Rationale:**
- Users have different needs:
  - Some want short retention (privacy)
  - Some want long-term clipboard history
- Default: 30 days (balances privacy and utility)
- Options: 30 days, 90 days, 1 year, forever
- Implementation:
  - Background cleanup runs daily
  - Respects favorites (never delete)
  - Respects pinned items (never delete)
  - Deletes expired items based on `createdAt` timestamp

**Consequences:**
- ✅ User choice (flexibility)
- ✅ Privacy-friendly default
- ✅ Respects favorites and pins
- ❌ Background cleanup overhead (mitigated: runs daily, ~86ms)
- ❌ Potential data loss if user forgets to favorite

**References:** `ClipboardCore/Sources/BusinessRules/RetentionPolicy.swift`

---

## ADR-011: Swift Package Manager for Modularization

**Date:** 2026-01-09  
**Status:** Accepted  
**Context:** Decide how to structure code for cross-platform sharing.

**Options Considered:**
1. **Swift Package Manager** - Native, local packages
2. **CocoaPods** - Third-party dependency manager
3. **Carthage** - Decentralized dependency manager
4. **Monolithic Xcode project** - All code in one target

**Decision:** Swift Package Manager with local packages

**Rationale:**
- SPM advantages:
  - First-party tool (built into Xcode)
  - Local packages (no need to publish)
  - Cross-platform by default (macOS, iOS, watchOS)
  - Clean module boundaries
  - Fast builds (incremental compilation per package)
- ClipboardCore as SPM package:
  - Can be imported by ClipboardMac (macOS)
  - Future: Import by ClipboardiOS, ClipboardWatch
  - No platform-specific code in Core
- No external dependencies:
  - Reduces supply chain risk
  - Faster builds (no CocoaPods/Carthage overhead)
  - Simpler onboarding

**Consequences:**
- ✅ Clean module separation
- ✅ Cross-platform ready
- ✅ Fast incremental builds
- ✅ No third-party dependency management
- ❌ Xcode workspace required (vs single project)
- ❌ Slightly more setup for new developers

**References:** `docs/CODEBASE.md`, `ClipboardCore/Package.swift`, `ClipboardMac/Package.swift`

---

## ADR-012: OSLog for Logging vs Third-Party

**Date:** 2026-01-15  
**Status:** Accepted  
**Context:** Need structured logging for debugging and crash analysis.

**Options Considered:**
1. **OSLog** - Native Apple logging framework
2. **CocoaLumberjack** - Popular third-party logger
3. **SwiftyBeaver** - Third-party logger with remote features
4. **print() statements** - Simple but limited

**Decision:** OSLog with structured subsystems/categories

**Rationale:**
- OSLog advantages:
  - Native (no dependencies)
  - Integrates with Console.app
  - Structured logging (subsystem, category, levels)
  - Performance-optimized (zero overhead when disabled)
  - Privacy-aware (redacts sensitive data)
- Subsystem: `com.paste.clipboard`
- Categories: `capture`, `paste`, `sync`, `database`, `ui`, `error`
- Log levels: debug, info, error, fault
- No remote logging needed (privacy-first app)

**Consequences:**
- ✅ Native, performant, privacy-aware
- ✅ Integrates with macOS debugging tools
- ✅ Structured logging for easy filtering
- ✅ No third-party dependencies
- ❌ No remote logging/crash service (mitigated: can add Sentry/Crashlytics later if needed)

**References:** `ClipboardMac/Sources/ClipboardMacServices/Services/Logging/Loggers.swift`, `ClipboardMac/Sources/ClipboardMacServices/Services/CrashReporter.swift`

---

## Future ADRs

Topics to document as decisions are made:

- **ADR-013:** In-app purchase architecture (when implemented)
- **ADR-014:** Analytics approach (if added)
- **ADR-015:** Localization strategy (for internationalization)
- **ADR-016:** Accessibility testing approach (VoiceOver automation)
- **ADR-017:** End-to-end encryption (if added for sensitive data)

---

## Changelog

**1.0.0** (2026-02-02)
- Initial ADR document with 12 decisions
- Covers: persistence, sync, monitoring, UI, security, modularization, logging

---

**Maintained By:** Engineering Team  
**Last Updated:** 2026-02-02
