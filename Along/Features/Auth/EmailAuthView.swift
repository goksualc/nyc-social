import SwiftUI

/// Email + password: "Welcome back." (sign in) and "Join Along." (sign up) on one screen.
struct EmailAuthView: View {
    @Environment(AppSession.self) private var session
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var localError: String?

    enum Mode { case signIn, signUp }

    private var filled: Bool {
        let base = !email.isEmpty && !password.isEmpty
        return mode == .signIn ? base : base && !name.isEmpty && !confirm.isEmpty
    }

    var body: some View {
        AuthScaffold(title: mode == .signIn ? "Welcome back." : "Join Along.") {
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                if mode == .signUp {
                    AuthField(label: "Full Name", text: $name, contentType: .name, capitalization: .words)
                }
                AuthField(label: "Email address", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                AuthField(label: "Password", text: $password, isSecure: true,
                          contentType: mode == .signIn ? .password : .newPassword,
                          submitLabel: mode == .signIn ? .go : .next, onSubmit: { if mode == .signIn { submit() } })
                if mode == .signUp {
                    AuthField(label: "Confirm Password", text: $confirm, isSecure: true, contentType: .newPassword,
                              submitLabel: .go, onSubmit: submit)
                    AuthMessage(text: "At least \(AuthValidation.minimumPasswordLength) characters.", isError: false)
                } else {
                    NavigationLink(value: WelcomeView.Step.forgot) {
                        Text("Forgot password?").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                            .frame(minHeight: AlongSize.minTouch)
                    }
                    .buttonStyle(.plain)
                }
                if let message = localError ?? session.errorMessage { AuthMessage(text: message) }
            }
        } footer: {
            VStack(spacing: AlongSpacing.xs) {
                AlongButton(title: mode == .signIn ? "Sign In" : "Create Account", isLoading: session.isBusy, action: submit)
                    .disabled(!filled || session.isBusy)
                Button {
                    alongWithAnimation(.alongQuick) { mode = mode == .signIn ? .signUp : .signIn }
                    localError = nil; session.clearError(); password = ""; confirm = ""
                } label: {
                    (Text(mode == .signIn ? "New to Along? " : "Already have an account? ")
                        .foregroundStyle(AlongColor.textTertiary)
                     + Text(mode == .signIn ? "Sign up" : "Sign in").foregroundStyle(AlongColor.navy).fontWeight(.semibold))
                        .font(AlongFont.subhead)
                        .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch)
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.clearError() }
    }

    private func submit() {
        guard filled, !session.isBusy else { return }
        localError = nil
        session.clearError()
        guard AuthValidation.isValidEmail(email) else { localError = "Enter a valid email address."; return }
        switch mode {
        case .signIn:
            Task { await session.signInWithEmail(email: email, password: password) }
        case .signUp:
            guard AuthValidation.isValidName(name) else { localError = "Enter your name."; return }
            if let problem = AuthValidation.passwordProblem(password) { localError = problem; return }
            guard password == confirm else { localError = "Passwords don't match."; return }
            Task { await session.signUpWithEmail(fullName: name, email: email, password: password) }
        }
    }
}

/// "Reset your password." — always answers the same way, whether or not the address has an account.
struct ForgotPasswordView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false
    @State private var localError: String?

    var body: some View {
        AuthScaffold(title: "Reset your password.") {
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                if sent {
                    AuthMessage(text: "Check your inbox for a password reset link.", isError: false)
                        .font(AlongFont.body)
                } else {
                    AuthField(label: "Email address", text: $email, contentType: .emailAddress, keyboard: .emailAddress,
                              submitLabel: .send, onSubmit: send)
                    if let message = localError ?? session.errorMessage { AuthMessage(text: message) }
                }
            }
        } footer: {
            if sent {
                AlongButton(title: "Back to Sign In") { dismiss() }
            } else {
                AlongButton(title: "Send Reset Link", isLoading: session.isBusy, action: send)
                    .disabled(email.isEmpty || session.isBusy)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.clearError() }
    }

    private func send() {
        guard !email.isEmpty, !session.isBusy else { return }
        localError = nil
        guard AuthValidation.isValidEmail(email) else { localError = "Enter a valid email address."; return }
        Task { sent = await session.requestPasswordReset(email: email) }
    }
}

/// "Check your inbox." — shown while an email confirmation is pending. The link opens Along and finishes sign-in.
struct CheckInboxView: View {
    let email: String
    @Environment(AppSession.self) private var session
    @State private var cooldown = 0
    @State private var resent = false

    var body: some View {
        AuthScaffold(title: "Check your inbox.", subtitle: "We sent you a verification link to confirm your email.") {
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                Text(email).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                if resent { AuthMessage(text: "Sent again. Check your inbox.", isError: false) }
                if let error = session.errorMessage { AuthMessage(text: error) }
            }
        } footer: {
            VStack(spacing: AlongSpacing.xs) {
                AlongButton(title: cooldown > 0 ? "Resend Email (\(cooldown)s)" : "Resend Email", style: .secondary,
                            isLoading: session.isBusy) {
                    Task {
                        if await session.resendVerification(email: email) { resent = true; cooldown = 60 }
                    }
                }
                .disabled(cooldown > 0 || session.isBusy)
                AlongButton(title: "Back to sign in", style: .ghost) { Task { await session.cancelPendingAuth() } }
            }
        }
        .task(id: cooldown) {
            guard cooldown > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { cooldown -= 1 }
        }
        .onAppear { session.clearError() }
    }
}

/// Shown after the user opens a password-reset link.
struct UpdatePasswordView: View {
    @Environment(AppSession.self) private var session
    @State private var password = ""
    @State private var confirm = ""
    @State private var localError: String?

    var body: some View {
        AuthScaffold(title: "Choose a new password.") {
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                AuthField(label: "New Password", text: $password, isSecure: true, contentType: .newPassword)
                AuthField(label: "Confirm New Password", text: $confirm, isSecure: true, contentType: .newPassword,
                          submitLabel: .go, onSubmit: update)
                AuthMessage(text: "At least \(AuthValidation.minimumPasswordLength) characters.", isError: false)
                if let message = localError ?? session.errorMessage { AuthMessage(text: message) }
            }
        } footer: {
            VStack(spacing: AlongSpacing.xs) {
                AlongButton(title: "Update Password", isLoading: session.isBusy, action: update)
                    .disabled(password.isEmpty || confirm.isEmpty || session.isBusy)
                AlongButton(title: "Cancel", style: .ghost) { Task { await session.cancelPendingAuth() } }
            }
        }
        .onAppear { session.clearError() }
    }

    private func update() {
        guard !password.isEmpty, !confirm.isEmpty, !session.isBusy else { return }
        localError = nil
        if let problem = AuthValidation.passwordProblem(password) { localError = problem; return }
        guard password == confirm else { localError = "Passwords don't match."; return }
        Task { await session.updatePassword(password) }
    }
}
