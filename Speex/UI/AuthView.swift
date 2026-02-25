import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUpMode = false
    @State private var isResetMode = false
    @State private var isProcessing = false
    @State private var resetEmailSent = false

    var body: some View {
        VStack(spacing: 0) {
            header
            providerButtons
            divider
            if isResetMode {
                resetPasswordForm
            } else {
                emailPasswordForm
            }
            feedbackMessages
            Spacer()
        }
        .frame(width: 380, height: 520)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                NSApp.keyWindow?.close()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.primary)

            Text("Speex")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Speech to text, on device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    // MARK: - Provider Buttons

    private var providerButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    isProcessing = true
                    await authService.signInWithGoogle()
                    isProcessing = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .medium))
                    Text("Continuar con Google")
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Divider

    private var divider: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
            Text("o")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    // MARK: - Email / Password Form

    private var emailPasswordForm: some View {
        VStack(spacing: 12) {
            TextField("Correo electrónico", text: $email)
                .textFieldStyle(.plain)
                .textContentType(.emailAddress)
                .font(.system(size: 15))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            SecureField("Contraseña", text: $password)
                .textFieldStyle(.plain)
                .textContentType(isSignUpMode ? .newPassword : .password)
                .font(.system(size: 15))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onSubmit { submitEmailForm() }

            Button {
                submitEmailForm()
            } label: {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                } else {
                    Text(isSignUpMode ? "Crear cuenta" : "Iniciar sesión")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || isProcessing)

            HStack {
                Button(isSignUpMode ? "¿Ya tienes cuenta? Inicia sesión" : "¿No tienes cuenta? Regístrate") {
                    isSignUpMode.toggle()
                    authService.errorMessage = nil
                }
                .buttonStyle(.link)
                .font(.caption)

                Spacer()

                if !isSignUpMode {
                    Button("¿Olvidaste tu contraseña?") {
                        isResetMode = true
                        authService.errorMessage = nil
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Reset Password Form

    private var resetPasswordForm: some View {
        VStack(spacing: 12) {
            Text("Recuperar contraseña")
                .font(.headline)

            TextField("Correo electrónico", text: $email)
                .textFieldStyle(.plain)
                .textContentType(.emailAddress)
                .font(.system(size: 15))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Button {
                Task {
                    isProcessing = true
                    await authService.resetPassword(email: email)
                    if authService.errorMessage == nil {
                        resetEmailSent = true
                    }
                    isProcessing = false
                }
            } label: {
                Text("Enviar enlace de recuperación")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || isProcessing)

            Button("Volver al inicio de sesión") {
                isResetMode = false
                resetEmailSent = false
                authService.errorMessage = nil
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Feedback Messages

    @ViewBuilder
    private var feedbackMessages: some View {
        if let error = authService.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }

        if resetEmailSent {
            Text("Se envió un enlace de recuperación a tu correo.")
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func submitEmailForm() {
        guard !email.isEmpty, !password.isEmpty, !isProcessing else { return }
        Task {
            isProcessing = true
            if isSignUpMode {
                await authService.signUpWithEmail(email: email, password: password)
            } else {
                await authService.signInWithEmail(email: email, password: password)
            }
            isProcessing = false
        }
    }
}
