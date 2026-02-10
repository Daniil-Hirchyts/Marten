# Shared Pinboards - Implementation Specification (A to Z)

Last updated: 2026-02-10
Status: Implementation-ready

## 1. Purpose
This document is the source-of-truth specification for implementing Shared Pinboards end-to-end in Marten.

It includes:
- Product scope and constraints
- Exact data model and CloudKit contracts
- Sync routing and conflict rules
- API contracts and lifecycle hooks
- UI/UX behavior and permission matrix
- Test acceptance criteria and rollout gates
- Multi-agent execution plan

This document is intended to be sufficient for parallel implementation without additional design decisions.

## 2. Goals and Non-Goals

### Goals
1. Share a pinboard with other iCloud users using CloudKit native sharing (`CKShare`).
2. Support owner and participant collaboration with role-based permissions.
3. Keep private sync behavior unchanged for non-shared data.
4. Prevent private/shared data leakage by explicit sync routing.
5. Enforce lock/share mutual exclusivity.
6. Provide predictable offline conflict resolution for v1.

### Non-Goals (v1)
1. No manual merge UI.
2. No server-side participant analytics.
3. No multi-share per pinboard.
4. No end-to-end automation of multi-account share acceptance in CI.

## 3. Current Architecture Constraints
1. Manual CloudKit orchestration remains in place.
2. Existing private sync stack remains:
- `CloudKitManager`
- `OutboundSyncEngine`
- `InboundSyncEngine`
- `SyncCoordinator`
3. Existing record types remain:
- `CKClipItem`
- `CKClipRepresentation`
- `CKPinboard`
- `CKPinboardMembership`
- `CKLinkPreview`
4. Existing `Pinboard.shareToken` is kept as deprecated compatibility field in v1.

## 4. High-Level Architecture

### 4.1 Databases
1. Private DB
- Personal pinboards and all non-shared records
- Owner-side shared zones and share records

2. Shared DB
- Participant view of owner shared zones
- Participant writes for shared data

### 4.2 Zone Strategy
1. Private personal zone (existing):
- `MartenZone`

2. Shared pinboard zones (new):
- Zone name format: `SharedPinboard-<pinboardUUID>`
- One zone per shared pinboard
- Root record: `CKPinboard` for that pinboard
- One `CKShare` per shared pinboard root record

## 5. Data Model (Core Data v3)

### 5.1 Entity Changes

#### Pinboard (modified)
Existing fields retained.

New relationship:
- `shareMetadata: ShareMetadata?` (to-one, optional, inverse `pinboard`)

Rules:
- `shareMetadata == nil` -> pinboard is not shared
- `shareMetadata != nil` -> pinboard is shared

#### ClipItem (modified)
Add fields:
- `lastModifiedBy: String?`
- `lastModifiedAt: Date?`

Purpose:
- Collaboration metadata for conflict resolution and UI hints

#### ShareMetadata (new)
Entity fields:
- `id: UUID` (required)
- `shareRecordName: String` (required)
- `rootRecordName: String` (required)
- `zoneName: String` (required)
- `zoneOwnerName: String` (required)
- `ownerUserRecordName: String?`
- `accessControlRaw: Int16` (required)
- `defaultPermissionRaw: Int16` (required)
- `isOwner: Bool` (required, default `false`)
- `shareURL: String?`
- `lastParticipantRefreshAt: Date?`

Relationship:
- `pinboard: Pinboard` (to-one, required, inverse `shareMetadata`)

Deletion rule:
- Deleting pinboard cascades to `ShareMetadata`

### 5.2 Enumerations
```swift
public enum ShareAccessControl: Int16, Sendable {
    case onlyInvited = 0
    case anyoneWithLink = 1
}

public enum SharePermission: Int16, Sendable {
    case owner = 0
    case canMakeChanges = 1
    case viewOnly = 2
}

public enum ShareRole: Int16, Sendable {
    case owner = 0
    case canMakeChanges = 1
    case viewOnly = 2
    case unknown = 3
}
```

### 5.3 Migration
1. Create `MartenV3.xcdatamodel`.
2. Set current model version to `MartenV3`.
3. Lightweight migration is expected (added optional attributes + new entity + new optional relationship).
4. Add migration test: v2 -> v3 preserves existing pinboards/items.

## 6. Pinboard State Model

### 6.1 States
1. `normal`
- Not shared
- Not locked

2. `locked`
- Locked via `PinboardLockController`
- Not shared

3. `shared`
- Has `shareMetadata`
- Cannot be locked

