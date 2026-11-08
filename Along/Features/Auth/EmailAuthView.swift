import SwiftUI
import Observation

/// The text typed into the email / sign-up form.
///
/// It is its own `@Observable` object, and each field reads only its own property. That way a keystroke re-renders the one
/// field being typed in (and the Sign In button's enabled state) instead of the whole screen — heading, scroll view, every
/// field and the footer — which is what made typing stutter when all four strings were `@State` on the parent view.
@MainActor @Observable
final class AuthFormModel {
    var name = ""
    var email = ""
    var password = ""
    var confirm = ""

    func isFilled(signUp: Bool) -> Bool {
        let base = !email.isEmpty && !password.isEmpty
        return signUp ? base && !name.isEmpty && !confirm.isEmpty : base
    }
}

/// Email + password: "Welcome back." (sign in) and "Come along." (sign up) on one screen.
struct EmailAuthView: View {
    @Environment(AppSession.self) private var session
    @State private var mode: Mode
    @State private var form: AuthFormModel
    @State private var localError: String?

    enum Mode { case signIn, signUp }

    #if DEBUG
    /// How many times this screen's own body ran. Typing must NOT increase it (see TypingPerformanceTests).
    nonisolated(unsafe) static var bodyEvaluations = 0
    #endif

    init(initialMode: Mode = .signIn, form: AuthFormModel? = nil) {
        _mode = State(initialValue: initialMode)
        _form = State(initialValue: form ?? AuthFormModel())
    }

    var body: some View {
        #if DEBUG
        let _ = { Self.bodyEvaluations += 1 }()
        #endif
        AuthScaffold(title: mode == .signIn ? "Welcome back." : "Come along.",
                     subtitle: mode == .signIn ? "Good to have you along." : "Your next NYC walk starts here.") {
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                if mode == .signUp {
                    FormField(form: form, field: \.name, label: "Full Name", contentType: .name, capitalization: .words)
                }
                FormField(form: form, field: \.email, label: "Email address", contentType: .emailAddress, keyboard: .emailAddress)
                FormField(form: form, field: \.password, label: "Password", isSecure: true,
                          contentType: mode == .signIn ? .password : .newPassword,
                          submitLabel: mode == .signIn ? .go : .next, onSubmit: { if mode == .signIn { submit() } })
                if mode == .signUp {
                    FormField(form: form, field: \.confirm, label: "Confirm Password", isSecure: true, contentType: .newPassword,
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
                SubmitButton(form: form, signUp: mode == .signUp, action: submit)
                Button {
                    alongWithAnimation(.alongQuick) { mode = mode == .signIn ? .signUp : .signIn }
                    localError = nil; session.clearError(); form.password = ""; form.confirm = ""
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
        guard form.isFilled(signUp: mode == .signUp), !session.isBusy else { return }
        localError = nil
        session.clearError()
        guard AuthValidation.isValidEmail(form.email) else { localError = "Enter a valid email address."; return }
        switch mode {
        case .signIn:
            Task { await session.signInWithEmail(email: form.email, password: form.password) }
        case .signUp:
            guard AuthValidation.isValidName(form.name) else { localError = "Enter your name."; return }
            if let problem = AuthValidation.passwordProblem(form.password) { localError = problem; return }
            guard form.password == form.confirm else { localError = "Passwords don't match."; return }
            Task { await session.signUpWithEmail(fullName: form.name, email: form.email, password: form.password) }
        }
    }
}

/// One text field bound to one property of the form model. The binding is created and read *here*, so typing re-renders
/// only this small view, never the screen that contains it.
private struct FormField: View {
    let form: AuthFormModel
    let field: ReferenceWritableKeyPath<AuthFormModel, String>
    let label: String
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        AuthField(label: label, text: Binding(get: { form[keyPath: field] }, set: { form[keyPath: field] = $0 }),
                  isSecure: isSecure, contentType: contentType, keyboard: keyboard, capitalization: capitalization,
                  submitLabel: submitLabel, onSubmit: onSubmit)
    }
}

/// The main button. It alone reads which fields are filled, so only it re-renders (cheaply) as the person types.
private struct SubmitButton: View {
    let form: AuthFormModel
    let signUp: Bool
    let action: () -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        AlongButton(title: signUp ? "Create Account" : "Sign In", isLoading: session.isBusy, action: action)
            .disabled(!form.isFilled(signUp: signUp) || session.isBusy)
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
