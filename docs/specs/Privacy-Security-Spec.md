# Privacy & Security Specification
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.0.0
- **Last Updated:** 2026-01-09
- **Status:** Draft
- **Owner:** Engineering Team
- **Dependencies:** 
 - `Architecture-Overview.md` (parent)
 - `Data-Model-Spec.md` (data protection)
 - `macOS-Services-Spec.md` (capture filtering)

---

## 1. Purpose and Scope

This document defines all privacy and security requirements for the Paste Clipboard Manager. It specifies content filtering, application ignore lists, data encryption, screen sharing behavior, and compliance considerations.

### 1.1 Goals

1. **User control:** Explicit, granular privacy settings
2. **Sensitive content protection:** Automatic detection and filtering
3. **Data security:** Encrypted storage and secure sync
4. **Transparency:** Clear communication about what is collected
5. **Compliance-ready:** Align with privacy regulations (GDPR, CCPA)

### 1.2 Privacy Principles

**Core Tenets:**
- **Local-first:** All processing happens on-device
- **No telemetry:** No usage data sent to servers
- **No third-party tracking:** No analytics SDKs
- **Opt-in sync:** iCloud sync requires explicit user consent
- **User ownership:** User data belongs to the user, fully exportable and deletable

---

## 2. Privacy Settings Overview

### 2.1 Setting Categories

**UI Location:** Settings > Privacy Tab

```
Privacy Settings
├── Visibility
│ └── Show during screen sharing
├── Content Filtering
│ ├── Generate link previews
│ ├── Ignore confidential content
│ └── Ignore transient content
└── Application Filtering
 └── Ignored Applications list
```

---

## 3. Ignored Applications

### 3.1 Purpose

Allow users to prevent clipboard monitoring for specific applications where sensitive data is commonly copied (e.g., password managers, banking apps).

### 3.2 Storage

**Data Model:**
```swift
struct IgnoredApp: Codable {
 var bundleIdentifier: String
 var name: String // Display name
 var iconData: Data? // Cached app icon
 var addedAt: Date
}

// Stored in UserDefaults
@AppStorage("ignoredApps") private var ignoredAppsData: Data = Data()

var ignoredApps: [IgnoredApp] {
 get {
 (try? JSONDecoder().decode([IgnoredApp].self, from: ignoredAppsData)) ?? []
 }
 set {
 ignoredAppsData = (try? JSONEncoder().encode(newValue)) ?? Data()
 }
}
```

### 3.3 Default Ignored Apps

**Pre-populated list (first launch):**
```swift
let defaultIgnoredApps = [
 "com.apple.keychainaccess", // Keychain Access
 "com.apple.Passwords", // Passwords (macOS 14+)
 "com.1password.1password", // 1Password
 "com.agilebits.onepassword7", // 1Password 7
 "com.lastpass.LastPass", // LastPass
 "com.dashlane.dashlanephonefinal", // Dashlane
 "com.bitwarden.desktop", // Bitwarden
 "com.todesktop.230313mzl4w4u92", // Bitwarden (alternate)
]
```

**Rationale:** Users expect password managers to be excluded by default.

### 3.4 Filtering Logic

**Implementation:**
```swift
func shouldCaptureItem(_ snapshot: PasteboardSnapshot) async throws -> Bool {
 // Check ignored apps
 if let sourceApp = snapshot.sourceApp {
 let ignoredBundleIDs = ignoredApps.map { $0.bundleIdentifier }
 
 if ignoredBundleIDs.contains(sourceApp.bundleIdentifier ?? "") {
 os_log("Ignoring clipboard from app: %@", 
 log: .privacy, 
 type: .info, 
 sourceApp.bundleIdentifier ?? "unknown")
 return false
 }
 }
 
 // Additional filters...
 return true
}
```

### 3.5 Limitations

**Known Issue:** macOS does not reliably expose which app wrote to the pasteboard.

**Mitigation:**
- Use frontmost app as best-effort approximation
- Document limitation in settings: "Based on active app when copying"
- Provide manual item deletion if incorrect captures occur

---

## 4. Confidential Content Detection

### 4.1 Purpose