### 6.2 Valid Transitions
1. `normal -> locked` allowed
2. `normal -> shared` allowed
3. `locked -> normal` allowed
4. `shared -> normal` allowed
5. `locked -> shared` forbidden
6. `shared -> locked` forbidden

### 6.3 Enforcement Layers
1. UI-level disablement and messaging
2. Repository-level hard validation
3. Sync-level safety checks

## 7. CloudKit Contract

### 7.1 Container
- `iCloud.com.hirchyts.marten`

### 7.2 Record Types
Record types remain unchanged:
- `CKClipItem`
- `CKClipRepresentation`
- `CKPinboard`
- `CKPinboardMembership`
- `CKLinkPreview`

### 7.3 Record IDs
Keep existing deterministic naming helpers:
- `ClipItem-<uuid>`
- `ClipRep-<uuid>`
- `Pinboard-<uuid>`
- `Membership-<uuid>`
- `LinkPreview-<uuid>`

### 7.4 Share Rules
1. Root record for sharing: `CKPinboard`.
2. One `CKShare` per shared pinboard.
3. Owner creates share from private DB zone.
4. Participants read/write through shared DB.

### 7.5 Subscriptions
1. Existing private zone subscription remains.
2. Add shared DB subscription:
- ID: `shared-database-subscription`
- `shouldSendContentAvailable = true`

## 8. Sync Routing Specification

## 8.1 Routing Inputs
Routing for each changed object depends on:
1. Whether object belongs to a shared pinboard
2. Share metadata (`isOwner`, `zoneName`, `zoneOwnerName`)
3. Operation type (insert/update/delete)

### 8.2 Routing Table
| Condition | Database | Zone |
|---|---|---|
| Pinboard has no `shareMetadata` | Private DB | `MartenZone` |
| Shared pinboard and `isOwner == true` | Private DB | `SharedPinboard-<pinboardUUID>` |
| Shared pinboard and `isOwner == false` | Shared DB | `zoneName` + `zoneOwnerName` from metadata |

### 8.3 Entity Routing Rules
1. `Pinboard`
- Route by its own `shareMetadata`

2. `CKPinboardMembership`
- Route by membership pinboard share state

3. `ClipItem`, `ClipRepresentation`, `LinkPreview`
- If item belongs to a shared pinboard: shared route
- If item belongs only to private pinboards: private route

### 8.4 Mixed Membership Policy (v1)
To avoid leakage/ambiguity:
1. A `ClipItem` cannot be assigned to both shared and non-shared custom pinboards.
2. Attempting mixed assignment throws repository validation error.
3. Existing "All items" system pinboard membership remains unaffected.

## 8.5 Transaction Author Filtering
Inbound saves MUST set transaction author:
- `private-inbound-sync`
- `shared-inbound-sync`

Outbound engines MUST ignore contexts with those authors to avoid sync loops.

## 9. Conflict Resolution (v1)

### 9.1 Policy
Last-Write-Wins by `modifiedAt`, tie-break by `recordID.recordName` lexicographic order.

### 9.2 Record Type Policies
1. `CKClipItem`: LWW by `modifiedAt`
2. `CKPinboard`: LWW by `modifiedAt`
3. `CKPinboardMembership`: LWW by `modifiedAt`
4. `CKClipRepresentation`: LWW by `modifiedAt`
5. `CKLinkPreview`: LWW by `fetchedAt`

### 9.3 Offline Behavior
1. Local changes queue normally.
2. On reconnect, outbound retries with existing backoff rules.
3. If conflict detected, resolver applies LWW automatically.
4. No manual merge prompt in v1.

## 10. API Contracts

### 10.1 Sharing Repository Contract
```swift
public protocol PinboardSharingRepositoryProtocol: Sendable {
    func createShare(
        pinboardID: NSManagedObjectID,
        accessControl: ShareAccessControl,
        defaultPermission: SharePermission
    ) async throws -> URL

    func acceptShare(metadata: CKShare.Metadata) async throws
    func stopSharing(pinboardID: NSManagedObjectID) async throws
    func leaveShare(pinboardID: NSManagedObjectID) async throws
    func refreshShareParticipants(pinboardID: NSManagedObjectID) async throws
}
```

### 10.2 Sync Coordinator Contract
```swift
@MainActor
public protocol SyncCoordinating: AnyObject {
    var status: SyncStatus { get }
    var lastSyncDate: Date? { get }
    var progress: SyncProgress { get }
    var syncEnabled: Bool { get set }

    func startSync() async throws
    func stopSync()
    func triggerSyncNow() async throws
    func handlePushNotification() async

    // New
    func acceptShare(metadata: CKShare.Metadata) async throws
    func syncSharedNow() async throws
}
```

