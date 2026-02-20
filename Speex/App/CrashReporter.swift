import Foundation
import FirebaseCore
import FirebaseCrashlytics

enum CrashReporter {
    static func configureIfAvailable() {
        guard FirebaseApp.app() == nil else { return }

        guard let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: plistPath) else {
            print("[Speex] ⚠️ Crashlytics not configured: GoogleService-Info.plist missing in app bundle")
            return
        }

        FirebaseApp.configure(options: options)

        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown", forKey: "app_version")
        crashlytics.setCustomValue(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "unknown", forKey: "build_number")
    }
}

