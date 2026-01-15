# macOS Services Specification
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.1.0
- **Last Updated:** 2026-01-14
- **Status:** Draft
- **Owner:** Engineering Team
- **Dependencies:** 
 - `Architecture-Overview.md` (parent)
 - `Data-Model-Spec.md` (data persistence)
 - `UI-Contract-Spec.md` (UI integration)

---

## 1. Purpose and Scope

This document defines all macOS-specific system integrations and services for the Paste Clipboard Manager. It covers clipboard monitoring, paste injection, hotkey management, and other platform-specific functionality.

### 1.1 Goals

1. **Reliable capture:** Detect and capture all clipboard changes
2. **Seamless pasting:** Inject content into active apps without user friction
3. **Global accessibility:** Hotkeys work from any application
4. **Privacy-aware:** Respect system security and user permissions
5. **Resource-efficient:** Minimal CPU/battery impact when idle

---

## 2. Pasteboard Monitoring Service

### 2.1 Technology Choice

**Primary Approach:** Poll `NSPasteboard.general.changeCount`

**Rationale:**
- Only reliable method for continuous monitoring
- No official pasteboard notification API
- Acceptable performance with smart polling

**Rejected Alternatives:**
- KVO on pasteboard (not supported)
- File system monitoring of pasteboard files (fragile, undocumented)

### 2.2 Architecture

```swift
class PasteboardMonitor: ObservableObject {
 private let pasteboard = NSPasteboard.general
 private var lastChangeCount: Int = 0
 private var timer: Timer?
 private var isMonitoring = false
 
 // Settings
 var pollInterval: TimeInterval = 0.5 // 500ms default
 var isEnabled: Bool = true
 
 // Callbacks
 var onClipboardChange: ((NSPasteboard) -> Void)?
 
 func start()
 func stop()
 func pause()
 func resume()
}
```

### 2.3 Polling Strategy

#### Basic Polling

```swift
func start() {
 guard !isMonitoring else { return }
 
 lastChangeCount = pasteboard.changeCount
 isMonitoring = true
 
 timer = Timer.scheduledTimer(
 withTimeInterval: pollInterval,
 repeats: true
 ) { [weak self] _ in
 self?.checkForChanges()
 }
 
 // Use RunLoop.common to work during modal dialogs
 RunLoop.current.add(timer!, forMode: .common)
}

private func checkForChanges() {
 let currentCount = pasteboard.changeCount
 
 guard currentCount != lastChangeCount else {
 return // No change
 }
 
 lastChangeCount = currentCount
 
 // Ignore changes made by this app
 if ignoreNextChange {
 ignoreNextChange = false
 return
 }
 
 onClipboardChange?(pasteboard)
}
```

#### Adaptive Polling

**Optimization:** Adjust poll frequency based on activity

```swift
enum PollState {
 case active // 250ms - recent activity
 case moderate // 500ms - some activity
 case idle // 1000ms - no activity
}

private var pollState: PollState = .active
private var lastActivityTime: Date = Date()
private let activityThreshold: TimeInterval = 30.0 // 30 seconds

func checkForChanges() {
 let currentCount = pasteboard.changeCount
 
 if currentCount != lastChangeCount {
 // Activity detected
 lastActivityTime = Date()
 updatePollState(.active)
 
 lastChangeCount = currentCount
 processClipboardChange()
 } else {
 // No activity - adjust polling
 let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)
 
 if timeSinceActivity > 300 { // 5 minutes
 updatePollState(.idle)
 } else if timeSinceActivity > activityThreshold {
 updatePollState(.moderate)
 }
 }
}

func updatePollState(_ newState: PollState) {
 guard newState != pollState else { return }
 
 pollState = newState
 
 // Restart timer with new interval
 timer?.invalidate()
 
 let interval: TimeInterval
 switch newState {
 case .active: interval = 0.25
 case .moderate: interval = 0.5
 case .idle: interval = 1.0
 }
 
 timer = Timer.scheduledTimer(
 withTimeInterval: interval,
 repeats: true
 ) { [weak self] _ in
 self?.checkForChanges()
 }
 
 RunLoop.current.add(timer!, forMode: .common)
}
```

### 2.4 Feedback Loop Prevention

**Problem:** App writes to pasteboard Monitor detects "change" Infinite loop

**Solution:** Flag self-initiated changes