### 10.3 Error Contract
Add `PinboardSharingError` with cases:
- `featureDisabled`
- `cannotShareLockedPinboard`
- `cannotLockSharedPinboard`
- `insufficientPermission`
- `ownerOnlyOperation`
- `shareNotFound`
- `invalidShareMetadata`
- `sharedZoneSetupFailed`
- `acceptShareFailed`
- `stopSharingFailed`
- `leaveShareFailed`

## 11. Share Lifecycle Flows

### 11.1 Create Share
1. Validate feature flag enabled.
2. Validate pinboard is not locked.
3. Ensure shared zone exists for pinboard.
4. Upsert root `CKPinboard` record in shared zone.
5. Create `CKShare(rootRecord:)`.
6. Configure access control:
- `onlyInvited` -> public permission none
- `anyoneWithLink` -> public permission mapped from `defaultPermission`
7. Save root + share records.
8. Persist `ShareMetadata`.
9. Return share URL.

### 11.2 Accept Share
1. System delivers `CKShare.Metadata` to app lifecycle callback.
2. Call `syncCoordinator.acceptShare(metadata:)`.
3. Accept share with CloudKit.
4. Persist/refresh local `ShareMetadata`.
5. Trigger immediate shared inbound sync.

### 11.3 Stop Sharing (Owner)
1. Validate current role owner.
2. Delete `CKShare` from owner private DB.
3. Clear local `ShareMetadata`.
4. Pinboard transitions `shared -> normal`.

### 11.4 Leave Share (Participant)
v1 behavior:
1. Remove local shared pinboard and metadata.
2. Clear shared zone token for that zone.
3. Do not auto-recreate locally unless share is accepted again.

Note: server-side participant removal is deferred in v1.

## 12. Permissions Matrix
| Operation | Owner | Can Make Changes | View Only |
|---|---|---|---|
| View shared pinboard | Yes | Yes | Yes |
| Add/edit/remove items | Yes | Yes | No |
| Reorder items | Yes | Yes | No |
| Rename/change color/icon | Yes | No | No |
| Manage participants | Yes | No | No |
| Change access control | Yes | No | No |
| Stop sharing | Yes | No | No |
| Leave share | No | Yes | Yes |
| Lock pinboard | No (shared state) | No | No |

## 13. UI/UX Specification

### 13.1 Entry Points
1. Pinboard context menu:
- `Share Pinboard...` (normal + unlocked)
- `Manage Sharing...` (shared)
- `Stop Sharing` (owner)
- `Leave Shared Pinboard` (participant)

2. Lock actions:
- Hidden/disabled for shared pinboards

### 13.2 Visual Indicators
1. Shared pinboard tab icon: `person.2.fill`.
2. Locked icon remains `lock.fill` and is mutually exclusive with shared icon.
3. Optional participant count badge (owner view).

### 13.3 Share Settings Sheet
Fields:
1. Access control
- Only invited people
- Anyone with link

2. Default permission
- Can make changes
- View only

3. Participants list
- Role labels
- Acceptance status

4. Actions
- Copy share link
- Open system sharing picker
- Remove participant (owner)

### 13.4 Read-only UX
1. Disable editing actions for `viewOnly` participants.
2. Show explanatory tooltip/help text.
3. Keep navigation and preview enabled.

## 14. App Lifecycle and Platform Integration

### 14.1 Required AppDelegate callback
```swift
func application(
    _ application: NSApplication,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
)
```

Behavior:
1. Forward metadata to `AppCoordinator`.
2. `AppCoordinator` forwards to `syncCoordinator.acceptShare(metadata:)`.

### 14.2 Remote Notifications
1. Keep existing push handling.
2. On push, sync coordinator triggers private + shared inbound paths (shared-only optimization allowed when notification scope is known).

### 14.3 Wrapper Configuration
1. `Info.plist` must include:
- `CKSharingSupported = YES`
2. Entitlements must include iCloud + CloudKit + push in signed build.

## 15. Feature Flag and Rollout Controls

### 15.1 Flag
- Key: `sharedPinboardsEnabled`
- Default: `false`

### 15.2 Behavior when disabled
1. Hide share UI entry points.
2. Existing shared metadata is ignored for write operations.
3. Shared sync engines do not start.

