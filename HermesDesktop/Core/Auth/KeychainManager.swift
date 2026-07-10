import Foundation
import Security

// MARK: - KeychainManager

/// Manages API key storage in the macOS Keychain.
///
/// Uses `kSecClassGenericPassword` with:
/// - Service name: `com.hermes-desktop.api-key`
/// - Account name: `hermes-api`
/// - Accessibility: `kSecAttrAccessibleWhenUnlocked`
///
/// All public methods are actor-isolated and `async`, satisfying Swift 6 strict concurrency.
public actor KeychainManager {

    // MARK: - Constants

    private let service = "com.hermes-desktop.api-key"
    private let account = "hermes-api"

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Saves an API key to the Keychain.
    ///
    /// If an entry already exists, it is updated in-place via `SecItemUpdate`
    /// (avoids the race condition of delete-then-add).
    public func save(key: String) throws {
        let data = Data(key.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Update the existing item's data.
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary,
                attributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(status: updateStatus)
            }
        default:
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Reads the API key from the Keychain.
    ///
    /// - Returns: The stored API key string, or `nil` if no key exists.
    /// - Throws: `KeychainError.readFailed` for unexpected Keychain errors.
    public func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status: status)
        }
    }

    /// Deletes the API key from the Keychain.
    ///
    /// If no key exists, this is a no-op (does not throw).
    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

// MARK: - KeychainError

/// Errors that can occur during Keychain operations.
public enum KeychainError: Error, LocalizedError {
    case saveFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save API key to Keychain (\(status))."
        case .readFailed(let status):
            return "Failed to read API key from Keychain (\(status))."
        case .deleteFailed(let status):
            return "Failed to delete API key from Keychain (\(status))."
        case .invalidData:
            return "Invalid data retrieved from Keychain — expected UTF-8 string."
        }
    }
}