```swift
private var ignoreNextChange = false

func writeToPasteboard(_ item: ClipItem) {
 ignoreNextChange = true
 
 pasteboard.clearContents()
 pasteboard.writeObjects([item.toPasteboardItem()])
 
 lastChangeCount = pasteboard.changeCount
}
```

**Alternative:** Track content hash

```swift
private var lastWrittenHash: String?

func writeToPasteboard(_ item: ClipItem) {
 lastWrittenHash = item.contentHash
 
 pasteboard.clearContents()
 pasteboard.writeObjects([item.toPasteboardItem()])
}

func checkForChanges() {
 // ... change detected ...
 
 let currentHash = computeHash(from: pasteboard)
 
 if currentHash == lastWrittenHash {
 return // Ignore, we just wrote this
 }
 
 processClipboardChange()
}
```

### 2.5 Capture Pipeline

```swift
func processClipboardChange() {
 Task.detached(priority: .userInitiated) {
 do {
 let snapshot = try await self.capturePasteboardSnapshot()
 let item = try await self.normalizeToClipItem(snapshot)
 
 // Apply filters
 guard try await self.shouldCaptureItem(item) else {
 return
 }
 
 // Persist
 try await self.persistenceController.saveClipItem(item)
 
 // Trigger sync
 await self.syncCoordinator.enqueueChange(item)
 
 // Notify UI
 await MainActor.run {
 NotificationCenter.default.post(
 name: .clipboardItemCaptured,
 object: item
 )
 }
 
 } catch {
 os_log("Failed to capture clipboard: %@", log: .capture, type: .error, error.localizedDescription)
 }
 }
}
```

### 2.6 Snapshot Extraction

```swift
struct PasteboardSnapshot {
 var items: [NSPasteboardItem]
 var types: Set<NSPasteboard.PasteboardType>
 var strings: [String]?
 var urls: [URL]?
 var images: [NSImage]?
 var sourceApp: NSRunningApplication?
}

func capturePasteboardSnapshot() async throws -> PasteboardSnapshot {
 return try await MainActor.run {
 guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
 throw CaptureError.emptyPasteboard
 }
 
 var snapshot = PasteboardSnapshot(items: items, types: [])
 
 // Extract types
 for item in items {
 snapshot.types.formUnion(item.types)
 }
 
 // Extract common types
 snapshot.strings = pasteboard.string(forType: .string).map { [$0] }
 snapshot.urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
 snapshot.images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage]
 
 // Get source app (best-effort)
 snapshot.sourceApp = NSWorkspace.shared.frontmostApplication
 
 return snapshot
 }
}
```

---

## 3. Content Normalization

### 3.1 Type Detection

```swift
enum ItemType: Int16 {
 case text = 0
 case richText = 1
 case image = 2
 case file = 3
 case url = 4
 case code = 5
 case mixed = 99
}

func detectItemType(_ snapshot: PasteboardSnapshot) -> ItemType {
 // Priority order (most specific first)
 
 if snapshot.types.contains(.fileURL) {
 return .file
 }
 
 if snapshot.types.contains(.tiff) || snapshot.types.contains(.png) {
 return .image
 }
 
 if let string = snapshot.strings?.first {
 if string.isValidURL {
 return .url
 }
 
 if string.looksLikeCode {
 return .code
 }
 }
 
 if snapshot.types.contains(.rtf) || snapshot.types.contains(.html) {
 return .richText
 }
 
 if snapshot.types.contains(.string) {
 return .text
 }
 
 return .mixed
}
```

### 3.2 Code Detection Heuristics

```swift
extension String {
 var looksLikeCode: Bool {
 let codeIndicators = [
 contains("func "),
 contains("class "),
 contains("import "),
 contains("const "),
 contains("function "),
 contains("public "),
 contains("#include"),
 contains("def "),
 contains("<html"),
 contains("SELECT "),
 ]
 
 let indicatorCount = codeIndicators.filter { $0 }.count
 
 // If 2+ indicators, likely code
 if indicatorCount >= 2 {
 return true
 }
 
 // Check for typical code structure
 let lines = components(separatedBy: .newlines)
 let indentedLines = lines.filter { $0.hasPrefix(" ") || $0.hasPrefix("\t") }
 let bracketCount = filter { $0 == "{" || $0 == "}" }.count
 
 if indentedLines.count > 3 && bracketCount > 2 {
 return true
 }
 
 return false
 }
}
```

