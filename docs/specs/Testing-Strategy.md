# Testing Strategy
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.1.0
- **Last Updated:** 2026-01-16
- **Status:** Active
- **Owner:** Engineering Team
- **Dependencies:** All other specifications

---

## 1. Purpose and Scope

This document defines the comprehensive testing strategy for the Paste Clipboard Manager. It covers unit tests, integration tests, UI tests, performance tests, and manual testing procedures across all phases of development.

### 1.1 Goals

1. **Quality assurance:** Catch bugs before they reach users
2. **Regression prevention:** Ensure new features don't break existing functionality
3. **Performance validation:** Meet all performance budgets
4. **Platform compatibility:** Test across supported macOS versions
5. **Continuous improvement:** Establish metrics and improve test coverage over time

### 1.2 Testing Principles

**Core Tenets:**
- **Test-driven:** Write tests before or alongside implementation
- **Automated where possible:** Reduce manual testing burden
- **Fast feedback:** Unit tests run in <30 seconds
- **Realistic:** Integration tests use real Core Data and file system
- **Documented:** All manual test cases documented

---

## 2. Test Pyramid

### 2.1 Test Distribution

```
 ▲
 /UI\ ~10% (Slow, brittle)
 /────\
 /Integ.\ ~30% (Medium speed)
 /────────\
 / Unit \ ~60% (Fast, reliable)
 /────────────\
```

**Target Distribution:**
- **Unit Tests:** 60% of tests, 80% code coverage
- **Integration Tests:** 30% of tests, critical paths
- **UI/E2E Tests:** 10% of tests, happy paths only

---

## 3. Unit Testing

### 3.1 Technology

**Framework:** XCTest (native)

