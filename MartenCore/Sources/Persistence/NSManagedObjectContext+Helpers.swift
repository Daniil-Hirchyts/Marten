import CoreData

public extension NSManagedObjectContext {
    func performAndWaitThrowing<T>(_ block: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        performAndWait {
            result = Result { try block() }
        }
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            fatalError("Missing result for managed object context block")
        }
    }
}
