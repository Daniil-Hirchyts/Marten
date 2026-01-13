# Data Model Specification
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.0.0
- **Last Updated:** 2026-01-09
- **Status:** Draft
- **Owner:** Engineering Team
- **Dependencies:** 
  - `Architecture-Overview.md` (parent)
  - `Cloud-Schema-Spec.md` (sync compatibility)

---

## 1. Purpose and Scope

This document defines the complete local data model for the Paste Clipboard Manager. It specifies Core Data entities, attributes, relationships, validation rules, and migration strategies.

### 1.1 Goals

1. **Completeness:** Model all captured clipboard data types
2. **Efficiency:** Support fast queries for UI rendering (<100ms)
3. **Sync-ready:** Map cleanly to CloudKit schema
4. **Extensibility:** Allow future content types without breaking changes

### 1.2 Technology Choice

**Primary:** Core Data with SQLite persistent store

**Rationale:**
- Native CloudKit integration via `NSPersistentCloudKitContainer` (if needed)
- Mature migration tooling
- SwiftUI integration via `@FetchRequest`
- Relationship management and cascade rules

---

## 2. Core Data Stack Configuration

### 2.1 Persistent Store Setup

```swift
// Configuration Summary
Store Type: NSSQLiteStoreType
Location: Application Support/com.yourcompany.Paste/Paste.sqlite
Backup: Excluded from iCloud backup (CloudKit handles sync)
WAL Mode: Enabled (for concurrent reads)
```

### 2.2 Context Architecture

```
┌─────────────────────────────────────┐
│   ViewContext (Main Thread)         │
│   - UI reads only                   │
│   - Fast fetch requests             │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│   PersistentStoreCoordinator        │
└─────────────────────────────────────┘
                ↑
┌─────────────────────────────────────┐
│   BackgroundContext                 │
│   - Capture pipeline writes         │
│   - Sync operations                 │
│   - Cleanup jobs                    │
└─────────────────────────────────────┘
```

---

## 3. Entity Definitions

### 3.1 ClipItem

**Description:** Represents a single clipboard capture event

#### Attributes

| Name | Type | Optional | Default | Indexed | Notes |
|------|------|----------|---------|---------|-------|
| `id` | UUID | No | UUID() | Yes (Primary) | Stable across devices |
| `createdAt` | Date | No | Date() | Yes | Capture timestamp |
| `modifiedAt` | Date | No | Date() | No | Last update time |
| `displayOrder` | Int64 | No | 0 | No | Manual/recency sort order |
| `sourceAppBundleID` | String | Yes | nil | Yes | e.g. "com.apple.Safari" |
| `sourceAppName` | String | Yes | nil | No | Display name cache |
| `itemType` | Int16 | No | 0 | Yes | Enum: ItemType |
| `primaryText` | String | Yes | nil | No | Preview/search text (max 10k chars) |
| `searchableText` | String | Yes | nil | No | Normalized for search |
| `contentHash` | String | No | "" | Yes (Unique) | Canonical content hash |
| `isSensitive` | Bool | No | false | Yes | Privacy flag |
| `isTransient` | Bool | No | false | No | Ephemeral content flag |
| `needsLinkPreview` | Bool | No | false | No | URL preview pending |
| `thumbnailPath` | String | Yes | nil | No | Relative path to thumbnail |
| `byteCount` | Int64 | No | 0 | No | Total size of representations |
| `isUserCreated` | Bool | No | false | No | "New Text Item" vs captured |
| `isPinned` | Bool | No | false | Yes | Quick-access flag |

#### Relationships

| Name | Destination | Cardinality | Delete Rule | Inverse |
|------|-------------|-------------|-------------|---------|
| `representations` | ClipRepresentation | One-to-Many | Cascade | `clipItem` |
| `pinboards` | Pinboard | Many-to-Many | Nullify | `items` |
| `stackEntries` | StackEntry | One-to-Many | Nullify | `clipItem` |
| `linkPreview` | LinkPreview | One-to-One (Optional) | Cascade | `clipItem` |

#### Validation Rules

```swift
// Content hash must be non-empty
validate(contentHash: String) -> Bool {
    return !contentHash.isEmpty && contentHash.count == 64 // SHA-256 hex
}

// CreatedAt must not be in future
validate(createdAt: Date) -> Bool {
    return createdAt <= Date()
}

// ByteCount must be non-negative
validate(byteCount: Int64) -> Bool {
    return byteCount >= 0
}
```

