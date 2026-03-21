import SwiftUI

struct SavedAccountRow: View {
    let account: Account
    let preferences: Preferences
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayEmail(for: account))
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    if let planType = account.planType {
                        Text(planType.rawValue.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                if let primary = account.usageSnapshot?.primary {
                    UsageBar(window: primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func displayEmail(for account: Account) -> String {
        if preferences.maskEmails ?? false {
            return account.maskedEmail
        }
        return account.email
    }
}