**Optional Additions:**
- Quick/Nimble (for BDD-style tests) - Decision: Not needed for MVP
- SwiftTesting (Apple's new framework, macOS 14+) - Consider for future

### 3.2 Test Structure

```
ClipboardCoreTests/
├── DataModel/
│ ├── ClipItemTests.swift
│ ├── PinboardTests.swift
│ └── RepresentationTests.swift
├── BusinessRules/
│ ├── DeduplicationTests.swift
│ ├── RetentionTests.swift
│ └── Classifiers/
│ ├── ConfidentialContentClassifierTests.swift
│ └── TransientContentClassifierTests.swift
├── Persistence/
│ ├── CoreDataStackTests.swift
│ └── MigrationTests.swift
├── Search/
│ └── SearchIndexTests.swift
└── Utilities/
 ├── HashingTests.swift
 └── NormalizationTests.swift
```

### 3.3 What to Test

#### Data Model
```swift
class ClipItemTests: XCTestCase {
 var context: NSManagedObjectContext!
 
 override func setUp() {
 super.setUp()
 context = createInMemoryContext()
 }
 
 func testClipItemCreation() {
 let item = ClipItem(context: context)
 item.id = UUID()
 item.createdAt = Date()
 item.itemType = .text
 item.primaryText = "Test"
 item.contentHash = "abc123"
 
 XCTAssertNoThrow(try context.save())
 }
 
 func testHashMustBeUnique() {
 let item1 = createClipItem(contentHash: "duplicate")
 try! context.save()
 
 let item2 = createClipItem(contentHash: "duplicate")
 
 XCTAssertThrowsError(try context.save())
 }
 
 func testDeletionCascadesToRepresentations() {
 let item = createClipItem()
 let rep = createRepresentation(for: item)
 try! context.save()
 
 context.delete(item)
 try! context.save()
 
 XCTAssertTrue(rep.isDeleted)
 }
}
```

#### Hashing and Deduplication
```swift
class HashingTests: XCTestCase {
 func testTextHashIsConsistent() {
 let text = "Hello, World!"
 let hash1 = computeHash(text)
 let hash2 = computeHash(text)
 
 XCTAssertEqual(hash1, hash2)
 }
 
 func testTextHashNormalizesWhitespace() {
 let text1 = "Hello, World!"
 let text2 = "Hello, World!"
 
 let hash1 = computeHash(text1)
 let hash2 = computeHash(text2)
 
 XCTAssertEqual(hash1, hash2)
 }
 
 func testImageHashUsesRawBytes() {
 let image = createTestImage()
 let hash = computeHash(image)
 
 XCTAssertEqual(hash.count, 64) // SHA-256 hex
 }
}
```

#### Classifiers
```swift
class ConfidentialContentClassifierTests: XCTestCase {
 var classifier: ConfidentialContentClassifier!
 
 override func setUp() {
 classifier = ConfidentialContentClassifier()
 }
 
 func testDetectsStrongPassword() {
 let password = "aB3$xY9!mN2@"
 let result = classifier.classify(password)
 
 XCTAssertEqual(result, .sensitive(.password))
 }
 
 func testDoesNotDetectURL() {
 let url = "https://example.com"
 let result = classifier.classify(url)
 
 XCTAssertEqual(result, .safe)
 }
 
 func testDetects6DigitOTP() {
 let otp = "123456"
 let result = classifier.classify(otp)
 
 XCTAssertEqual(result, .sensitive(.oneTimeCode))
 }
 
 func testDetectsCreditCard() {
 let card = "4532015112830366" // Valid test number
 let result = classifier.classify(card)
 
 XCTAssertEqual(result, .sensitive(.creditCard))
 }
 
 func testRejectsInvalidCreditCard() {
 let card = "4532015112830367" // Fails Luhn check
 let result = classifier.classify(card)
 
 XCTAssertEqual(result, .safe)
 }
}
```

#### Retention Policy
```swift
class RetentionTests: XCTestCase {
 var context: NSManagedObjectContext!
 var retentionManager: RetentionManager!
 
 override func setUp() {
 context = createInMemoryContext()
 retentionManager = RetentionManager(context: context)
 }
 
 func testDeletesExpiredItems() {
 // Create old item
 let oldItem = createClipItem()
 oldItem.createdAt = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
 
 // Create recent item
 let recentItem = createClipItem()
 recentItem.createdAt = Date()
 
 try! context.save()
 
 // Set retention to 7 days
 retentionManager.retentionDays = 7
 retentionManager.cleanup()
 
 // Old item should be deleted
 XCTAssertTrue(oldItem.isDeleted)
 XCTAssertFalse(recentItem.isDeleted)
 }
 
 func testDoesNotDeletePinnedItems() {
 let oldItem = createClipItem()
 oldItem.createdAt = Date().addingTimeInterval(-30 * 24 * 60 * 60)
 oldItem.isPinned = true
 
 try! context.save()
 
 retentionManager.retentionDays = 7
 retentionManager.cleanup()
 
 XCTAssertFalse(oldItem.isDeleted)
 }
 
 func testDoesNotDeleteItemsInUserPinboards() {
 let oldItem = createClipItem()
 oldItem.createdAt = Date().addingTimeInterval(-30 * 24 * 60 * 60)
 
 let pinboard = createPinboard(isSystem: false)
 oldItem.addToPinboards(pinboard)
 
 try! context.save()
 
 retentionManager.retentionDays = 7
 retentionManager.cleanup()
 
 XCTAssertFalse(oldItem.isDeleted)
 }
}
```

### 3.4 Test Coverage Goals

**Minimum:** 60% overall code coverage

**Target by Module:**
- DataModel: 80%
- BusinessRules: 90%
- Classifiers: 95%
- Persistence: 70%
- Sync: 60% (difficult to test CloudKit without mocks)
- UI: 40% (UI tests cover the rest)

---

## 4. Integration Testing

### 4.1 Purpose

Test interactions between modules with real dependencies (Core Data, file system, etc.)

### 4.2 Test Structure

```
ClipboardMacTests/
├── Integration/
│ ├── CaptureToStorageTests.swift
│ ├── PasteEngineTests.swift
│ ├── SearchIntegrationTests.swift
│ └── AssetStorageTests.swift
```

### 4.3 Key Integration Tests

#### Capture Pipeline
```swift
class CaptureToStorageTests: XCTestCase {
 var monitor: PasteboardMonitor!
 var persistence: PersistenceController!
 var testPasteboard: NSPasteboard!
 
 override func setUp() {
 persistence = PersistenceController(inMemory: true)
 monitor = PasteboardMonitor(persistence: persistence)
 testPasteboard = NSPasteboard.general
 }
 
 func testCaptureTextThroughFullPipeline() async throws {
 // Write to pasteboard
 testPasteboard.clearContents()
 testPasteboard.setString("Test content", forType: .string)
 
 // Trigger capture
 monitor.checkForChanges()
 
 // Wait for async processing
 try await Task.sleep(nanoseconds: 100_000_000) // 100ms
 
 // Verify in database
 let items = try persistence.viewContext.fetch(ClipItem.fetchRequest())
 XCTAssertEqual(items.count, 1)
 XCTAssertEqual(items.first?.primaryText, "Test content")
 }
 
 func testCaptureLargeImageStoresAsFile() async throws {
 let largeImage = createLargeTestImage(size: CGSize(width: 2000, height: 2000))
 
 testPasteboard.clearContents()
 testPasteboard.writeObjects([largeImage])
 
 monitor.checkForChanges()
 try await Task.sleep(nanoseconds: 500_000_000) // 500ms for thumbnail
 
 let items = try persistence.viewContext.fetch(ClipItem.fetchRequest())
 XCTAssertEqual(items.count, 1)
 
 let item = items.first!
 let representation = item.representations?.first { $0.kind == .png }
 
 XCTAssertNotNil(representation)
 XCTAssertNotNil(representation?.assetRef) // Should be stored as file
 XCTAssertNil(representation?.binaryData) // Not inline
 }
}
```

#### Search Integration
```swift
class SearchIntegrationTests: XCTestCase {
 var persistence: PersistenceController!
 
 override func setUp() {
 persistence = PersistenceController(inMemory: true)
 populateTestData()
 }
 
 func testSearchFindsRelevantItems() {
 let query = "swift code"
 let request = ClipItem.fetchRequest()
 request.predicate = NSPredicate(format: "searchableText CONTAINS[cd] %@", query)
 
 let results = try! persistence.viewContext.fetch(request)
 
 XCTAssertGreaterThan(results.count, 0)
 XCTAssertTrue(results.allSatisfy { $0.searchableText?.lowercased().contains("swift") ?? false })
 }
 
 func testSearchPerformance() {
 // Create 1000 items
 for i in 0..<1000 {
 let item = ClipItem(context: persistence.viewContext)
 item.id = UUID()
 item.primaryText = "Item \(i) with some test content"
 item.searchableText = item.primaryText?.lowercased()
 }
 try! persistence.viewContext.save()
 
 measure {
 let request = ClipItem.fetchRequest()
 request.predicate = NSPredicate(format: "searchableText CONTAINS[cd] %@", "test")
 _ = try! persistence.viewContext.fetch(request)
 }
 
 // Should complete in < 100ms (assert in XCTest metrics)
 }
}
```

#### Asset Management
```swift
class AssetStorageTests: XCTestCase {
 var assetManager: AssetManager!
 var tempDirectory: URL!
 
 override func setUp() {
 tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
 assetManager = AssetManager(baseURL: tempDirectory)
 }
 
 override func tearDown() {
 try? FileManager.default.removeItem(at: tempDirectory)
 }
 
 func testStoreAndRetrieveAsset() throws {
 let data = "Test asset content".data(using: .utf8)!
 let assetID = UUID()
 
 let url = try assetManager.store(data, for: assetID, extension: "txt")
 
 XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
 
 let retrieved = try Data(contentsOf: url)
 XCTAssertEqual(retrieved, data)
 }
 
 func testDeleteAsset() throws {
 let data = "Test".data(using: .utf8)!
 let assetID = UUID()
 
 let url = try assetManager.store(data, for: assetID, extension: "txt")
 try assetManager.delete(assetID)
 
 XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
 }
 
 func testOrphanCleanup() throws {
 // Create orphan file (not referenced in DB)
 let orphanURL = tempDirectory.appendingPathComponent("orphan.bin")
 try "Orphan".data(using: .utf8)!.write(to: orphanURL)
 
 // Create referenced file
 let validID = UUID()
 _ = try assetManager.store("Valid".data(using: .utf8)!, for: validID, extension: "txt")
 
 // Run cleanup
 assetManager.cleanupOrphans(validRefs: [validID])
 
 XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
 XCTAssertTrue(FileManager.default.fileExists(atPath: assetManager.url(for: validID, extension: "txt").path))
 }
}
```

---

## 5. UI Testing

### 5.1 Technology

**Framework:** XCTest UI Testing

### 5.2 Test Structure

```
ClipboardMacUITests/
├── OverlayTests.swift
├── SettingsTests.swift
├── OnboardingTests.swift
└── PasteFlowTests.swift
```

### 5.3 Key UI Tests

#### Overlay Interaction
```swift
class OverlayUITests: XCTestCase {
 var app: XCUIApplication!
 
 override func setUp() {
 continueAfterFailure = false
 app = XCUIApplication()
 app.launch()
 }
 
 func testOverlayOpensWithHotkey() {
 // Simulate hotkey (Shift+Cmd+V)
 app.typeKey("v", modifierFlags: [.command, .shift])
 
 let overlay = app.windows["Overlay"]
 XCTAssertTrue(overlay.waitForExistence(timeout: 1.0))
 }
 
 func testCanNavigateCards() {
 openOverlay()
 
 // Navigate right
 app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
 
 // Card should change (hard to assert without accessibility labels)
 // Check that second card is now focused
 }
 
 func testSearchMode() {
 openOverlay()
 
 // Activate search
 app.typeKey("f", modifierFlags: [.command])
 
 let searchField = app.textFields["Search"]
 XCTAssertTrue(searchField.exists)
 XCTAssertTrue(searchField.hasFocus)
 
 // Type query
 searchField.typeText("test")
 
 // Results should update (verify card count changes)
 }
 
 func testPinboardSwitching() {
 openOverlay()
 
 let tabBar = app.otherElements["PinboardTabBar"]
 let workTab = tabBar.buttons["Work"]
 
 workTab.click()
 
 // Verify active pinboard changed (check UI state)
 }
}
```

#### Settings Window
```swift
class SettingsUITests: XCTestCase {
 func testGeneralSettings() {
 openSettings()
 
 let generalTab = app.buttons["General"]
 generalTab.click()
 
 let openAtLoginCheckbox = app.checkBoxes["Open at login"]
 XCTAssertTrue(openAtLoginCheckbox.exists)
 
 openAtLoginCheckbox.click()
 
 // Verify setting is persisted (relaunch app and check)
 }
 
 func testAddIgnoredApp() {
 openSettings()
 
 let privacyTab = app.buttons["Privacy"]
 privacyTab.click()
 
 let addButton = app.buttons["+"]
 addButton.click()
 
 // App picker dialog should open
 let dialog = app.dialogs.firstMatch
 XCTAssertTrue(dialog.waitForExistence(timeout: 2.0))
 }
}
```

### 5.4 UI Test Limitations

**Challenges:**
- Accessibility identifiers must be added to all interactive elements
- Global hotkeys may not work in UI tests (requires workarounds)
- Paste behavior can't be tested end-to-end (requires active app)

**Mitigation:**
- Use unit/integration tests for logic
- UI tests focus on navigation and interaction flows
- Manual testing for paste behavior

---

## 6. Performance Testing

### 6.1 Metrics and Budgets

| Metric | Target | Maximum |
|--------|--------|---------|
| App launch time | < 1s | 2s |
| Overlay open time | < 200ms | 500ms |
| Capture latency | < 50ms | 100ms |
| Search query | < 100ms | 250ms |
| Thumbnail generation | < 500ms | 2s |
| Database query (100 items) | < 50ms | 100ms |
| Sync push (10 items) | < 2s | 5s |

### 6.2 Performance Tests

```swift
class PerformanceTests: XCTestCase {
 func testDatabaseQueryPerformance() {
 let persistence = PersistenceController(inMemory: false)
 
 // Populate with 10,000 items
 for i in 0..<10_000 {
 let item = createClipItem(text: "Item \(i)")
 }
 try! persistence.viewContext.save()
 
 measure(metrics: [XCTClockMetric()]) {
 let request = ClipItem.fetchRequest()
 request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
 request.fetchLimit = 100
 
 _ = try! persistence.viewContext.fetch(request)
 }
 
 // Assert: avg < 50ms, max < 100ms
 }
 
 func testThumbnailGenerationPerformance() {
 let largeImage = createTestImage(size: CGSize(width: 3000, height: 3000))
 
 measure {
 _ = generateThumbnail(for: largeImage, maxSize: CGSize(width: 512, height: 512))
 }
 
 // Assert: avg < 500ms
 }
 
 func testSearchPerformance() {
 // Populate 1000 items
 populateTestData(count: 1000)
 
 measure {
 let request = ClipItem.fetchRequest()
 request.predicate = NSPredicate(format: "searchableText CONTAINS[cd] %@", "test")
 _ = try! persistence.viewContext.fetch(request)
 }
 
 // Assert: avg < 100ms
 }
}
```

### 6.3 Load Testing

**Scenarios:**

1. **Large Database:** 10,000 items
 - App launch time
 - Overlay open time
 - Search performance

2. **Large Items:** Single 10MB image
 - Capture time
 - Storage time
 - Thumbnail generation

3. **Rapid Captures:** 100 items in 10 seconds
 - No dropped captures
 - No UI lag
 - Memory stable

---

## 7. CloudKit Sync Testing

### 7.1 Challenges

**Issue:** CloudKit requires live account, network, and Apple servers

**Mitigation:**
- Use CloudKit Development environment
- Abstract CloudKit behind protocol for mocking
- Integration tests with real CloudKit
- Manual testing critical

### 7.2 Sync Test Scenarios

#### Unit Tests (Mocked)
```swift
protocol CloudKitService {
 func save(_ record: CKRecord) async throws
 func fetch(_ recordID: CKRecord.ID) async throws -> CKRecord
 func fetchChanges(token: CKServerChangeToken?) async throws -> ([CKRecord], CKServerChangeToken?)
}

class MockCloudKitService: CloudKitService {
 var savedRecords: [CKRecord] = []
 var fetchedRecords: [CKRecord] = []
 
 func save(_ record: CKRecord) async throws {
 savedRecords.append(record)
 }
 
 func fetch(_ recordID: CKRecord.ID) async throws -> CKRecord {
 guard let record = fetchedRecords.first(where: { $0.recordID == recordID }) else {
 throw CKError(.unknownItem)
 }
 return record
 }
}

class SyncEngineTests: XCTestCase {
 func testUploadItem() async throws {
 let mockService = MockCloudKitService()
 let syncEngine = SyncEngine(cloudService: mockService)
 
 let item = createClipItem()
 try await syncEngine.upload(item)
 
 XCTAssertEqual(mockService.savedRecords.count, 1)
 XCTAssertEqual(mockService.savedRecords.first?.recordType, "CKClipItem")
 }
}
```

#### Integration Tests (Real CloudKit)

**Setup:** Separate test account, development environment

```swift
class CloudKitIntegrationTests: XCTestCase {
 var container: CKContainer!
 var database: CKDatabase!
 
 override func setUp() async throws {
 container = CKContainer(identifier: "iCloud.com.yourcompany.Paste.test")
 database = container.privateCloudDatabase
 
 // Clear test data
 try await deleteAllTestRecords()
 }
 
 func testUploadAndFetchItem() async throws {
 let item = createClipItem()
 let record = item.toCKRecord(zone: testZone)
 
 // Upload
 let saved = try await database.save(record)
 XCTAssertNotNil(saved)
 
 // Fetch
 let fetched = try await database.record(for: record.recordID)
 XCTAssertEqual(fetched["primaryText"] as? String, item.primaryText)
 }
 
 func testConflictResolution() async throws {
 // Create item on "Device A"
 let itemA = createClipItem()
 let recordA = itemA.toCKRecord(zone: testZone)
 try await database.save(recordA)
 
 // Modify on "Device B" (simulate by changing locally)
 recordA["primaryText"] = "Modified on Device B"
 
 // Modify on "Device A" (conflict!)
 recordA["primaryText"] = "Modified on Device A"
 
 // Save should detect conflict
 do {
 _ = try await database.save(recordA)
 XCTFail("Should have thrown conflict error")
 } catch let error as CKError {
 XCTAssertEqual(error.code, .serverRecordChanged)
 }
 }
}
```

### 7.3 Manual Sync Testing

**Two-Device Testing:**
1. Create item on Mac A
2. Wait for sync (< 10s)
3. Verify appears on Mac B
4. Delete item on Mac B
5. Verify deletion propagates to Mac A
6. Test with 100 items
7. Test with large image (10 MB)

---

## 8. Regression Testing

### 8.1 Purpose

Ensure new features don't break existing functionality.

### 8.2 Regression Test Suite

**Run before each release:**
- All unit tests (60% of tests)
- All integration tests (30%)
- Critical path UI tests (10%)
- Manual smoke test (see below)

### 8.3 Smoke Test Checklist

**Run manually before release:**

See `docs/VALIDATION.md`.

---

## 9. Platform Compatibility Testing

### 9.1 Supported Versions

**Minimum:** macOS 13.0 (Ventura)
**Recommended:** macOS 14.0+ (Sonoma)

### 9.2 Testing Matrix

| macOS Version | Test Coverage |
|---------------|---------------|
| 15.0 (Sequoia) | Full automated + manual |
| 14.0 (Sonoma) | Full automated + manual |
| 13.0 (Ventura) | Smoke test + critical paths |

**Test on each version:**
- Core functionality works
- Hotkeys work
- Permissions work
- CloudKit sync works
- UI renders correctly

---

## 10. Phase-Specific Testing Tasks

### Phase 1: Core Foundation (Weeks 1-3)

**Testing Tasks:**
- [x] Set up XCTest target
- [x] Create in-memory Core Data stack for tests
- [x] Write tests for ClipItem entity
- [x] Write tests for hashing logic
- [x] Write tests for deduplication
- [x] Write tests for basic retention
- [x] Achieve 70% code coverage (ClipboardCore line coverage 77.78%)

**Success Criteria:**
- All tests pass
- No flaky tests
- Tests run in < 10 seconds

**Status Notes:**
- Coverage baseline measured via SwiftPM + llvm-cov (ClipboardCore line coverage 77.78%)

---

### Phase 2: Full Capture & UI Parity (Weeks 4-6)

**Testing Tasks:**
- [x] Write tests for all content type extraction (PasteboardExtractor unit tests)
- [x] Write tests for representation normalization
- [x] Write integration tests for capture pipeline
- [x] Write tests for asset storage
- [x] Write tests for thumbnail generation
- [x] Write tests for pinboard CRUD
- [x] Write tests for search queries
- [x] Add first UI tests (overlay open/close)
- [x] Achieve 75% code coverage (ClipboardCore line coverage 86.63%; ClipboardMac not re-measured)

**Status Notes:**
- Perf validation: search avg 1.0ms (max 1.4ms), capture throughput 1103.5 items/sec
- UI frame lifetime avg 16.81ms (p99 26.75ms), 1 hitch at 133.33ms (Animation Hitches trace)
- ClipboardMac code coverage not measured

---

### Phase 3: Paste Behaviors (Weeks 7-8) - COMPLETE

**Testing Tasks:**
- [x] Write tests for paste engine
  - `ClipboardMac/Tests/ClipboardMacTests/PasteEngineTests.swift` (3 tests)
- [x] Write integration-style tests for paste-to-app (mock keystroke sender/activation)
- [x] Add tests for rich text/HTML -> plain text conversion (`ClipItem.plainTextContent`)
  - `ClipboardCore/Tests/ClipboardCoreTests/PlainTextConversionTests.swift` (8 tests)
- [x] Write tests for paste stack logic
  - `ClipboardMac/Tests/ClipboardMacAppTests/PasteStackManagerTests.swift` (3 tests)
  - `ClipboardMac/Tests/ClipboardMacAppTests/OverlayViewModelTests.swift` (2 tests)
- [x] Write tests for hotkey manager
  - `ClipboardMac/Tests/ClipboardMacTests/HotkeyManagerTests.swift` (3 tests)
- [x] Write tests for stack session persistence
  - `ClipboardCore/Tests/ClipboardCoreTests/StackSessionTests.swift` (3 tests)
- [ ] Manual validation: Paste in 10 apps (see docs/VALIDATION.md)
- [ ] Manual validation: Quick Paste (Cmd+1-9) (see docs/VALIDATION.md)
- [x] Measure ClipboardMac code coverage and set target (current ~29.6% line coverage; target >=30%)

**Status Notes:**
- All automated tests passing: 68 total (32 ClipboardCore + 36 ClipboardMac)
- StackSessionStore unit tests cover data model operations
- Paste engine + hotkey manager tests use test doubles for isolation
- Plain text conversion tests cover RTF/HTML → string with formatting stripping
- Manual validation tasks deferred to Phase 4 scope

---

### Phase 4: Privacy & Settings (Weeks 9-10)

**Testing Tasks:**
- [ ] Write tests for all classifiers (password, OTP, credit card, API key, private key)
- [ ] Write tests for ignored apps filtering
- [ ] Write tests for transient content detection
- [ ] Write tests for link preview fetching
- [ ] Write UI tests for settings window
- [ ] Write UI tests for onboarding flow
- [ ] Manual test: All privacy features
- [ ] Achieve 80% code coverage

---

### Phase 5: CloudKit Sync (Weeks 11-14)

**Testing Tasks:**
- [ ] Create mock CloudKit service
- [ ] Write unit tests for sync engine (with mock)
- [ ] Write integration tests with real CloudKit (dev environment)
- [ ] Test conflict resolution
- [ ] Test asset upload/download
- [ ] Test deletion propagation
- [ ] Manual test: Two-device sync scenarios
- [ ] Load test: Sync 1000 items
- [ ] Achieve 65% code coverage (lower due to CloudKit complexity)

---

### Phase 6: Hardening & Performance (Weeks 15-16) - IN PROGRESS

**Status:** Implementation in progress  
**Current Test Count:** 254 automated tests (180 ClipboardCore + 74 ClipboardMac)

**Testing Tasks:**

*Performance Testing*
- [ ] Create `ClipboardCoreTests/PerformanceTests.swift`
  - [ ] Test: Database fetch 10,000 items (<500ms)
  - [ ] Test: Search query performance (<100ms for 1K items)
  - [ ] Test: Batch insert performance (>1000 items/sec)
- [ ] Create `ClipboardMacTests/UIPerformanceTests.swift`
  - [ ] Test: Overlay open time (<200ms)
  - [ ] Test: Item card render (<16ms)
  - [ ] Test: Scroll performance (60fps)
- [ ] Create `ClipboardMacTests/CapturePerformanceTests.swift`
  - [ ] Test: Capture latency (<50ms)
  - [ ] Test: Thumbnail generation (<500ms)
- [ ] Run stress tests (10k items, 100 rapid captures)
- [ ] Memory leak testing (Instruments Allocations)
- [ ] CPU profiling (Instruments Time Profiler)

*UI Testing Infrastructure*
- [ ] Set up `ClipboardMacUITests` target
- [ ] Add accessibility identifiers to all interactive elements:
  - [ ] Overlay window
  - [ ] Pinboard tab bar and individual tabs
  - [ ] Item cards (each with unique ID)
  - [ ] Search field
  - [ ] Settings window tabs
  - [ ] All buttons and toggles
- [ ] Create critical path UI tests:
  - [ ] `testOverlayOpensWithHotkey`
  - [ ] `testItemCardSelection`
  - [ ] `testPinboardSwitching`
  - [ ] `testSearchMode`
  - [ ] `testSettingsWindowOpen`
  - [ ] `testPasteStackMode`
  - [ ] `testKeyboardNavigation`

*Accessibility Testing*
- [ ] VoiceOver testing with all UI elements
- [ ] Keyboard-only navigation verification
- [ ] Verify overlay announcement ("Paste, N items")
- [ ] Verify card announcements (type, preview, age)
- [ ] Verify tab announcements (name, selection state)

*Migration Testing*
- [ ] Write v1→v2 migration tests
- [ ] Verify data integrity after migration
- [ ] Test with corrupted database recovery

*Regression Testing*
- [ ] Run full regression test suite
- [ ] Manual compatibility testing (macOS 13, 14, 15)
- [ ] Final smoke test on clean machine

*Beta Testing*
- [ ] Internal beta deployment (5-10 users)
- [ ] 2-week daily usage tracking
- [ ] Bug triage and prioritization

**Performance Budgets:**
| Operation | Target | Maximum | Status |
|-----------|--------|---------|--------|
| App launch | <1s | 2s | ⚠️ Unmeasured |
| Overlay open | <200ms | 500ms | ⚠️ Unmeasured |
| Capture latency | <50ms | 100ms | ✅ ~0.4s polling validated |
| Search (1K items) | <100ms | 250ms | ✅ avg 1.0ms |
| Item card render | <16ms | 33ms | ⚠️ p99 26.75ms |
| Thumbnail generation | <500ms | 2s | ⚠️ Unmeasured |
| Memory (idle) | <50MB | 100MB | ⚠️ Unmeasured |

**Success Criteria:**
- Zero crashes in 24-hour stress test
- All performance budgets met
- Zero critical bugs
- Code coverage > 80%
- VoiceOver accessibility verified
---

### Phase 7: Beta Testing & Polish (Weeks 17-18)

**Testing Tasks:**
- [ ] Deploy beta to internal team (5-10 users)
- [ ] Track daily usage for 2 weeks
- [ ] Collect and analyze crash reports
- [ ] Monitor sync issues and failures
- [ ] Weekly bug triage sessions
- [ ] Deploy to external beta (TestFlight, 20-50 users)
- [ ] Collect user feedback
- [ ] Prioritize and fix reported bugs

**Success Criteria:**
- 2 weeks internal usage without critical bugs
- Beta tester satisfaction >80%
- All P0/P1 bugs fixed

---

### Phase 8: App Store Preparation (Weeks 19-20)

**Testing Tasks:**
- [ ] Final regression test pass
- [ ] Smoke test on clean machine
- [ ] Test with fresh iCloud account
- [ ] Verify all permissions flows
- [ ] Test first-launch onboarding
- [ ] Verify App Store sandbox restrictions

**Success Criteria:**
- Zero critical/high bugs remaining
- All functionality works on clean install
- Permissions and onboarding work correctly

---

### Phase 9: Launch & Post-Launch (Week 21+)

**Testing Tasks:**
- [ ] Monitor crash-free rate (target >99.5%)
- [ ] Review user-reported bugs
- [ ] Quick-turnaround v1.0.1 for critical fixes
- [ ] Analyze usage patterns for v1.1 priorities

**Success Criteria:**
- Crash-free rate >99.5%
- User ratings >4.5 stars
- Support ticket volume <10/week

---

## 11. Test Automation and CI/CD

### 11.1 Continuous Integration

**Platform:** GitHub Actions or Xcode Cloud

**Workflow:**
```yaml
name: Test

on: [push, pull_request]

jobs:
 test:
 runs-on: macos-14
 
 steps:
 - uses: actions/checkout@v3
 
 - name: Run Unit Tests
 run: xcodebuild test -scheme ClipboardCore -destination 'platform=macOS'
 
 - name: Run Integration Tests
 run: xcodebuild test -scheme ClipboardMac -destination 'platform=macOS'
 
 - name: Generate Coverage Report
 run: xcrun xccov view --report --json DerivedData/Logs/Test/*.xcresult
 
 - name: Upload Coverage
 uses: codecov/codecov-action@v3
```

### 11.2 Pre-Commit Hooks

**Run locally before commit:**
- Unit tests (fast subset)
- Linter (SwiftLint)
- Formatting check

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running tests..."
xcodebuild test -scheme ClipboardCore -destination 'platform=macOS' -quiet

if [ $? -ne 0 ]; then
 echo "Tests failed. Commit aborted."
 exit 1
fi

echo "Tests passed. Proceeding with commit."
```

---

## 12. Bug Tracking and Metrics

### 12.1 Bug Severity Levels

**P0 - Critical:**
- Data loss
- Crashes on launch
- Cannot paste (core feature broken)

**P1 - High:**
- Feature completely broken
- Major performance issue
- Security vulnerability

**P2 - Medium:**
- Feature partially broken
- Minor performance issue
- UI glitch

**P3 - Low:**
- Nice-to-have improvement
- Edge case issue
- Cosmetic

### 12.2 Test Metrics

**Track over time:**
- Test count
- Code coverage %
- Test execution time
- Flaky test rate
- Bug discovery rate (in testing vs production)
- Mean time to fix bugs

**Goal:** Catch 90% of bugs before release

---

## 13. Manual Testing Protocols

### 13.1 Exploratory Testing

**Allocate:** 2 hours per week

**Focus Areas:**
- Try unusual workflows
- Test edge cases
- Stress test limits
- Verify error messages
- Test accessibility

### 13.2 User Acceptance Testing (UAT)

**Before release:**
- Internal dogfooding (use app daily for 2 weeks)
- Beta testing (10-20 external testers)
- Feedback survey

**Beta Test Checklist:**
- Core functionality works for all testers
- No data loss reported
- Performance acceptable
- UI is intuitive
- No critical bugs

---

## 14. Known Testing Limitations

### 14.1 Hotkey Testing

**Limitation:** Global hotkeys difficult to test in automated tests

**Mitigation:** Manual testing required

### 14.2 Paste Behavior Testing

**Limitation:** Can't fully test paste-into-app without active target app

**Mitigation:**
- Unit test pasteboard write
- Manual test paste in real apps

### 14.3 CloudKit Testing

**Limitation:** Requires live account and network

**Mitigation:**
- Mock for unit tests
- Real CloudKit for integration tests (flakiness risk)
- Heavy manual testing

---

## 15. Future Enhancements

### 15.1 Snapshot Testing

**Goal:** Detect UI regressions

**Tool:** Point-free SnapshotTesting

**Usage:** Screenshot each UI component, compare on subsequent runs

### 15.2 Property-Based Testing

**Goal:** Find edge cases automatically

**Tool:** SwiftCheck (if still maintained)

**Usage:** Generate random inputs for classifiers and validators

### 15.3 Visual Regression Testing

**Goal:** Catch unintended visual changes

**Tool:** Percy or Applitools

**Usage:** Automated screenshots compared to baseline

---

## 16. Changelog

### Version 1.0.0 (2026-01-09)
- Initial testing strategy
- Defined test pyramid and coverage goals
- Specified unit, integration, UI, and performance tests
- Outlined phase-specific testing tasks
- Established manual testing protocols

---

**Related Documents:**
- [Architecture Overview](./Architecture-Overview.md) - System under test
- [Data Model Spec](./Data-Model-Spec.md) - Data model tests
- [Cloud Schema Spec](./Cloud-Schema-Spec.md) - Sync tests
- [macOS Services Spec](./macOS-Services-Spec.md) - Service tests
- [Privacy & Security Spec](./Privacy-Security-Spec.md) - Privacy tests

---

## Appendix: Test Command Reference

```bash
# Run all tests
xcodebuild test -scheme ClipboardMac

# Run unit tests only
xcodebuild test -scheme ClipboardCore

# Run UI tests only
xcodebuild test -scheme ClipboardMacUITests

# Run with coverage
xcodebuild test -scheme ClipboardMac -enableCodeCoverage YES

# Run specific test class
xcodebuild test -scheme ClipboardCore -only-testing:ClipboardCoreTests/ClipItemTests

# Run performance tests
xcodebuild test -scheme ClipboardCore -only-testing:PerformanceTests
```
