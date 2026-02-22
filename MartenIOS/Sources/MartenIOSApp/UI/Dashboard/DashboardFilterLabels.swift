import Foundation
import MartenCore

extension ClipItemDateFilter {
    var label: String {
        switch self {
        case .any: return "Any Time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        }
    }
}

extension ItemType {
    var label: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "Link"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Mixed"
        }
    }
}

extension ClipItemSourceDevice {
    var label: String {
        switch self {
        case .thisDevice: return "This Device"
        case .unknown: return "Unknown"
        case .named(let name): return name
        }
    }
}

