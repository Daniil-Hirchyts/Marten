@testable import MartenIOSApp
import XCTest

@MainActor
final class VoiceDictationServiceTests: XCTestCase {
    func testStartAndStopTransitionsRecordingState() async throws {
        let client = MockVoiceRecognitionClient()
        let service = VoiceDictationService(client: client)

        var latestTranscript = ""
        try await service.start { transcript, _ in
            latestTranscript = transcript
        }

        XCTAssertTrue(service.isRecording)
        XCTAssertTrue(client.didStart)

        client.emit(text: "Hello Marten", isFinal: false)
        XCTAssertEqual(latestTranscript, "Hello Marten")

        service.stop()
        XCTAssertFalse(service.isRecording)
        XCTAssertTrue(client.didStop)
    }

    func testPermissionDeniedThrowsAndDoesNotStart() async {
        let client = MockVoiceRecognitionClient()
        client.authorizationGranted = false
        let service = VoiceDictationService(client: client)

        do {
            try await service.start { _, _ in }
            XCTFail("Expected permission denied error")
        } catch {
            XCTAssertFalse(service.isRecording)
        }
    }
}
