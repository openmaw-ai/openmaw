import AuthenticationServices
import AppKit

/// Wraps ASAuthorizationAppleIDProvider for async/await Apple sign-in.
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    struct AppleSignInResult {
        let identityToken: String
        let userIdentifier: String
        let fullName: PersonNameComponents?
        let email: String?
    }

    func signIn() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.email, .fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            continuation?.resume(throwing: AuthError.appleSignInFailed("Missing identity token"))
            continuation = nil
            return
        }

        let result = AppleSignInResult(
            identityToken: identityToken,
            userIdentifier: credential.user,
            fullName: credential.fullName,
            email: credential.email
        )
        continuation?.resume(returning: result)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            continuation?.resume(throwing: AuthError.cancelled)
        } else {
            continuation?.resume(throwing: AuthError.appleSignInFailed(error.localizedDescription))
        }
        continuation = nil
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}

enum AuthError: LocalizedError {
    case cancelled
    case appleSignInFailed(String)
    case googleSignInFailed(String)
    case magicLinkFailed(String)
    case serverError(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign in was cancelled."
        case .appleSignInFailed(let msg): return "Apple sign in failed: \(msg)"
        case .googleSignInFailed(let msg): return "Google sign in failed: \(msg)"
        case .magicLinkFailed(let msg): return "Magic link failed: \(msg)"
        case .serverError(let msg): return "Server error: \(msg)"
        case .noRefreshToken: return "No refresh token available."
        }
    }
}
