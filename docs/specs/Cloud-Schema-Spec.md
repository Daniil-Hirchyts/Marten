# Cloud Schema Specification
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.0.0
- **Last Updated:** 2026-01-09
- **Status:** Draft
- **Owner:** Engineering Team
- **Dependencies:** 
  - `Architecture-Overview.md` (parent)
  - `Data-Model-Spec.md` (local model mapping)

---

## 1. Purpose and Scope

This document defines the complete CloudKit schema, synchronization engine, conflict resolution policies, and operational procedures for the Paste Clipboard Manager's iCloud sync feature.

### 1.1 Goals

1. **Seamless sync:** Changes appear on all devices within 10 seconds
2. **Zero data loss:** Conflicts resolve deterministically without user data loss
3. **Efficient:** Minimize network usage and CloudKit operation costs
4. **Cross-platform ready:** iOS and watchOS can use the same schema
5. **Privacy-preserving:** Sync respects user privacy settings

### 1.2 Technology Choice

**Primary:** CloudKit (CKContainer, CKDatabase, CKRecord)

**Why CloudKit:**
- Native iOS/macOS/watchOS integration
- Free tier sufficient for individual users
- Built-in conflict detection
- CKAsset for large binary handling
- CKShare for pinboard collaboration (future)

**Alternative Considered:** NSPersistentCloudKitContainer
- **Decision:** Use direct CloudKit APIs for fine-grained control
- **Rationale:** Better error handling, custom conflict resolution, explicit asset management

---

## 2. CloudKit Container Configuration

### 2.1 Container Setup

```
Container Identifier: iCloud.com.yourcompany.Paste
Environment: Development / Production
Capabilities:
  - Private Database (user data)
  - Public Database (future: shared pinboard templates)
  - CloudKit Database (enabled)
  - Push Notifications (for sync triggers)
```

### 2.2 Database Structure