### 3.3 Multi-Representation Extraction

```swift
func extractRepresentations(_ snapshot: PasteboardSnapshot) async throws -> [ClipRepresentation] {
 var representations: [ClipRepresentation] = []
 var order: Int16 = 0
 
 // Plain text (highest priority for preview)
 if let string = snapshot.strings?.first {
 let rep = ClipRepresentation(context: context)
 rep.uti = "public.utf8-plain-text"
 rep.kind = .plainText
 rep.textData = string.data(using: .utf8)
 rep.displayOrder = order
 representations.append(rep)
 order += 1
 }
 
 // RTF
 if let rtfData = pasteboard.data(forType: .rtf) {
 let rep = ClipRepresentation(context: context)
 rep.uti = "public.rtf"
 rep.kind = .rtf
 rep.textData = rtfData
 rep.displayOrder = order
 representations.append(rep)
 order += 1
 }
 
 // HTML
 if let htmlData = pasteboard.data(forType: .html) {
 let rep = ClipRepresentation(context: context)
 rep.uti = "public.html"
 rep.kind = .html
 rep.textData = htmlData
 rep.displayOrder = order
 representations.append(rep)
 order += 1
 }
 
 // Images
 if let image = snapshot.images?.first {
 let rep = try await createImageRepresentation(image, order: order)
 representations.append(rep)
 order += 1
 }
 
 // File URLs
 if let urls = snapshot.urls {
 for url in urls {
 let rep = createFileRepresentation(url, order: order)
 representations.append(rep)
 order += 1
 }
 }
 
 return representations
}

func createImageRepresentation(_ image: NSImage, order: Int16) async throws -> ClipRepresentation {
 let rep = ClipRepresentation(context: context)
 rep.uti = "public.png"
 rep.kind = .png
 rep.displayOrder = order
 
 // Convert to PNG
 guard let tiff = image.tiffRepresentation,
 let bitmap = NSBitmapImageRep(data: tiff),
 let pngData = bitmap.representation(using: .png, properties: [:]) else {
 throw CaptureError.imageConversionFailed
 }
 
 // If large, write to file
 if pngData.count > 1_000_000 { // 1 MB
 let assetRef = UUID()
 let path = "Assets/\(assetRef.uuidString).png"
 let url = assetManager.assetURL(for: path)
 
 try pngData.write(to: url)
 rep.assetRef = assetRef
 rep.byteCount = Int64(pngData.count)
 } else {
 rep.binaryData = pngData
 rep.byteCount = Int64(pngData.count)
 }
 
 return rep
}
```

---

## 4. Pasting Engine

### 4.1 Paste Modes

```swift
enum PasteMode {
 case toActiveApp // Paste into previously active app
 case toClipboard // Write to clipboard only
}

enum PasteFormat {
 case preserved // Keep rich formatting
 case plainText // Strip all formatting
}
```

### 4.2 Active App Tracking

```swift
class ActiveAppTracker {
 private(set) var recordedApp: NSRunningApplication?
 
 func recordFrontmostApp() {
 recordedApp = NSWorkspace.shared.frontmostApplication
 
 os_log("Recorded frontmost app: %@", 
 log: .paste, 
 type: .info, 
 recordedApp?.bundleIdentifier ?? "unknown")
 }
 
 func reactivateRecordedApp() {
 guard let app = recordedApp else {
 os_log("No recorded app to reactivate", log: .paste, type: .error)
 return
 }
 
 app.activate(options: .activateIgnoringOtherApps)
 }
}
```

### 4.3 Paste to Active App

**Flow:**
1. Record frontmost app when overlay opens
2. User selects item
3. Write item to pasteboard
4. Re-activate recorded app
5. Send synthetic Command+V
6. Close overlay

**Implementation:**

