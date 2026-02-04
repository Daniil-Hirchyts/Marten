import CloudKit
import Foundation

/// Protocol for sync token storage, enabling testability.
public protocol SyncTokenStoring: Sendable {
    func saveToken(_ data: Data, forKey key: String) throws
    func loadToken(forKey key: String) throws -> Data?
    func deleteToken(forKey key: String) throws
    func deleteAllTokens() throws
}

/// UserDefaults-based implementation of token storage.
// SAFETY: UserDefaults is thread-safe for concurrent reads/writes; this type adds no additional
// shared mutable state.
public final class UserDefaultsSyncTokenStorage: SyncTokenStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "com.paste.sync.token."
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    public func saveToken(_ data: Data, forKey key: String) throws {
        userDefaults.set(data, forKey: prefixedKey(key))
    }

    public func loadToken(forKey key: String) throws -> Data? {
        userDefaults.data(forKey: prefixedKey(key))
    }

    public func deleteToken(forKey key: String) throws {
        userDefaults.removeObject(forKey: prefixedKey(key))
    }

    public func deleteAllTokens() throws {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(keyPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func prefixedKey(_ key: String) -> String {
        keyPrefix + key
    }
}

/// Manages CloudKit server change tokens for incremental sync.
///
/// This class handles persistence of CKServerChangeToken objects, which are used
/// to track sync state and fetch only changes since the last sync.
public final class SyncTokenManager {
    private let storage: SyncTokenStoring
    private let lock = NSLock()

    /// In-memory cache of tokens to avoid repeated deserialization.
    private var tokenCache: [String: CKServerChangeToken] = [:]

    public init(storage: SyncTokenStoring = UserDefaultsSyncTokenStorage()) {
        self.storage = storage
    }

    // MARK: - Token Operations

    /// Saves a server change token for the specified zone.
    ///
    /// - Parameters:
    ///   - token: The CKServerChangeToken to save.
    ///   - zoneID: The zone identifier this token belongs to.
    /// - Throws: `SyncTokenError` if persistence fails.
    public func saveToken(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) throws {
        let key = storageKey(for: zoneID)

        let data: Data
        do {
            data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
        } catch {
            throw SyncTokenError.persistenceFailed(error)
        }

        lock.lock()
        defer { lock.unlock() }

        do {
            try storage.saveToken(data, forKey: key)
            tokenCache[key] = token
        } catch {
            throw SyncTokenError.persistenceFailed(error)
        }
    }

    /// Loads a server change token for the specified zone.
    ///
    /// - Parameter zoneID: The zone identifier to load the token for.
    /// - Returns: The stored token, or `nil` if no token exists.
    /// - Throws: `SyncTokenError` if loading or decoding fails.
    public func loadToken(for zoneID: CKRecordZone.ID) throws -> CKServerChangeToken? {
        let key = storageKey(for: zoneID)

        lock.lock()
        defer { lock.unlock() }

        if let cached = tokenCache[key] {
            return cached
        }

        guard let data = try storage.loadToken(forKey: key) else {
            return nil
        }

        let token: CKServerChangeToken
        do {
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
            ) else {
                throw SyncTokenError.invalidTokenFormat
            }
            token = decoded
        } catch let error as SyncTokenError {
            throw error
        } catch {
            throw SyncTokenError.decodingFailed(error)
        }

        tokenCache[key] = token
        return token
    }

    /// Clears the token for the specified zone.
    ///
    /// This should be called when the zone is reset or deleted.
    ///
    /// - Parameter zoneID: The zone identifier to clear the token for.
    /// - Throws: `SyncTokenError` if deletion fails.
    public func clearToken(for zoneID: CKRecordZone.ID) throws {
        let key = storageKey(for: zoneID)

        lock.lock()
        defer { lock.unlock() }

        try storage.deleteToken(forKey: key)
        tokenCache.removeValue(forKey: key)
    }

    /// Clears all stored tokens.
    ///
    /// This should be called when performing a full re-sync.
    ///
    /// - Throws: `SyncTokenError` if deletion fails.
    public func clearAllTokens() throws {
        lock.lock()
        defer { lock.unlock() }

        try storage.deleteAllTokens()
        tokenCache.removeAll()
    }

    /// Saves a database change token for tracking database-level changes.
    ///
    /// - Parameters:
    ///   - token: The database change token to save.
    ///   - databaseScope: The scope (private, shared, public) of the database.
    /// - Throws: `SyncTokenError` if persistence fails.
    public func saveDatabaseToken(
        _ token: CKServerChangeToken,
        for databaseScope: CKDatabase.Scope
    ) throws {
        let key = databaseStorageKey(for: databaseScope)

        let data: Data
        do {
            data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
        } catch {
            throw SyncTokenError.persistenceFailed(error)
        }

        lock.lock()
        defer { lock.unlock() }

        do {
            try storage.saveToken(data, forKey: key)
            tokenCache[key] = token
        } catch {
            throw SyncTokenError.persistenceFailed(error)
        }
    }

    /// Loads a database change token.
    ///
    /// - Parameter databaseScope: The scope of the database.
    /// - Returns: The stored database token, or `nil` if none exists.
    /// - Throws: `SyncTokenError` if loading or decoding fails.
    public func loadDatabaseToken(for databaseScope: CKDatabase.Scope) throws -> CKServerChangeToken? {
        let key = databaseStorageKey(for: databaseScope)

        lock.lock()
        defer { lock.unlock() }

        if let cached = tokenCache[key] {
            return cached
        }

        guard let data = try storage.loadToken(forKey: key) else {
            return nil
        }

        let token: CKServerChangeToken
        do {
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
            ) else {
                throw SyncTokenError.invalidTokenFormat
            }
            token = decoded
        } catch let error as SyncTokenError {
            throw error
        } catch {
            throw SyncTokenError.decodingFailed(error)
        }

        tokenCache[key] = token
        return token
    }

    /// Clears the database token for the specified scope.
    ///
    /// - Parameter databaseScope: The scope of the database.
    /// - Throws: `SyncTokenError` if deletion fails.
    public func clearDatabaseToken(for databaseScope: CKDatabase.Scope) throws {
        let key = databaseStorageKey(for: databaseScope)

        lock.lock()
        defer { lock.unlock() }

        try storage.deleteToken(forKey: key)
        tokenCache.removeValue(forKey: key)
    }

    // MARK: - Key Generation

    private func storageKey(for zoneID: CKRecordZone.ID) -> String {
        "zone.\(zoneID.ownerName).\(zoneID.zoneName)"
    }

    private func databaseStorageKey(for scope: CKDatabase.Scope) -> String {
        switch scope {
        case .private:
            return "database.private"
        case .shared:
            return "database.shared"
        case .public:
            return "database.public"
        @unknown default:
            return "database.unknown"
        }
    }
}

// SAFETY: SyncTokenManager protects its in-memory cache with `lock` and only uses `storage` via the
// Sendable `SyncTokenStoring` abstraction.
extension SyncTokenManager: @unchecked Sendable {}