```
┌────────────────────────────────────────┐
│         CKContainer.default()          │
├────────────────────────────────────────┤
│  ┌──────────────────────────────────┐  │
│  │   Private Database               │  │
│  │   - User's clipboard history     │  │
│  │   - Pinboards                    │  │
│  │   - Settings                     │  │
│  └──────────────────────────────────┘  │
│  ┌──────────────────────────────────┐  │
│  │   Custom Zone: "ClipboardZone"   │  │
│  │   - Enables change tokens        │  │
│  │   - Better batch operations      │  │
│  │   - Deletion tracking            │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

### 2.3 Custom Zone Benefits

**Why use a custom zone:**
- Change token support (incremental sync)
- Atomic batch operations
- Reliable deletion tracking
- Better conflict detection

**Setup:**
```swift
let zone = CKRecordZone(zoneName: "ClipboardZone")
try await privateDatabase.save(zone)
```

---

## 3. CloudKit Record Types

### 3.1 CKClipItem

**Purpose:** Represents a captured clipboard item

#### Fields

| Field Name | Type | Indexed | Searchable | Notes |
|------------|------|---------|------------|-------|
| `recordID` | String | Auto | No | Format: `ClipItem-{UUID}` |
| `id` | String | Yes | No | Matches local ClipItem.id |
| `createdAt` | Date | Yes | No | Capture timestamp |
| `modifiedAt` | Date | Yes | No | Last modification (for conflicts) |
| `sourceAppBundleID` | String | Yes | No | Source application |
| `sourceAppName` | String | No | Yes | Display name |
| `itemType` | Int64 | Yes | No | Enum raw value |
| `primaryText` | String | No | Yes | Truncated to 10k chars |
| `contentHash` | String | Yes | No | SHA-256 for deduplication |
| `isSensitive` | Int64 | No | No | Bool as Int (0/1) |
| `isTransient` | Int64 | No | No | Bool as Int |
| `isPinned` | Int64 | Yes | No | Bool as Int |
| `thumbnailAsset` | CKAsset | No | No | Optional thumbnail |
| `byteCount` | Int64 | No | No | Total size |

#### Indexes

```
- createdAt (queryable)
- itemType (queryable)
- contentHash (for duplicate detection)
- isPinned (for filtered queries)
```

#### Security

- Read: Creator only
- Write: Creator only
- Delete: Creator only

#### Relationships

- Has many `CKClipRepresentation` (via parent reference)
- Has many `CKPinboardMembership` (linking to pinboards)
- Has one `CKLinkPreview` (optional, via parent reference)

---

### 3.2 CKClipRepresentation

**Purpose:** Stores a single format/flavor of a ClipItem

#### Fields

| Field Name | Type | Indexed | Searchable | Notes |
|------------|------|---------|------------|-------|
| `recordID` | String | Auto | No | Format: `ClipRep-{UUID}` |
| `id` | String | Yes | No | Matches local ID |
| `clipItemID` | String | Yes | No | Foreign key to CKClipItem |
| `clipItemRef` | CKRecord.Reference | No | No | Parent reference (for atomic operations) |
| `uti` | String | Yes | No | Uniform Type Identifier |
| `kind` | Int64 | Yes | No | RepresentationKind enum |
| `displayOrder` | Int64 | No | No | Sort priority |
| `textData` | String | No | No | For text formats (max 10 MB) |
| `asset` | CKAsset | No | No | For binaries (images, files) |
| `byteCount` | Int64 | No | No | Size |
| `modifiedAt` | Date | No | No | For conflict resolution |

#### Parent Reference

```swift
let parentRef = CKRecord.Reference(
    recordID: clipItemRecordID,
    action: .deleteSelf  // Cascade delete when parent is deleted
)
record["clipItemRef"] = parentRef
```

---

### 3.3 CKPinboard

**Purpose:** Named collection of clips

#### Fields

| Field Name | Type | Indexed | Searchable | Notes |
|------------|------|---------|------------|-------|
| `recordID` | String | Auto | No | Format: `Pinboard-{UUID}` |
| `id` | String | Yes | No | Stable ID |
| `name` | String | No | Yes | User-visible name |
| `colorHex` | String | No | No | Hex color code |
| `sortOrder` | Int64 | Yes | No | Display order |
| `isSystemClipboard` | Int64 | Yes | No | Bool as Int |
| `createdAt` | Date | Yes | No | Creation time |
| `modifiedAt` | Date | Yes | No | Last update |
| `iconName` | String | No | No | SF Symbol name |

#### Sharing

- Supports CKShare for collaborative pinboards (Phase 6+)

---

### 3.4 CKPinboardMembership

**Purpose:** Many-to-many relationship between ClipItems and Pinboards

#### Fields

| Field Name | Type | Indexed | Searchable | Notes |
|------------|------|---------|------------|-------|
| `recordID` | String | Auto | No | Format: `Membership-{UUID}` |
| `id` | String | Yes | No | Stable ID |
| `clipItemID` | String | Yes | No | Foreign key |
| `pinboardID` | String | Yes | No | Foreign key |
| `addedAt` | Date | No | No | When added |
| `modifiedAt` | Date | No | No | For conflict resolution |

#### Indexes

```
compound index: [clipItemID, pinboardID] (uniqueness check)
```

---

### 3.5 CKLinkPreview

**Purpose:** Cached URL metadata

#### Fields

| Field Name | Type | Indexed | Searchable | Notes |
|------------|------|---------|------------|-------|
| `recordID` | String | Auto | No | Format: `LinkPreview-{UUID}` |
| `id` | String | Yes | No | Stable ID |
| `clipItemID` | String | Yes | No | Foreign key |
| `clipItemRef` | CKRecord.Reference | No | No | Parent reference |
| `url` | String | No | No | Original URL |
| `title` | String | No | Yes | Page title |
| `summary` | String | No | Yes | Description |
| `imageAsset` | CKAsset | No | No | Preview image |
| `siteName` | String | No | No | e.g. "GitHub" |
| `fetchedAt` | Date | No | No | Cache timestamp |

---

### 3.6 CKStackSession (Optional - Phase 3)

**Purpose:** Paste Stack session sync (optional feature)

#### Fields

| Field Name | Type | Indexed | Notes |
|------------|------|---------|-------|
| `id` | String | Yes | Stable ID |
| `createdAt` | Date | Yes | Session start |
| `isActive` | Int64 | Yes | Bool as Int |
| `separator` | String | No | Text separator |
| `mode` | Int64 | No | StackMode enum |
| `modifiedAt` | Date | No | For conflicts |

**Note:** Stack sync is low priority. Consider making stacks device-local only.

---

### 3.7 CKUserSetting (Optional)

**Purpose:** Sync subset of user settings (if needed)

#### Fields

| Field Name | Type | Indexed | Notes |
|------------|------|---------|-------|
| `key` | String | Yes | Setting identifier (unique) |
| `value` | String | No | JSON-encoded value |
| `modifiedAt` | Date | No | For conflicts |

**Settings to Sync (examples):**
- Pinboard sort order
- Retention policy
- iCloud sync enabled (ironic, but useful for multi-device coordination)

**Settings NOT to Sync:**
- Hotkeys (device-specific)
- Ignored apps (may vary per device)
- Local file paths

---

## 4. Sync Engine Architecture

### 4.1 Sync Coordinator Overview

```swift
class SyncCoordinator {
    let container: CKContainer
    let privateDatabase: CKDatabase
    let zone: CKRecordZone
    
