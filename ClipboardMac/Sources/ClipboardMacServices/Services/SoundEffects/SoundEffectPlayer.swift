import AppKit
import Foundation

public final class SoundEffectPlayer {
    public enum Sound: String {
        case capture = "capture"
        case paste = "paste"
        case copy = "copy"
        case delete = "delete"
    }

    private let userDefaults: UserDefaults
    private let userDefaultsKey: String
    private var sounds: [Sound: NSSound] = [:]
    private var isEnabledStorage = true
    private let lock = NSLock()

    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return isEnabledStorage
        }
        set {
            lock.lock()
            isEnabledStorage = newValue
            lock.unlock()
        }
    }

    public init(
        userDefaults: UserDefaults = .standard, userDefaultsKey: String = "soundEffectsEnabled"
    ) {
        self.userDefaults = userDefaults
        self.userDefaultsKey = userDefaultsKey
        preload()
    }

    public func play(_ sound: Sound) {
        guard userDefaults.bool(forKey: userDefaultsKey) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }

        guard isEnabledStorage else { return }

        if sounds[sound] == nil {
            sounds[sound] = loadSound(sound)
        }
        _ = sounds[sound]?.play()
    }

    private func preload() {
        lock.lock()
        defer { lock.unlock() }

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

// SAFETY: SoundEffectPlayer synchronizes mutable state (`isEnabledStorage`, `sounds`) with `lock`.
extension SoundEffectPlayer: @unchecked Sendable {}
