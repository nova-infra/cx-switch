import Foundation

enum UsageProbeError: Error, LocalizedError {
    case invalidResponse
    case missingHeaders

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "暂时无法获取用量信息"
        case .missingHeaders:
            return "暂时无法读取用量详情"
        }
    }
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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "Originator")
        request.setValue("codex_cli_rs/0.1.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "model": "gpt-5.1-codex",
            "instructions": "ping",
            "input": [
                ["role": "user", "content": [["type": "input_text", "text": "hi"]]]
            ],
            "store": false,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageProbeError.invalidResponse
        }

        // Diagnostic: write probe result to file for debugging
        let diag = """
        [\(Date())] chatgptAccountId=\(chatgptAccountId) HTTP=\(http.statusCode)
        headers: \(http.allHeaderFields.filter { ($0.key as? String)?.contains("codex") == true })
        body: \(String(data: responseData.prefix(500), encoding: .utf8) ?? "nil")
        ---
        """
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("cx-switch-probe.log")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(diag.utf8))
            handle.closeFile()
        } else {
            try? Data(diag.utf8).write(to: logURL)
        }

        guard let primary = parseWindow(from: http, prefix: "primary") else {
            NSLog("[CXSwitch] UsageProbe: missingHeaders — HTTP %d", http.statusCode)
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
