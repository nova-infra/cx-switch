import Foundation

struct LoginFlowState: Codable {
    var active: Bool
    var loginId: String?
    var authUrl: String?
    var status: String?
    var message: String?
    var error: String?
    var startedAt: Date?
    var completedAt: Date?

    static func empty() -> LoginFlowState {
        LoginFlowState(
            active: false,
            loginId: nil,
            authUrl: nil,
            status: nil,
            message: nil,
            error: nil,
            startedAt: nil,
            completedAt: nil
        )
    }
}
