# Clipboard Manager (Paste-like) for macOS

## Technical Specification and Development Documentation (macOS-first, iCloud Sync-ready)

### Document status

* Scope: macOS application only (initial deliverable), with full iCloud synchronization architecture implemented from day one to support future iOS and watchOS clients.
* Reference basis: the user interfaces and behaviors visible in the provided screenshots, plus standard clipboard-manager requirements needed to achieve functional equivalence.

---

## 1. Product scope and constraints

### 1.1 Goals

1. Provide a native macOS clipboard history manager with a global “overlay” UI for browsing, searching, and pasting clipboard items.
2. Support multiple “Pinboards” (named collections) with colors, add/rename/delete, and pinboard navigation.
3. Support “Paste Stack” behavior (multi-item paste workflow).
4. Provide strong privacy controls: ignore specific apps, ignore confidential content, ignore transient content, optional link previews, and screen-sharing visibility control.
5. Implement complete iCloud synchronization (data model, cloud schema, sync engine, conflict strategy, deletion propagation, asset handling) so future iOS/watchOS clients can attach without redesign.

### 1.2 Non-goals (initial macOS milestone)

* Shipping iOS/watchOS apps. Only ensure the cloud and shared code are ready.
* Cloning proprietary branding, assets, or protected UI trade dress. The implementation must be original even if feature-equivalent.

### 1.3 Platform constraints to acknowledge early

* macOS: reading `NSPasteboard.general` is permitted; continuous monitoring is feasible via polling `changeCount`.
* iOS/watchOS (future): continuous clipboard monitoring is not permitted. iOS can read clipboard only in user-driven contexts and will show privacy prompts. Therefore, “full parity” on iOS typically means browsing synced history and copying items to the system clipboard, not silently capturing everything.

---

## 2. Functional capabilities (macOS)

This section describes required capabilities, including those evidenced by the screenshots.

### 2.1 Clipboard capture and history

* Monitor the system pasteboard continuously while enabled.
* Capture at minimum:

  * Plain text
  * Rich text / attributed text (RTF, HTML when available)
  * Images
  * Files (URLs, file promises if feasible, otherwise degrade gracefully)
  * Links (URL strings) with optional metadata previews
* Maintain a time-ordered history with a retention policy:

  * Keep History: Day / Week / Month / Year / Forever (as seen in settings)
* Support manual “Erase History”.

#### Deduplication rules

* Configurable or fixed policy:

  * Avoid storing identical consecutive items (same canonical representation).
  * Optionally merge identical items within a time window.

### 2.2 Pinboards (collections)

Visible UI indicates multiple named pinboards with a color dot and a plus button to create new ones.

Required behavior:

* A default pinboard “Clipboard” representing chronological history.
* User pinboards:

  * Create pinboard
  * Rename pinboard
  * Delete pinboard
  * Assign a color label
* Move/copy items into pinboards (drag-and-drop or context action).
* “Show next pinboard” and “Show previous pinboard” shortcuts (seen in settings).

Optional but recommended (visible in context menu):

* Share Pinboard (see Sync section; implement CloudKit sharing or export-based sharing).

### 2.3 Overlay browser UI (primary interaction model)

Based on screenshots, the app provides a large bottom overlay with:

* Pinboard tabs row (with color dots)
* Horizontal row of item cards
* Search entry point (magnifier icon) and a dedicated search mode with a search field

Required interactions:

* Global hotkey to open overlay (“Activate Paste”: Shift+Command+V as shown).
* Selecting an item triggers one of two paste behaviors (configurable in General settings):

  1. Paste to active app: immediately paste into the previously active application.
  2. Copy to clipboard: put the item onto the system clipboard only.
* Quick Paste: Command + [1..9] (shown) selects/pastes indexed items.
* Plain Text mode:

  * A “Always paste as Plain Text” setting (shown).
  * A shortcut modifier for plain text mode (“Plain Text mode”: Shift as shown). This implies “hold Shift while selecting/pasting” to force plain conversion even if default is rich.
* Paste Stack:

  * Separate activation shortcut (“Activate Paste Stack”: Shift+Command+C as shown).
  * Allows selecting multiple items to paste sequentially or as a combined payload.

### 2.4 Item types, previews, and metadata

For each captured item:

