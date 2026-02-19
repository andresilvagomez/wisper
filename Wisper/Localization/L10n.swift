import Foundation

enum L10n {
    private static let interfaceLanguageKey = "interfaceLanguage"

    static func t(_ key: String) -> String {
        let selected = UserDefaults.standard.string(forKey: interfaceLanguageKey) ?? "system"
        guard selected != "system",
              let bundle = bundle(for: selected) else {
            return NSLocalizedString(key, comment: "")
        }

        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        let selected = UserDefaults.standard.string(forKey: interfaceLanguageKey) ?? "system"
        let locale = selected == "system" ? Locale.current : Locale(identifier: selected)
        return String(format: t(key), locale: locale, arguments: args)
    }

    private static func bundle(for languageCode: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return bundle
    }
}