    private var changeToken: CKServerChangeToken?
    private var syncInProgress = false
    
    // MARK: - Lifecycle
    func start()
    func stop()
    func performFullSync()
    
    // MARK: - Outbound
    func pushLocalChanges()
    func uploadRecord(_ record: CKRecord) async throws
    func uploadAsset(_ asset: CKAsset, for record: CKRecord) async throws
    
    // MARK: - Inbound
    func fetchRemoteChanges() async throws
    func applyRemoteChanges(_ records: [CKRecord])
    func handleDeletion(_ recordID: CKRecord.ID)
    
    // MARK: - Conflict Resolution
    func resolveConflict(_ local: CKRecord, _ remote: CKRecord) -> CKRecord
}
```

### 4.2 Change Tracking (Local → Cloud)

**Strategy:** Observe Core Data notifications and enqueue changes

```swift
// Observe saves in background context
NotificationCenter.default.addObserver(
    forName: .NSManagedObjectContextDidSave,
    object: backgroundContext,
    queue: .main
) { notification in
    let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>
    let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>
    let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>
    
    syncCoordinator.enqueueChanges(
        inserted: inserted,
        updated: updated,
        deleted: deleted
    )
}
```

**Debouncing:** Batch changes every 2 seconds to avoid excessive uploads

### 4.3 Change Fetching (Cloud → Local)

**Strategy:** Use `CKFetchRecordZoneChangesOperation` with change tokens

```swift
func fetchRemoteChanges() async throws {
    let operation = CKFetchRecordZoneChangesOperation()
    
    // Configure
    let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
    options.previousServerChangeToken = self.changeToken
    
    operation.recordZoneIDs = [zone.zoneID]
    operation.configurationsByRecordZoneID = [zone.zoneID: options]
    
    // Callbacks
    operation.recordWasChangedBlock = { recordID, result in
        switch result {
        case .success(let record):
            await self.applyRemoteRecord(record)
        case .failure(let error):
            self.handleFetchError(error)
        }
    }
    
    operation.recordWithIDWasDeletedBlock = { recordID, recordType in
        await self.handleRemoteDeletion(recordID, type: recordType)
    }
    
    operation.recordZoneChangeTokensUpdatedBlock = { zoneID, token, _ in
        self.changeToken = token
        self.persistChangeToken(token)
    }
    
    operation.recordZoneFetchResultBlock = { zoneID, result in
        // Handle completion
    }
    
    privateDatabase.add(operation)
}
```

**Frequency:**
- On app launch
- On receiving push notification
- Every 5 minutes (background timer)
- After local changes are pushed (to catch conflicts early)

---

## 5. Conflict Resolution

### 5.1 Conflict Detection

CloudKit detects conflicts automatically when:
- Two devices modify the same record
- Local `modifiedAt` doesn't match server's

### 5.2 Resolution Policies

#### Policy 1: Immutable ClipItems (Recommended)

**Rule:** Captured clipboard items are never edited, only created or deleted.

**Conflicts:** Should not occur for content. If they do, prefer remote (server wins).

**Rationale:** A clipboard item represents a point-in-time capture. Editing it doesn't make semantic sense.

#### Policy 2: Last-Writer-Wins for Mutable Entities

**Applies to:** Pinboards, Settings, Memberships

**Algorithm:**
```swift
func resolveConflict(_ local: CKRecord, _ remote: CKRecord) -> CKRecord {
    guard let localModified = local["modifiedAt"] as? Date,
          let remoteModified = remote["modifiedAt"] as? Date else {
        return remote // Fallback: server wins
    }
    
    if localModified > remoteModified {
        return local
    } else {
        return remote
    }
}
```

**Edge Case:** If timestamps are identical (unlikely), use record name lexicographic order for determinism.

#### Policy 3: Set Union for Memberships

**Rule:** Pinboard memberships are treated as a set. Adding an item to a pinboard on two devices results in one membership, not a conflict.

**Implementation:**
- Check for existing membership by compound key `(clipItemID, pinboardID)`
- If exists, update `modifiedAt`
- If not exists, create new

**Deletions:** Respect deletion records. If Device A adds and Device B deletes simultaneously, deletion wins (safer).

#### Policy 4: Asset Conflicts

**Rule:** Assets are immutable. If asset CKAsset URL changes, prefer the remote version (assume upload completed).

---

### 5.3 Conflict Handling Code

```swift
func uploadRecord(_ record: CKRecord) async throws {
    let operation = CKModifyRecordsOperation(recordsToSave: [record])
    operation.savePolicy = .changedKeys
    
    operation.perRecordResultBlock = { recordID, result in
        switch result {
        case .success(let saved):
            // Success
            await self.markSynced(recordID)
            
        case .failure(let error as CKError):
            if error.code == .serverRecordChanged {
                // Conflict detected
                let serverRecord = error.serverRecord
                let clientRecord = error.clientRecord
                
                let resolved = self.resolveConflict(clientRecord, serverRecord)
                
                // Retry with resolved record
                try await self.uploadRecord(resolved)
            } else {
                // Other error
                throw error
            }
        }
    }
    
    privateDatabase.add(operation)
}
```

---

## 6. Asset Management

### 6.1 CKAsset Upload Strategy

**When to use CKAsset:**
- Images (always)
- Rich text > 100 KB
- Any binary > 50 KB

**Upload Process:**
1. Write data to temporary file URL
2. Create `CKAsset(fileURL: tempURL)`
3. Attach to CKRecord field
4. Upload record (CloudKit handles asset upload)
5. Delete temporary file after success

```swift
func uploadImageAsset(_ imageData: Data, for record: CKRecord) async throws {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
    
    try imageData.write(to: tempURL)
    
    let asset = CKAsset(fileURL: tempURL)
    record["asset"] = asset
    
    try await uploadRecord(record)
    
    try? FileManager.default.removeItem(at: tempURL)
}
```

### 6.2 CKAsset Download Strategy

**Options:**
1. **Eager:** Download assets immediately when fetching records
2. **Lazy:** Download assets on-demand when user views item
3. **Hybrid:** Download thumbnails eagerly, full assets lazily

**Recommended:** Hybrid approach

```swift
func fetchRecordWithAssets(_ recordID: CKRecord.ID) async throws -> CKRecord {
    let record = try await privateDatabase.record(for: recordID)
    
    // Download thumbnail immediately
    if let thumbnailAsset = record["thumbnailAsset"] as? CKAsset,
       let url = thumbnailAsset.fileURL {
        let data = try Data(contentsOf: url)
        await cacheAsset(data, for: recordID, type: .thumbnail)
    }
    
    // Schedule full asset download in background
    Task.detached {
        if let asset = record["asset"] as? CKAsset {
            await self.downloadFullAsset(asset, for: recordID)
        }
    }
    
    return record
}
```

### 6.3 Asset Deduplication

**Strategy:** Use SHA-256 hash to avoid uploading identical assets

```swift
func uploadAssetIfNeeded(_ data: Data, for record: CKRecord) async throws {
    let hash = data.sha256()
    
    // Check if asset with this hash already exists in cloud
    let query = CKQuery(
        recordType: "CKClipRepresentation",
        predicate: NSPredicate(format: "assetHash == %@", hash)
    )
    
    let results = try await privateDatabase.records(matching: query)
    
    if let existing = results.matchResults.first?.value {
        // Reuse existing asset reference
        record["asset"] = existing["asset"]
        record["assetHash"] = hash
    } else {
        // Upload new asset
        try await uploadImageAsset(data, for: record)
        record["assetHash"] = hash
    }
}
```

---

## 7. Deletion Handling

### 7.1 Soft Delete vs Hard Delete

**Decision:** Use hard deletes (CloudKit deletion records)

**Rationale:**
- CloudKit tracks deletions natively via `recordWithIDWasDeletedBlock`
- No need for tombstone records
- Cleaner schema

### 7.2 Deletion Propagation

```swift
func deleteItem(_ itemID: UUID) async throws {
    // 1. Delete local
    let item = try fetchClipItem(id: itemID)
    context.delete(item)
    try context.save()
    
    // 2. Delete from CloudKit
    let recordID = CKRecord.ID(
        recordName: "ClipItem-\(itemID.uuidString)",
        zoneID: zone.zoneID
    )
    
    try await privateDatabase.deleteRecord(withID: recordID)
    
    // 3. Child records (representations, link previews) delete via parent reference cascade
}