#### Computed Properties

```swift
extension ClipItem {
    var relativeTimeString: String {
        // "now", "3m", "2h", "1d", "Jan 5"
    }
    
    var typeDisplayString: String {
        // "Text", "Image", "File", "Code"
    }
    
    var hasMultipleRepresentations: Bool {
        return (representations?.count ?? 0) > 1
    }
}
```

---

### 3.2 ClipRepresentation

**Description:** Stores a single format/flavor of a ClipItem (e.g., plain text, RTF, PNG)

#### Attributes

| Name | Type | Optional | Default | Indexed | Notes |
|------|------|----------|---------|---------|-------|
| `id` | UUID | No | UUID() | Yes (Primary) | Stable ID |
| `uti` | String | No | "" | Yes | Uniform Type Identifier |
| `kind` | Int16 | No | 0 | Yes | Enum: RepresentationKind |
| `displayOrder` | Int16 | No | 0 | No | Sort priority (0 = primary) |
| `textData` | Data | Yes | nil | No | For text formats (UTF-8) |
| `binaryData` | Data | Yes | nil | No | For small binaries (<1MB) |
| `assetRef` | UUID | Yes | nil | Yes | Reference to external file |
| `fileExtension` | String | Yes | nil | No | e.g. "png", "txt" |
| `byteCount` | Int64 | No | 0 | No | Size of data/asset |

#### Relationships

| Name | Destination | Cardinality | Delete Rule | Inverse |
|------|-------------|-------------|-------------|---------|
| `clipItem` | ClipItem | Many-to-One | Nullify | `representations` |

#### Enums

```swift
enum RepresentationKind: Int16 {
    case plainText = 0
    case rtf = 1
    case html = 2
    case markdown = 3
    case png = 10
    case jpeg = 11
    case tiff = 12
    case pdf = 20
    case fileURL = 30
    case url = 31
    case custom = 99
}
```

#### Validation Rules

```swift
// Must have exactly one of: textData, binaryData, or assetRef
validate() -> Bool {
    let count = [textData, binaryData, assetRef]
        .compactMap { $0 }
        .count
    return count == 1
}

// UTI must be valid
validate(uti: String) -> Bool {
    return !uti.isEmpty && uti.contains(".")
}
```

---

### 3.3 Pinboard

**Description:** Named collection of clips (like folders/tags)

#### Attributes

| Name | Type | Optional | Default | Indexed | Notes |
|------|------|----------|---------|---------|-------|
| `id` | UUID | No | UUID() | Yes (Primary) | Stable across devices |
| `name` | String | No | "" | No | User-visible name |
| `colorHex` | String | No | "#808080" | No | Hex color code |
| `sortOrder` | Int16 | No | 0 | Yes | Display order |
| `isSystemClipboard` | Bool | No | false | Yes | True for "Clipboard" default |
| `createdAt` | Date | No | Date() | No | Creation timestamp |
| `iconName` | String | Yes | nil | No | SF Symbol name (optional) |
| `shareToken` | String | Yes | nil | No | CloudKit share reference |

#### Relationships

| Name | Destination | Cardinality | Delete Rule | Inverse |
|------|-------------|-------------|-------------|---------|
| `items` | ClipItem | Many-to-Many | Nullify | `pinboards` |

#### Validation Rules

```swift
// Name must be non-empty and unique
validate(name: String) -> Bool {
    return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

// System clipboard cannot be deleted
validate(isSystemClipboard: Bool) -> Bool {
    // Enforce in business logic, not Core Data
}

// ColorHex must be valid
validate(colorHex: String) -> Bool {
    return colorHex.matches(regex: "^#[0-9A-Fa-f]{6}$")
}
```

#### Computed Properties

```swift
extension Pinboard {
    var itemCount: Int {
        return items?.count ?? 0
    }
    
    var color: NSColor/UIColor {
        return Color(hex: colorHex) ?? .gray
    }
}
```

---

### 3.4 StackSession

**Description:** Represents a Paste Stack workflow session

#### Attributes

| Name | Type | Optional | Default | Indexed | Notes |
|------|------|----------|---------|---------|-------|
| `id` | UUID | No | UUID() | Yes (Primary) | Stable ID |
| `createdAt` | Date | No | Date() | Yes | Session start |
| `isActive` | Bool | No | true | Yes | Currently building |
| `separator` | String | No | "\n" | No | Text join separator |
| `mode` | Int16 | No | 0 | No | Enum: StackMode |