```swift
func pasteToActiveApp(_ item: ClipItem, format: PasteFormat) async throws {
 // 1. Write to pasteboard
 await writeToPasteboard(item, format: format)
 
 // 2. Reactivate app
 await MainActor.run {
 activeAppTracker.reactivateRecordedApp()
 }
 
 // 3. Small delay for app activation
 try await Task.sleep(nanoseconds: 50_000_000) // 50ms
 
 // 4. Send Command+V
 try await sendPasteKeystroke()
 
 // 5. Close overlay
 await MainActor.run {
 overlayWindow.close()
 }
}

func sendPasteKeystroke() async throws {
 // Check Accessibility permission
 guard AXIsProcessTrusted() else {
 throw PasteError.accessibilityPermissionDenied
 }
 
 // Create Command+V event
 let source = CGEventSource(stateID: .hidSystemState)
 
 // Key down for Command
 let cmdDown = CGEvent(
 keyboardEventSource: source,
 virtualKey: CGKeyCode(kVK_Command),
 keyDown: true
 )
 cmdDown?.flags = .maskCommand
 
 // Key down for V
 let vDown = CGEvent(
 keyboardEventSource: source,
 virtualKey: CGKeyCode(kVK_ANSI_V),
 keyDown: true
 )
 vDown?.flags = .maskCommand
 
 // Key up for V
 let vUp = CGEvent(
 keyboardEventSource: source,
 virtualKey: CGKeyCode(kVK_ANSI_V),
 keyDown: false
 )
 vUp?.flags = .maskCommand
 
 // Key up for Command
 let cmdUp = CGEvent(
 keyboardEventSource: source,
 virtualKey: CGKeyCode(kVK_Command),
 keyDown: false
 )
 
 // Post events
 cmdDown?.post(tap: .cghidEventTap)
 vDown?.post(tap: .cghidEventTap)
 vUp?.post(tap: .cghidEventTap)
 cmdUp?.post(tap: .cghidEventTap)
}
```

**Alternative: Accessibility API Paste**

```swift
func pasteUsingAccessibility(_ item: ClipItem) throws {
 guard let app = activeAppTracker.recordedApp,
 let element = AXUIElementCreateApplication(app.processIdentifier) else {
 throw PasteError.noActiveApp
 }
 
 // Get focused element
 var focusedElement: CFTypeRef?
 let result = AXUIElementCopyAttributeValue(
 element,
 kAXFocusedUIElementAttribute as CFString,
 &focusedElement
 )
 
 guard result == .success,
 let focused = focusedElement else {
 throw PasteError.noFocusedElement
 }
 
 // Perform paste action
 AXUIElementPerformAction(
 focused as! AXUIElement,
 kAXPasteAction as CFString
 )
}
```

### 4.4 Plain Text Conversion

```swift
func writeToPasteboard(_ item: ClipItem, format: PasteFormat) async {
 await MainActor.run {
 pasteboard.clearContents()
 
 switch format {
 case .preserved:
 // Write all representations
 writeAllRepresentations(item)
 
 case .plainText:
 // Write plain text only
 if let plainText = item.plainTextContent {
 pasteboard.setString(plainText, forType: .string)
 }
 }
 
 ignoreNextChange = true
 lastChangeCount = pasteboard.changeCount
 }
}

extension ClipItem {
 var plainTextContent: String? {
 // Priority: explicit plain text rep > derived from rich > URL
 
 if let plainRep = representations?.first(where: { $0.kind == .plainText }),
 let data = plainRep.textData,
 let string = String(data: data, encoding: .utf8) {
 return string
 }
 
 if let rtfRep = representations?.first(where: { $0.kind == .rtf }),
 let data = rtfRep.textData,
 let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
 return attributed.string
 }
 
 if let htmlRep = representations?.first(where: { $0.kind == .html }),
 let data = htmlRep.textData,
 let attributed = NSAttributedString(html: data, documentAttributes: nil) {
 return attributed.string
 }
 
 if itemType == .url {
 return primaryText // URL string
 }
 
 return primaryText
 }
}
```

### 4.5 Paste Stack Implementation

**Strategy:** Sequential paste with delays

