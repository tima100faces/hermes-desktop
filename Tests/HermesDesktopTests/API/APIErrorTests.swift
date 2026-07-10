import XCTest
@testable import HermesDesktop

final class APIErrorTests: XCTestCase {

    // MARK: - HTTP Status Code Mapping

    func testHTTP401MapsToUnauthorized() {
        let error = APIError(httpStatusCode: 401)
        XCTAssertEqual(error, .unauthorized)
    }

    func testHTTP404MapsToNotFound() {
        let error = APIError(httpStatusCode: 404)
        XCTAssertEqual(error, .notFound)
    }

    func testHTTP500MapsToServerError() {
        let error = APIError(httpStatusCode: 500)
        XCTAssertEqual(error, .serverError(statusCode: 500))
    }

    func testHTTP503MapsToServerError() {
        let error = APIError(httpStatusCode: 503)
        XCTAssertEqual(error, .serverError(statusCode: 503))
    }

    func testHTTP200ReturnsNil() {
        let error = APIError(httpStatusCode: 200)
        XCTAssertNil(error)
    }

    func testHTTP201ReturnsNil() {
        let error = APIError(httpStatusCode: 201)
        XCTAssertNil(error)
    }

    func testHTTP302ReturnsUnknown() {
        let error = APIError(httpStatusCode: 302)
        XCTAssertNotNil(error)
        if let error {
            guard case .unknown = error else {
                XCTFail("Expected .unknown for HTTP 302, got \(error)")
                return
            }
        }
    }

    // MARK: - URLError Mapping

    func testURLErrorNotConnectedToInternet() {
        let error = APIError(urlError: URLError(.notConnectedToInternet))
        guard case .networkError = error else {
            XCTFail("Expected .networkError, got \(error)")
            return
        }
    }

    func testURLErrorTimedOut() {
        let error = APIError(urlError: URLError(.timedOut))
        guard case .networkError = error else {
            XCTFail("Expected .networkError, got \(error)")
            return
        }
    }

    // MARK: - Equatable

    func testEquatableSameValues() {
        XCTAssertEqual(APIError.unauthorized, APIError.unauthorized)
        XCTAssertEqual(APIError.notFound, APIError.notFound)
        XCTAssertEqual(
            APIError.serverError(statusCode: 500),
            APIError.serverError(statusCode: 500)
        )
        XCTAssertEqual(
            APIError.networkError(underlying: URLError(.notConnectedToInternet)),
            APIError.networkError(underlying: URLError(.notConnectedToInternet))
        )
        XCTAssertEqual(
            APIError.decodingError(underlying: NSError(domain: "test", code: 1)),
            APIError.decodingError(underlying: NSError(domain: "test", code: 1))
        )
        XCTAssertEqual(
            APIError.unknown("foo"),
            APIError.unknown("foo")
        )
    }

    func testEquatableDifferentValues() {
        XCTAssertNotEqual(APIError.unauthorized, APIError.notFound)
        XCTAssertNotEqual(APIError.unauthorized, APIError.serverError(statusCode: 401))
        XCTAssertNotEqual(
            APIError.serverError(statusCode: 500),
            APIError.serverError(statusCode: 501)
        )
        XCTAssertNotEqual(
            APIError.networkError(underlying: URLError(.notConnectedToInternet)),
            APIError.networkError(underlying: URLError(.timedOut))
        )
        XCTAssertNotEqual(
            APIError.decodingError(underlying: NSError(domain: "a", code: 1)),
            APIError.decodingError(underlying: NSError(domain: "b", code: 1))
        )
        XCTAssertNotEqual(
            APIError.unknown("foo"),
            APIError.unknown("bar")
        )
    }

    func testServerErrorDifferentCodesNotEqual() {
        let error500 = APIError.serverError(statusCode: 500)
        let error501 = APIError.serverError(statusCode: 501)
        XCTAssertNotEqual(error500, error501)
    }

    // MARK: - Error Descriptions

    func testErrorDescriptionNotEmpty() {
        let cases: [APIError] = [
            .unauthorized,
            .notFound,
            .serverError(statusCode: 502),
            .networkError(underlying: URLError(.notConnectedToInternet)),
            .decodingError(underlying: NSError(domain: "test", code: 0)),
            .unknown("something went wrong")
        ]
        for (index, errorCase) in cases.enumerated() {
            let description = errorCase.errorDescription
            XCTAssertNotNil(description, "Description should not be nil for case at index \(index)")
            if let description {
                XCTAssertFalse(
                    description.isEmpty,
                    "Description should not be empty for case at index \(index)"
                )
            }
        }
    }

    func testDecodingErrorHasDescription() {
        let underlying = NSError(domain: "HermesDesktop", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "JSON parse failure"
        ])
        let error = APIError.decodingError(underlying: underlying)
        let description = error.errorDescription
        XCTAssertNotNil(description)
        XCTAssertTrue(
            description?.contains("JSON parse failure") ?? false,
            "Description should include the underlying error message"
        )
    }
}
