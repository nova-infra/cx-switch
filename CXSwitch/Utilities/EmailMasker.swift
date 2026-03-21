import Foundation

enum EmailMasker {
    static func mask(_ email: String) -> String {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return email }
        let localPart = String(parts[0])
        let domainPart = String(parts[1])
        guard !localPart.isEmpty, !domainPart.isEmpty else { return email }
        if localPart.count <= 2 {
            let first = localPart.first.map(String.init) ?? ""
            return "\(first)••••@\(domainPart)"
        }
        let first = localPart.prefix(1)
        let last = localPart.suffix(1)
        return "\(first)••••\(last)@\(domainPart)"
    }
}
