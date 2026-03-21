import Foundation

enum UsageProbeError: Error {
    case invalidResponse
    case missingHeaders
}

final class UsageProbe {
    private let session: URLSession
    private let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.session = session
        self.timeout = timeout
    }

    func probeUsage(accessToken: String, chatgptAccountId: String) async throws -> UsageSnapshot {
        guard let url = URL(string: "https://chatgpt.com/backend-api/codex/responses") else {
            throw UsageProbeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(chatgptAccountId, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "gpt-5.1-codex",
            "max_output_tokens": 1,
            "store": false,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageProbeError.invalidResponse
        }

        guard let primary = parseWindow(from: http, prefix: "primary") else {
            throw UsageProbeError.missingHeaders
        }

        let secondary = parseWindow(from: http, prefix: "secondary")

        return UsageSnapshot(
            limitId: nil,
            planType: nil,
            updatedAt: Date(),
            primary: primary,
            secondary: secondary,
            credits: nil
        )
    }

    private func parseWindow(from response: HTTPURLResponse, prefix: String) -> UsageWindow? {
        let percentKey = "x-codex-\(prefix)-used-percent"
        let resetKey = "x-codex-\(prefix)-reset-after-seconds"
        let durationKey = "x-codex-\(prefix)-window-minutes"

        guard
            let percentString = response.value(forHTTPHeaderField: percentKey),
            let percent = Double(percentString)
        else {
            return nil
        }

        let resetSeconds = response.value(forHTTPHeaderField: resetKey).flatMap(Double.init)
        let windowMins = response.value(forHTTPHeaderField: durationKey).flatMap(Int.init) ?? 0
        let resetDate = resetSeconds.map { Date().addingTimeInterval($0) }

        return UsageWindow(
            label: prefix == "primary" ? "5 Hours" : "Weekly",
            windowDurationMins: windowMins,
            usedPercent: percent,
            resetsAt: resetDate
        )
    }
}
