import AppKit
import Foundation

public final class SoundEffectPlayer {
    public enum Sound: String {
        case capture = "capture"
        case paste = "paste"
        case copy = "copy"
        case delete = "delete"
    }

    public var isEnabled = true
    private let userDefaults: UserDefaults
    private let userDefaultsKey: String
    private var sounds: [Sound: NSSound] = [:]

    public init(
        userDefaults: UserDefaults = .standard, userDefaultsKey: String = "soundEffectsEnabled"
    ) {
        self.userDefaults = userDefaults
        self.userDefaultsKey = userDefaultsKey
        preload()
    }

    public func play(_ sound: Sound) {
        guard isEnabled, userDefaults.bool(forKey: userDefaultsKey) else {
            return
        }
        if sounds[sound] == nil {
            sounds[sound] = loadSound(sound)
        }
        _ = sounds[sound]?.play()
    }

    private func preload() {
        for sound in [Sound.capture, .paste, .copy, .delete] {
            sounds[sound] = loadSound(sound)
        }
    }

    private func loadSound(_ sound: Sound) -> NSSound? {
        if let url = Bundle.module.url(forResource: sound.rawValue, withExtension: "aiff") {
            return NSSound(contentsOf: url, byReference: true)
        }
        return NSSound(named: NSSound.Name(sound.rawValue))
    }
}

// SAFETY: SoundEffectPlayer is expected to be used from the main thread/UI. It maintains an
// internal cache of NSSound instances which is not synchronized.
extension SoundEffectPlayer: @unchecked Sendable {}
