#if !os(watchOS)
import AuthenticationServices
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Represents Apple ID user credentials.
public struct AppleIDCredentials: Codable, Sendable {
    public let userID: String
    public let email: String?
    public let givenName: String?
    public let familyName: String?
    
    public var displayName: String {
        if let given = givenName, let family = familyName {
            return "\(given) \(family)"
        } else if let given = givenName {
            return given
        } else if let family = familyName {
            return family
        }
        return email ?? "Apple ID User"
    }
    
    public var initials: String {
        let first = givenName?.prefix(1).uppercased() ?? ""
        let last = familyName?.prefix(1).uppercased() ?? ""

        if !first.isEmpty && !last.isEmpty {
            return "\(first)\(last)"
        } else if !first.isEmpty {
            return first
        } else if !last.isEmpty {
            return last
        } else if let email = email, let firstChar = email.first {
            // Use first letter of email as fallback
            return String(firstChar).uppercased()
        }
        return ""
    }
    
    public init(userID: String, email: String?, givenName: String?, familyName: String?) {
        self.userID = userID
        self.email = email
        self.givenName = givenName
        self.familyName = familyName
    }
}

/// Manages Apple ID authentication using Sign in with Apple.
@MainActor
@Observable
public final class AppleAuthManager: NSObject {
    public private(set) var credentials: AppleIDCredentials?
    public private(set) var isSignedIn: Bool = false
    public private(set) var isAuthenticating: Bool = false
    
    private let userDefaultsKey = "appleUserID"
    private let credentialsKey = "appleCredentials"
    private let userDefaults: UserDefaults
    
    private var authContinuation: CheckedContinuation<Void, Error>?
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        super.init()
        checkExistingCredentials()
    }
    
    /// Initiates Sign in with Apple flow.
    public func signIn() async throws {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
        
        // Wait for authentication to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.authContinuation = continuation
        }
    }
    
    /// Signs out the current user.
    public func signOut() {
        credentials = nil
        isSignedIn = false
        userDefaults.removeObject(forKey: userDefaultsKey)
        userDefaults.removeObject(forKey: credentialsKey)
    }
    
    /// Checks for existing credentials on app launch.
    private func checkExistingCredentials() {
        guard let data = userDefaults.data(forKey: credentialsKey),
              let storedCredentials = try? JSONDecoder().decode(AppleIDCredentials.self, from: data) else {
            return
        }
        
        // Optimistically set signed-in state to prevent UI flickering
        self.credentials = storedCredentials
        self.isSignedIn = true
        
        // Verify the credential is still valid
        Task {
            let provider = ASAuthorizationAppleIDProvider()
            do {
                let credentialState = try await provider.credentialState(forUserID: storedCredentials.userID)
                
                await MainActor.run {
                    switch credentialState {
                    case .authorized:
                        // Confirmed valid, state is already correct
                        break
                    case .revoked, .notFound, .transferred:
                        self.signOut()
                    @unknown default:
                        self.signOut()
                    }
                }
            } catch {
                await MainActor.run {
                    self.signOut()
                }
            }
        }
    }
    
    /// Saves credentials to UserDefaults.
    private func saveCredentials(_ credentials: AppleIDCredentials) {
        if let data = try? JSONEncoder().encode(credentials) {
            userDefaults.set(data, forKey: credentialsKey)
            userDefaults.set(credentials.userID, forKey: userDefaultsKey)
        }
    }

    /// Loads credentials from UserDefaults for a specific user ID.
    private func loadCredentialsFromStorage(userID: String) -> AppleIDCredentials? {
        guard let data = userDefaults.data(forKey: credentialsKey),
              let storedCredentials = try? JSONDecoder().decode(AppleIDCredentials.self, from: data),
              storedCredentials.userID == userID else {
            return nil
        }
        return storedCredentials
    }
}

// MARK: - ASAuthorizationControllerDelegate & PresentationContextProviding

extension AppleAuthManager: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            authContinuation?.resume(throwing: NSError(
                domain: "AppleAuthManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid credential type"]
            ))
            authContinuation = nil
            return
        }
        
        let userID = appleIDCredential.user
        let email = appleIDCredential.email
        let givenName = appleIDCredential.fullName?.givenName
        let familyName = appleIDCredential.fullName?.familyName

        // Check if we have existing credentials to merge with
        // (name/email only provided on first sign-in)
        // First check in-memory, then check UserDefaults
        let existing = credentials ?? loadCredentialsFromStorage(userID: userID)

        let finalCredentials: AppleIDCredentials
        if let existing = existing {
            finalCredentials = AppleIDCredentials(
                userID: userID,
                email: email ?? existing.email,
                givenName: givenName ?? existing.givenName,
                familyName: familyName ?? existing.familyName
            )
        } else {
            finalCredentials = AppleIDCredentials(
                userID: userID,
                email: email,
                givenName: givenName,
                familyName: familyName
            )
        }
        
        credentials = finalCredentials
        isSignedIn = true
        saveCredentials(finalCredentials)
        
        authContinuation?.resume()
        authContinuation = nil
    }
    
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError

        // User cancelled - don't treat as error
        if nsError.code == 1001 {
            authContinuation?.resume(throwing: CancellationError())
        } else {
            authContinuation?.resume(throwing: error)
        }
        authContinuation = nil
    }

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(AppKit)
        // macOS: Return the key window
        return NSApplication.shared.keyWindow ?? NSWindow()
        #else
        // iOS: Return the key window
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
        #endif
    }
}
#endif
