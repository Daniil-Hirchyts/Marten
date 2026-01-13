import AppKit
import Foundation

public final class SoundEffectPlayer {
    public enum Sound: String {
        case capture = "Pop"
        case paste = "Submarine"
        case delete = "Glass"
    }

    public var isEnabled = true
    private var sounds: [Sound: NSSound] = [:]

    public init() {
        preload()
    }

    public func play(_ sound: Sound) {
        guard isEnabled else { return }
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