func handleRemoteDeletion(_ recordID: CKRecord.ID, type: String) async {
    switch type {
    case "CKClipItem":
        let uuid = extractUUID(from: recordID.recordName)
        let item = try? fetchClipItem(id: uuid)
        if let item = item {
            context.delete(item)
            try? context.save()
        }
        
    case "CKPinboard":
        // Similar logic
        
    default:
        break
    }
}
```

### 7.3 Cascade Rules

**CloudKit Parent References:**
- `CKClipRepresentation.clipItemRef` → `.deleteSelf` (cascade)
- `CKLinkPreview.clipItemRef` → `.deleteSelf` (cascade)

**Local Core Data:**
- ClipItem delete → Cascade representations, link preview
- Pinboard delete → Nullify item relationships

---

## 8. Sync Status and Error Handling

### 8.1 Sync States

```swift
enum SyncStatus {
    case synced           // All changes uploaded and fetched
    case syncing          // Operation in progress
    case error(Error)     // Sync failed
    case paused           // User disabled sync
    case accountIssue     // iCloud account not available
}
```

### 8.2 Error Categories

| Error | Recovery Strategy |
|-------|-------------------|
| `.notAuthenticated` | Show "Sign in to iCloud" alert |
| `.networkUnavailable` | Retry with exponential backoff |
| `.quotaExceeded` | Alert user, prompt to manage storage |
| `.zoneBusy` | Retry after delay |
| `.serverRecordChanged` | Apply conflict resolution |
| `.assetFileNotFound` | Re-generate asset from local data |
| `.partialFailure` | Retry failed records individually |

### 8.3 Retry Logic

```swift
func uploadWithRetry(_ record: CKRecord, maxAttempts: Int = 3) async throws {
    var attempt = 0
    var delay: TimeInterval = 1.0
    
    while attempt < maxAttempts {
        do {
            try await uploadRecord(record)
            return // Success
        } catch let error as CKError {
            attempt += 1
            
            if error.code == .networkUnavailable || error.code == .zoneBusy {
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2 // Exponential backoff
                    continue
                }
            }
            
            throw error // Unrecoverable or max attempts reached
        }
    }
}
```

### 8.4 User-Facing Sync Status

**Settings UI Display:**
```
iCloud Sync: [ON]
Status: Synced now | Last synced 2m ago | Syncing... | Error
```

**Errors to Surface:**
- "iCloud account not signed in"
- "iCloud storage full"
- "Sync paused due to network error"

---

## 9. Security and Privacy

### 9.1 Data Encryption

**CloudKit Default:**
- All data encrypted in transit (TLS)
- Data encrypted at rest on Apple servers
- Keys managed by Apple (not end-to-end encrypted by default)

**Sensitive Content Handling:**
- Items marked `isSensitive == true` are stored in CloudKit but flagged
- Consider: Skip syncing sensitive items entirely (user preference)

### 9.2 Privacy Controls

**Sync Toggle:**
- When disabled: Stop all uploads and downloads
- When re-enabled: Perform full reconciliation

**Selective Sync (Future Enhancement):**
- Sync only non-sensitive items
- Sync only specific pinboards

### 9.3 Access Control

**Private Database:**
- Only the user can read/write their own records
- No sharing by default

**Public Database (Future):**
- For shared pinboard templates (read-only)

---

## 10. Phase-Specific Implementation Tasks

### Phase 1-4: No Sync (Local Only)

**Tasks:**
- [x] Design CloudKit schema (this document)
- [ ] Create record types in CloudKit Dashboard
- [ ] No implementation yet

**Status:** Deferred (local-only through Phase 4)

---

### Phase 5: CloudKit Sync (Weeks 11-14)

#### Week 11: Setup and Schema

- [ ] Configure CloudKit container in Xcode
- [ ] Enable CloudKit capability
- [ ] Create custom zone "ClipboardZone"
- [ ] Define all record types in CloudKit Dashboard
- [ ] Set up indexes for queryable fields
- [ ] Configure record security (private by default)
- [ ] Test schema in development environment

**Deliverables:**
- CloudKit container configured
- All record types created
- Schema documentation updated

---

#### Week 12: Outbound Sync

- [ ] Implement `SyncCoordinator` class
- [ ] Observe Core Data context saves
- [ ] Implement change queue (debounced)
- [ ] Map Core Data entities to CKRecords
- [ ] Upload CKClipItem records
- [ ] Upload CKClipRepresentation records
- [ ] Upload CKPinboard records
- [ ] Upload CKPinboardMembership records
- [ ] Handle asset uploads (CKAsset)
- [ ] Implement retry logic with exponential backoff
- [ ] Add unit tests for record mapping

**Success Criteria:**
- Local changes upload within 5s
- Assets upload correctly
- No data loss on network interruption

---

#### Week 13: Inbound Sync

- [ ] Implement `CKFetchRecordZoneChangesOperation`
- [ ] Store and load server change token
- [ ] Map CKRecords to Core Data entities
- [ ] Handle record create/update
- [ ] Handle record deletion
- [ ] Download assets on-demand
- [ ] Update UI after remote changes applied
- [ ] Handle partial failures
- [ ] Test on two devices simultaneously

**Success Criteria:**
- Remote changes appear locally within 10s
- Deletions propagate correctly
- No duplicate items created

---

#### Week 14: Conflict Resolution and Polish

- [ ] Implement conflict detection
- [ ] Apply last-writer-wins policy
- [ ] Handle asset conflicts
- [ ] Handle membership set union
- [ ] Add sync status UI indicator
- [ ] Implement sync toggle in settings
- [ ] Handle iCloud account state changes
- [ ] Show user-friendly error messages
- [ ] Add logging for debugging sync issues
- [ ] Performance test with 1000+ items
- [ ] Test airplane mode scenarios
- [ ] Test simultaneous edits on multiple devices

**Success Criteria:**
- Zero data loss during conflicts
- All conflicts resolve deterministically
- User can understand sync status
- Sync performs well with large datasets

---

### Phase 6: Hardening (Weeks 15-16)

#### Sync Hardening Tasks

- [ ] Stress test sync with 10,000 items
- [ ] Test sync with slow network (simulated)
- [ ] Test sync with interrupted uploads
- [ ] Measure CloudKit operation costs
- [ ] Optimize batch sizes to reduce operations
- [ ] Implement asset download queue with priority
- [ ] Add telemetry for sync success rate (local only)
- [ ] Test migration from sync-off to sync-on
- [ ] Test account switching
- [ ] Validate data integrity after sync
- [ ] Document known limitations
- [ ] Create troubleshooting guide for users

**Success Criteria:**
- Sync remains stable under stress
- No crashes during sync operations
- Asset downloads don't block UI
- Error recovery is robust

---

## 11. CloudKit Quotas and Limits

### 11.1 Free Tier Limits (per user)

| Resource | Limit |
|----------|-------|
| Database storage | 1 GB |
| Asset storage | 10 GB |
| Requests | 40 requests/sec |
| Asset bandwidth | 500 MB/day download |

**Mitigation Strategies:**
- Compress images before upload
- Set asset size caps (50 MB per item)
- Cache assets locally
- Batch operations
- Implement lazy asset downloads

### 11.2 Record Size Limits

| Limit | Value |
|-------|-------|
| Max record size | 1 MB (including metadata) |
| Max asset size | 250 MB |
| Max string field | 512 KB |
| Max asset downloads | 40 MB/request |

**Design Implications:**
- Use CKAsset for large binaries
- Truncate `primaryText` to 10k characters
- Split very large records

---

## 12. Testing Strategy

### 12.1 Unit Tests

```swift
func testRecordMapping() {
    let clipItem = createTestClipItem()
    let record = clipItem.toCKRecord()
    
    XCTAssertEqual(record.recordType, "CKClipItem")
    XCTAssertEqual(record["id"] as? String, clipItem.id.uuidString)
    XCTAssertEqual(record["itemType"] as? Int64, Int64(clipItem.itemType))
}