```swift
func pasteStack(_ session: StackSession) async throws {
 let entries = session.entries?.sorted(by: { $0.position < $1.position }) ?? []
 
 guard !entries.isEmpty else {
 throw PasteError.emptyStack
 }
 
 // Record app
 activeAppTracker.recordFrontmostApp()
 
 // Reactivate
 activeAppTracker.reactivateRecordedApp()
 try await Task.sleep(nanoseconds: 50_000_000) // 50ms
 
 for (index, entry) in entries.enumerated() {
 guard let item = entry.clipItem else { continue }
 
 // Write to pasteboard
 await writeToPasteboard(item, format: .preserved)
 
 // Paste
 try await sendPasteKeystroke()
 
 // Separator handling
 if index < entries.count - 1 {
 // Optionally insert separator
 if session.mode == .combined {
 await insertSeparator(session.separator)
 }
 
 // Delay before next paste
 try await Task.sleep(nanoseconds: 150_000_000) // 150ms
 }
 }
 
 // Close overlay
 await MainActor.run {
 overlayWindow.close()
 }
}

func insertSeparator(_ separator: String) async {
 await MainActor.run {
 pasteboard.clearContents()
 pasteboard.setString(separator, forType: .string)
 ignoreNextChange = true
 }
 
 try? await sendPasteKeystroke()
}
```

---

## 5. Hotkey Management

### 5.1 Technology Choice

**Primary:** `CGEvent` API with event tap

**Alternative:** Third-party libraries (KeyboardShortcuts.swift)

### 5.2 Architecture

```swift
class HotkeyManager: ObservableObject {
 struct Hotkey: Codable {
 var keyCode: UInt16
 var modifiers: NSEvent.ModifierFlags
 var action: String // Identifier
 }
 
 private var eventTap: CFMachPort?
 private var hotkeys: [String: Hotkey] = [:]
 private var handlers: [String: () -> Void] = [:]
 
 func register(action: String, hotkey: Hotkey, handler: @escaping () -> Void)
 func unregister(action: String)
 func start()
 func stop()
}
```

### 5.3 Event Tap Implementation

```swift
func start() {
 guard eventTap == nil else { return }
 
 // Create event tap
 let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
 
 guard let tap = CGEvent.tapCreate(
 tap: .cgSessionEventTap,
 place: .headInsertEventTap,
 options: .defaultTap,
 eventsOfInterest: mask,
 callback: { proxy, type, event, refcon in
 let manager = Unmanaged<HotkeyManager>
 .fromOpaque(refcon!)
 .takeUnretainedValue()
 
 return manager.handleEvent(proxy: proxy, type: type, event: event)
 },
 userInfo: Unmanaged.passUnretained(self).toOpaque()
 ) else {
 os_log("Failed to create event tap", log: .hotkey, type: .error)
 return
 }
 
 eventTap = tap
 
 let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
 CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
 CGEvent.tapEnable(tap: tap, enable: true)
 
 os_log("Hotkey event tap started", log: .hotkey, type: .info)
}

func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
 guard type == .keyDown else {
 return Unmanaged.passUnretained(event)
 }
 
 let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
 let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
 
 // Check if matches any registered hotkey
 for (action, hotkey) in hotkeys {
 if keyCode == hotkey.keyCode && flags.contains(hotkey.modifiers) {
 // Execute handler on main thread
 DispatchQueue.main.async {
 self.handlers[action]?()
 }
 
 // Consume event (don't pass to other apps)
 return nil
 }
 }
 
 // Pass through
 return Unmanaged.passUnretained(event)
}
```

### 5.4 Default Hotkeys

```swift
enum DefaultHotkey {
 static let activatePaste = Hotkey(
 keyCode: UInt16(kVK_ANSI_V),
 modifiers: [.command, .shift],
 action: "activatePaste"
 )
 
 static let activatePasteStack = Hotkey(
 keyCode: UInt16(kVK_ANSI_C),
 modifiers: [.command, .shift],
 action: "activatePasteStack"
 )
 
 static let nextPinboard = Hotkey(
 keyCode: UInt16(kVK_RightArrow),
 modifiers: [.command],
 action: "nextPinboard"
 )
 
 static let previousPinboard = Hotkey(
 keyCode: UInt16(kVK_LeftArrow),
 modifiers: [.command],
 action: "previousPinboard"
 )
 
 static func quickPaste(_ number: Int) -> Hotkey {
 let keyCodes: [UInt16] = [
 UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
 UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6),
 UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
 ]
 
 return Hotkey(
 keyCode: keyCodes[number - 1],
 modifiers: [.command],
 action: "quickPaste\(number)"
 )
 }
}
```

### 5.5 Permission Handling

```swift
func checkInputMonitoringPermission() -> Bool {
 // Check if app has Input Monitoring permission
 // Required for global hotkeys
 
 let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
 return AXIsProcessTrustedWithOptions(options)
}

func requestInputMonitoringPermission() {
 let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
 _ = AXIsProcessTrustedWithOptions(options)
}
```

