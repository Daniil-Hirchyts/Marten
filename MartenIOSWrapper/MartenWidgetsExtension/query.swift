import AppIntents

@available(iOS 18.0, *)
struct OpenURLIntent: AppIntent {
    static var title: LocalizedStringResource = "Open URL"
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "URL")
    var url: URL
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
