import Foundation

/// Keychain wrapper for auth tokens, using the existing KeychainHelper.
enum AuthTokenStore {
    private static let accessTokenKey = "auth_access_token"
    private static let refreshTokenKey = "auth_refresh_token"
    private static let userKey = "auth_user"

    static var accessToken: String? {
        get { KeychainHelper.load(key: accessTokenKey) }
        set {
            if let value = newValue {
                KeychainHelper.save(key: accessTokenKey, value: value)
            } else {
                KeychainHelper.delete(key: accessTokenKey)
            }
        }
    }

    static var refreshToken: String? {
        get { KeychainHelper.load(key: refreshTokenKey) }
        set {
            if let value = newValue {
                KeychainHelper.save(key: refreshTokenKey, value: value)
            } else {
                KeychainHelper.delete(key: refreshTokenKey)
            }
        }
    }

    static var savedUser: AuthUser? {
        get {
            guard let json = KeychainHelper.load(key: userKey),
                  let data = json.data(using: .utf8),
                  let user = try? JSONDecoder().decode(AuthUser.self, from: data)
            else { return nil }
            return user
        }
        set {
            if let user = newValue,
               let data = try? JSONEncoder().encode(user),
               let json = String(data: data, encoding: .utf8) {
                KeychainHelper.save(key: userKey, value: json)
            } else {
                KeychainHelper.delete(key: userKey)
            }
        }
    }

    static func clear() {
        accessToken = nil
        refreshToken = nil
        savedUser = nil
    }
}
