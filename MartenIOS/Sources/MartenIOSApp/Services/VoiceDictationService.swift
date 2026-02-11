import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
import Speech
#endif

enum VoiceDictationError: LocalizedError {
    case unavailable
    case permissionDenied
    case startFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Voice dictation is unavailable on this device."
        case .permissionDenied:
            return "Speech recognition permission was denied."
        case .startFailed:
            return "Voice dictation could not be started."
        }
    }
}

@MainActor
protocol VoiceRecognitionClient {
    func requestAuthorization() async -> Bool
    func startTranscribing(
        onText: @escaping @MainActor (_ text: String, _ isFinal: Bool) -> Void,
        onError: @escaping @MainActor (_ message: String) -> Void
    ) throws
    func stopTranscribing()
}

@MainActor
final class VoiceDictationService {
    private let client: any VoiceRecognitionClient

    private(set) var isRecording = false
    private(set) var lastErrorMessage: String?

    init(client: (any VoiceRecognitionClient)? = nil) {
        self.client = client ?? DefaultVoiceRecognitionClient()
    }

    func start(
        onTranscript: @escaping @MainActor (_ text: String, _ isFinal: Bool) -> Void
    ) async throws {
        guard !isRecording else { return }
        guard await client.requestAuthorization() else {
            lastErrorMessage = VoiceDictationError.permissionDenied.localizedDescription
            throw VoiceDictationError.permissionDenied
        }

        do {
            try client.startTranscribing(
                onText: { [weak self] text, isFinal in
                    onTranscript(text, isFinal)
                    if isFinal {
                        self?.isRecording = false
                    }
                },
                onError: { [weak self] message in
                    self?.isRecording = false
                    self?.lastErrorMessage = message
                }
            )
            lastErrorMessage = nil
            isRecording = true
        } catch {
            isRecording = false
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func stop() {
        guard isRecording else { return }
        client.stopTranscribing()
        isRecording = false
    }
}

#if canImport(Speech) && canImport(AVFoundation) && canImport(UIKit)
@MainActor
private final class DefaultVoiceRecognitionClient: NSObject, VoiceRecognitionClient {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestAuthorization() async -> Bool {
        guard recognizer != nil else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startTranscribing(
        onText: @escaping @MainActor (String, Bool) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceDictationError.unavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceDictationError.startFailed
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw VoiceDictationError.startFailed
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                Task { @MainActor in
                    onText(result.bestTranscription.formattedString, result.isFinal)
                }
            }

            if let error {
                Task { @MainActor in
                    onError(error.localizedDescription)
                }
                self?.stopTranscribing()
                return
            }

            if result?.isFinal == true {
                self?.stopTranscribing()
            }
        }
    }

    func stopTranscribing() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#else
@MainActor
private final class DefaultVoiceRecognitionClient: VoiceRecognitionClient {
    func requestAuthorization() async -> Bool { false }

    func startTranscribing(
        onText: @escaping @MainActor (String, Bool) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) throws {
        throw VoiceDictationError.unavailable
    }

    func stopTranscribing() {}
}
#endif
