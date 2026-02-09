import Foundation
import XCTest
@testable import MartenCore

final class ConfidentialContentClassifierTests: XCTestCase {
    private let classifier = ConfidentialContentClassifier()

    func testDetectsStrongPassword() {
        XCTAssertEqual(classifier.classify("aB3$xY9!mN2@"), .sensitive(.password))
    }

    func testDoesNotDetectWeakPassword() {
        XCTAssertEqual(classifier.classify("password123"), .safe)
    }

    func testDoesNotDetectURL() {
        XCTAssertEqual(classifier.classify(" `https://example.com/path` "), .safe)
    }

    func testDoesNotDetectEmail() {
        XCTAssertEqual(classifier.classify("user@example.com"), .safe)
    }

    func testDetects6DigitOTP() {
        XCTAssertEqual(classifier.classify("123456"), .sensitive(.oneTimeCode))
    }

    func testDetects8DigitOTP() {
        XCTAssertEqual(classifier.classify("12345678"), .sensitive(.oneTimeCode))
    }

    func testDoesNotDetect5DigitNumber() {
        XCTAssertEqual(classifier.classify("12345"), .safe)
    }

    func testDetectsValidCreditCard() {
        XCTAssertEqual(classifier.classify("4532015112830366"), .sensitive(.creditCard))
    }

    func testRejectsInvalidLuhnCard() {
        XCTAssertEqual(classifier.classify("4532015112830367"), .safe)
    }

    func testDetectsJWTToken() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        XCTAssertEqual(classifier.classify(jwt), .sensitive(.apiKey))
    }

    func testDetectsGitHubToken() {
        let token = "ghp_" + String(repeating: "x", count: 36)
        XCTAssertEqual(classifier.classify(token), .sensitive(.apiKey))
    }

    func testDetectsAWSAccessKey() {
        XCTAssertEqual(classifier.classify("AKIAIOSFODNN7EXAMPLE"), .sensitive(.apiKey))
    }

    func testDetectsLongAlphanumericToken() {
        let token = String(repeating: "A", count: 45)
        XCTAssertEqual(classifier.classify(token), .sensitive(.apiKey))
    }

    func testDetectsRSAPrivateKey() {
        let key = "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJB\n-----END RSA PRIVATE KEY-----"
        XCTAssertEqual(classifier.classify(key), .sensitive(.privateKey))
    }

    func testDetectsSSHPrivateKey() {
        let key = "-----BEGIN OPENSSH PRIVATE KEY-----\nMIIBOgIBAAJB\n-----END OPENSSH PRIVATE KEY-----"
        XCTAssertEqual(classifier.classify(key), .sensitive(.privateKey))
    }

    func testDetectsSSNWithDashes() {
        XCTAssertEqual(classifier.classify("123-45-6789"), .sensitive(.ssn))
    }

    func testDetectsSSNWithoutDashes() {
        XCTAssertEqual(classifier.classify("123456789"), .sensitive(.ssn))
    }

    func testNormalTextIsSafe() {
        XCTAssertEqual(classifier.classify("Hello, this is normal text!"), .safe)
    }
}

