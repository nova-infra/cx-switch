import Foundation

struct Account: Identifiable, Codable {
    let id: String
    var email: String
    var maskedEmail: String
    var accountType: AccountType?
    var planType: PlanType?
    var chatgptAccountId: String?
    var addedAt: Date
    var lastUsedAt: Date?
    var usageSnapshot: UsageSnapshot?
    var authKeychainKey: String?  // Legacy keychain account ID retained for migration only
    var storedAuth: String?       // Base64 encoded AuthBlob stored in registry
    var usageError: String?
    var isCurrent: Bool = false
}

enum AccountType: String, Codable, CaseIterable {
    case oauth
    case setupToken = "setup-token"
    case apiKey = "apikey"
    case upstream
    case bedrock
    case unknown

    var displayName: String {
        switch self {
        case .oauth:
            return "OAuth"
        case .setupToken:
            return "Setup Token"
        case .apiKey:
            return "API Key"
        case .upstream:
            return "Upstream"
        case .bedrock:
            return "Bedrock"
        case .unknown:
            return "Unknown"
        }
    }
}

enum PlanType: String, Codable, CaseIterable {
    case free
    case go
    case plus
    case pro
    case team
    case business
    case enterprise
    case edu
    case unknown

    var displayName: String {
        switch self {
        case .free:
            return Strings.L("免费", en: "Free")
        case .go:
            return Strings.L("Go", en: "Go")
        case .plus:
            return Strings.L("Plus", en: "Plus")
        case .pro:
            return Strings.L("Pro", en: "Pro")
        case .team:
            return Strings.L("团队", en: "Team")
        case .business:
            return Strings.L("商业版", en: "Business")
        case .enterprise:
            return Strings.L("企业版", en: "Enterprise")
        case .edu:
            return Strings.L("教育版", en: "Edu")
        case .unknown:
            return Strings.L("未知计划", en: "Unknown")
        }
    }
}