* Display type (Text/Image/etc.) and relative time (for example “Text 3m”, “Image now” as in screenshots).
* Show a preview snippet or thumbnail.
* Maintain a stable identifier for sync and indexing.

Optional but strongly recommended:

* Generate thumbnails for images and file icons.
* For code-like snippets, preserve monospaced preview rendering (without promising syntax highlighting).

### 2.5 Menu bar app and app menu

Screenshots show a menu containing:

* About
* New Text Item (Command+N)
* Settings
* Help
* Pause Paste
* Quit Paste (Command+Q)

Required:

* NSStatusItem in the menu bar.
* Ability to pause/resume clipboard monitoring.
* “New Text Item”: user creates a persistent snippet not sourced from clipboard.

### 2.6 Settings (macOS)

Tabs visible: General, Privacy, Shortcuts, Subscription.

Implement at minimum:

#### General (as seen)

* Open at login (toggle)
* Run in background (toggle)
* iCloud sync (toggle + status “Synced now”)
* Sound effects (toggle)
* Paste Items:

  * To active app
  * To clipboard
  * Always paste as Plain Text (checkbox)
* Keep History slider: Day/Week/Month/Year/Forever
* Erase History button

#### Privacy (as seen)

* Show during screen sharing (toggle)
* Generate link previews (toggle)
* Ignore confidential content (toggle)
* Ignore transient content (toggle)
* Ignore Applications list with add/remove UI (examples shown: Keychain Access, Passwords)

#### Shortcuts (as seen)

* Activate Paste: Shift+Command+V
* Activate Paste Stack: Shift+Command+C
* Show next Pinboard: Command+Right
* Show previous Pinboard: Command+Left
* Quick Paste: Command+[1..9]
* Plain Text mode modifier: Shift
* Reset shortcuts to default

#### “Subscription” tab (your app is paid, no subscription)

Replace the content with “License / Purchase” while keeping the tab structure if you want parity:

* Show purchase status (paid app vs IAP).
* Show restore purchases if applicable (StoreKit 2).

---

## 3. macOS UI implementation specification

### 3.1 Technology choice

* Use SwiftUI for most UI to maximize cross-platform reuse later.
* Use AppKit where required:

  * Global hotkeys (can be done in SwiftUI, but typically requires AppKit-level event monitoring or a dedicated hotkey library).
  * Overlay window behavior (non-activating panel, always-on-top).
  * Accessibility-based “paste to active app”.

Recommended structure:

* SwiftUI views hosted in `NSPanel` via `NSHostingView`.
* A window controller that manages:

  * Opening/closing overlay
  * Capturing frontmost app reference
  * Animations and screen placement

### 3.2 Overlay window behavior (critical)

Requirements:

* Appears above other windows, anchored near bottom.
* Does not steal focus from the previously active app when in “Paste to active app” mode.
* Supports keyboard navigation and selection.

Implementation approach:

* Use a custom `NSPanel` configured as:

  * Floating level (`.floating` or higher if needed)
  * Collection behavior: can appear on all spaces if desired
  * Non-activating if you want the frontmost app to remain active; however you still need keyboard input. Common compromise:

    * Activate overlay for navigation, but record the previously active app and explicitly re-activate it before pasting.
* Track the frontmost application using:

  * `NSWorkspace.shared.frontmostApplication` at the moment the overlay opens.

### 3.3 Pinboard tab bar

* Horizontal list of pinboards with:

  * Title
  * Color dot
  * Plus button to create
  * Context menu: Rename, Share Pinboard, Delete, Color selection

### 3.4 Item card row

* Horizontal scroll view with snap-to-card feel.
* Each card shows:

  * Type + time label (top-left)
  * Preview content
  * Index label (bottom-right) for Quick Paste mapping
  * Optional small “action” icon (context menu trigger)

Card actions:

* Select/paste
* Copy to clipboard
* Move to pinboard
* Delete item (if not in clipboard history policy)
* Pin/unpin (optional)

### 3.5 Search mode

* A search field that filters across:

  * Current pinboard
  * Or all pinboards (define explicit scope)
* The search UI in screenshot suggests a centered search field with results as cards.

Search requirements:

* Incremental results while typing
* Tokenized matching for text
* Optional matching for URL host/title if link previews enabled

---

## 4. System architecture

### 4.1 High-level modules

Create a multi-target Xcode workspace with shared Swift packages.

