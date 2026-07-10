import Foundation

// MARK: - APIError

/// Domain-specific error type for Hermes Desktop API calls.
///
/// Conforms to `Error`, `LocalizedError`, and `Equatable`.
/// HTTP status codes are mapped via the `httpStatusCode` factory, and
/// `URLError` values via the `urlError` factory.
public enum APIError: Error, LocalizedError, Equatable {

    // MARK: Cases

    /// HTTP 401 – the request lacks valid authentication credentials.
    case unauthorized

    /// HTTP 404 – the requested resource was not found.
    case notFound

    /// HTTP 405 – the HTTP method is not allowed for this endpoint.
    case methodNotAllowed

    /// HTTP 500+ – the server encountered an unexpected condition.
    case serverError(statusCode: Int)

    /// A transport-level failure (e.g. no connectivity, timeout, DNS failure).
    case networkError(underlying: Error)

    /// The response payload could not be decoded (JSON parse failure, type mismatch, etc.).
    case decodingError(underlying: Error)

    /// A catch-all for errors that do not fit any other case.
    case unknown(String)

    // MARK: HTTP Status Code Factory

    /// Creates an `APIError` from an HTTP status code.
    ///
    /// Returns `nil` when the status code falls in the 2xx (success) range.
    ///
    /// - Parameter httpStatusCode: The status code from `HTTPURLResponse.statusCode`.
    /// - Returns: An `APIError` matching the status code, or `nil` for 200–299.
    public init?(httpStatusCode: Int) {
        switch httpStatusCode {
        case 200...299:
            return nil
        case 401:
            self = .unauthorized
        case 404:
            self = .notFound
        case 405:
            self = .methodNotAllowed
        case let code where code >= 500:
            self = .serverError(statusCode: code)
        default:
            self = .unknown("Unhandled HTTP status code: \(httpStatusCode)")
        }
    }

    // MARK: URLError Factory

    /// Creates an `APIError` from a `URLError`.
    ///
    /// Common connectivity and transport failures map to `.networkError(_:)`.
    ///
    /// - Parameter urlError: The `URLError` raised by a `URLSession` call.
    /// - Returns: An `APIError.networkError` wrapping the original error.
    public init(urlError: URLError) {
        self = .networkError(underlying: urlError)
    }

    // MARK: LocalizedError

    /// Human-readable description suitable for showing to the user.
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized. Please check your API key and try again."
        case .notFound:
            return "The requested resource was not found."
        case .methodNotAllowed:
            return "HTTP 405: Method not allowed. The server does not support this request method."
        case .serverError(let statusCode):
            return "Server error (\(statusCode)). Please try again later."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .decodingError(let underlying):
            return "Failed to process the server response: \(underlying.localizedDescription)"
        case .unknown(let message):
            return message
        }
    }

    // MARK: Equatable

    /// Custom equality because `Error` does not conform to `Equatable`.
    /// Underlying `Error` values are compared by their `localizedDescription`.
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized):
            return true
        case (.notFound, .notFound):
            return true
        case (.methodNotAllowed, .methodNotAllowed):
            return true
        case (.serverError(let lCode), .serverError(let rCode)):
            return lCode == rCode
        case (.networkError(let lErr), .networkError(let rErr)):
            return (lErr as NSError).domain == (rErr as NSError).domain
                && (lErr as NSError).code == (rErr as NSError).code
        case (.decodingError(let lErr), .decodingError(let rErr)):
            return (lErr as NSError).domain == (rErr as NSError).domain
                && (lErr as NSError).code == (rErr as NSError).code
        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}