#### Relationships

| Name | Destination | Cardinality | Delete Rule | Inverse |
|------|-------------|-------------|-------------|---------|
| `entries` | StackEntry | One-to-Many | Cascade | `session` |

#### Enums

```swift
enum StackMode: Int16 {
    case sequential = 0  // Paste one at a time
    case combined = 1     // Join and paste as one
}
```

---

### 3.5 StackEntry

**Description:** Links a ClipItem to a StackSession with ordering

#### Attributes

| Name | Type | Optional | Default | Indexed | Notes |
|------|------|----------|---------|---------|-------|
| `id` | UUID | No | UUID() | Yes (Primary) | Stable ID |
| `position` | Int16 | No | 0 | Yes | Sort order in stack |
| `addedAt` | Date | No | Date() | No | When added to stack |

#### Relationships

| Name | Destination | Cardinality | Delete Rule | Inverse |
|------|-------------|-------------|-------------|---------|
| `session` | StackSession | Many-to-One | Nullify | `entries` |
| `clipItem` | ClipItem | Many-to-One | Nullify | `stackEntries` |

---

### 3.6 LinkPreview

**Description:** Cached metadata for URL items

#### Attributes

| Name | Type | Optional | Default | Indexed | Notes |
|------|------|----------|---------|---------|-------|
| `id` | UUID | No | UUID() | Yes (Primary) | Stable ID |
| `url` | String | No | "" | No | Original URL |
| `title` | String | Yes | nil | No | Page title |
| `summary` | String | Yes | nil | No | Description/excerpt |
| `imageURL` | String | Yes | nil | No | Preview image URL |
| `imagePath` | String | Yes | nil | No | Cached image local path |
| `siteName` | String | Yes | nil | No | e.g. "GitHub" |
| `fetchedAt` | Date | No | Date() | No | When metadata was fetched |
| `fetchFailed` | Bool | No | false | No | Fetch error flag |

#### Relationships

| Name | Destination | Cardinality | Delete Rule | Inverse |
|------|-------------|-------------|-------------|---------|
| `clipItem` | ClipItem | One-to-One | Nullify | `linkPreview` |

---

### 3.7 UserSetting (Optional Entity)

**Note:** Most settings should be in `UserDefaults`. Use this entity only for settings that need sync or transactions.

#### Attributes

| Name | Type | Optional | Default | Indexed | Notes |
|------|------|----------|---------|---------|-------|
| `key` | String | No | "" | Yes (Unique) | Setting identifier |
| `value` | String | Yes | nil | No | JSON-encoded value |
| `modifiedAt` | Date | No | Date() | No | Last update |

---

## 4. Indexes and Performance

### 4.1 Required Indexes

```swift
// ClipItem
index on: [createdAt DESC]           // Timeline queries
index on: [contentHash]              // Duplicate detection
index on: [sourceAppBundleID, createdAt DESC]  // Filtered timeline
index on: [isPinned DESC, createdAt DESC]      // Pinned first
compound index on: [itemType, createdAt DESC]  // Type filtering

// ClipRepresentation
index on: [clipItem, displayOrder]   // Ordered fetch

// Pinboard
index on: [sortOrder, name]          // UI display order

// StackEntry
index on: [session, position]        // Stack ordering
```

### 4.2 Fetch Request Optimization

```swift
// Example: Recent items for overlay
fetchRequest.predicate = NSPredicate(
    format: "isTransient == NO AND createdAt > %@",
    Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
)
fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
fetchRequest.fetchLimit = 100
fetchRequest.relationshipKeyPathsForPrefetching = ["representations", "pinboards"]
```

### 4.3 Performance Budgets

| Operation | Target | Limit |
|-----------|--------|-------|
| Insert single item | <10ms | 50ms |
| Fetch 100 recent items | <50ms | 100ms |
| Search query | <100ms | 250ms |
| Delete with cascade | <20ms | 100ms |

---

## 5. Data Lifecycle

### 5.1 Creation Flow

```
1. PasteboardMonitor detects change
2. Create ClipItem in background context
3. Compute canonical hash from primary representation
4. Check for duplicate (fetch by contentHash)
5. If duplicate: update modifiedAt, skip
6. If new: Create ClipRepresentation(s)
7. Add to system "Clipboard" pinboard
8. Save context
9. Post notification for UI update
10. Enqueue for sync
```