1. `ClipboardCore` (Swift Package)

   * Data model
   * Persistence abstraction
   * Search index abstraction
   * Sync engine abstraction (CloudKit)
   * Business rules (dedupe, retention, privacy filtering)

2. `ClipboardMac` (macOS app target)

   * Pasteboard monitoring service
   * Overlay UI and settings UI
   * Menu bar integration
   * Accessibility-driven paste injection

3. Future targets (not shipped now, but compile-able skeletons recommended)

   * `ClipboardiOS`
   * `ClipboardWatch`

### 4.2 Data flow overview

1. Pasteboard Monitor detects change.
2. Capture pipeline loads pasteboard items, normalizes representations, applies privacy filters.
3. Persist item locally (database + asset store).
4. Update search index.
5. Enqueue sync change for CloudKit.
6. UI observes local store changes and updates overlay instantly.
7. Sync engine resolves remote changes and merges into local store.

---

## 5. Data model (local)

Use Core Data backed by SQLite, or a custom SQLite schema. For speed and CloudKit compatibility, Core Data is practical.

### 5.1 Entities

#### `ClipItem`

* `id: UUID` (stable across devices)
* `createdAt: Date`
* `sourceAppBundleID: String?`
* `sourceAppName: String?` (cached display)
* `itemType: Enum` (text, richText, image, file, url, mixed)
* `primaryText: String?` (for indexing and previews)
* `hash: String` (canonical hash for dedupe)
* `isSensitive: Bool`
* `isTransient: Bool`
* `needsLinkPreview: Bool`
* Relationships:

  * `representations: [ClipRepresentation]`
  * `pinboards: [Pinboard]` (many-to-many)
  * `stackMemberships: [StackEntry]` (optional)

#### `ClipRepresentation`

Stores multiple flavors of the same logical item.

* `id: UUID`
* `uti: String` (Uniform Type Identifier)
* `kind: Enum` (plainText, rtf, html, png, jpeg, fileURL, url, custom)
* `textData: Data?` (for text formats)
* `assetRef: AssetRef?` (for large binaries)
* `displayOrder: Int`

#### `AssetRef`

* `id: UUID`
* `relativePath: String` (in app sandbox container)
* `byteCount: Int`
* `sha256: String`
* `thumbnailPath: String?`

#### `Pinboard`

* `id: UUID`
* `name: String`
* `color: Enum/Int`
* `sortOrder: Int`
* `isSystemClipboard: Bool`

#### `StackSession` and `StackEntry`

* `StackSession`:

  * `id: UUID`
  * `createdAt: Date`
  * `isActive: Bool`
* `StackEntry`:

  * `id: UUID`
  * `sessionID`
  * `clipItemID`
  * `position: Int`

#### `UserSetting`

Prefer storing settings in `UserDefaults` locally and syncing a subset via CloudKit. Keep minimal settings in the database only if you need transactional sync.

### 5.2 Retention policy

Implement a retention job:

* Periodic cleanup (for example every few hours, plus at launch):

  * Remove items older than the retention window unless pinned to a user pinboard.
  * Remove orphaned assets and thumbnails.
* If “Forever” is selected:

  * Only enforce storage caps if you define them.

---

## 6. Pasteboard capture pipeline (macOS)

### 6.1 Monitoring strategy

Use `NSPasteboard.general.changeCount` polling.

* Poll interval: 250–500 ms is typical; adaptively back off when idle.
* Store `lastChangeCount`.
* When change is detected:

  * Read pasteboard items.
  * Avoid feedback loops by marking when the app itself writes to the pasteboard.

### 6.2 Capture steps

1. Snapshot pasteboard contents:

   * Iterate `NSPasteboard.general.pasteboardItems`.
   * Extract available UTIs.
2. Normalize into a `ClipItem` candidate:

   * Determine `itemType`.
   * Extract best preview text:

     * Prefer plain string
     * Else derive from RTF/HTML by stripping formatting
3. Compute canonical hash:

   * For text: normalized Unicode + trimmed whitespace policy (define explicitly).
   * For images: hash raw bytes.
   * For files: hash file URL string + metadata (or content hash if feasible, but expensive).
4. Apply privacy filters (Section 9).
5. Persist item and assets.
6. Trigger link preview fetch if enabled and candidate is URL-like.

