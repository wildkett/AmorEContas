import Foundation

enum L10n {
    private static let languageDefaultsKey = "appLanguageCode"
    static let systemLanguageCode = "system"

    private static var selectedLanguageCode: String {
        let stored = UserDefaults.standard.string(forKey: languageDefaultsKey) ?? systemLanguageCode
        return stored.isEmpty ? systemLanguageCode : stored
    }

    private static var bundle: Bundle {
        let code = selectedLanguageCode
        guard code != systemLanguageCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static var currentLocale: Locale {
        let code = selectedLanguageCode
        return code == systemLanguageCode ? .current : Locale(identifier: code)
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: currentLocale, arguments: args)
    }
}