## 16. Multi-Agent Execution Plan

### 16.1 Wave Plan
| Wave | Parallel Agents | Gate |
|---|---|---|
| Wave 0 | A0 | Contract PR merged |
| Wave 1 | A1, A2, A8 | Builds + tests green with stubs |
| Wave 2 | A3, A4, A5 | Shared sync end-to-end in unit/integration tests |
| Wave 3 | A6, A7 | UI and lifecycle flows complete |
| Wave 4 | A8, A9, A0 | Full regression + docs + rollout checklist |

### 16.2 Agent Ownership

#### A0 Orchestrator/Integrator
Primary files:
- `docs/SHARED-PINBOARDS-AGENT-WORKBOARD.md` (new)
- `docs/SETUP.md`

#### A1 Data Model + Migration
Primary files:
- `MartenCore/Sources/DataModel/Marten.xcdatamodeld/MartenV3.xcdatamodel/contents`
- `MartenCore/Sources/DataModel/Marten.momd/VersionInfo.plist`
- `MartenCore/Sources/DataModel/Pinboard+CoreDataProperties.swift`
- `MartenCore/Sources/DataModel/ClipItem+CoreDataProperties.swift`
- New `ShareMetadata` files under `MartenCore/Sources/DataModel/`

#### A2 CloudKit Sharing Primitives
Primary files:
- `MartenCore/Sources/Sync/CloudKitManager.swift`
- `MartenCore/Sources/Sync/CloudKitConfiguration.swift`
- `MartenCore/Sources/Sync/ShareCoordinator.swift` (new)
- `MartenCore/Sources/Sync/SharedDatabaseManager.swift` (new)
- `MartenCore/Sources/Sync/ShareZoneRegistry.swift` (new)
- `MartenCore/Sources/DataModel/Cloud/CKRecordExtensions.swift`

#### A3 Shared Inbound Sync
Primary files:
- `MartenCore/Sources/Sync/SharedInboundSyncEngine.swift` (new)
- `MartenCore/Sources/Sync/SyncTokenManager.swift`
- `MartenCore/Sources/DataModel/Cloud/CloudRecordMapper.swift`
- `MartenCore/Sources/Sync/ConflictResolver.swift`

#### A4 Shared Outbound Sync + Routing
Primary files:
- `MartenCore/Sources/Sync/SharedOutboundSyncEngine.swift` (new)
- `MartenCore/Sources/Sync/OutboundSyncEngine.swift`
- `MartenCore/Sources/Sync/SyncCoordinator.swift`
- `MartenCore/Sources/DataModel/Cloud/CloudRecordMapper.swift`

#### A5 Domain/Repository Permissions
Primary files:
- `MartenCore/Sources/BusinessRules/Protocols/PinboardRepositoryProtocol.swift`
- `MartenCore/Sources/BusinessRules/PinboardRepository.swift`
- `MartenCore/Sources/BusinessRules/ClipItemStore.swift`
- `MartenMac/Sources/MartenMacApp/UI/Overlay/OverlayDependencies.swift`
- `MartenMac/Sources/MartenMacApp/UI/Overlay/PinboardManager.swift`

#### A6 UI/UX Sharing Flows
Primary files:
- `MartenMac/Sources/MartenMacApp/UI/Components/ContextMenus.swift`
- `MartenMac/Sources/MartenMacApp/UI/Components/PinboardTab.swift`
- `MartenMac/Sources/MartenMacApp/UI/Overlay/PinboardTabBar/PinboardTabBarTabs.swift`
- `MartenMac/Sources/MartenMacApp/UI/Overlay/Shell/OverlayPinboardActions.swift`
- New sharing views under `MartenMac/Sources/MartenMacApp/UI/Overlay/Sharing/`

#### A7 App Lifecycle + Invitation Acceptance
Primary files:
- `MartenMac/Sources/MartenMacApp/App/AppDelegate.swift`
- `MartenMac/Sources/MartenMacApp/App/AppCoordinator.swift`
- `MartenMac/Sources/MartenMacApp/App/AppServiceContainer.swift`
- `MartenMacWrapper/MartenMacWrapper/Info.plist`
- `MartenMacWrapper/MartenMacWrapper/MartenMacWrapper.entitlements`

