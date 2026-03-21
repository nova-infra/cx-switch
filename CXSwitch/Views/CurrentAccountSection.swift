import SwiftUI

struct CurrentAccountSection: View {
    let account: Account?
    let preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.currentAccount)
                .font(.headline)

            if let account {
                Text(displayEmail(for: account))
                    .font(.subheadline)

                if let planType = account.planType {
                    Text(planType.rawValue.uppercased())
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }

                if let snapshot = account.usageSnapshot {
                    HStack(spacing: 12) {
                        if let primary = snapshot.primary {
                            UsageBar(window: primary)
                        }
                        if let secondary = snapshot.secondary {
                            UsageBar(window: secondary)
                        }
                    }
                }

                if let error = account.usageError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text(Strings.noActiveAccount)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayEmail(for account: Account) -> String {
        if preferences.maskEmails ?? false {
            return account.maskedEmail
        }
        return account.email
    }
}
