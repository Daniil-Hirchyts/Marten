import CoreData
import Foundation

public enum StackSessionStoreError: Error {
    case missingSession
    case missingItem
}

public final class StackSessionStore {
    private let persistence: PersistenceController

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    @discardableResult
    public func createSession(
        mode: StackMode = .sequential,
        separator: String = "\n",
        deactivateExisting: Bool = true
    ) throws -> StackSession {
        let now = Date()
        let context = persistence.newBackgroundContext()
        var createdObjectID: NSManagedObjectID?

        try context.performAndWaitThrowing {
            if deactivateExisting {
                let request = StackSession.fetchRequest()
                request.predicate = NSPredicate(format: "isActive == YES")
                let activeSessions = try context.fetch(request)
                for session in activeSessions {
                    session.isActive = false
                }
            }

            guard
                let session = NSEntityDescription.insertNewObject(
                    forEntityName: "StackSession",
                    into: context
                ) as? StackSession
            else {
                throw StackSessionStoreError.missingSession
            }

            session.id = UUID()
            session.createdAt = now
            session.isActive = true
            session.separator = separator
            session.modeValue = mode

            try context.save()
            createdObjectID = session.objectID
        }

        guard let objectID = createdObjectID else {
            throw StackSessionStoreError.missingSession
        }

        let viewContext = persistence.viewContext
        var fetched: StackSession?
        try viewContext.performAndWaitThrowing {
            fetched = try viewContext.existingObject(with: objectID) as? StackSession
        }

        guard let session = fetched else {
            throw StackSessionStoreError.missingSession
        }

        return session
    }

    public func fetchActiveSession() throws -> StackSession? {
        let context = persistence.viewContext
        var session: StackSession?
        try context.performAndWaitThrowing {
            let request = StackSession.fetchRequest()
            request.predicate = NSPredicate(format: "isActive == YES")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchLimit = 1
            session = try context.fetch(request).first
        }
        return session
    }

    public func setEntries(sessionID: NSManagedObjectID, clipItemIDs: [NSManagedObjectID]) throws {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let session = try context.existingObject(with: sessionID) as? StackSession else {
                throw StackSessionStoreError.missingSession
            }

            if let existing = session.entries {
                for entry in existing {
                    context.delete(entry)
                }
            }

            let now = Date()
            for (index, clipItemID) in clipItemIDs.enumerated() {
                guard let item = try context.existingObject(with: clipItemID) as? ClipItem else {
                    throw StackSessionStoreError.missingItem
                }

                guard
                    let entry = NSEntityDescription.insertNewObject(
                        forEntityName: "StackEntry",
                        into: context
                    ) as? StackEntry
                else {
                    throw StackSessionStoreError.missingSession
                }

                entry.id = UUID()
                entry.position = Int16(index)
                entry.addedAt = now
                entry.session = session
                entry.clipItem = item
                session.addToEntries(entry)
            }

            try context.save()
        }

        let viewContext = persistence.viewContext
        try viewContext.performAndWaitThrowing {
            if let session = try? viewContext.existingObject(with: sessionID) as? StackSession {
                viewContext.refresh(session, mergeChanges: true)
            }
        }
    }

    public func clearEntries(sessionID: NSManagedObjectID) throws {
        try setEntries(sessionID: sessionID, clipItemIDs: [])
    }

    public func fetchEntries(sessionID: NSManagedObjectID) throws -> [StackEntry] {
        let context = persistence.viewContext
        var entries: [StackEntry] = []
        try context.performAndWaitThrowing {
            guard let session = try context.existingObject(with: sessionID) as? StackSession else {
                throw StackSessionStoreError.missingSession
            }
            let request = StackEntry.fetchRequest()
            request.predicate = NSPredicate(format: "session == %@", session)
            request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            entries = try context.fetch(request)
        }
        return entries
    }

    public func deactivateSession(sessionID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let session = try context.existingObject(with: sessionID) as? StackSession else {
                throw StackSessionStoreError.missingSession
            }
            session.isActive = false
            try context.save()
        }
    }

    public func deleteSession(sessionID: NSManagedObjectID) throws {
        let context = persistence.newBackgroundContext()
        try context.performAndWaitThrowing {
            guard let session = try context.existingObject(with: sessionID) as? StackSession else {
                throw StackSessionStoreError.missingSession
            }
            context.delete(session)
            if context.hasChanges {
                try context.save()
            }
        }
    }
}

extension StackSessionStore: @unchecked Sendable {}
