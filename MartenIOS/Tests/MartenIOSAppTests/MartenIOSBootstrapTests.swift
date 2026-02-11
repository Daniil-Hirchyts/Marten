import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class MartenIOSBootstrapTests: XCTestCase {
    func testBootstrapUsesInjectedPersistenceController() {
        let persistence = PersistenceController(inMemory: true)
        let bootstrap = MartenIOSBootstrap(persistenceController: persistence)

        XCTAssertTrue(bootstrap.persistenceController === persistence)
        XCTAssertTrue(bootstrap.container.persistenceController === persistence)
    }
}
