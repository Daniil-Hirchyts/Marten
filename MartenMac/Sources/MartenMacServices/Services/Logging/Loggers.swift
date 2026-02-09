import OSLog

public extension Logger {
    static let app = Logger(subsystem: "com.hirchyts.marten", category: "App")
    static let pasteboard = Logger(subsystem: "com.hirchyts.marten", category: "Pasteboard")
    static let paste = Logger(subsystem: "com.hirchyts.marten", category: "Paste")
    static let hotkey = Logger(subsystem: "com.hirchyts.marten", category: "Hotkey")
    static let retention = Logger(subsystem: "com.hirchyts.marten", category: "Retention")
    static let permissions = Logger(subsystem: "com.hirchyts.marten", category: "Permissions")
    static let drag = Logger(subsystem: "com.hirchyts.marten", category: "Drag")
    static let ui = Logger(subsystem: "com.hirchyts.marten", category: "UI")
    static let preferences = Logger(subsystem: "com.hirchyts.marten", category: "Preferences")
    static let thumbnails = Logger(subsystem: "com.hirchyts.marten", category: "Thumbnails")
    static let integrity = Logger(subsystem: "com.hirchyts.marten", category: "Integrity")
    static let ocr = Logger(subsystem: "com.hirchyts.marten", category: "OCR")
}