### 5.6 Modifier Key Monitoring
**Purpose:** Detect Shift key state for "Paste as Plain Text"

**Implementation:**
- Uses `NSEvent.addLocalMonitorForEvents` for modifier flags
- Updates `OverlayViewModel` state in real-time
- Visual indicator in footer toggles when Shift is held

---

## 6. Login Item Management

### 6.1 Modern Approach (SMAppService)

**Technology:** `SMAppService` (macOS 13+)

**Advantages:**
- Declarative
- User-controllable in System Settings
- No helper app required

```swift
import ServiceManagement

class LoginItemManager {
 private let service = SMAppService.mainApp
 
 var isEnabled: Bool {
 return service.status == .enabled
 }
 
 func enable() throws {
 guard service.status != .enabled else { return }
 
 try service.register()
 
 os_log("Login item enabled", log: .lifecycle, type: .info)
 }
 
 func disable() throws {
 guard service.status == .enabled else { return }
 
 try service.unregister()
 
 os_log("Login item disabled", log: .lifecycle, type: .info)
 }
}
```

### 6.2 Fallback for macOS 12 and Earlier

**Technology:** `SMLoginItemSetEnabled` (deprecated but necessary for older macOS)

```swift
#if !targetEnvironment(macCatalyst)
import ServiceManagement

func enableLoginItemLegacy() -> Bool {
 let identifier = "com.yourcompany.PasteHelper" as CFString
 return SMLoginItemSetEnabled(identifier, true)
}
#endif
```

---

## 7. Sound Effects

### 7.1 Audio Playback

```swift
import AVFoundation

class SoundEffectPlayer {
 private var players: [String: AVAudioPlayer] = [:]
 var isEnabled: Bool = true
 
 enum Sound: String {
 case capture = "capture.wav"
 case paste = "paste.wav"
 case delete = "delete.wav"
 }
 
 init() {
 preloadSounds()
 }
 
 func preloadSounds() {
 for sound in [Sound.capture, Sound.paste, Sound.delete] {
 guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: nil) else {
 continue
 }
 
 do {
 let player = try AVAudioPlayer(contentsOf: url)
 player.prepareToPlay()
 players[sound.rawValue] = player
 } catch {
 os_log("Failed to load sound: %@", log: .audio, type: .error, sound.rawValue)
 }
 }
 }
 
 func play(_ sound: Sound, volume: Float = 1.0) {
 guard isEnabled else { return }
 
 guard let player = players[sound.rawValue] else {
 os_log("Sound not found: %@", log: .audio, type: .error, sound.rawValue)
 return
 }
 
 player.volume = volume
 player.play()
 }
}
```

### 7.2 Respect System Settings

```swift
extension SoundEffectPlayer {
    var shouldPlaySounds: Bool {
        // Respect Do Not Disturb
        // Note: No public API for DND status, but we can respect user's setting
        
        guard isEnabled else { return false }
        
        // Could check system volume
        // Could check focus modes (private API)
        
        return true
    }
}
```

### 7.3 Implemented Sounds

- **Pop** (Selection/Action)
- **Submarine** (Error/Limit)
- **Glass** (Success/Paste)
- Uses `NSSound` (System sounds) rather than custom WAV files for native integration.

---

## 8. Background Operation

### 8.1 LSUIElement Configuration

**Option 1: Always background (no dock icon)**

In `Info.plist`:
```xml
<key>LSUIElement</key>
<true/>
```

**Option 2: Toggle at runtime (not supported cleanly)**

For dynamic toggling, ship two configurations or use a helper app.

### 8.2 App Lifecycle

```swift
@main
struct PasteApp: App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
 @StateObject private var pasteboardMonitor = PasteboardMonitor()
 
 var body: some Scene {
 MenuBarExtra("Paste", systemImage: "doc.on.clipboard") {
 MenuBarView()
 }
 .menuBarExtraStyle(.menu)
 
 Settings {
 SettingsView()
 }
 }
}

class AppDelegate: NSObject, NSApplicationDelegate {
 func applicationDidFinishLaunching(_ notification: Notification) {
 // Start monitoring
 pasteboardMonitor.start()
 
 // Register hotkeys
 hotkeyManager.start()
 
 // Check permissions
 checkPermissions()
 }
 
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
 // Keep running in background
 return false
 }
}
```