Automatically detect and filter sensitive content types:
- Passwords
- One-time codes (2FA)
- Credit card numbers
- API keys / tokens
- Private keys
- Social Security Numbers (SSN)

### 4.2 Classifier Architecture

```swift
protocol ContentClassifier {
 func classify(_ text: String) -> ClassificationResult
}

enum ClassificationResult {
 case safe
 case sensitive(reason: SensitiveReason)
}

enum SensitiveReason {
 case password
 case oneTimeCode
 case creditCard
 case apiKey
 case privateKey
 case ssn
}

class ConfidentialContentClassifier: ContentClassifier {
 func classify(_ text: String) -> ClassificationResult {
 if isPassword(text) { return .sensitive(.password) }
 if isOneTimeCode(text) { return .sensitive(.oneTimeCode) }
 if isCreditCard(text) { return .sensitive(.creditCard) }
 if isAPIKey(text) { return .sensitive(.apiKey) }
 if isPrivateKey(text) { return .sensitive(.privateKey) }
 if isSSN(text) { return .sensitive(.ssn) }
 
 return .safe
 }
}
```

### 4.3 Detection Heuristics

#### Password Detection

**Indicators:**
- High entropy (randomness)
- Length 8-64 characters
- Mix of uppercase, lowercase, numbers, symbols
- No dictionary words
- Not a URL or email

```swift
func isPassword(_ text: String) -> Bool {
 let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
 
 // Length check
 guard (8...64).contains(trimmed.count) else { return false }
 
 // Must not contain spaces (most passwords don't)
 guard !trimmed.contains(" ") else { return false }
 
 // Must not be a URL
 if trimmed.lowercased().hasPrefix("http") { return false }
 
 // Calculate entropy
 let entropy = calculateEntropy(trimmed)
 
 // High entropy threshold (bits per character)
 guard entropy > 3.5 else { return false }
 
 // Character diversity
 let hasUpper = trimmed.rangeOfCharacter(from: .uppercaseLetters) != nil
 let hasLower = trimmed.rangeOfCharacter(from: .lowercaseLetters) != nil
 let hasDigit = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
 let hasSymbol = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?/~`")) != nil
 
 let diversityScore = [hasUpper, hasLower, hasDigit, hasSymbol].filter { $0 }.count
 
 return diversityScore >= 3
}

func calculateEntropy(_ text: String) -> Double {
 var frequencies: [Character: Int] = [:]
 
 for char in text {
 frequencies[char, default: 0] += 1
 }
 
 let length = Double(text.count)
 var entropy = 0.0
 
 for (_, count) in frequencies {
 let probability = Double(count) / length
 entropy -= probability * log2(probability)
 }
 
 return entropy
}
```

#### One-Time Code Detection

**Patterns:**
- 6-8 digit numeric code
- No other characters
- Copied alone (not part of larger text)

```swift
func isOneTimeCode(_ text: String) -> Bool {
 let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
 
 // Length check: 6-8 digits
 guard (6...8).contains(trimmed.count) else { return false }
 
 // Must be all digits
 guard CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: trimmed)) else {
 return false
 }
 
 return true
}
```

#### Credit Card Detection

**Algorithm:** Luhn check for valid card numbers

```swift
func isCreditCard(_ text: String) -> Bool {
 let digits = text.filter { $0.isNumber }
 
 // Card numbers are 13-19 digits
 guard (13...19).contains(digits.count) else { return false }
 
 // Luhn algorithm
 var sum = 0
 var shouldDouble = false
 
 for char in digits.reversed() {
 guard let digit = Int(String(char)) else { return false }
 
 if shouldDouble {
 let doubled = digit * 2
 sum += doubled > 9 ? doubled - 9 : doubled
 } else {
 sum += digit
 }
 
 shouldDouble.toggle()
 }
 
 return sum % 10 == 0
}
```

#### API Key / Token Detection

**Patterns:**
- JWT tokens (three base64 segments with dots)
- GitHub tokens (ghp_, gho_, ghs_ prefix)
- AWS keys (AKIA prefix)
- Generic: long alphanumeric strings (40+ chars)

```swift
func isAPIKey(_ text: String) -> Bool {
 let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
 
 // JWT pattern
 if trimmed.components(separatedBy: ".").count == 3 {
 let parts = trimmed.components(separatedBy: ".")
 if parts.allSatisfy({ $0.count > 20 && $0.isBase64Like }) {
 return true
 }
 }
 
 // GitHub token prefixes
 let githubPrefixes = ["ghp_", "gho_", "ghs_", "ghu_", "ghr_"]
 if githubPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
 return true
 }
 
 // AWS access key
 if trimmed.hasPrefix("AKIA") && trimmed.count == 20 {
 return true
 }
 
 // Generic: long alphanumeric (likely a token)
 if trimmed.count >= 40 && trimmed.isAlphanumeric && !trimmed.contains(" ") {
 return true
 }
 
 return false
}