### 5.2 Retention Policy

**Implementation:** Background scheduled task (every 6 hours + at launch)

```swift
func cleanupExpiredItems() {
    let retentionDate = calculateRetentionDate() // Based on user setting
    
    let fetchRequest = ClipItem.fetchRequest()
    fetchRequest.predicate = NSPredicate(
        format: "createdAt < %@ AND pinboards.@count == 0 AND isPinned == NO",
        retentionDate as NSDate
    )
    
    let expired = try context.fetch(fetchRequest)
    
    for item in expired {
        // Delete external assets
        deleteAssets(for: item)
        
        // Delete entity (cascade to representations)
        context.delete(item)
    }
    
    try context.save()
}
```

**Retention Options (from settings):**
- Day: 24 hours
- Week: 7 days
- Month: 30 days
- Year: 365 days
- Forever: No automatic deletion

**Protection Rules:**
- Items in user pinboards are never auto-deleted
- Pinned items are never auto-deleted
- User-created items (not captured) are never auto-deleted

### 5.3 Deletion Rules

```
ClipItem deleted:
  → Cascade delete all ClipRepresentations
  → Cascade delete LinkPreview
  → Cascade delete StackEntry references
  → Nullify Pinboard relationships
  → Manually delete external assets (AssetManager)
  
Pinboard deleted:
  → Nullify all ClipItem relationships (items remain)
  → Prevent if isSystemClipboard == true
  
StackSession deleted:
  → Cascade delete all StackEntry records
  → Nullify ClipItem references
```

---

## 6. Asset Management

### 6.1 File-Based Assets

**Location:**
```
Application Support/com.yourcompany.Paste/
  ├── Paste.sqlite
  ├── Assets/
  │   ├── {UUID}.png         # Image representations
  │   ├── {UUID}.rtf         # Rich text files
  │   └── {UUID}.bin         # Generic binaries
  └── Thumbnails/
      └── {UUID}_thumb.png   # Generated thumbnails
```

### 6.2 Storage Strategy

| Representation Type | Storage | Threshold |
|---------------------|---------|-----------|
| Plain text | `textData` (Data) | < 1 MB |
| Rich text (RTF) | `textData` or file | > 100 KB → file |
| HTML | `textData` or file | > 100 KB → file |
| Images | File always | > 10 KB |
| PDFs | File always | Any size |
| File URLs | `textData` (path string) | N/A |

### 6.3 Thumbnail Generation

**Rules:**
- Generate for images, PDFs, file icons
- Max size: 512x512 @ 2x (Retina)
- Format: PNG with alpha
- Background thread only
- Cache on disk

**Implementation:**
```swift
func generateThumbnail(for item: ClipItem) async throws -> String {
    guard item.itemType == .image || item.itemType == .file else {
        throw ThumbnailError.unsupportedType
    }
    
    let thumbnail = try await ThumbnailGenerator.create(
        from: item.primaryRepresentation,
        maxSize: CGSize(width: 512, height: 512)
    )
    
    let path = "Thumbnails/\(item.id.uuidString)_thumb.png"
    try thumbnail.png?.write(to: assetURL(for: path))
    
    return path
}
```

### 6.4 Orphan Cleanup

**Trigger:** During retention cleanup + manual "Erase History"

```swift
func cleanupOrphanedAssets() {
    let allAssetRefs = fetchAllAssetRefs() // From DB
    let filesOnDisk = listAssetDirectory()
    
    let orphans = filesOnDisk.filter { !allAssetRefs.contains($0) }
    
    for orphan in orphans {
        try? FileManager.default.removeItem(at: orphan)
    }
}
```

---

## 7. Search Implementation

### 7.1 Search Index

**Approach:** Core Data NSPredicate + optional in-memory index for speed

**Indexed Fields:**
- `primaryText` (contains, case-insensitive)
- `searchableText` (normalized: lowercased, diacritics removed)
- `sourceAppName`
- `itemType`

### 7.2 Search Query Syntax

```swift
// User query: "swift code"
predicate = NSPredicate(format: "searchableText CONTAINS[cd] %@", "swift code")

// Advanced: Scoped to pinboard
predicate = NSPredicate(
    format: "searchableText CONTAINS[cd] %@ AND ANY pinboards.id == %@",
    query, pinboardID
)

// Filter by type
predicate = NSPredicate(format: "itemType == %d", ItemType.code.rawValue)
```