### 6.3 Handling mixed-content pasteboard items

Some copies include multiple representations simultaneously (plain + RTF + HTML). Store them as multiple `ClipRepresentation` linked to one `ClipItem`.

### 6.4 Performance and memory

* Decode heavy formats (RTF, images) off the main thread.
* Generate thumbnails asynchronously.
* Cap thumbnail sizes.

---

## 7. Pasting engine

### 7.1 Paste modes

#### Mode A: Paste to active app

Behavior:

1. Record frontmost app when overlay opens.
2. When user selects an item:

   * Write selected representation to `NSPasteboard.general`.
   * Reactivate the recorded frontmost app.
   * Send synthetic paste keystroke (Command+V), or alternatively use Accessibility APIs to perform a paste command.

Requirements:

* Accessibility permission is typically required to send synthetic keyboard events to other apps.
* Provide onboarding that explains why.

#### Mode B: Copy to clipboard

* Write selected item to `NSPasteboard.general`.
* Do not send keystrokes.

### 7.2 Plain text paste

Rules:

* If “Always paste as Plain Text” enabled, default representation is plain string.
* If user holds the “Plain Text mode” modifier, force plain conversion for that action.
  Conversion:
* From RTF/HTML: strip formatting, keep text content.
* From URL: paste canonical URL string.
* From image/file: no-op or convert to file path string based on policy.

### 7.3 Paste Stack

Two acceptable implementations:

1. Sequential paste:

   * User builds a stack.
   * On confirm, the app pastes each item with a configurable delimiter or delay.
2. Combined payload:

   * Join text items with newline separators.
   * For mixed types, define precedence or restrict stack to text-only.

Given platform complexity, define V1 as text-only sequential paste with a small delay (for example 50–150 ms) and a user-configurable separator.

### 7.4 Quick Paste (Command + 1..9)

* Map visible items to indices.
* If fewer than 9, only active indices work.
* In paste-to-active-app mode, Quick Paste should immediately paste.

---

## 8. iCloud synchronization (implemented now)

### 8.1 iCloud technology choice

Use CloudKit as the authoritative sync transport. Two viable patterns:

1. Direct CloudKit records (recommended for fine control and cross-platform parity)
2. `NSPersistentCloudKitContainer` (recommended for fastest implementation if you commit fully to Core Data and accept its operational model)

For a clipboard manager with assets, pinboards, sharing, and explicit conflict policies, direct CloudKit is usually the more predictable long-term approach.

### 8.2 CloudKit container and databases

* Use a single iCloud container identifier shared across macOS/iOS/watchOS targets.
* Use the private database (`CKContainer.default().privateCloudDatabase`) for user data.
* Create a custom record zone, for example: `ClipboardZone`.

  * Enables change tokens for incremental sync.
  * Improves performance and deletion tracking.

### 8.3 Record types (cloud schema)

Define stable CloudKit record types:

#### `CKClipItem`

Fields:

* `id` (UUID string)
* `createdAt` (Date)
* `sourceAppBundleID` (String)
* `itemType` (Int)
* `primaryText` (String) truncated (for search/display only)
* `hash` (String)
* `isSensitive` (Bool)
* `isTransient` (Bool)
* `deletedAt` (Date?) optional tombstone strategy if needed

#### `CKClipRepresentation`

* `id`
* `clipItemID` (Reference to `CKClipItem`)
* `uti`
* `kind`
* `textData` (Bytes or String for small payloads)
* `asset` (`CKAsset`) for large binaries

#### `CKAssetRef` (optional if you want separate assets)

If you store large binaries separately:

* `id`
* `clipItemID` ref
* `asset` CKAsset
* `sha256`
* `byteCount`

#### `CKPinboard`

* `id`
* `name`
* `color`
* `sortOrder`
* `isSystemClipboard`

#### `CKPinboardMembership`

* `id`
* `clipItemID` ref
* `pinboardID` ref
* `addedAt`

### 8.4 Sync engine responsibilities

Implement a `SyncCoordinator` in `ClipboardCore`:

* Outbound:

  * Observe local database changes (create/update/delete).
  * Batch and push to CloudKit.
  * Upload assets via `CKAsset` (temporary file URLs required).
* Inbound:

  * Fetch zone changes using server change tokens.
  * Apply creates/updates/deletes locally.
  * Download assets on demand (or eagerly for recent items).

