import XCTest
@testable import HermesDesktop

// MARK: - MockAPIURLProtocol

/// A `URLProtocol` subclass that intercepts all requests for `HermesAPIClient` tests.
///
/// Set `mockData` to the JSON body the endpoint should return, and `mockStatusCode`
/// to the desired HTTP status. Both are reset in every test's `tearDown`.
final class MockAPIURLProtocol: URLProtocol {

    static var mockData: Data?
    static var mockStatusCode: Int = 200
    /// Captures the `Authorization` header of the most recent request (for assertion).
    static var lastAuthorizationHeader: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")

        guard let data = Self.mockData else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.mockStatusCode,
            httpVersion: "1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - HermesAPIClientTests

final class HermesAPIClientTests: XCTestCase {

    private let baseURL = URL(string: "https://api.hermes.example")!
    // Dedicated service/account, isolated from the real one — this test used
    // to run against the production KeychainManager() default, which meant
    // every test run overwrote and then deleted the user's real stored API
    // key. Never point this back at the production defaults.
    private let keychain = KeychainManager(
        service: "com.hermes-desktop.api-key.tests",
        account: "hermes-api-tests"
    )

    override func setUp() async throws {
        // Store a valid token so `authenticationToken()` does not throw.
        try await keychain.save(key: "test-api-key-12345")
    }

    override func tearDown() async throws {
        MockAPIURLProtocol.mockData = nil
        MockAPIURLProtocol.mockStatusCode = 200
        MockAPIURLProtocol.lastAuthorizationHeader = nil
        try? await keychain.delete()
    }

    /// Creates a `HermesAPIClient` whose `URLSession` routes through `MockAPIURLProtocol`.
    private func makeClient() -> HermesAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAPIURLProtocol.self]
        let session = URLSession(configuration: config)
        return HermesAPIClient(baseURL: baseURL, keychainManager: keychain, session: session)
    }

    // MARK: - Health Check Success

    func testHealthCheckSuccess() async throws {
        let json = #"{"status": "ok"}"#.data(using: .utf8)!
        MockAPIURLProtocol.mockData = json
        MockAPIURLProtocol.mockStatusCode = 200

        let client = makeClient()
        let result: [String: String] = try await client.request(.health)

        XCTAssertEqual(result["status"], "ok")
    }

    // MARK: - Unauthorized

    func testUnauthorized() async {
        MockAPIURLProtocol.mockData = Data()
        MockAPIURLProtocol.mockStatusCode = 401

        let client = makeClient()
        do {
            let _: [String: String] = try await client.request(.health)
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Not Found

    func testNotFound() async {
        MockAPIURLProtocol.mockData = Data()
        MockAPIURLProtocol.mockStatusCode = 404

        let client = makeClient()
        do {
            let _: [String: String] = try await client.request(.runStatus(runId: "nonexistent"))
            XCTFail("Expected notFound error")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Server Error

    func testServerError() async {
        MockAPIURLProtocol.mockData = Data()
        MockAPIURLProtocol.mockStatusCode = 500

        let client = makeClient()
        do {
            let _: [String: String] = try await client.request(.health)
            XCTFail("Expected serverError")
        } catch let error as APIError {
            guard case .serverError(let code) = error else {
                XCTFail("Expected serverError, got \(error)")
                return
            }
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Decoding Error

    func testDecodingError() async {
        // Return valid JSON that just doesn't match the expected type.
        let json = #"{"unexpected_key": 42}"#.data(using: .utf8)!
        MockAPIURLProtocol.mockData = json
        MockAPIURLProtocol.mockStatusCode = 200

        let client = makeClient()
        do {
            // T is a struct that requires a "status" field.
            let _: StatusResponse = try await client.request(.health)
            XCTFail("Expected decodingError")
        } catch let error as APIError {
            guard case .decodingError = error else {
                XCTFail("Expected decodingError, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Bearer Token Added

    func testBearerTokenAdded() async throws {
        let json = #"{"status": "ok"}"#.data(using: .utf8)!
        MockAPIURLProtocol.mockData = json
        MockAPIURLProtocol.mockStatusCode = 200

        let client = makeClient()
        let _: [String: String] = try await client.request(.health)

        XCTAssertEqual(
            MockAPIURLProtocol.lastAuthorizationHeader,
            "Bearer test-api-key-12345"
        )
    }
}

// MARK: - Test Helper: StatusResponse

/// Minimal decodable type used by `testDecodingError`.
private struct StatusResponse: Decodable {
    let status: String
}