### 7.3 Search Performance

**Target:** <100ms for 10,000 items

**Optimizations:**
1. Limit results to 50 initially (pagination)
2. Prefetch relationships
3. Use `fetchBatchSize = 20`
4. Consider full-text search extension for large datasets

---

## 8. Phase-Specific Implementation Tasks

### Phase 1: Core Foundation (Weeks 1-3)

**Data Model Tasks:**
- [x] Define Core Data model file (.xcdatamodeld)
- [x] Create `ClipItem` entity with basic attributes
- [x] Create `ClipRepresentation` entity
- [x] Create `Pinboard` entity
- [x] Set up Core Data stack in `ClipboardCore`
- [x] Implement basic CRUD operations
- [x] Add text-only item creation
- [x] Implement contentHash-based deduplication
- [x] Add unit tests for data model

**Implementation Notes:**
- Attribute name is `contentHash` in the shipped model to avoid `NSObject.hash` collisions
- SwiftPM bundles a precompiled `Paste.momd` (manual `momc` until automated)

**Success Criteria:**
- Can insert 1000 items in <1s
- Fetch recent 100 items in <50ms
- Hash collision rate: 0%
  
**Status Notes:**
- Persistence across restarts validated via XCTest
- Performance targets and hash-collision rate are not yet benchmarked

**Code Deliverables:**
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

---

### Phase 2: Full Capture & UI Parity (Weeks 4-6)

**Data Model Tasks:**
- [x] Add `LinkPreview` entity
- [x] Add `thumbnailPath` to ClipItem (present in model)
- [x] Implement asset file storage (AssetStore + thresholded binary storage)
- [x] Add thumbnail generation pipeline (image payloads generate thumbnails)
- [x] Create pinboard CRUD operations (ClipItemStore)
- [x] Implement many-to-many pinboard relationships (model relationships in place)
- [x] Add search indexing (searchableText generation)
- [x] Create fetch requests for UI components (recent items + search)

**Success Criteria:**
- Support all content types (text, image, RTF, URL)
- Thumbnails generate in <500ms
- Pinboard operations complete in <20ms

---

### Phase 3: Paste Behaviors (Weeks 7-8)

**Data Model Tasks:**
- [x] Create `StackSession` entity
- [x] Create `StackEntry` entity
- [x] Implement stack CRUD operations (StackSessionStore)
- [x] Add `isPinned` flag to ClipItem
- [x] Create specialized fetch requests for Quick Paste (reuse `fetchRecentItems`)

**Success Criteria:**
- Stack with 50 items performs adequately
- Pinned items persist across app restarts

---

### Phase 4: Privacy & Settings (Weeks 9-10)

**Data Model Tasks:**
- [ ] Add `isSensitive` classifier results to ClipItem
- [ ] Add `isTransient` detection flags
- [ ] Implement filtered fetch requests (exclude sensitive)
- [ ] Add `sourceAppBundleID` indexing
- [ ] Create retention policy cleanup job
- [ ] Test edge cases (large datasets, boundary conditions)

**Success Criteria:**
- Sensitive items correctly flagged
- Retention cleanup runs without errors
- Ignored apps are not captured

---

### Phase 5: CloudKit Sync (Weeks 11-14)

**Data Model Tasks:**
- [ ] Add CloudKit sync metadata fields (ckRecordID, modifiedAt)
- [ ] Implement NSPersistentCloudKitContainer integration OR
- [ ] Implement custom CloudKit mapping layer
- [ ] Add conflict resolution logic
- [ ] Handle deletion propagation
- [ ] Test bidirectional sync

**Success Criteria:**
- Changes sync within 10s
- No data loss during conflicts
- Deletions propagate correctly

**Note:** See `Cloud-Schema-Spec.md` for CloudKit-specific details

---

### Phase 6: Hardening & Performance (Weeks 15-16)

**Data Model Tasks:**
- [ ] Profile fetch requests with Instruments
- [ ] Optimize slow queries
- [ ] Add missing indexes
- [ ] Implement database migration tests
- [ ] Create v1.0 → v1.1 migration mapping model
- [ ] Load test with 10,000+ items
- [ ] Validate data integrity on startup

**Success Criteria:**
- All queries meet performance budgets
- Migration succeeds 100% of the time
- No crashes under load

---

## 9. Migration Strategy

### 9.1 Versioning

Use Core Data lightweight migrations when possible, heavyweight when necessary.