### 8.5 Conflict resolution policy

Conflicts can occur when:

* Same item edited on two devices (for example title/name if you add it later).
* Pinboard rename on two devices.

Define deterministic rules:

* Immutable clip items: treat captured items as append-only; do not edit content after creation. This eliminates most conflicts.
* Pinboards: last-writer-wins using `modifiedAt` timestamps, but preserve deletions using tombstones.
* Membership: treat as set union; deletions propagate.

### 8.6 Deletion propagation

CloudKit supports deletion records in zone change fetches. Ensure the local store processes deletions and removes local assets.

### 8.7 Sync toggle behavior

When iCloud Sync is disabled:

* Stop outbound pushes.
* Stop inbound fetches.
* Keep local data intact unless the user explicitly requests a purge.
  When re-enabled:
* Perform a full reconciliation:

  * Fetch latest changes
  * Push missing local items (or choose cloud as source of truth; define a clear rule)

### 8.8 Sharing “Pinboard”

If you want “Share Pinboard” to behave like collaborative sharing:

* Use CloudKit sharing (`CKShare`) on a pinboard record and include membership/child records in the share.
* This requires explicit CloudKit sharing capability and user flow for invitation.

If you want simpler V1 behavior:

* Export pinboard content to a file (JSON + assets) and share via `NSSharingServicePicker`.
* This does not provide live collaboration.

---

## 9. Privacy and security

### 9.1 Ignore applications

Implement an ignore list by bundle identifier:

* Maintain `[String] ignoredBundleIDs`.
* On capture, obtain source app:

  * Use the frontmost app at the moment of copy as an approximation.
  * Note: macOS does not reliably expose the “source app that wrote to pasteboard” in a first-class way; treat this as best-effort.
* If source app is ignored, skip storing.

UI requirements:

* List with icons and app names.
* Add button opens an app picker (NSOpenPanel targeting Applications or use `NSWorkspace` enumeration).
* Remove button deletes from list.

### 9.2 Ignore confidential content

Implement content classifiers (text-only) to mark sensitive and skip saving when enabled:

* Password-like heuristics:

  * High-entropy strings
  * Common password field patterns
  * Length thresholds plus character set diversity
* One-time code heuristics:

  * 6–8 digit codes copied alone
* Credit card heuristics:

  * Luhn check for 13–19 digits
* Private keys/tokens:

  * PEM headers
  * JWT structure (three base64url segments with dots)

Policy:

* If classifier triggers, either:

  * Do not save at all (matches screenshot intent), or
  * Save as redacted stub (not recommended given screenshot wording).

### 9.3 Ignore transient content

Implement a “do not store ephemeral items” rule:

* Detect known transient pasteboard types when available.
* Maintain a denylist of UTIs or marker types encountered in practice.
* Provide telemetry-free logging (local only) during development to identify transient markers.

### 9.4 Link previews

When enabled:

* If a captured item is URL-like, fetch metadata with `LPMetadataProvider`:

  * Title, icon, image
* Store preview metadata and cached thumbnail.
  When disabled:
* Do not perform network fetches.

### 9.5 Show during screen sharing

Implement a privacy display mode:

* When disabled, the overlay should be hidden or replaced with a neutral placeholder if you detect screen capture.
  Detection options:
* Best-effort public checks (not always reliable).
* Provide manual override:

  * A “panic hide” shortcut that instantly hides the overlay regardless of detection.

### 9.6 Data at rest

Minimum:

* Rely on macOS file protection and sandbox container.
  Recommended:
* Encrypt stored assets with a per-user key stored in Keychain if you intend to protect clipboard history beyond OS-level encryption.

---

## 10. Background operation, login, and lifecycle

### 10.1 Open at login

Use `SMAppService` (modern replacement for legacy login items) to register/unregister.

### 10.2 Run in background

Define precisely what this toggle means, because LSUIElement cannot be toggled at runtime cleanly.

Recommended definition:

* When enabled:

  * The capture service runs continuously.
  * App stays resident after closing any windows.
* When disabled:

  * The capture service stops when the UI is closed.
  * The app may terminate automatically.

Alternatively, ship two helpers:

* A background agent (menu bar, LSUIElement=1)
* A settings app
  This is more complex but cleaner.

### 10.3 Sound effects

