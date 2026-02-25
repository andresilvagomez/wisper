import FirebaseAuth
import FirebaseCore
import GoogleSignIn

@MainActor
final class AuthService: ObservableObject {

    @Published private(set) var currentUser: FirebaseAuth.User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    var userEmail: String? { currentUser?.email }
    var userDisplayName: String? { currentUser?.displayName }

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentUser = user
                self.isAuthenticated = user != nil
                self.isLoading = false
                print("[Speex] Auth state: \(user?.email ?? "signed out")")
            }
        }
    }

    // MARK: - Email / Password

    func signInWithEmail(email: String, password: String) async {
        errorMessage = nil
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    func signUpWithEmail(email: String, password: String) async {
        errorMessage = nil
        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    func resetPassword(email: String) async {
        errorMessage = nil
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        errorMessage = nil

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Google Sign-In no configurado. Descarga el GoogleService-Info.plist actualizado desde Firebase Console."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            errorMessage = "No se pudo abrir la ventana de inicio de sesión."
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "No se obtuvo el token de autenticación de Google."
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
        } catch {
            let nsError = error as NSError
            if nsError.code == GIDSignInError.canceled.rawValue { return }
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Skip Login

    func skipLogin() {
        isAuthenticated = true
        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
        isAuthenticated = false
    }

    // MARK: - Error Messages

    private static func friendlyMessage(for error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidEmail:
            return "El correo electrónico no es válido."
        case .wrongPassword, .invalidCredential:
            return "Correo o contraseña incorrectos."
        case .userNotFound:
            return "No existe una cuenta con este correo."
        case .emailAlreadyInUse:
            return "Ya existe una cuenta con este correo."
        case .weakPassword:
            return "La contraseña debe tener al menos 6 caracteres."
        case .networkError:
            return "Error de conexión. Verifica tu internet."
        case .tooManyRequests:
            return "Demasiados intentos. Intenta de nuevo más tarde."
        case .userDisabled:
            return "Esta cuenta ha sido deshabilitada."
        default:
            return error.localizedDescription
        }
    }

}
