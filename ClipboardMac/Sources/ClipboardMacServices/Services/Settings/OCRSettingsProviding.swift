import Foundation

public enum OCRLanguage: String, CaseIterable {
    case auto = ""
    case english = "en-US"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"
    case italian = "it-IT"
    case portuguese = "pt-BR"
    case russian = "ru-RU"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case chinese = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case arabic = "ar-SA"
    case ukrainian = "uk-UA"
    
    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chinese: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .arabic: return "Arabic"
        case .ukrainian: return "Ukrainian"
        }
    }
}

public enum OCRSettingsKeys {
    public static let defaultMode = "ocr.defaultMode"
    public static let preferredLanguage = "ocr.preferredLanguage"
    public static let showCaptureNotification = "ocr.showCaptureNotification"
}

public protocol OCRSettingsProviding {
    var defaultCaptureMode: OCRCaptureMode { get }
    var preferredLanguageCode: String? { get }
    var showCaptureNotification: Bool { get }
}

public struct UserDefaultsOCRSettingsProvider: OCRSettingsProviding {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var defaultCaptureMode: OCRCaptureMode {
        guard
            let rawValue = userDefaults.string(forKey: OCRSettingsKeys.defaultMode),
            let mode = OCRCaptureMode(rawValue: rawValue)
        else {
            return .staticSnapshot
        }
        return mode
    }

    public var preferredLanguageCode: String? {
        guard let rawValue = userDefaults.string(forKey: OCRSettingsKeys.preferredLanguage) else {
            return nil
        }
        return rawValue.isEmpty ? nil : rawValue
    }

    public var showCaptureNotification: Bool {
        if userDefaults.object(forKey: OCRSettingsKeys.showCaptureNotification) == nil {
            return true
        }
        return userDefaults.bool(forKey: OCRSettingsKeys.showCaptureNotification)
    }
}
