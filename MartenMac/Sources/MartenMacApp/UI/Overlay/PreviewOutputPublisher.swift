import Foundation

@MainActor
enum PreviewOutputPublisher {
    static func publish<Value>(
        _ value: Value,
        binding: inout Value,
        callback: ((Value) -> Void)?
    ) {
        binding = value
        callback?(value)
    }
}