**Version Naming:**
- `Paste_v1.xcdatamodel` (Initial release)
- `Paste_v2.xcdatamodel` (First update with new fields)
- `Paste_v3.xcdatamodel` (etc.)

### 9.2 Migration Rules

**Lightweight (automatic):**
- Adding new optional attributes
- Adding new entities
- Changing optional → required with default value
- Renaming with mapping

**Heavyweight (manual):**
- Changing attribute types
- Refactoring relationships
- Data transformations

### 9.3 Migration Testing

```swift
func testMigrationFromV1ToV2() throws {
    // Load v1 store
    let v1Store = loadFixture("TestStore_v1.sqlite")
    
    // Perform migration
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v2Model)
    let options = [NSMigratePersistentStoresAutomaticallyOption: true]
    let store = try coordinator.addPersistentStore(
        ofType: NSSQLiteStoreType,
        configurationName: nil,
        at: v1Store,
        options: options
    )
    
    // Validate data
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    
    let items = try context.fetch(ClipItem.fetchRequest())
    XCTAssertEqual(items.count, expectedCount)
    // ... more assertions
}
```

---

## 10. Open Questions

### 10.1 Decisions Needed

1. **Full-Text Search:** Use Core Data predicates or integrate `CSSearchableIndex`?
   - **Recommendation:** Start with Core Data, migrate to Spotlight if needed
   
2. **Asset Size Limits:** Should we cap individual asset sizes?
   - **Recommendation:** 50 MB per item, warn user if exceeded

3. **Pinboard Limits:** Maximum number of pinboards?
   - **Recommendation:** 50 pinboards (UI constraint)

### 10.2 Future Enhancements

- [ ] Tags (in addition to pinboards)
- [ ] Smart pinboards (dynamic filters)
- [ ] Item annotations/notes
- [ ] Version history per item
- [ ] Encryption at rest (per-item key)

---

## 11. Validation Checklist

Before marking Phase 1 complete:

- [x] All entities compile without errors
- [x] Relationships have correct delete rules
- [x] All required indexes are defined
- [ ] Unit tests cover basic CRUD operations
- [x] Sample data can be inserted and queried
- [ ] No force-unwraps in model code
- [ ] Documentation comments on all entities
- [ ] Migration path from empty DB is tested

**Notes:**
- CRUD tests cover create/fetch/delete paths; update-specific tests are still missing

---

## 12. Appendix: Example Code

### 12.1 Creating a ClipItem

```swift
func createClipItem(
    from pasteboard: NSPasteboard,
    in context: NSManagedObjectContext
) throws -> ClipItem {
    let item = ClipItem(context: context)
    item.id = UUID()
    item.createdAt = Date()
    item.modifiedAt = Date()
    
    // Extract text
    if let string = pasteboard.string(forType: .string) {
        item.primaryText = String(string.prefix(10000))
        item.searchableText = string.normalized()
        item.itemType = .text
        
        // Create plain text representation
        let rep = ClipRepresentation(context: context)
        rep.id = UUID()
        rep.uti = "public.utf8-plain-text"
        rep.kind = .plainText
        rep.textData = string.data(using: .utf8)
        rep.displayOrder = 0
        item.addToRepresentations(rep)
    }
    
    // Compute canonical hash
    item.contentHash = try item.computeCanonicalHash()
    
    // Add to default pinboard
    let clipboard = try fetchSystemClipboardPinboard(in: context)
    item.addToPinboards(clipboard)
    
    try context.save()
    return item
}
```

### 12.2 Fetching Recent Items

```swift
func fetchRecentItems(
    limit: Int = 100,
    in context: NSManagedObjectContext
) throws -> [ClipItem] {
    let request = ClipItem.fetchRequest()
    request.predicate = NSPredicate(format: "isTransient == NO")
    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
    request.fetchLimit = limit
    request.relationshipKeyPathsForPrefetching = ["representations", "pinboards"]
    
    return try context.fetch(request)
}
```

---

## 13. Changelog

### Version 1.0.0 (2026-01-09)
- Initial data model specification
- Defined 7 core entities
- Specified indexes and performance targets
- Outlined phase-specific tasks

---

**Related Documents:**
- [Architecture Overview](./Architecture-Overview.md)
- [Cloud Schema Spec](./Cloud-Schema-Spec.md) - Maps to CloudKit types
- [macOS Services Spec](./macOS-Services-Spec.md) - Data producers/consumers
