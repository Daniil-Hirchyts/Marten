import OSLog

public extension Logger {
    static let app = Logger(subsystem: "com.paste.clipboard", category: "App")
    static let pasteboard = Logger(subsystem: "com.paste.clipboard", category: "Pasteboard")
    static let hotkey = Logger(subsystem: "com.paste.clipboard", category: "Hotkey")
    static let retention = Logger(subsystem: "com.paste.clipboard", category: "Retention")
}
