import Foundation

struct UsageSnapshot: Codable {
    var limitId: String?
    var planType: PlanType?
    var updatedAt: Date?
    var windows: [UsageWindow]?
    var primary: UsageWindow?
    var secondary: UsageWindow?
    var credits: Credits?
}

struct UsageWindow: Codable {
    var label: String
    var windowDurationMins: Int
    var usedPercent: Double
    var resetsAt: Date?
    var remainingSeconds: Int?
    var resetText: String?
}

struct Credits: Codable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}