extension String {
 var isBase64Like: Bool {
 let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
 return CharacterSet(charactersIn: self).isSubset(of: base64Chars)
 }
 
 var isAlphanumeric: Bool {
 return CharacterSet.alphanumerics.isSuperset(of: CharacterSet(charactersIn: self))
 }
}
```

#### Private Key Detection

**Patterns:**
- PEM format headers (BEGIN RSA PRIVATE KEY, BEGIN PRIVATE KEY, BEGIN OPENSSH PRIVATE KEY)
- SSH key format

```swift
func isPrivateKey(_ text: String) -> Bool {
 let markers = [
 "BEGIN RSA PRIVATE KEY",
 "BEGIN PRIVATE KEY",
 "BEGIN OPENSSH PRIVATE KEY",
 "BEGIN EC PRIVATE KEY",
 "BEGIN DSA PRIVATE KEY",
 "BEGIN PGP PRIVATE KEY",
 ]
 
 return markers.contains { text.contains($0) }
}
```

#### Social Security Number (US)

**Pattern:** XXX-XX-XXXX or XXXXXXXXX

```swift
func isSSN(_ text: String) -> Bool {
 let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
 
 // Pattern with dashes
 let patternWithDashes = "^\\d{3}-\\d{2}-\\d{4}$"
 
 // Pattern without dashes
 let patternNoDashes = "^\\d{9}$"
 
 let regexWithDashes = try? NSRegularExpression(pattern: patternWithDashes)
 let regexNoDashes = try? NSRegularExpression(pattern: patternNoDashes)
 
 let range = NSRange(trimmed.startIndex..., in: trimmed)
 
 if regexWithDashes?.firstMatch(in: trimmed, range: range) != nil {
 return true
 }
 
 if regexNoDashes?.firstMatch(in: trimmed, range: range) != nil {
 return true
 }
 
 return false
}
```

### 4.4 False Positive Mitigation

**Strategy:** Prefer false negatives over false positives

- Threshold adjustments favor letting through borderline cases
- Allow user to manually delete if incorrectly captured
- Future: Machine learning model trained on labeled data

### 4.5 User Feedback

**When content is blocked:**
- No notification (silent filter to avoid interrupting workflow)
- Setting description explains what is filtered
- User can disable filter if too aggressive

**Setting UI:**
```
 Ignore confidential content
 Automatically filters passwords, credit cards, 
 API keys, and other sensitive data.
 
 [Learn more...]
```

---

## 5. Transient Content Detection

### 5.1 Purpose

Some clipboard content is ephemeral and not useful in history:
- Temporary drag-and-drop data
- Inter-app communication markers
- macOS system clipboard placeholders

### 5.2 Detection Strategy

**Approach:** UTI-based filtering

```swift
func isTransient(_ snapshot: PasteboardSnapshot) -> Bool {
 let transientUTIs = [
 "com.apple.pasteboard.promised-file-url", // File promise (drag-drop)
 "com.apple.pasteboard.promised-file-content-type",
 "dyn.age", // Dynamic UTI often used for temp data
 ]
 
 // If only transient types present, skip
 let nonTransientTypes = snapshot.types.filter { uti in
 !transientUTIs.contains(uti.rawValue)
 }
 
 return nonTransientTypes.isEmpty
}
```

### 5.3 Heuristics

**Additional indicators:**
- Very small content (<10 bytes)
- Only system-private UTIs (starting with underscore)
- Known temporary markers from common apps

---

## 6. Link Previews

### 6.1 Purpose

Fetch and display rich previews for copied URLs (title, icon, image).

**Privacy Trade-off:**
- **Enabled:** Better UX, but requires network requests to third-party servers
- **Disabled:** No network leaks, but URLs display as plain text

### 6.2 Implementation

**Technology:** `LinkPresentation` framework

```swift
import LinkPresentation

