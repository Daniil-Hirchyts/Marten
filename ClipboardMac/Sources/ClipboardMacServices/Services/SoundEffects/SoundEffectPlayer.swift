import AppKit
import Foundation

public final class SoundEffectPlayer {
    public enum Sound: String {
        case capture = "Pop"
        case paste = "Submarine"
        case delete = "Glass"
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
        guard isEnabled, userDefaults.bool(forKey: userDefaultsKey) else { return }
        if sounds[sound] == nil {
            sounds[sound] = NSSound(named: NSSound.Name(sound.rawValue))
        }
        sounds[sound]?.play()
    }

    private func preload() {
        for sound in [Sound.capture, .paste, .delete] {
            sounds[sound] = NSSound(named: NSSound.Name(sound.rawValue))
        }
    }
}

extension SoundEffectPlayer: @unchecked Sendable {}
