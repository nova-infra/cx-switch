import Foundation

struct Preferences: Codable {
    static let defaultLanguage = "zh"

    var language: String
    var maskEmails: Bool?
    var saveToKeychain: Bool?
    var refreshPolicy: String?
    var dataFolder: String?

    init(
        language: String = Preferences.defaultLanguage,
        maskEmails: Bool? = nil,
        saveToKeychain: Bool? = false,
        refreshPolicy: String? = nil,
        dataFolder: String? = nil
    ) {
        self.language = language
        self.maskEmails = maskEmails
        self.saveToKeychain = saveToKeychain
        self.refreshPolicy = refreshPolicy
        self.dataFolder = dataFolder
    }
}