class LinkPreviewFetcher {
 private let provider = LPMetadataProvider()
 var isEnabled: Bool = true
 
 func fetchPreview(for url: URL) async throws -> LinkPreview {
 guard isEnabled else {
 throw PreviewError.disabled
 }
 
 let metadata = try await provider.startFetchingMetadata(for: url)
 
 var preview = LinkPreview()
 preview.url = url.absoluteString
 preview.title = metadata.title
 preview.summary = metadata.summary
 preview.siteName = metadata.siteName
 
 // Fetch image
 if let imageProvider = metadata.imageProvider {
 let image = try await fetchImage(from: imageProvider)
 preview.imageData = image.pngData()
 }
 
 preview.fetchedAt = Date()
 
 return preview
 }
 
 private func fetchImage(from provider: NSItemProvider) async throws -> NSImage {
 return try await withCheckedThrowingContinuation { continuation in
 provider.loadObject(ofClass: NSImage.self) { image, error in
 if let error = error {
 continuation.resume(throwing: error)
 } else if let image = image as? NSImage {
 continuation.resume(returning: image)
 } else {
 continuation.resume(throwing: PreviewError.invalidImage)
 }
 }
 }
 }
}
```

### 6.3 Privacy Considerations

**What is sent to servers:**
- URL being previewed
- User-Agent header (identifies as macOS app)
- IP address (visible to destination server)

**User Control:**
- Setting to disable link previews entirely
- Previews only fetched for URLs, never for other content types
- No tracking pixels or analytics in fetched HTML

**Disclosure:**
```
Settings > Privacy > Generate link previews

 Generate link previews

When enabled, Paste will fetch metadata from 
websites you copy. This requires sending the URL 
to the website's server.

Your IP address will be visible to the website.
```

### 6.4 Caching

**Strategy:** Cache all fetched previews locally

- Reduces repeat requests
- Faster preview display
- Less network exposure

**Cache Invalidation:**
- Re-fetch after 7 days (configurable)
- User can manually refresh

---

## 7. Screen Sharing Visibility

### 7.1 Purpose

Hide the overlay UI during screen sharing to protect clipboard history from viewers.

**Use Cases:**
- Zoom meetings
- Screen recordings
- Remote desktop sessions
- Presentations

### 7.2 Detection Methods

**Option 1: Manual Toggle**
- User manually enables "Screen Sharing Mode"
- Simplest, but requires user action

**Option 2: Automatic Detection (Limited)**
- macOS does not provide reliable public API for screen sharing detection
- Can detect screen recording via `CGWindowListCreateImage` behavior (unreliable)

**Recommendation:** Hybrid approach
- Provide manual toggle in menu bar (quick access)
- Optional: Heuristic detection as a helper

### 7.3 Implementation

```swift
class ScreenSharingManager: ObservableObject {
 @Published var isScreenSharingModeActive = false
 @AppStorage("showDuringScreenSharing") private var showDuringScreenSharing = true
 
 var shouldShowOverlay: Bool {
 if !showDuringScreenSharing && isScreenSharingModeActive {
 return false
 }
 return true
 }
 
 func toggleScreenSharingMode() {
 isScreenSharingModeActive.toggle()
 
 if isScreenSharingModeActive {
 // Hide overlay immediately
 NotificationCenter.default.post(name: .hideOverlay, object: nil)
 }
 }
}
```

### 7.4 UI Behavior

**When screen sharing mode is active:**
- Overlay does not appear when hotkey is pressed
- Show brief notification: "Paste is hidden during screen sharing"
- Menu bar icon changes to indicate hidden state (optional)

**Quick Toggle:**
- Menu bar: "Screen Sharing Mode" checkbox
- Keyboard: P (configurable)

---

## 8. Data Security

### 8.1 Data at Rest

**Encryption:**
- **Default:** macOS file system encryption (if FileVault is enabled)
- **Enhanced (optional):** Encrypt sensitive fields with user keychain key

**Keychain Integration:**
```swift
import Security

