import Foundation

struct Preferences: Codable {
    static let defaultLanguage = "zh"

    var language: String
    var maskEmails: Bool?
    var refreshPolicy: String?
    var dataFolder: String?

    init(
        language: String = Preferences.defaultLanguage,
        maskEmails: Bool? = nil,
        refreshPolicy: String? = nil,
        dataFolder: String? = nil
    ) {
        self.language = language
        self.maskEmails = maskEmails
        self.refreshPolicy = refreshPolicy
        self.dataFolder = dataFolder
    }
}
