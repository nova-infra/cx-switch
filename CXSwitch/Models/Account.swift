import Foundation

struct Account: Identifiable, Codable {
    let id: String
    var email: String
    var maskedEmail: String
    var planType: PlanType?
    var chatgptAccountId: String?
    var addedAt: Date
    var lastUsedAt: Date?
    var usageSnapshot: UsageSnapshot?
    var authKeychainKey: String?
    var storedAuth: String?       // Base64 encoded AuthBlob (non-keychain fallback)
    var usageError: String?
    var isCurrent: Bool = false
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
}