class KeychainManager {
 func storeEncryptionKey(_ key: Data) throws {
 let query: [String: Any] = [
 kSecClass as String: kSecClassGenericPassword,
 kSecAttrAccount as String: "paste-encryption-key",
 kSecValueData as String: key,
 kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
 ]
 
 let status = SecItemAdd(query as CFDictionary, nil)
 
 guard status == errSecSuccess else {
 throw KeychainError.saveFailed(status)
 }
 }
 
 func retrieveEncryptionKey() throws -> Data {
 let query: [String: Any] = [
 kSecClass as String: kSecClassGenericPassword,
 kSecAttrAccount as String: "paste-encryption-key",
 kSecReturnData as String: true,
 ]
 
 var result: AnyObject?
 let status = SecItemCopyMatching(query as CFDictionary, &result)
 
 guard status == errSecSuccess, let data = result as? Data else {
 throw KeychainError.retrieveFailed(status)
 }
 
 return data
 }
}
```

**Encrypted Field Example:**
```swift
extension ClipItem {
 var encryptedPrimaryText: Data? {
 guard let text = primaryText,
 let key = try? keychainManager.retrieveEncryptionKey() else {
 return nil
 }
 
 return try? encrypt(text, with: key)
 }
}

func encrypt(_ text: String, with key: Data) throws -> Data {
 // Use CryptoKit for encryption
 let textData = text.data(using: .utf8)!
 let symmetricKey = SymmetricKey(data: key)
 let sealedBox = try AES.GCM.seal(textData, using: symmetricKey)
 return sealedBox.combined!
}
```

**Decision:** MVP does not include field-level encryption (rely on FileVault + iCloud encryption). Consider for future release.

### 8.2 Data in Transit

**CloudKit Sync:**
- All data encrypted in transit (TLS 1.3)
- CloudKit handles encryption automatically
- Data encrypted at rest on Apple servers

**No Custom Servers:**
- App does not send data to any servers except iCloud
- No analytics endpoints
- No crash reporting to third parties

### 8.3 iCloud Sync Privacy

**User Control:**
- iCloud sync is opt-in (disabled by default)
- Clear disclosure of what is synced

**Settings UI:**
```
 iCloud Sync

Sync your clipboard history across all your 
devices using iCloud.

What's synced:
• Clipboard items and metadata
• Pinboards and organization
• Settings and preferences

Your data is encrypted in transit and at rest 
on Apple's servers. Apple may have access to 
your data.

[Learn more about iCloud security...]
```

---

## 9. Compliance and Legal

### 9.1 Privacy Policy

**Required for App Store:**
- Clear disclosure of data collection
- Explain how data is used
- User rights (access, deletion, portability)

**Key Points to Include:**
- "We do not collect any personal data"
- "All clipboard data is stored locally on your device"
- "If iCloud sync is enabled, data is synced via Apple's iCloud service"
- "We do not use third-party analytics or tracking"

### 9.2 GDPR Considerations

**Applicability:** If offering in EU

**User Rights:**
- **Access:** User can view all data (built-in: browse clipboard history)
- **Deletion:** User can erase history (built-in: "Erase History" button)
- **Portability:** Export data (future: JSON export feature)
- **Consent:** Explicit opt-in for iCloud sync

### 9.3 CCPA Considerations

**Applicability:** If offering in California, USA

**Requirements:**
- Disclose data collection practices (privacy policy)
- Provide deletion mechanism (built-in)
- No sale of data (not applicable: we don't collect data to sell)

### 9.4 App Store Privacy Nutrition Labels

**Data Collected:**
- None (if no iCloud sync)
- If iCloud sync enabled: "User Content" (clipboard history)

**Tracking:**
- None

**Example Label:**
```
Data Used to Track You: None

Data Linked to You:
 - User Content (if iCloud sync enabled)
 
Data Not Linked to You: None
```

---

## 10. User Education and Transparency

### 10.1 Onboarding Disclosure

**Privacy Screen (optional step in onboarding):**

```
Your Privacy Matters

Paste stores your clipboard history locally 
on your Mac.

• No data is sent to our servers
• No analytics or tracking
• You control what is captured

