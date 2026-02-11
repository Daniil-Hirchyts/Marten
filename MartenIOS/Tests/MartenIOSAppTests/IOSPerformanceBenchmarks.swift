import MartenCore
@testable import MartenIOSApp
import XCTest

final class IOSPerformanceBenchmarks: XCTestCase {
    func testItemCardPresentationBatchPerformance() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        var items: [ClipItem] = []
        for i in 0..<200 {
            let item = try store.createTextItem(text: "Benchmark item \(i)")
            items.append(item)
        }

        measure {
            for item in items {
                _ = ItemCardPresentation(item: item)
            }
        }
    }

    @MainActor
    func testUpdateOptionsPerformance() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        var items: [ClipItem] = []
        for i in 0..<500 {
            let item = try store.createTextItem(text: "Options item \(i)")
            items.append(item)
        }

        let model = DashboardSearchModel(
            queryService: BenchmarkQueryService(),
            debounceNanoseconds: 0
        )

        measure {
            // Reset cache to force recomputation each iteration
            model.updateOptions(from: [])
            model.updateOptions(from: items)
        }
    }

    func testSearchPipelinePerformance() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        for i in 0..<500 {
            _ = try store.createTextItem(text: "Pipeline item \(i) searchable content")
        }

        let service = ClipItemQueryService(store: store)

        measure {
            let expectation = XCTestExpectation(description: "search")
            Task {
                _ = try await service.search(
                    request: ClipItemSearchRequest(query: "searchable", limit: 50)
                )
                expectation.fulfill()
            }
            _ = XCTWaiter.wait(for: [expectation], timeout: 5.0)
        }
    }
}

private actor BenchmarkQueryService: ClipItemQuerying {
    func search(request: ClipItemSearchRequest) async throws -> [ClipItem] {
        []
    }
}