---

## 9. Permissions and Onboarding

### 9.1 Required Permissions

**1. Accessibility**
- Purpose: Paste into active apps, send keystrokes
- Request: Prompt user to open System Settings

**2. Input Monitoring** (optional, depending on hotkey implementation)
- Purpose: Global hotkey detection
- Request: Automatically prompted by system

### 9.2 Permission Checking

```swift
class PermissionManager: ObservableObject {
 @Published var hasAccessibility = false
 @Published var hasInputMonitoring = false
 
 func checkAccessibility() -> Bool {
 let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
 return AXIsProcessTrustedWithOptions(options)
 }
 
 func requestAccessibility() {
 let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
 _ = AXIsProcessTrustedWithOptions(options)
 
 // Open System Settings manually (more reliable)
 let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
 NSWorkspace.shared.open(url)
 }
 
 func startMonitoring() {
 Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
 self?.hasAccessibility = self?.checkAccessibility() ?? false
 }
 }
}
```

### 9.3 Onboarding UI Integration

**Trigger:** First launch or missing permissions

**Flow:**
1. Welcome
2. **Permission request screen** Services integration
3. How to use
4. Complete

---

## 10. Phase-Specific Implementation Tasks

### Phase 1: Core Foundation (Weeks 1-3)

**Services Tasks:**
- [x] Implement `PasteboardMonitor` with basic polling
- [x] Detect text changes only
- [x] Extract plain text from pasteboard
- [x] Test feedback loop prevention
- [x] Add basic logging

**Success Criteria:**
- Monitor detects changes within 500ms
- No feedback loops
- CPU usage < 1% when idle

**Status Notes:**
- Feedback-loop suppression validated; paste-to-app integration still pending
- Latency/CPU benchmarks captured (avg 0.394s, max 0.409s; CPU idle 0.20%)
- Default poll interval set to 0.4s to meet latency target

---

### Phase 2: Full Capture & UI Parity (Weeks 4-6)

**Services Tasks:**
- [x] Extend capture to all content types (images, RTF, files, URLs)
- [x] Implement multi-representation extraction
- [x] Add type detection (text, code, image, file, URL)
- [x] Implement asset file storage for large content (thresholded binary data)
- [x] Generate thumbnails for images (initial generator + thumbnail updates)
- [x] Add source app detection
- [x] Implement adaptive polling

**Success Criteria:**
- All content types captured correctly
- Thumbnails generate in <500ms
- Memory usage stable with large items

---

### Phase 3: Paste Behaviors (Weeks 7-8)

**Services Tasks:**
- [x] Implement `ActiveAppTracker`
- [x] Implement `sendPasteKeystroke()` with CGEvent
- [ ] Test paste in 10+ applications
- [x] Implement plain text conversion
- [x] Implement paste stack sequential logic
- [x] Add paste delays and separator handling
- [x] Implement `HotkeyManager` with event tap
- [x] Register default hotkeys
- [x] Add Quick Paste (1-9) handlers
- [x] Implement system sound integration
- [x] Add modifier key monitoring for plain text mode
- [ ] Test hotkeys globally

**Success Criteria:**
- Paste works in 95% of apps
- Plain text conversion strips formatting correctly
- Paste stack handles 20+ items
- Hotkeys respond instantly
- No hotkey conflicts with system

**Status Notes:**
- Phase 3 core features implemented (Paste Engine, Hotkeys, Paste Stack).
- "Copy to Clipboard" available via context menu; global preference pending Phase 4.
- Validation pending for broad app compatibility and hotkey reliability.

---

### Phase 4: Privacy & Settings (Weeks 9-10)

**Services Tasks:**
- [ ] Implement login item management (`SMAppService`)
- [ ] Add sound effect player
- [ ] Create onboarding flow with permission requests
- [ ] Implement permission checking/monitoring
- [ ] Add "Pause" functionality to monitor
- [ ] Test all permission scenarios

**Success Criteria:**
- Login item works reliably
- Sound effects play without delay
- Onboarding guides user successfully
- Permissions are requested gracefully

---

### Phase 5: CloudKit Sync (Weeks 11-14)

**Services Tasks:**
- [ ] No additional services work (handled in sync layer)

---

### Phase 6: Hardening & Performance (Weeks 15-16)