You can customize privacy settings anytime.

[Continue]
```

### 10.2 In-App Documentation

**Help menu item: "Privacy & Security"**

Opens documentation explaining:
- What data is stored
- How ignored apps work
- How sensitive content detection works
- iCloud sync security model
- How to delete data

### 10.3 Transparency Reports

**Option:** Annual transparency report (if app grows large user base)

Content:
- Number of users (aggregated, anonymous)
- Any law enforcement requests (if any, which there shouldn't be for a local app)
- Security incidents (if any)

---

## 11. Phase-Specific Implementation Tasks

### Phase 1-3: No Privacy Features

**Focus:** Core functionality only

**Status:** Deferred (no privacy features implemented yet)

---

### Phase 4: Privacy & Settings (Weeks 9-10)

**Privacy Tasks:**
- [ ] Implement `IgnoredApp` data model
- [ ] Create default ignored apps list
- [ ] Add ignored apps filtering to capture pipeline
- [ ] Implement `ConfidentialContentClassifier`
- [ ] Add password detection heuristic
- [ ] Add OTP detection heuristic
- [ ] Add credit card detection (Luhn algorithm)
- [ ] Add API key detection
- [ ] Add private key detection
- [ ] Test all classifiers with sample data
- [ ] Implement transient content detection
- [ ] Add `LinkPreviewFetcher` with LPMetadataProvider
- [ ] Add link preview toggle in settings
- [ ] Implement screen sharing mode toggle
- [ ] Create Privacy tab UI (all controls)
- [ ] Add app picker for ignored apps
- [ ] Write in-app privacy documentation
- [ ] Draft privacy policy (for App Store)

**Success Criteria:**
- Ignored apps are not captured
- Passwords are filtered when "Ignore confidential" is enabled
- Credit card numbers are filtered
- Link previews fetch correctly (when enabled)
- Screen sharing mode hides overlay

**Deliverables:**
```
ClipboardCore/BusinessRules/
├── IgnoredAppsManager.swift
├── Classifiers/
│ ├── ContentClassifier.swift (protocol)
│ ├── ConfidentialContentClassifier.swift
│ └── TransientContentClassifier.swift
├── LinkPreviewFetcher.swift
└── ScreenSharingManager.swift

ClipboardMac/UI/Settings/
└── PrivacyTab.swift

docs/
├── PrivacyPolicy.md
└── SecurityDocumentation.md
```

---

### Phase 5: CloudKit Sync (Weeks 11-14)

**Privacy Tasks:**
- [ ] Add iCloud sync privacy disclosure in UI
- [ ] Make iCloud sync opt-in (disabled by default)
- [ ] Show clear explanation of what is synced
- [ ] Test that disabled sync prevents all network traffic
- [ ] Validate encryption in transit (TLS verification)

---

### Phase 6: Hardening (Weeks 15-16)

**Privacy Tasks:**
- [ ] Security audit of classifier logic
- [ ] Test with known sensitive data samples (passwords, keys)
- [ ] Measure false positive/negative rates
- [ ] Review all network requests (should only be iCloud + link previews)
- [ ] Validate data isolation (no cross-user leaks)
- [ ] Test with multiple user accounts on same Mac
- [ ] Finalize privacy policy
- [ ] Submit App Store privacy nutrition label

**Success Criteria:**
- Zero false negatives for common sensitive patterns
- False positive rate < 5%
- No unauthorized network requests
- Privacy policy approved by legal (if applicable)

---

## 12. Testing Strategy

### 12.1 Classifier Testing

```swift
func testPasswordDetection() {
 let classifier = ConfidentialContentClassifier()
 
 // True positives
 XCTAssertEqual(classifier.classify("aB3$xY9!mN2@"), .sensitive(.password))
 XCTAssertEqual(classifier.classify("MyP@ssw0rd!123"), .sensitive(.password))
 
 // False negatives (should be safe)
 XCTAssertEqual(classifier.classify("https://example.com"), .safe)
 XCTAssertEqual(classifier.classify("user@example.com"), .safe)
 XCTAssertEqual(classifier.classify("Hello, world!"), .safe)
}

