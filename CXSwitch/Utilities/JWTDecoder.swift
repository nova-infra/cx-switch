import Foundation

enum JWTDecoder {
    static func decodePayload(_ token: String?) -> [String: Any]? {
        guard let token, !token.isEmpty else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let data = decodeBase64Url(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func decodeBase64Url(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - normalized.count % 4) % 4
        if padding > 0 {
            normalized.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: normalized)
    }
}