**Services Tasks:**
- [ ] Profile pasteboard monitoring CPU usage
- [ ] Optimize polling intervals
- [ ] Test with 10,000+ capture events
- [ ] Stress test paste engine (rapid pastes)
- [ ] Validate hotkey reliability
- [ ] Test on multiple macOS versions (if supporting older)
- [ ] Handle edge cases (locked screen, screen saver, etc.)

**Success Criteria:**
- CPU usage < 0.5% idle, < 5% active
- No memory leaks over 24 hours
- Paste success rate > 99%
- Hotkeys work after wake from sleep

---

## 11. Testing Strategy

### 11.1 Unit Tests

```swift
func testFeedbackLoopPrevention() {
 let monitor = PasteboardMonitor()
 let pasteboard = NSPasteboard.general
 
 monitor.start()
 
 let initialCount = pasteboard.changeCount
 
 // Write using monitor (should be ignored)
 monitor.writeToPasteboard(testItem)
 
 // Simulate check
 monitor.checkForChanges()
 
 // Handler should NOT be called
 XCTAssertFalse(handlerCalled)
}

func testAdaptivePolling() {
 let monitor = PasteboardMonitor()
 
 // Simulate activity
 monitor.checkForChanges() // Change detected
 XCTAssertEqual(monitor.pollState, .active)
 
 // Simulate idle
 monitor.lastActivityTime = Date().addingTimeInterval(-400)
 monitor.checkForChanges() // No change
 XCTAssertEqual(monitor.pollState, .idle)
}
```

### 11.2 Integration Tests

**Pasteboard Capture:**
- Write to pasteboard programmatically
- Verify capture triggers
- Check correct representation extraction

**Paste Engine:**
- Mock active app
- Verify pasteboard write
- Verify keystroke sent (hard to test directly)

### 11.3 Manual Testing Checklist

- [ ] Copy text from 10 different apps All captured
- [ ] Copy images Captured with thumbnail
- [ ] Copy files Captured with icons
- [ ] Copy code Detected as code type
- [ ] Paste into TextEdit Works
- [ ] Paste into Xcode Works
- [ ] Paste into browser Works
- [ ] Paste into password field Respects privacy (if implemented)
- [ ] Quick paste 1 Instant
- [ ] Paste stack with 5 items Sequential paste works
- [ ] Restart Mac Login item launches app
- [ ] Pause monitoring No captures
- [ ] Resume monitoring Captures resume

---

## 12. Known Limitations

### 12.1 Platform Constraints

**Source app attribution:**
- macOS does not expose "which app wrote to pasteboard"
- We use frontmost app as approximation (not 100% reliable)

**Some apps block paste:**
- Financial apps, password managers may block synthetic events
- Fallback: User must manually paste (we copy to clipboard)

**Screen saver / lock screen:**
- Monitoring may pause when screen is locked
- Resume on unlock

### 12.2 Permission Dependencies

**Accessibility required:**
- Without it, can only write to clipboard (not paste into apps)
- Must be communicated clearly in onboarding

**Input Monitoring (optional):**
- Required for certain hotkey implementations
- App works without it (using alternative hotkey method)

---

## 13. Open Questions

### 13.1 Decisions Needed

1. **Paste fallback when app doesn't accept synthetic events?**
 - **Recommendation:** Show notification "Item copied, paste manually"
 - **Alternative:** Use Accessibility API paste (less reliable)

2. **Should we monitor when screen is locked?**
 - **Recommendation:** Pause monitoring (privacy + battery)
 - **Alternative:** Continue monitoring (completeness)

3. **Hotkey conflict resolution?**
 - **Recommendation:** Detect conflicts, warn user, offer alternatives
 - **Alternative:** Override system hotkeys (not recommended)

---

## 14. Changelog

### Version 1.0.0 (2026-01-09)
- Initial macOS services specification
- Defined pasteboard monitoring strategy
- Specified paste engine architecture
- Outlined hotkey management approach
- Detailed phase-specific tasks

---

**Related Documents:**
- [Architecture Overview](./Architecture-Overview.md)
- [Data Model Spec](./Data-Model-Spec.md) - Data created by services
- [UI Contract Spec](./UI-Contract-Spec.md) - UI triggers for services
- [Privacy & Security Spec](./Privacy-Security-Spec.md) - Privacy filters in capture
