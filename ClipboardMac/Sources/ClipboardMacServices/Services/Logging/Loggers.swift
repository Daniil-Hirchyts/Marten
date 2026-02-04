import OSLog

public extension Logger {
    static let app = Logger(subsystem: "com.paste.clipboard", category: "App")
    static let pasteboard = Logger(subsystem: "com.paste.clipboard", category: "Pasteboard")
    static let paste = Logger(subsystem: "com.paste.clipboard", category: "Paste")
    static let hotkey = Logger(subsystem: "com.paste.clipboard", category: "Hotkey")
    static let retention = Logger(subsystem: "com.paste.clipboard", category: "Retention")
    static let permissions = Logger(subsystem: "com.paste.clipboard", category: "Permissions")
    static let drag = Logger(subsystem: "com.paste.clipboard", category: "Drag")
    static let ui = Logger(subsystem: "com.paste.clipboard", category: "UI")
    static let preferences = Logger(subsystem: "com.paste.clipboard", category: "Preferences")
    static let thumbnails = Logger(subsystem: "com.paste.clipboard", category: "Thumbnails")
    static let integrity = Logger(subsystem: "com.paste.clipboard", category: "Integrity")
    static let ocr = Logger(subsystem: "com.paste.clipboard", category: "OCR")
}
