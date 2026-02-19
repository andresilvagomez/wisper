import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }
}
