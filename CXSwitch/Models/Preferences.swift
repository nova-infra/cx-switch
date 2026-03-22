import Foundation

struct Preferences: Codable {
    static let defaultLanguage = "zh"
    static let defaultTheme = "system"

    var language: String
    var maskEmails: Bool?
    var theme: String?
    var refreshPolicy: String?
    var dataFolder: String?

    init(
        language: String = Preferences.defaultLanguage,
        maskEmails: Bool? = nil,
        theme: String? = Preferences.defaultTheme,
        refreshPolicy: String? = nil,
        dataFolder: String? = nil
    ) {
        self.language = language
        self.maskEmails = maskEmails
        self.theme = theme
        self.refreshPolicy = refreshPolicy
        self.dataFolder = dataFolder
    }
}