func testConflictResolution() {
    let local = createRecord(modifiedAt: Date())
    let remote = createRecord(modifiedAt: Date().addingTimeInterval(-10))
    
    let resolved = syncCoordinator.resolveConflict(local, remote)
    
    XCTAssertEqual(resolved, local) // Local is newer
}
```

### 12.2 Integration Tests

**Scenarios:**
1. Upload item from Device A, fetch on Device B
2. Create pinboard on Device A, see on Device B
3. Delete item on Device A, deletion propagates to Device B
4. Simultaneous edits: Device A and B modify same pinboard name
5. Offline mode: Queue changes, sync when online

**Test Environment:**
- Use CloudKit Development environment
- Use separate test user accounts
- Reset database between tests

### 12.3 Manual Testing Checklist

- [ ] Sign out of iCloud → Sync shows error
- [ ] Sign back in → Sync resumes
- [ ] Enable airplane mode → Changes queue locally
- [ ] Disable airplane mode → Changes upload
- [ ] Create 100 items on Device A → All appear on Device B
- [ ] Delete pinboard on Device A → Disappears on Device B
- [ ] Modify pinboard name on both devices simultaneously → Conflict resolves
- [ ] Upload 10 MB image → Downloads on Device B
- [ ] Toggle sync off → No network requests
- [ ] Toggle sync on → Full sync completes

---

## 13. Operational Procedures

### 13.1 Schema Deployment

**Development → Production:**
1. Test schema in development environment
2. Validate all record types and indexes
3. Deploy to production via CloudKit Dashboard
4. Cannot delete fields (only deprecate)
5. Can add new optional fields anytime

**Schema Evolution:**
- Use versioning: Add new fields with version suffix if needed
- Maintain backward compatibility

### 13.2 Monitoring and Debugging

**CloudKit Dashboard:**
- Monitor request rates
- Check for throttling
- View sample records
- Check zone health

**Local Logging:**
```swift
os_log("Sync: Uploaded %d records", log: .sync, type: .info, count)
os_log("Sync: Conflict detected for %@", log: .sync, type: .error, recordID)
```

### 13.3 User Support

**Common Issues:**
1. "Items not syncing"
   - Check iCloud sign-in
   - Check network connectivity
   - Check sync toggle in settings
   - Force full sync

2. "Duplicate items appearing"
   - Check for hash collision (unlikely)
   - Validate deduplication logic
   - Check for multiple devices with same ID

3. "Assets not downloading"
   - Check network connectivity
   - Check CloudKit quota
   - Retry asset download

---

## 14. Future Enhancements

### 14.1 Pinboard Sharing (CKShare)

**Goal:** Allow users to share pinboards with others

**Implementation:**
```swift
func sharePin board(_ pinboard: Pinboard) async throws -> CKShare {
    let record = pinboard.toCKRecord()
    let share = CKShare(rootRecord: record)
    
    share[CKShare.SystemFieldKey.title] = pinboard.name
    share.publicPermission = .readOnly
    
    try await privateDatabase.save(share)
    
    return share
}
```

**UI:**
- "Share Pinboard" context menu
- System share sheet for invitation link

### 14.2 Public Pinboard Templates

**Goal:** User-curated pinboards discoverable by others (e.g., "Developer Snippets")

**Implementation:**
- Use public database
- Moderate content (if needed)
- Allow users to "import" templates

### 14.3 Conflict-Free Replicated Data Types (CRDT)

**Goal:** Eliminate last-writer-wins conflicts for certain fields

**Example:** Use a CRDT for pinboard item lists to allow concurrent additions without conflicts

**Complexity:** High, defer to later versions

---

## 15. Open Questions

### 15.1 Decisions Needed

1. **Sync StackSessions?**
   - **Recommendation:** No, keep stacks device-local (ephemeral workflow)
   - **Alternative:** Sync active stack only

2. **Sync ignored apps list?**
   - **Recommendation:** No, device-specific preference
   - **Alternative:** Sync as user setting

3. **Thumbnail resolution?**
   - **Recommendation:** 512x512 @ 2x (balance quality and size)

4. **Asset retention in cloud?**
   - **Recommendation:** Match local retention policy
   - **Implementation:** Delete cloud records when local cleanup runs

### 15.2 Known Limitations

- CloudKit does not support true offline mode (requires periodic connectivity)
- Asset downloads can be slow on cellular networks
- Quota limits may affect power users (mitigate with size caps)

---

## 16. Changelog

### Version 1.0.0 (2026-01-09)
- Initial CloudKit schema specification
- Defined 7 record types
- Specified sync engine architecture
- Outlined conflict resolution policies
- Detailed Phase 5 implementation tasks

---

## 17. Appendix: Code Examples

### 17.1 Entity to CKRecord Mapping

```swift
extension ClipItem {
    func toCKRecord(zone: CKRecordZone) -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: "ClipItem-\(id.uuidString)",
            zoneID: zone.zoneID
        )
        
        let record = CKRecord(recordType: "CKClipItem", recordID: recordID)
        record["id"] = id.uuidString
        record["createdAt"] = createdAt
        record["modifiedAt"] = modifiedAt
        record["sourceAppBundleID"] = sourceAppBundleID
        record["sourceAppName"] = sourceAppName
        record["itemType"] = Int64(itemType)
        record["primaryText"] = String(primaryText?.prefix(10000) ?? "")
        record["contentHash"] = hash
        record["isSensitive"] = isSensitive ? 1 : 0
        record["isTransient"] = isTransient ? 1 : 0
        record["isPinned"] = isPinned ? 1 : 0
        record["byteCount"] = byteCount
        
        return record
    }
    
    static func fromCKRecord(_ record: CKRecord, context: NSManagedObjectContext) -> ClipItem {
        let item = ClipItem(context: context)
        item.id = UUID(uuidString: record["id"] as! String)!
        item.createdAt = record["createdAt"] as! Date
        item.modifiedAt = record["modifiedAt"] as! Date
        item.sourceAppBundleID = record["sourceAppBundleID"] as? String
        item.sourceAppName = record["sourceAppName"] as? String
        item.itemType = Int16(record["itemType"] as! Int64)
        item.primaryText = record["primaryText"] as? String
        item.contentHash = record["contentHash"] as! String
        item.isSensitive = (record["isSensitive"] as! Int64) == 1
        item.isTransient = (record["isTransient"] as! Int64) == 1
        item.isPinned = (record["isPinned"] as! Int64) == 1
        item.byteCount = record["byteCount"] as! Int64
        
        return item
    }
}
```

---

**Related Documents:**
- [Architecture Overview](./Architecture-Overview.md)
- [Data Model Spec](./Data-Model-Spec.md) - Local entity definitions
- [Privacy & Security Spec](./Privacy-Security-Spec.md) - Sync privacy controls