func testCreditCardDetection() {
 let classifier = ConfidentialContentClassifier()
 
 // Valid credit card (test number)
 XCTAssertEqual(classifier.classify("4532015112830366"), .sensitive(.creditCard))
 
 // Invalid (failed Luhn check)
 XCTAssertEqual(classifier.classify("4532015112830367"), .safe)
}
```

### 12.2 Integration Testing

**Ignored Apps:**
1. Add "Safari" to ignored apps
2. Copy text from Safari
3. Verify: Not captured
4. Copy from another app
5. Verify: Captured

**Confidential Content:**
1. Enable "Ignore confidential content"
2. Copy a strong password
3. Verify: Not captured (check logs)
4. Copy normal text
5. Verify: Captured

**Link Previews:**
1. Enable link previews
2. Copy https://github.com
3. Verify: Preview fetched, title and icon displayed
4. Disable link previews
5. Copy another URL
6. Verify: No preview, displays as plain URL

### 12.3 Manual Testing Checklist

- [ ] Copy password from 1Password Not captured
- [ ] Copy 6-digit OTP Not captured
- [ ] Copy credit card number Not captured
- [ ] Copy API key (JWT format) Not captured
- [ ] Copy private key (PEM format) Not captured
- [ ] Copy normal text Captured
- [ ] Add app to ignored list Subsequent copies from that app not captured
- [ ] Enable screen sharing mode Overlay does not appear
- [ ] Disable screen sharing mode Overlay works normally
- [ ] Enable link previews URLs show rich preview
- [ ] Disable link previews URLs show as plain text
- [ ] Disable iCloud sync No network traffic to Apple servers (verify with network monitor)

---

## 13. Known Limitations

### 13.1 Source App Detection

**Limitation:** macOS does not expose "which app wrote to pasteboard"

**Impact:** Ignored apps list uses frontmost app (approximation)

**Mitigation:**
- Document limitation
- Recommend users avoid switching apps immediately after copying
- Future: Explore private APIs or system extensions (if feasible)

### 13.2 False Positives/Negatives

**Limitation:** Heuristic classifiers are not perfect

**Impact:**
- Some passwords may not be detected (false negative)
- Some non-sensitive text may be blocked (false positive)

**Mitigation:**
- Tune thresholds conservatively
- Allow users to disable filtering
- Provide manual deletion

### 13.3 Screen Sharing Detection

**Limitation:** No reliable public API for detecting active screen sharing

**Impact:** Automatic screen sharing mode is not possible

**Mitigation:**
- Manual toggle only
- Quick-access in menu bar
- Document in user guide

---

## 14. Future Enhancements

### 14.1 Machine Learning Classifier

**Goal:** More accurate sensitive content detection

**Approach:**
- Train model on labeled dataset (passwords, credit cards, API keys, vs normal text)
- Use Core ML for on-device inference
- Update heuristics with ML predictions

**Privacy:** All training and inference on-device (no cloud ML)

### 14.2 Encrypted Local Database

**Goal:** Encrypt clipboard history even if FileVault is off

**Approach:**
- Generate user key in Keychain
- Encrypt sensitive fields in Core Data
- Decrypt on-demand for display

**Trade-off:** Performance overhead (encryption/decryption on every access)

### 14.3 Selective Sync

**Goal:** Sync only non-sensitive items to iCloud

**Approach:**
- Mark sensitive items as local-only
- Exclude from CloudKit upload
- UI: "Sync sensitive items" toggle

### 14.4 Export and Deletion

**Goal:** GDPR compliance, user data control

**Approach:**
- Export to JSON (all clipboard history)
- Import from JSON (for migration)
- Complete data deletion with confirmation

---

## 15. Changelog

### Version 1.0.0 (2026-01-09)
- Initial privacy and security specification
- Defined ignored apps system
- Specified confidential content classifiers
- Outlined link preview privacy model
- Detailed phase-specific privacy tasks

---

**Related Documents:**
- [Architecture Overview](./Architecture-Overview.md)
- [Data Model Spec](./Data-Model-Spec.md) - Sensitive data fields
- [macOS Services Spec](./macOS-Services-Spec.md) - Capture filtering
- [Cloud Schema Spec](./Cloud-Schema-Spec.md) - Sync security
