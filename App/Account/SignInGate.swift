import AuthenticationServices
import FabriqueAccounts
import SwiftUI

/// The sign-in screen: Sign in with Apple, or email with a password or a link. The Library
/// works without an account, so a way past the screen is always on it.
///
/// The kit's own `SignInView` is English-only and light-themed; this one is drawn in Baika's
/// theme over the same `AccountsClient` calls.
struct SignInGate: View {
    let openLibrary: () -> Void

    @Environment(AccountsClient.self) private var accounts

    private enum Mode: Hashable { case signIn, signUp }
    private enum Field { case email, password }

    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var notice: String?
    @State private var appleNonce: String?
    @FocusState private var focus: Field?

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !cleanEmail.isEmpty && password.count >= 6 }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                SpeakingOrb(mode: .breathing, size: 150)
                    .padding(.top, 8)
                VStack(spacing: 8) {
                    Text("Baika")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.cream)
                    Text("Pick a topic and a style. Hear it told as a story.")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 14) {
                    appleButton
                    HStack(spacing: 10) {
                        Rectangle().frame(height: 1).foregroundStyle(Theme.line)
                        Text("or").font(.caption).foregroundStyle(Theme.muted)
                        Rectangle().frame(height: 1).foregroundStyle(Theme.line)
                    }
                    .accessibilityHidden(true)

                    Picker("", selection: $mode) {
                        Text("Sign in").tag(Mode.signIn)
                        Text("Create account").tag(Mode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    fields
                    Button(action: submit) {
                        ZStack {
                            Text(mode == .signIn ? "Sign in" : "Create account").opacity(busy ? 0 : 1)
                            if busy { ProgressView().tint(Theme.ink) }
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit || busy)

                    Button(action: magicLink) {
                        Label("Email me a sign-in link", systemImage: "envelope")
                            .font(.headline)
                            .foregroundStyle(Theme.amber)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(cleanEmail.isEmpty || busy)
                    .opacity(cleanEmail.isEmpty ? 0.45 : 1)

                    if let notice {
                        Text(notice).font(.footnote).foregroundStyle(Theme.cream)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: 420)

                Button("Open my library", action: openLibrary)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .inkBackground()
        .onChange(of: problem) { _, new in announce(new) }
        .onChange(of: notice) { _, new in announce(new) }
    }

    private var appleButton: some View {
        SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
            let nonce = AppleAuthNonce.make()
            appleNonce = nonce.raw
            request.requestedScopes = [.fullName, .email]
            request.nonce = nonce.sha256
        } onCompletion: { result in
            handleApple(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 52)
        .opacity(busy ? 0.4 : 1)
        .allowsHitTesting(!busy)
    }

    private var fields: some View {
        VStack(spacing: 0) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
                .frame(minHeight: 48)
            Divider().overlay(Theme.line)
            SecureField(mode == .signUp ? "Choose a password (6+ characters)" : "Password", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { if canSubmit { submit() } }
                .frame(minHeight: 48)
        }
        .foregroundStyle(Theme.cream)
        .padding(.horizontal, Theme.gap)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: Actions

    private func announce(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        run {
            let address = cleanEmail
            switch mode {
            case .signIn:
                _ = try await accounts.signIn(email: address, password: password)
            case .signUp:
                try await accounts.signUp(email: address, password: password)
                if !accounts.isSignedIn {
                    notice = String(localized: "Check \(address) to confirm the address.")
                }
            }
            password = ""
        }
    }

    private func magicLink() {
        focus = nil
        run {
            let address = cleanEmail
            try await accounts.sendMagicLink(email: address)
            notice = String(localized: "Check \(address) for the link.")
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let error):
            appleNonce = nil
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            problem = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let data = credential.identityToken,
                let token = String(data: data, encoding: .utf8),
                let nonce = appleNonce
            else {
                appleNonce = nil
                problem = String(localized: "Apple did not return an identity token.")
                return
            }
            appleNonce = nil
            run { _ = try await accounts.signInWithApple(idToken: token, nonce: nonce) }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        problem = nil
        notice = nil
        Task {
            defer { busy = false }
            do {
                try await work()
            } catch is CancellationError {
                return
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
