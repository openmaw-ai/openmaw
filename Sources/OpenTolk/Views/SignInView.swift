import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @ObservedObject private var authManager = AuthManager.shared

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if codeSent {
                codeEntryView
            } else {
                signInOptionsView
            }
        }
    }

    // MARK: - Sign In Options

    private var signInOptionsView: some View {
        VStack(spacing: 16) {
            // Social sign-in buttons
            VStack(spacing: 10) {
                SignInWithAppleButton(.signIn, onRequest: { request in
                    request.requestedScopes = [.email, .fullName]
                }, onCompletion: { result in
                    handleAppleSignIn(result)
                })
                .frame(height: 32)
                .frame(maxWidth: 260)
                .disabled(isLoading)

                Button {
                    signInWithGoogle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: 260)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isLoading)
            }

            // Divider with "or"
            HStack {
                Rectangle().fill(.separator).frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Rectangle().fill(.separator).frame(height: 1)
            }
            .padding(.horizontal, 40)

            // Email field
            VStack(spacing: 8) {
                TextField("Email address", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Button {
                    sendCode()
                } label: {
                    Text(isLoading ? "Sending..." : "Continue with email")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(email.isEmpty || !email.contains("@") || isLoading)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Code Entry

    private var codeEntryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Check your email")
                    .font(.headline)
                Text(email)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("Enter 6-digit code", text: $code)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .font(.system(size: 15, design: .monospaced))
                .multilineTextAlignment(.center)

            Button {
                verifyCode()
            } label: {
                Text(isLoading ? "Verifying..." : "Verify")
                    .frame(width: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(code.count != 6 || isLoading)

            Button("Use a different email") {
                codeSent = false
                code = ""
                errorMessage = nil
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                errorMessage = "Failed to get Apple identity token"
                return
            }

            var displayName: String?
            if let fullName = credential.fullName {
                displayName = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if displayName?.isEmpty == true { displayName = nil }
            }

            isLoading = true
            errorMessage = nil
            Task {
                do {
                    try await authManager.signInWithAppleToken(
                        identityToken: identityToken,
                        displayName: displayName
                    )
                    await MainActor.run { isLoading = false }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = error.localizedDescription
                    }
                }
            }

        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.signInWithGoogle()
                await MainActor.run { isLoading = false }
            } catch AuthError.cancelled {
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func sendCode() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.sendMagicCode(email: email)
                await MainActor.run {
                    isLoading = false
                    codeSent = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func verifyCode() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.verifyMagicCode(email: email, code: code)
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