* Play short feedback sounds for:

  * Capture event (optional)
  * Paste confirmation
* Respect system volume and Do Not Disturb behavior.

---

## 11. Permissions and entitlements (macOS App Store)

### 11.1 Required capabilities

* iCloud (CloudKit)
* App Sandbox

### 11.2 Likely required user-granted permissions

* Accessibility permission if you implement “paste to active app” via synthetic events or UI scripting.
* Possibly Input Monitoring depending on implementation of global hotkeys and event taps.

Onboarding must:

* Explain what is collected and why.
* Provide a direct link to System Settings panels when possible.

---

## 12. Testing strategy

### 12.1 Unit tests

* Canonical hashing and dedupe
* Sensitive-content classifier
* Retention cleanup logic
* Serialization/deserialization of representations

### 12.2 Integration tests (macOS)

* Pasteboard capture with synthetic pasteboard writes
* Asset storage and thumbnail generation
* Search indexing correctness

### 12.3 CloudKit tests

* Use a development CloudKit environment.
* Automated tests should run with CloudKit mocked or abstracted behind a protocol to avoid flakiness.

### 12.4 UI tests

* Overlay open/close
* Pinboard navigation shortcuts
* Quick Paste mapping

---

## 13. Distribution and paid model

Given the requirement “paid, no subscription”:

* Preferred: paid app on the Mac App Store (simplest).
* Alternative: free app + one-time non-consumable IAP unlock (StoreKit 2). This is useful if you want trials.

If you keep a “Subscription” settings tab for UI parity, rename the contents to “Purchase” and show:

* Ownership status
* Restore purchases
* Receipt validation strategy (local receipt validation is typical; server-side optional)

---

## 14. Implementation plan (macOS-first, sync-ready)

### Phase 1: Core foundation

* `ClipboardCore` package with data model, persistence, hashing, retention.
* Basic pasteboard monitor that stores text only.
* Minimal overlay UI listing recent items.

### Phase 2: Full capture and UI parity

* Rich text + image + file capture.
* Card previews and time/type labels.
* Pinboards and tab bar management.
* Search mode UI and indexing.
* Menu bar menu + pause.

### Phase 3: Paste behaviors

* Paste to active app mode with Accessibility-based paste injection.
* Quick Paste 1..9.
* Plain text mode and modifier behavior.
* Paste Stack.

### Phase 4: Privacy and settings

* General/Privacy/Shortcuts settings panels.
* Ignored apps list.
* Confidential/transient filters.
* Link previews toggle + metadata fetching.

### Phase 5: CloudKit sync complete

* Cloud schema deployment.
* Full outbound/inbound sync with tokens.
* Asset upload/download strategy.
* Deletion propagation and conflict policies.
* Sync status UI (“Synced now”).

### Phase 6: Hardening

* Performance profiling
* Database migration strategy
* Crash resilience, recovery, and data integrity checks

---

## 15. Future iOS and watchOS integration (design-ready now)

Even though you are not shipping these yet, the cloud and core model must support:

* iOS client:

  * Browse synced items
  * Search
  * Copy selected item to iOS clipboard (user-driven)
  * Optional share extension to save content into the database
* watchOS client:

  * Browse recent items (small subset)
  * Copy-to-clipboard is not a watch concept; instead:

    * Show text snippets for reference
    * Handoff to iPhone/macOS for paste

This implies:

* The sync engine must support partial download (for watch).
* The data model must allow “lightweight” representations for small screens (primaryText, thumbnail).

---

## Appendix A: Shortcut defaults (from screenshots)

* Activate Paste: Shift+Command+V
* Activate Paste Stack: Shift+Command+C
* Show next Pinboard: Command+Right
* Show previous Pinboard: Command+Left
* Quick Paste: Command + [1..9]
* Plain Text mode modifier: Shift

---

## Appendix B: Key engineering risks to manage early

1. Source application attribution for clipboard entries is not guaranteed by public APIs; treat ignore-app behavior as best-effort and document it.
2. Paste injection requires Accessibility permission and careful focus management; implement robust fallbacks.
3. CloudKit asset sync can become expensive; design storage caps, lazy downloads, and thumbnail-first UI.
4. iOS clipboard constraints prevent true background capture; ensure your product definition for iOS/watch is “synced library” rather than “always-recording clipboard.”