#### A8 Test Infrastructure + QA Matrix
Primary files:
- `MartenCore/Tests/MartenCoreTests/Sync/CloudKitManagerTests.swift`
- `MartenCore/Tests/MartenCoreTests/SyncCoordinatorTests.swift`
- `MartenCore/Tests/MartenCoreTests/InboundSyncEngineTests.swift`
- `MartenCore/Tests/MartenCoreTests/OutboundSyncEngineTests.swift`
- `MartenCore/Tests/MartenCoreTests/MigrationTests.swift`
- `MartenMac/Tests/MartenMacAppTests/PinboardManagerTests.swift`
- New share-focused tests in both packages

#### A9 Documentation + Rollout
Primary files:
- `docs/SHARED-PINBOARDS.md`
- `docs/ARCHITECTURE-DECISIONS.md`
- `docs/SETUP.md`
- `docs/SHARED-PINBOARDS-ROLLOUT.md` (new)

### 16.3 Integration Rules
1. Branch naming: `codex/shared-pinboards-a<agent-number>-<topic>`.
2. A0 merges only after agent-specific acceptance tests pass.
3. Shared ownership files (`SyncCoordinator.swift`, `CloudRecordMapper.swift`, `OverlayDependencies.swift`) are modified only via contract-approved deltas.
4. Rebase before merge; no force-push after review start.
5. Every merge updates workboard doc and reruns package tests.

## 17. Test Plan and Acceptance Criteria

### 17.1 Core Data / Migration
1. v2 -> v3 migration preserves existing records.
2. New fields default correctly (`nil`/default values).
3. Existing non-shared behavior unchanged.

### 17.2 Share Lifecycle
1. Owner can create share and obtain URL.
2. Invitee can accept and see shared pinboard.
3. Owner stop-sharing removes shared state.
4. Participant leave-share removes local shared state.

### 17.3 Permission Enforcement
1. Read-only cannot mutate shared content.
2. Read-write can mutate items.
3. Owner-only operations blocked for non-owner.

### 17.4 Lock/Share Matrix
1. Locked pinboard cannot be shared.
2. Shared pinboard cannot be locked.
3. State transitions match section 6.

### 17.5 Sync Routing
1. Shared-only records never upload to private zone.
2. Private-only records never upload to shared zone.
3. Inbound transaction authors are ignored by outbound.

### 17.6 Conflict / Offline
1. Concurrent edits resolve by LWW.
2. Offline updates sync after reconnect.
3. Expired tokens clear and full zone resync succeeds.

### 17.7 App Lifecycle
1. Share acceptance callback triggers accept + sync.
2. Push notification triggers shared inbound.

### 17.8 Performance
1. No significant baseline regression in sync cycle time.
2. Shared sync batching follows current retry/backoff limits.

## 18. Manual QA Script (Signed Build)
1. Account A creates shared pinboard and shares link.
2. Account B accepts invite from system share flow.
3. Account B edits item; Account A receives update.
4. Account B set view-only; verify write actions disabled.
5. Account A stops sharing; Account B loses access gracefully.
6. Repeat with offline edit + reconnect.

## 19. Rollout and Monitoring

### 19.1 Rollout Stages
1. Ship with `sharedPinboardsEnabled = false`.
2. Internal dogfood (2 iCloud accounts) for 1 week.
3. Enable for test cohort.
4. Promote to default-on after stability threshold.

### 19.2 Metrics (required)
1. `shared_pinboard_create_success`
2. `shared_pinboard_create_failure`
3. `shared_pinboard_accept_success`
4. `shared_pinboard_accept_failure`
5. `shared_pinboard_permission_denied`
6. `shared_sync_inbound_failure`
7. `shared_sync_outbound_failure`
8. `shared_sync_token_reset`

### 19.3 Kill Switch
If instability is detected:
1. Flip `sharedPinboardsEnabled` to `false`.
2. Stop shared engines at startup.
3. Keep private sync unaffected.

## 20. Assumptions and Defaults
1. One share per pinboard in v1.
2. `shareToken` remains deprecated compatibility field in v1.
3. Participant list persistence is cache-only; `CKShare` is authoritative.
4. Signed app with iCloud + CloudKit + push is required for full validation.
5. CI does not fully automate multi-account share acceptance.
6. No manual merge UI in v1.

## 21. Definition of Done
Feature is done only when all are true:
1. Data model v3 merged and migration tests pass.
2. Share create/accept/stop/leave APIs implemented and tested.
3. Private and shared sync routing tests pass.
4. Lock/share mutual exclusivity enforced in UI + repository.
5. Lifecycle callback for share acceptance integrated.
6. UI tests for shared state matrix pass.
7. Manual signed two-account QA script passes.
8. Rollout docs and operational metrics are in place.
